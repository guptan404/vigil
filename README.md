# Vigil

Vigil is a Flutter-first HTTP inspector for development and testing. It captures
Dio traffic, masks sensitive data, correlates mobile and Express requests with
W3C `traceparent`, displays `Server-Timing`, and can show opt-in backend error
diagnostics without replacing your existing API responses.

> Vigil is currently a `0.1.x` development release. Enable it only in trusted
> development or test environments until you have reviewed the masking,
> authentication, retention, and transport settings for your application.

## Packages

| Package | Registry | Purpose |
| --- | --- | --- |
| `vigil` | pub.dev | Recommended Flutter package; exports the complete client API |
| `vigil_core` | pub.dev | Capture models, masking, trace context, timing parsing, and cURL export |
| `vigil_dio` | pub.dev | Dio request/response interceptor |
| `vigil_ui` | pub.dev | Searchable Flutter inspector overlay |
| `vigil_backend` | pub.dev | Optional batched upload of captured calls |
| `@vigil/core` | npm | Node protocol, trace, timing, masking, and debug helpers |
| `@vigil/express` | npm | Express middleware, error diagnostics, and ingest handler |

## Flutter quick start

Add the umbrella package and Dio:

```sh
flutter pub add vigil dio
```

Initialize Vigil before creating your Dio client. Keep it disabled in release
builds unless you have explicitly designed a production-safe deployment.

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
      maskHeaders: {'authorization', 'cookie', 'set-cookie', 'vigil-key'},
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

`VigilOverlay` opens on a shake by default. Set `showFloatingButton: true` for
an explicit launcher, or render `VigilInspector` from your own debug menu.

## Express integration

Install the Express bridge:

```sh
npm install @vigil/express
```

Mount request middleware before routes and the Vigil error middleware after
routes. When your app already has an error handler, use `passThroughErrors` so
Vigil adds diagnostics and then delegates response formatting.

```ts
import express from "express";
import { vigilErrorHandler, vigilMiddleware } from "@vigil/express";

const app = express();

app.use(vigilMiddleware({
  enabled: process.env.NODE_ENV !== "production",
}));

app.get("/report", async (req, res) => {
  const report = await req.vigil.time("db", "Load report", loadReport);
  res.json(report);
});

app.use(vigilErrorHandler({
  enabled: process.env.NODE_ENV !== "production",
  debugKey: process.env.VIGIL_DEBUG_KEY,
  passThroughErrors: true,
}));

app.use(existingErrorHandler);
```

The middleware always emits a total server duration when enabled. Timed work
added with `req.vigil.time()` appears as additional `Server-Timing` metrics.

For Flutter Web, expose `Server-Timing`, `traceparent`, and `Vigil-Debug` in
your CORS configuration or browsers will hide them from Dio.

## Optional backend ingest

The Flutter connector can batch completed calls to an Express endpoint:

```dart
final connection = VigilBackendConnection.connect(
  config: VigilBackendConfig(
    endpoint: Uri.parse('https://dev-api.example.com/vigil/ingest'),
    ingestKey: const String.fromEnvironment('VIGIL_INGEST_KEY'),
    clientInfo: const {'app': 'example'},
  ),
);
```

```ts
import { createMemoryVigilSink, vigilIngestHandler } from "@vigil/express";

const sink = createMemoryVigilSink();

app.use(express.json());
app.post("/vigil/ingest", vigilIngestHandler({
  enabled: process.env.NODE_ENV !== "production",
  ingestKey: process.env.VIGIL_INGEST_KEY,
  onBatch: sink.onBatch,
}));
```

The built-in memory sink is intended for development and tests. Production
retention needs a bounded, access-controlled store designed for your data.

## Security model

- Request and response bodies can contain personal or secret data. Review and
  extend `maskHeaders` and `maskBodyFields` for your API.
- Values shipped in a mobile or web application can be recovered by users.
  Treat ingest/debug keys as development gates, not as durable authentication.
- Use HTTPS outside localhost, restrict CORS, rate-limit ingest, and disable
  diagnostics in production by default.
- `Vigil-Debug` is emitted only for errors and only when `Vigil-Key` matches the
  backend `debugKey`.
- The ingest endpoint accepts `POST` requests; it is not a WebSocket endpoint.

## Workspace development

Prerequisites: Dart 3.9+, Flutter 3.27+, and Node.js 22.12+ for workspace
development. Published Node libraries support Node.js 18+.

```sh
dart pub get
dart run melos bootstrap
dart run melos run analyze
dart run melos run test
npm ci
npm run check
```

Runnable examples live in [`example/flutter_app`](example/flutter_app) and
[`example/node_server`](example/node_server).

## Release validation

Before publishing, run tests and the registry dry runs:

```sh
./tool/release_check.sh
```

The full first-release and subsequent-release procedure is documented in
[`RELEASING.md`](RELEASING.md).

The first pub.dev package releases must be published in dependency order:
`vigil_core`, then `vigil_backend` / `vigil_dio` / `vigil_ui`, then `vigil`.
Scoped npm packages require access to the `@vigil` npm organization and public
visibility. Use npm trusted publishing when possible so releases receive
provenance attestations.

## Support

Report defects and security-sensitive concerns through the
[GitHub issue tracker](https://github.com/guptan404/vigil/issues). Do not attach
real credentials, tokens, request bodies, or customer data to an issue.
