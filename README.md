# Vigil

Vigil is a Flutter-first network inspector with an optional Node/Express bridge.
The Phase 1 vertical slice captures Dio requests in Flutter, correlates them with
an Express backend using `traceparent`, renders `Server-Timing`, and exposes gated
debug diagnostics through `Vigil-Debug`.

## Workspace

- `dart/vigil_core`: pure Dart models, storage, parsers, masking, cURL export
- `dart/vigil_backend`: optional backend upload connector for captured calls
- `dart/vigil_dio`: Dio interceptor
- `dart/vigil_ui`: compact Flutter overlay inspector
- `dart/vigil`: umbrella package
- `node/packages/core`: shared Node protocol helpers
- `node/packages/express`: Express middleware and error handler
- `example/flutter_app`: sample Flutter app
- `example/node_server`: sample Express server

## Local Checks

```sh
cd dart/vigil_core && dart test
cd ../vigil_backend && dart test
cd ../vigil_dio && flutter test
cd ../vigil_ui && flutter test
cd ../../node && npm test
```

## Backend Upload

Flutter/Dart apps can opt into backend upload without changing local capture:

```dart
final connection = VigilBackendConnection.connect(
  config: VigilBackendConfig(
    endpoint: Uri.parse('http://localhost:4010/vigil/ingest'),
    ingestKey: 'dev-vigil',
  ),
);
```

Express backends can receive those batches with a gated ingest route:

```ts
const sink = createMemoryVigilSink();

app.use(express.json());
app.post('/vigil/ingest', vigilIngestHandler({
  enabled: process.env.NODE_ENV !== 'production',
  ingestKey: 'dev-vigil',
  onBatch: sink.onBatch,
}));
```
# vigil
