# Vigil for Flutter

Vigil is an in-app HTTP inspector for Flutter development. Add one Dio
interceptor to capture requests, responses, and failures, then open a searchable
inspector without changing your API responses. This package exports the core
capture API, Dio interceptor, Flutter UI, and optional backend uploader.

Pair it with
[`@vigiljs/express` on npm](https://www.npmjs.com/package/@vigiljs/express)
to correlate client calls with backend timings and gated error diagnostics.

## What the inspector provides

- Shake to open, show a floating launcher, or open it from your own debug menu.
- Inspect request and response headers and bodies, client and server timing,
  trace IDs, and failures in dedicated tabs.
- **Copy cURL** to give a backend teammate a request they can replay after
  replacing any redacted credentials.
- **Copy lifecycle** or **Share lifecycle** to send JSON with the captured
  request, response, trace, timings, and error details.
- View client failures even without a server response. When the backend is
  configured with a matching development key, the Debug tab also shows its
  error message, stack trace, and request context. This is per-request
  diagnostics, not a general backend log stream.

> Vigil is a development tool. Keep it disabled in production unless you have
> reviewed its data capture, access control, and retention for your application.

## Installation

```sh
flutter pub add vigil dio
```

## Usage

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vigil/vigil.dart';

final dio = Dio()..interceptors.add(VigilDioInterceptor());

void main() {
  Vigil.instance.init(
    config: const VigilConfig(
      enabled: kDebugMode,
      debugKey: String.fromEnvironment('VIGIL_DEBUG_KEY'),
      maskBodyFields: {'password', 'token', 'secret'},
    ),
  );
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) => VigilOverlay(
        enabled: kDebugMode,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(body: Center(child: Text('Shake to inspect'))),
    );
  }
}
```

The inspector opens on shake. Set `showFloatingButton: true` when an on-screen
launcher is more convenient.

## Connect an Express backend

Install [`@vigiljs/express`](https://www.npmjs.com/package/@vigiljs/express)
on the server:

```sh
npm install @vigiljs/express
```

```ts
import express from 'express';
import { vigilErrorHandler, vigilMiddleware } from '@vigiljs/express';

const app = express();
app.use(vigilMiddleware({
  enabled: process.env.NODE_ENV !== 'production',
  debugKey: process.env.VIGIL_DEBUG_KEY,
}));

app.get('/health', async (req, res) => {
  const result = await req.vigil.time('check', 'Health check',
    async () => ({ ok: true }));
  res.json(result);
});

app.use(vigilErrorHandler({
  enabled: process.env.NODE_ENV !== 'production',
  debugKey: process.env.VIGIL_DEBUG_KEY,
}));
```

Vigil sends `traceparent` with Dio requests. Express returns the correlated
trace and `Server-Timing`; a matching `Vigil-Key` also enables `Vigil-Debug` on
error responses. Pass the same development key with
`--dart-define=VIGIL_DEBUG_KEY=<development-key>` and the backend environment
variable. Without the Express package, local capture and sharing still work.
If your app already formats errors, set `passThroughErrors: true` on
`vigilErrorHandler` and mount your handler after it.

## Optional backend upload

[`vigil_backend`](https://pub.dev/packages/vigil_backend), already exported by
this package, can send completed and failed call summaries in batches. Point it
at an endpoint built with `vigilIngestHandler` from `@vigiljs/express`:

```dart
final connection = VigilBackendConnection.connect(
  config: VigilBackendConfig(
    endpoint: Uri.parse('https://dev-api.example.com/vigil/ingest'),
    ingestKey: const String.fromEnvironment('VIGIL_INGEST_KEY'),
  ),
);

// Later, when the owning component or application shuts down:
await connection.dispose();
```

The uploader is separate from response diagnostics. `Vigil-Ingest-Key` gates
upload; `Vigil-Key` gates error details. Neither key is durable authentication
when embedded in a client app.

Review copied cURL and lifecycle data before sharing. Configured headers and
JSON body fields are masked, but URL paths and query parameters may still
contain sensitive values.

See the [repository README](https://github.com/guptan404/vigil#readme) for the
Express bridge, security guidance, CORS requirements, and full examples.
