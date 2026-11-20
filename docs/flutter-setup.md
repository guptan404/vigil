# Flutter frontend setup

The umbrella `vigil` package exports capture, Dio integration, UI, and upload.
The frontend can work alone; [Express setup](backend-setup.md) adds desktop
monitoring, backend timing/logs, and server simulation.

## Install the matching Git packages

Use a Flutter SDK with Dart 3.9+ for this Git workspace. Add these entries to
your app's `pubspec.yaml`. The overrides ensure the umbrella package does not
resolve its internal dependencies to older registry releases.

```yaml
dependencies:
  flutter:
    sdk: flutter
  dio: ^5.0.0
  vigil:
    git:
      url: https://github.com/guptan404/vigil.git
      ref: feature/debugging-workflows
      path: dart/vigil

dependency_overrides:
  vigil_core:
    git:
      url: https://github.com/guptan404/vigil.git
      ref: feature/debugging-workflows
      path: dart/vigil_core
  vigil_dio:
    git:
      url: https://github.com/guptan404/vigil.git
      ref: feature/debugging-workflows
      path: dart/vigil_dio
  vigil_ui:
    git:
      url: https://github.com/guptan404/vigil.git
      ref: feature/debugging-workflows
      path: dart/vigil_ui
  vigil_backend:
    git:
      url: https://github.com/guptan404/vigil.git
      ref: feature/debugging-workflows
      path: dart/vigil_backend
```

Run `flutter pub get`. Keep all five refs identical. Commit your app's lockfile
and inspect its Git `resolved-ref` to verify the revision being built. To
deliberately advance a branch dependency, run
`flutter pub upgrade vigil vigil_core vigil_dio vigil_ui vigil_backend`.
For a fixed integration, replace every branch ref with the same commit SHA.

## Complete application

This small `lib/main.dart` connects to the backend guide's `/example` route.
It initializes capture once, shares a mock controller between transport and
UI, provides replay, and starts upload before the first request. In an existing
app, attach the interceptor to your authorized Dio client and own these
objects for that client's lifetime.

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vigil/vigil.dart';

const appEnvironment = String.fromEnvironment('APP_ENV', defaultValue: 'production');
const vigilEnabled = appEnvironment == 'development' || appEnvironment == 'test';
const apiOrigin = String.fromEnvironment(
  'VIGIL_API_ORIGIN', defaultValue: 'http://127.0.0.1:4010',
);
const ingestKey = String.fromEnvironment('VIGIL_INGEST_KEY');
const debugKey = String.fromEnvironment('VIGIL_DEBUG_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Vigil.instance.init(config: VigilConfig(
    enabled: vigilEnabled,
    debugKey: debugKey.isEmpty ? null : debugKey,
    session: VigilSession.create(deviceName: 'QA device'),
    maskHeaders: {
      ...const VigilConfig().maskHeaders,
      'x-api-key', 'vigil-ingest-key',
    },
    maskBodyFields: {
      ...const VigilConfig().maskBodyFields,
      'accesstoken', 'refreshtoken', 'pin',
    },
  ));
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});
  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final VigilMockController mocks;
  late final Dio dio;
  late final VigilDioReplay replay;
  late final VigilBackendConnection connection;
  String result = 'Send a request, then open Vigil.';

  @override
  void initState() {
    super.initState();
    mocks = VigilMockController(allowedOrigins: {apiOrigin});
    dio = Dio(BaseOptions(
      baseUrl: apiOrigin,
      receiveTimeout: const Duration(seconds: 5),
    ))..interceptors.add(VigilDioInterceptor(mocks: mocks));
    replay = VigilDioReplay(dio, allowedOrigins: {apiOrigin});
    connection = VigilBackendConnection.connect(config: VigilBackendConfig(
      enabled: vigilEnabled && ingestKey.isNotEmpty,
      endpoint: Uri.parse('$apiOrigin/vigil/ingest'),
      ingestKey: ingestKey,
      includePendingCalls: true,
      flushInterval: const Duration(seconds: 1),
      clientInfo: const {'app': 'example', 'environment': appEnvironment},
    ));
  }

  Future<void> sendRequest() async {
    String nextResult;
    try {
      final response = await dio.get<Object?>('/example');
      nextResult = '${response.statusCode}: ${response.data}';
    } on DioException catch (error) {
      nextResult = '${error.response?.statusCode ?? error.type}: '
          '${error.response?.data ?? error.message}';
    }
    if (mounted) setState(() => result = nextResult);
  }

  @override
  void dispose() {
    unawaited(connection.dispose(flushPending: false));
    dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: VigilOverlay(
      enabled: vigilEnabled,
      showFloatingButton: true,
      replay: replay.send,
      mocks: mocks,
      child: Scaffold(
        appBar: AppBar(title: const Text('Vigil example')),
        body: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(result),
            FilledButton(onPressed: sendRequest, child: const Text('Send request')),
          ],
        )),
      ),
    ),
  );
}
```

For Flutter Web, use a fixed dev port matching backend CORS:

```sh
flutter run -d chrome --web-port=4020 \
  --dart-define=APP_ENV=development \
  --dart-define=VIGIL_API_ORIGIN=http://127.0.0.1:4010 \
  --dart-define=VIGIL_INGEST_KEY=replace-with-server-ingest-key \
  --dart-define=VIGIL_DEBUG_KEY=replace-with-server-debug-key
```

Use your test values from the backend configuration, not the literal
placeholders above. `VIGIL_DEBUG_KEY` is optional for session-only server
simulation; omit it if you do not need backend diagnostics. The ingest key is
needed to upload to a key-protected handler. Never add the inspector or control
key to this command or your app. See the [four-key table](README.md#the-four-keys).

`APP_ENV` and the Dart define names are application conventions, not automatic
SDK settings. The example explicitly passes them into capture, upload, and UI.
The default environment disables Vigil. If your application uses `kDebugMode`
instead, remember it is false in a release build, including a release QA build.
Enable only deliberately configured development/test builds. Rebuild after
changing compile-time defines; a running binary cannot read server SSM updates.

## Device addresses and CORS

| Runtime | Address for a backend running on your development computer |
| --- | --- |
| Flutter Web / desktop / iOS simulator | `http://127.0.0.1:4010` |
| Standard Android emulator | `http://10.0.2.2:4010` |
| Physical device | Computer's reachable LAN address, or a reachable HTTPS test host |

On a phone, `localhost` means the phone. Bind the server to a reachable
interface when needed. Prefer HTTPS; if local HTTP needs platform allowances,
scope them to debug/test configuration instead of disabling TLS validation.
An HTTPS web app cannot call a plain HTTP backend due to mixed-content rules.

Flutter Web requires the server to allow `traceparent`, `Vigil-Key`,
`Vigil-Ingest-Key`, `Vigil-Session-Id`, and `Vigil-Device-Type` in request headers
and expose `Server-Timing`, `traceparent`, `Vigil-Debug`, and `Vigil-Simulation`
in response headers. Include your app's normal auth/content headers too.

## Capture, masking, and identity

Initialize Vigil before creating the interceptor and uploader. Do not reinitialize
per request: each initialization creates a fresh device session unless supplied
through `VigilConfig.session`. The interceptor automatically sends the matching
session ID/device type and the uploader sends the same identity. Do not set a
different `clientInfo.sessionId`; canonical session fields are owned by Vigil.

Copy the ID from the Flutter inspector or read `Vigil.instance.session.id`.
Device type is detected from the runtime, not a hardware identifier. Clearing
calls retains the identity; reinitializing/new app runs rotate it. A custom
`VigilSession.create(sessionId: ...)` accepts 1–128 ASCII characters matching
`[A-Za-z0-9][A-Za-z0-9._-]{0,127}`. Old rules do not follow a new ID.

Capture defaults to 500 calls with up to 64 KiB per body preview.
Masking changes recorded previews, not the real request's credentials or body.
Custom masking sets **replace defaults**, so extend the defaults as above.
Names are lowercase; `accessToken` needs `accesstoken`, while `access_token`
is a different key. Review query masking, URL paths, headers, and application
payloads before exporting. Paths and unconfigured fields can still contain
sensitive data. Exclude sensitive endpoints using your application's capture
integration when masking is insufficient.

## Upload lifecycle

Keep the connection alive for the recording lifetime. It uses a separate HTTP
client, so uploads do not recursively become captured Dio calls. By default it
uploads completed/failed calls every five seconds in batches of 20, keeps up
to 500 queued calls, and times out uploads after eight seconds. The example
uses a one-second interval and `includePendingCalls: true` so the desktop sees
request starts and later updates the same request on completion.

`await connection.flush()` attempts the next batch, not an unlimited drain.
Inspect `connection.queuedCount` when investigating upload issues. Local capture
works during an ingest outage; retries happen on a later flush, and a full
queue drops older entries. Queues do not survive process termination.
Await `connection.dispose()` at an async lifecycle boundary when a final flush
is wanted; the widget example disposes without a final flush during teardown.

## Optional replay and local mocks

Replay requires a callback: pass `VigilDioReplay(dio, allowedOrigins: {...}).send`
to `VigilOverlay` or `VigilInspector`. Use your real development Dio client so
authentication interceptors apply. The editor supports method, same-origin
URL/query, extra headers, and JSON body changes. Redacted/reserved headers
cannot be replayed as usable credentials. Confirmation is required for methods
that can change data. A replay sends a real API request unless a local mock
handles it. The helper disables redirects where Dio controls them; Flutter Web
redirects remain controlled by the browser.

For local mocks, pass the **same** `VigilMockController` to interceptor and UI.
The editor supports JSON response, timeout, connection error, and delay. Rules
match an allowed origin plus exact method/path, ignore query strings, persist
in memory until removed/restart, and have no one-shot count. Local delays are
capped at 30 seconds. To add a rule in code:

```dart
mocks.put(VigilMockRule(
  method: 'GET',
  path: '/example',
  effect: VigilMockEffect.response,
  statusCode: 200,
  jsonBody: '{"user":{"id":"mock-user"}}',
));
```

Remove local rules before testing Express failure points, so the request
reaches backend code. Follow the [workflow guide](debugging-workflows.md) to
save/compare calls, connect a desktop session, and enable backend failures.
