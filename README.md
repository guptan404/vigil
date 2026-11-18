# Vigil

Vigil is a Flutter-first HTTP inspector for development and testing. It captures
Dio traffic, masks sensitive data, correlates mobile and Express requests with
W3C `traceparent`, displays `Server-Timing`, and can show opt-in backend error
diagnostics without replacing your existing API responses.

Use the [Flutter package on pub.dev](https://pub.dev/packages/vigil) in the app
and the [Express package on npm](https://www.npmjs.com/package/@vigiljs/express)
on a Node backend. Either side can be used alone; together they connect a
captured client call to server timing and error details through the same trace.

## What you can do

- Open the in-app inspector by shaking the device, using a floating button, or
  presenting it from your own debug menu. Search calls and inspect the request,
  response, timing, and Debug tabs. Combine host, method, status, and duration
  filters, search expandable JSON fields, and copy their JSON paths.
- Compare two captured calls from the details pane. Save a named capture with
  notes under **Inspector tools → Debug sessions**. Saved sessions survive app
  restarts and can be copied as JSON and imported from the clipboard.
- Copy a cURL command to help a backend teammate replay a request after
  replacing redacted credentials. Copy or share lifecycle JSON containing the
  request, response, timing, trace, and failure details.
- See client errors even when there is no server response. With a matching
  development key, the backend can also return its error message, stack trace,
  request context, and explicitly recorded request logs in the Debug tab.
- Optionally upload completed and failed call summaries in batches to an
  Express ingest endpoint and inspect it in a desktop browser.

> Vigil is currently a `0.1.x` development release. Enable it only in trusted
> development or test environments until you have reviewed the masking,
> authentication, retention, and transport settings for your application.

## Packages

| Package | Registry | Purpose |
| --- | --- | --- |
| [`vigil`](https://pub.dev/packages/vigil) | pub.dev | Recommended Flutter package; exports the complete client API |
| [`vigil_core`](https://pub.dev/packages/vigil_core) | pub.dev | Capture models, masking, trace context, timing parsing, and cURL export |
| [`vigil_dio`](https://pub.dev/packages/vigil_dio) | pub.dev | Dio request/response interceptor |
| [`vigil_ui`](https://pub.dev/packages/vigil_ui) | pub.dev | Searchable Flutter inspector overlay |
| [`vigil_backend`](https://pub.dev/packages/vigil_backend) | pub.dev | Optional batched upload of captured calls |
| [`@vigiljs/core`](https://www.npmjs.com/package/@vigiljs/core) | npm | Node protocol, trace, timing, masking, and debug helpers |
| [`@vigiljs/express`](https://www.npmjs.com/package/@vigiljs/express) | npm | Express middleware, error diagnostics, and ingest handler |

## Install the feature branch

For Flutter, use the Git repository URL, `ref: feature/debugging-workflows`,
and `path: dart/vigil` for the `vigil` dependency. Override `vigil_core`,
`vigil_dio`, `vigil_ui`, and `vigil_backend` with the same URL/ref and each
package's path so every Vigil package comes from that branch.

For Node, the repository root provides the Express package entry point:

```json
{
  "dependencies": {
    "@vigiljs/express": "git+https://github.com/guptan404/vigil.git#feature/debugging-workflows"
  }
}
```

Git installation builds and includes both Node packages from the resolved
revision. Commit the application's lockfile to keep that revision reproducible.

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
      debugKey: String.fromEnvironment('VIGIL_DEBUG_KEY'),
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
In request details, use **Copy cURL** to send a replayable command to a
backend teammate. **Copy lifecycle** and **Share lifecycle** include the
captured request, response, timings, trace, and error as JSON. Review that
content before sharing. Vigil masks configured headers, JSON fields, and query
parameters. URL paths and unconfigured fields can contain sensitive values.
Saved sessions use local app preferences.

## Local web preview

Run `npm run preview` from the repository root. It builds the example in debug
mode and serves the Flutter app and Express API together at
[http://127.0.0.1:4010](http://127.0.0.1:4010). Open
[the desktop inspector](http://127.0.0.1:4010/vigil/inspector) with the local demo
read key `dev-vigil-read`. Keep the command running while using the preview.
Set `PORT` to use a different local port.

## Replay and simulation

In development builds, share a mock controller between the Dio interceptor
and the inspector. Pass a replay callback that uses your development client.

```dart
const origin = 'https://dev-api.example.com';
final mocks = VigilMockController(allowedOrigins: {origin});
final dio = Dio(BaseOptions(baseUrl: origin))
  ..interceptors.add(VigilDioInterceptor(mocks: mocks));
final replay = VigilDioReplay(dio, allowedOrigins: {origin});

final overlay = VigilOverlay(
  enabled: kDebugMode,
  showFloatingButton: true,
  replay: replay.send,
  mocks: mocks,
  child: const MyApp(),
);
```

Open **Edit and replay** from a completed or failed request to edit its
method, same-origin URL (including query parameters), additional headers, and
JSON body. Use your app's development client to supply authentication.
The editor requires confirmation for methods that can change data. The Dio
helper requests that redirects be disabled. On Flutter Web, browser redirects
are controlled by the browser.

Open **Inspector tools → Mock responses** to add an in-memory rule for a
method and exact path. Rules can return a status and JSON body, simulate a
timeout or connection failure, or delay and forward the original request.

### Express-side failure simulation

The desktop inspector can enable named failure points inside Express
application code. In the example, open `/vigil/inspector`, connect with
`dev-vigil-read`, expand **Express failure simulation**, and enter
`dev-vigil-control`. Choose `GET /ok`, failure location **users.lookup**,
and request count 1, then click **Enable rule**.

The next Flutter `/ok` request reaches the route and throws
`UserStoreUnavailableError` inside its user lookup operation. The route's
own catch block sends `503` with error code `USER_STORE_UNAVAILABLE`.
The following request succeeds. Remove matching Flutter mock rules so the
request reaches Express.

To add this to your backend, register error factories in `failurePoints`,
pass the simulation to `vigilMiddleware`, and call
`req.vigil.failPoint("users.lookup")` at the operation you want to exercise.
Your application's error handling chooses the response.

The **Before route** location also offers custom HTTP error responses,
exceptions through Express error handlers, delayed routes, receive timeouts,
and connection drops. The Flutter example uses a five-second receive timeout.
Set `VIGIL_SIMULATION_KEY` to replace the example's control key. See the
Express package README for integration details.

## Express integration

Install the Express bridge:

```sh
npm install @vigiljs/express
```

Mount request middleware before routes and the Vigil error middleware after
routes. When your app already has an error handler, use `passThroughErrors` so
Vigil adds diagnostics and then delegates response formatting.

```ts
import express from "express";
import { vigilErrorHandler, vigilMiddleware } from "@vigiljs/express";

const app = express();

app.use(vigilMiddleware({
  enabled: process.env.NODE_ENV !== "production",
  debugKey: process.env.VIGIL_DEBUG_KEY,
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
Set the same development key in the Flutter `VIGIL_DEBUG_KEY` Dart define and
the server `VIGIL_DEBUG_KEY` environment variable to receive gated details.
For example, run Flutter with `--dart-define=VIGIL_DEBUG_KEY=<development-key>`.
With a matching `Vigil-Key`, direct 4xx/5xx responses include a status and
trace diagnostic. Errors passed through `vigilErrorHandler` also include the
server error and stack. The Debug tab shows captured client failure details
even when a network failure prevents any server response.
Use `req.vigil.log("info", "Loaded report", { reportId })` to attach a log
entry to that request. Logs recorded before response headers are sent appear in
the Debug tab on successful and failed responses when the debug key matches.

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
import { createMemoryVigilSink, vigilIngestHandler } from "@vigiljs/express";

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

## Desktop browser inspector

Mount the router with the same sink used by the ingest handler and a separate
read key kept on the server:

```ts
import { vigilInspectorRouter } from "@vigiljs/express";

app.use("/vigil/inspector", vigilInspectorRouter({
  sink,
  readKey: process.env.VIGIL_INSPECTOR_KEY!,
}));
```

Open `/vigil/inspector` on that server, enter the read key, and make a request
from the app. The inspector refreshes recent uploads and lets you search by URL,
method, status, or trace ID and filter by `clientInfo.device` or
`clientInfo.sessionId`. The example serves the inspector at
`http://localhost:4010/vigil/inspector` with the local demo read key
`dev-vigil-read`.

## Security model

- Request and response bodies can contain personal or secret data. Review and
  extend `maskHeaders` and `maskBodyFields` for your API.
- Values shipped in a mobile or web application can be recovered by users.
  Treat ingest/debug keys as development gates, not as durable authentication.
- Use HTTPS outside localhost, restrict CORS, rate-limit ingest, and disable
  diagnostics in production by default.
- `Vigil-Debug` carries errors or explicit request logs when `Vigil-Key` matches
  the backend `debugKey`.
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
npm run test:integration
```

The integration command starts a local Express server and checks real Dio
requests, response diagnostics, and ingest uploads against it.

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
Scoped npm packages require access to the `@vigiljs` npm organization and public
visibility. Use npm trusted publishing when possible so releases receive
provenance attestations.

## Support

Report defects and security-sensitive concerns through the
[GitHub issue tracker](https://github.com/guptan404/vigil/issues). Do not attach
real credentials, tokens, request bodies, or customer data to an issue.
