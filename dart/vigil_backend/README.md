# vigil_backend

An optional uploader for sending calls captured by `vigil_core` to a backend
ingest endpoint in bounded batches. Local capture continues even when upload is
disabled or temporarily fails.

Pair this pub.dev package with
[`@vigiljs/express` on npm](https://www.npmjs.com/package/@vigiljs/express):
its `vigilIngestHandler` receives these version 1 JSON batches. The recommended
Flutter [`vigil` package](https://pub.dev/packages/vigil) already exports this
uploader alongside the Dio interceptor and inspector UI.

## Installation

```sh
dart pub add vigil_backend vigil_core
```

## Usage

```dart
import 'package:vigil_backend/vigil_backend.dart';
import 'package:vigil_core/vigil_core.dart';

Future<void> main() async {
  Vigil.instance.init();

  final connection = VigilBackendConnection.connect(
    config: VigilBackendConfig(
      endpoint: Uri.parse('https://dev-api.example.com/vigil/ingest'),
      ingestKey: const String.fromEnvironment('VIGIL_INGEST_KEY'),
      batchSize: 20,
      maxQueueSize: 500,
      clientInfo: const {'app': 'example'},
    ),
  );

  // Dispose the connection with the component or application that owns it.
  await connection.dispose();
}
```

Completed and failed calls are queued by default. A batch is removed only after
a successful `2xx` response; otherwise it remains for a later flush. The queue
is memory-only and drops its oldest entries when `maxQueueSize` is reached.
Uploading captured calls is separate from backend diagnostics. To show a
backend error message and stack in the Flutter Debug tab, use
`vigilMiddleware` and `vigilErrorHandler` from `@vigiljs/express` with a
matching development debug key. Upload does not retrieve general server logs.

The ingest key is sent in `Vigil-Ingest-Key`. A key embedded in a client app is
not a secret, so combine it with development-only enablement, TLS, rate limits,
and appropriate backend authentication when the endpoint is remotely reachable.
