# vigil_dio

A Dio interceptor that records requests, responses, and failures in Vigil. It
adds W3C `traceparent`, parses backend `Server-Timing`, and decodes gated
`Vigil-Debug` error diagnostics.

For an in-app inspector with Copy cURL and lifecycle sharing, use the
[`vigil` Flutter package](https://pub.dev/packages/vigil). Pair the interceptor
with [`@vigiljs/express` on npm](https://www.npmjs.com/package/@vigiljs/express)
to see correlated backend timing and per-request error message, stack, and
context in its Debug tab. This does not retrieve arbitrary backend logs.

## Installation

```sh
flutter pub add vigil_dio vigil_core dio
```

## Usage

```dart
import 'package:dio/dio.dart';
import 'package:vigil_core/vigil_core.dart';
import 'package:vigil_dio/vigil_dio.dart';

void main() {
  Vigil.instance.init(
    config: const VigilConfig(
      debugKey: String.fromEnvironment('VIGIL_DEBUG_KEY'),
    ),
  );

  final dio = Dio()..interceptors.add(VigilDioInterceptor());
}
```

Add the interceptor once to each Dio instance. Configure masking through
`VigilConfig` before making requests. Streamed bodies are marked unavailable
instead of being consumed.

The debug key is sent as `Vigil-Key`; it is separate from the ingest key used by
`vigil_backend`. Values compiled into an app are recoverable, so use this only
as a development gate and keep backend diagnostics disabled in production.

For Flutter Web, expose `Server-Timing`, `traceparent`, and `Vigil-Debug` through
your backend CORS configuration.
