import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vigil_core/vigil_core.dart';
import 'package:vigil_ui/vigil_ui.dart';

void main() {
  testWidgets('overlay hides launcher button by default', (tester) async {
    Vigil.instance.init();

    await tester.pumpWidget(
      const MaterialApp(
        home: VigilOverlay(
          enabled: true,
          enableShake: false,
          child: Scaffold(body: Text('App')),
        ),
      ),
    );

    expect(find.byIcon(Icons.network_check), findsNothing);
  });

  testWidgets('overlay opens inspector from optional launcher button',
      (tester) async {
    Vigil.instance.init();

    await tester.pumpWidget(
      const MaterialApp(
        home: VigilOverlay(
          enabled: true,
          enableShake: false,
          showFloatingButton: true,
          child: Scaffold(body: Text('App')),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.network_check));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vigil'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('inspector background covers system safe-area insets',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(
      top: 44,
      bottom: 34,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    Vigil.instance.init();

    await tester.pumpWidget(
      const MaterialApp(
        home: VigilOverlay(
          enableShake: false,
          showFloatingButton: true,
          child: ColoredBox(color: Colors.pink),
        ),
      ),
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final inspector = find.byType(Scaffold).last;
    expect(tester.getTopLeft(inspector), Offset.zero);
    expect(tester.getBottomRight(inspector), const Offset(390, 844));
  });

  testWidgets('overlay opens inspector from shake', (tester) async {
    Vigil.instance.init();
    final shakeEvents = StreamController<UserAccelerometerEvent>();
    addTearDown(shakeEvents.close);

    await tester.pumpWidget(
      MaterialApp(
        home: VigilOverlay(
          enabled: true,
          shakeEvents: shakeEvents.stream,
          child: const Scaffold(body: Text('App')),
        ),
      ),
    );

    shakeEvents.add(UserAccelerometerEvent(22, 0, 0, DateTime.now()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vigil'), findsWidgets);
  });

  testWidgets('overlay works from MaterialApp builder', (tester) async {
    Vigil.instance.init();

    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Text('App')),
        builder: (context, child) => VigilOverlay(
          enabled: true,
          enableShake: false,
          showFloatingButton: true,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.network_check));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Vigil'), findsWidgets);
  });

  testWidgets('inspector renders captured calls', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vigil = Vigil.instance..init();
    final trace = VigilTraceContext.generate();
    final id = vigil.startCall(
      VigilHttpRequest(
        method: 'GET',
        uri: Uri.parse(
          'https://example.com/api/v3/balance/all?walletId=abc-123'
          '&page=1&limit=150&hideZeroBalances=true&currency=USD'
          '&bypassCache=false&sortBy=total&sortOrder=desc',
        ),
        headers: {'traceparent': trace.toHeader()},
        body: VigilBodySummary.empty,
        timestamp: DateTime.now(),
        traceContext: trace,
      ),
    );
    vigil.completeCall(
      id,
      VigilHttpResponse(
        statusCode: 200,
        headers: const {},
        body: const VigilBodySummary(
          kind: VigilBodyKind.json,
          text: '{"ok":true}',
        ),
        timestamp: DateTime.now(),
        serverTimings: const [VigilServerTiming(name: 'db', duration: 4)],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: VigilInspector(vigil: vigil)));

    expect(find.textContaining('example.com'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);

    await tester.tap(find.textContaining('/api/v3/balance/all'));
    await tester.pumpAndSettle();

    expect(find.text('Request details'), findsOneWidget);
    expect(find.text('/api/v3/balance/all'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Payload'), findsNothing);

    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();

    expect(find.text('URL'), findsOneWidget);
    expect(find.textContaining('walletId=abc-123'), findsOneWidget);
  });

  testWidgets('inspector searches and filters captured calls', (tester) async {
    final vigil = Vigil.instance..init();
    final startedAt = DateTime.now();

    String start(String method, String path) {
      final trace = VigilTraceContext.generate();
      return vigil.startCall(
        VigilHttpRequest(
          method: method,
          uri: Uri.parse('https://example.com$path'),
          headers: {'traceparent': trace.toHeader()},
          body: VigilBodySummary.empty,
          timestamp: startedAt,
          traceContext: trace,
        ),
      );
    }

    final usersId = start('GET', '/users/profile');
    vigil.completeCall(
      usersId,
      VigilHttpResponse(
        statusCode: 200,
        headers: const {},
        body: VigilBodySummary.empty,
        timestamp: startedAt.add(const Duration(milliseconds: 180)),
      ),
    );

    final authId = start('POST', '/api/auth/refresh');
    vigil.failCall(
      authId,
      VigilHttpError(
        message: 'Unauthorized',
        timestamp: startedAt.add(const Duration(milliseconds: 420)),
      ),
      response: VigilHttpResponse(
        statusCode: 401,
        headers: const {},
        body: VigilBodySummary.empty,
        timestamp: startedAt.add(const Duration(milliseconds: 420)),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: VigilInspector(vigil: vigil)));

    expect(find.text('/users/profile'), findsOneWidget);
    expect(find.text('/api/auth/refresh'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Failed'));
    await tester.pump();

    expect(find.text('/users/profile'), findsNothing);
    expect(find.text('/api/auth/refresh'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.enterText(find.byType(TextField), 'users');
    await tester.pump();

    expect(find.text('/users/profile'), findsOneWidget);
    expect(find.text('/api/auth/refresh'), findsNothing);
  });

  testWidgets('debug tab shows a transport failure without a response',
      (tester) async {
    final vigil = Vigil.instance..init();
    final id = vigil.startCall(
      VigilHttpRequest(
        method: 'GET',
        uri: Uri.parse('https://example.com/offline'),
        headers: const {},
        body: VigilBodySummary.empty,
        timestamp: DateTime.now(),
        traceContext: VigilTraceContext.generate(),
      ),
    );
    vigil.failCall(
      id,
      VigilHttpError(
        message: 'Connection refused',
        type: 'connectionError',
        timestamp: DateTime.now(),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: VigilInspector(vigil: vigil)));
    await tester.tap(find.text('/offline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();

    expect(find.text('No server response'), findsOneWidget);
    expect(find.text('Connection refused'), findsOneWidget);
    expect(find.text('No gated server debug payload received'), findsOneWidget);
  });

  testWidgets('debug tab shows an HTTP failure without a gated header',
      (tester) async {
    final vigil = Vigil.instance..init();
    final id = vigil.startCall(
      VigilHttpRequest(
        method: 'GET',
        uri: Uri.parse('https://example.com/unavailable'),
        headers: const {},
        body: VigilBodySummary.empty,
        timestamp: DateTime.now(),
        traceContext: VigilTraceContext.generate(),
      ),
    );
    vigil.failCall(
      id,
      VigilHttpError(message: 'Bad response', timestamp: DateTime.now()),
      response: VigilHttpResponse(
        statusCode: 503,
        headers: const {},
        body: const VigilBodySummary(
          kind: VigilBodyKind.json,
          text: '{"message":"Service unavailable"}',
        ),
        timestamp: DateTime.now(),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: VigilInspector(vigil: vigil)));
    await tester.tap(find.text('/unavailable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();

    expect(find.text('503'), findsWidgets);
    expect(find.textContaining('Service unavailable'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('No gated server debug payload received'), findsOneWidget);
  });

  testWidgets('debug tab shows gated backend diagnostics', (tester) async {
    final vigil = Vigil.instance..init();
    final id = vigil.startCall(
      VigilHttpRequest(
        method: 'GET',
        uri: Uri.parse('https://example.com/broken'),
        headers: const {},
        body: VigilBodySummary.empty,
        timestamp: DateTime.now(),
        traceContext: VigilTraceContext.generate(),
      ),
    );
    vigil.failCall(
      id,
      VigilHttpError(message: 'Bad response', timestamp: DateTime.now()),
      response: VigilHttpResponse(
        statusCode: 500,
        headers: const {},
        body: VigilBodySummary.empty,
        timestamp: DateTime.now(),
        serverDebug: const VigilDebugPayload(
          error: 'backend exploded',
          stack: 'at routeHandler',
        ),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: VigilInspector(vigil: vigil)));
    await tester.tap(find.text('/broken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('backend exploded'), findsOneWidget);
    expect(find.text('at routeHandler'), findsOneWidget);
  });

  testWidgets('copies bodies and a complete request lifecycle', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final vigil = Vigil.instance..init();
    final startedAt = DateTime.utc(2026, 10, 3, 8, 30);
    final trace = VigilTraceContext.generate();
    const requestBody = '{"username":"vigil"}';
    const responseBody = '{"authenticated":true}';
    final id = vigil.startCall(
      VigilHttpRequest(
        method: 'POST',
        uri: Uri.parse('https://example.com/api/lifecycle?source=test'),
        headers: const {'content-type': 'application/json'},
        body: const VigilBodySummary(
          kind: VigilBodyKind.json,
          text: requestBody,
          byteLength: 20,
          contentType: 'application/json',
        ),
        timestamp: startedAt,
        traceContext: trace,
      ),
    );
    vigil.completeCall(
      id,
      VigilHttpResponse(
        statusCode: 201,
        statusMessage: 'Created',
        headers: const {'content-type': 'application/json'},
        body: const VigilBodySummary(
          kind: VigilBodyKind.json,
          text: responseBody,
          byteLength: 22,
          contentType: 'application/json',
        ),
        timestamp: startedAt.add(const Duration(milliseconds: 125)),
        serverTimings: const [
          VigilServerTiming(name: 'db', duration: 12.5),
        ],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: VigilInspector(vigil: vigil)));
    await tester.tap(find.textContaining('/api/lifecycle'));
    await tester.pumpAndSettle();

    expect(find.text('Share lifecycle'), findsOneWidget);

    await tester.tap(find.text('Copy lifecycle'));
    await tester.pump();

    final lifecycle = jsonDecode(clipboardText!) as Map<String, Object?>;
    expect(lifecycle['format'], 'vigil-request-lifecycle');
    expect(
      (lifecycle['request'] as Map<String, Object?>)['body'],
      containsPair('text', requestBody),
    );
    expect(
      (lifecycle['response'] as Map<String, Object?>)['body'],
      containsPair('text', responseBody),
    );
    expect(lifecycle['durationMs'], 125);

    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy body'));
    await tester.pump();
    expect(clipboardText, requestBody);

    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy body'));
    await tester.pump();
    expect(clipboardText, responseBody);
  });
}
