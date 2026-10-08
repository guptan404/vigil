Vigil is the recommended all-in-one Flutter package for inspecting Dio network
traffic during development. It exports the core capture API, Dio interceptor,
Flutter inspector UI, and optional backend uploader.

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
Pass the same development key to your Express `debugKey` setting and the
Flutter `VIGIL_DEBUG_KEY` Dart define to see gated server diagnostics. The Debug
tab also shows captured client failure details when no server payload arrives.

## Optional backend upload

```dart
final connection = VigilBackendConnection.connect(
  config: VigilBackendConfig(
    endpoint: Uri.parse('https://dev-api.example.com/vigil/ingest'),
    ingestKey: const String.fromEnvironment('VIGIL_INGEST_KEY'),
  ),
);

// Attempt a final batch and release resources when the owner is disposed.
await connection.dispose();
```

See the [repository README](https://github.com/guptan404/vigil#readme) for the
Express bridge, security guidance, CORS requirements, and full examples.
