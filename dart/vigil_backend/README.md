An optional uploader for sending calls captured by `vigil_core` to a backend
ingest endpoint in bounded batches. Local capture continues even when upload is
disabled or temporarily fails.

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

The ingest key is sent in `Vigil-Ingest-Key`. A key embedded in a client app is
not a secret, so combine it with development-only enablement, TLS, rate limits,
and appropriate backend authentication when the endpoint is remotely reachable.
