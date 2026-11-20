import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vigil_core/vigil_core.dart';
import 'package:vigil_ui/vigil_ui.dart';

void main() {
  testWidgets('searches JSON by field and compares completed requests',
      (tester) async {
    tester.view.physicalSize = const Size(1150, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vigil = Vigil.instance..init();
    final time = DateTime(2026, 1, 1);
    for (final (path, status, body) in [
      ('/earlier', 201, '{"nested":{"field":1},"unrelated":true}'),
      ('/later', 202, '{"nested":{"field":2},"unrelated":true}'),
    ]) {
      final id = vigil.startCall(VigilHttpRequest(
        method: 'PATCH',
        uri: Uri.parse('https://example.com$path'),
        headers: const {},
        body: VigilBodySummary.empty,
        timestamp: time,
        traceContext: VigilTraceContext.generate(),
      ));
      vigil.completeCall(
          id,
          VigilHttpResponse(
            statusCode: status,
            headers: const {},
            body: VigilBodySummary(kind: VigilBodyKind.json, text: body),
            timestamp: time.add(const Duration(milliseconds: 250)),
          ));
    }
    await tester.pumpWidget(MaterialApp(home: VigilInspector(vigil: vigil)));

    await tester.tap(find.widgetWithText(Tab, 'Response'));
    await tester.pumpAndSettle();
    final search =
        find.widgetWithText(TextField, 'Search JSON fields or values');
    await tester.ensureVisible(search);
    await tester.enterText(search, 'field');
    await tester.pumpAndSettle();
    expect(find.text('field: 2'), findsOneWidget);
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final field = find
        .ancestor(of: find.text('field: 2'), matching: find.byType(Row))
        .first;
    await tester.tap(
        find.descendant(of: field, matching: find.byTooltip('Copy JSON path')));
    await tester.pump();
    expect(copied, r'$["nested"]["field"]');
    expect(find.text('unrelated: true'), findsNothing);

    // Scrolling the response to the JSON search collapsed the header to
    // icon-only actions.
    expect(find.byTooltip('Expand header'), findsOneWidget);
    await tester.tap(find.byTooltip('Compare'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('PATCH /earlier'));
    await tester.pumpAndSettle();
    expect(find.text('Request comparison'), findsOneWidget);
    expect(find.text('Response body["nested"]["field"]'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Advanced filters'));
    await tester.pumpAndSettle();
    final minimum = find.widgetWithText(TextFormField, 'Minimum status');
    await tester.enterText(minimum, '202');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('/earlier'), findsNothing);
    expect(find.byTooltip('Advanced filters active'), findsOneWidget);
  });

  testWidgets('reopens a saved session after the live recorder is cleared',
      (tester) async {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
    final vigil = Vigil.instance..init();
    final time = DateTime(2026, 1, 1);
    final id = vigil.startCall(VigilHttpRequest(
      method: 'GET',
      uri: Uri.parse('https://example.com/checkout'),
      headers: const {},
      body: VigilBodySummary.empty,
      timestamp: time,
      traceContext: VigilTraceContext.generate(),
    ));
    vigil.completeCall(
        id,
        VigilHttpResponse(
          statusCode: 429,
          headers: const {},
          body: VigilBodySummary.empty,
          timestamp: time.add(const Duration(milliseconds: 20)),
        ));

    await tester.pumpWidget(MaterialApp(home: VigilInspector(vigil: vigil)));
    Future<void> openSessions() async {
      await tester.tap(find.byTooltip('Inspector tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Debug sessions'));
      await tester.pumpAndSettle();
    }

    await openSessions();
    await tester.tap(find.text('Save current capture'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Session name'), 'Checkout test');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    vigil.clear();
    await tester.pumpAndSettle();
    await openSessions();
    await tester.tap(find.text('Checkout test'));
    await tester.pumpAndSettle();
    expect(find.text('/checkout'), findsOneWidget);
    expect(find.text('429'), findsOneWidget);
  });

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
    // The trigger time is visible on phone-width dashboards.
    expect(find.text(_clock(vigil.calls.single.startedAt)), findsOneWidget);

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
    await _scrollDetailTo(
        tester, find.text('No gated server debug payload received'));
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
    await _scrollDetailTo(tester, find.textContaining('Service unavailable'));
    expect(find.textContaining('Service unavailable'), findsOneWidget);
    await _scrollDetailTo(
        tester, find.text('No gated server debug payload received'));
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

    // Selective copy actions in the header copy readable, indented content.
    await tester.tap(find.text('Copy endpoint'));
    await tester.pump();
    expect(clipboardText, 'https://example.com/api/lifecycle?source=test');

    await tester.tap(find.text('Copy request'));
    await tester.pump();
    expect(clipboardText, '{\n  "username": "vigil"\n}');

    await tester.tap(find.text('Copy response'));
    await tester.pump();
    expect(clipboardText, '{\n  "authenticated": true\n}');

    // One action copies the endpoint, request, and response together.
    await tester.tap(find.text('Copy all'));
    await tester.pump();
    expect(
      clipboardText,
      'Endpoint\n'
      'POST https://example.com/api/lifecycle?source=test\n'
      '\n'
      'Request\n'
      '{\n  "username": "vigil"\n}\n'
      '\n'
      'Response (201 Created)\n'
      '{\n  "authenticated": true\n}',
    );

    await tester.tap(find.widgetWithText(Tab, 'Request'));
    await tester.pumpAndSettle();
    await _scrollDetailTo(tester, find.text('Copy body'));
    await tester.tap(find.text('Copy body'));
    await tester.pump();
    expect(clipboardText, '{\n  "username": "vigil"\n}');

    await tester.tap(find.widgetWithText(Tab, 'Response'));
    await tester.pumpAndSettle();
    await _scrollDetailTo(tester, find.text('Copy body'));
    await tester.tap(find.text('Copy body'));
    await tester.pump();
    expect(clipboardText, '{\n  "authenticated": true\n}');
  });

  testWidgets('copy options hide disabled copy actions', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vigil = Vigil.instance..init();
    _recordJsonCall(vigil, path: '/api/options', responseFields: 2);

    await tester.pumpWidget(MaterialApp(
      home: VigilInspector(
        vigil: vigil,
        copyOptions: const VigilCopyOptions(
          endpoint: false,
          responseContent: false,
        ),
      ),
    ));
    await tester.tap(find.textContaining('/api/options'));
    await tester.pumpAndSettle();

    expect(find.text('Copy endpoint'), findsNothing);
    expect(find.text('Copy request'), findsOneWidget);
    expect(find.text('Copy response'), findsNothing);

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
    // Copy all leaves out the parts that are disabled.
    await tester.tap(find.text('Copy all'));
    await tester.pump();
    expect(clipboardText, 'Request\n{\n  "username": "vigil"\n}');

    await tester.tap(find.widgetWithText(Tab, 'Request'));
    await tester.pumpAndSettle();
    expect(find.text('Copy URL'), findsNothing);
    await _scrollDetailTo(tester, find.text('Copy body'));
    expect(find.text('Copy body'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Response'));
    await tester.pumpAndSettle();
    await _scrollDetailTo(tester, find.text('Headers'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Copy body'), findsNothing);
  });

  testWidgets('copy options can disable every selective copy action',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vigil = Vigil.instance..init();
    _recordJsonCall(vigil, path: '/api/none', responseFields: 2);

    await tester.pumpWidget(MaterialApp(
      home: VigilInspector(
        vigil: vigil,
        copyOptions: const VigilCopyOptions.none(),
      ),
    ));
    await tester.tap(find.textContaining('/api/none'));
    await tester.pumpAndSettle();

    expect(find.text('Copy endpoint'), findsNothing);
    expect(find.text('Copy request'), findsNothing);
    expect(find.text('Copy response'), findsNothing);
    expect(find.text('Copy all'), findsNothing);
    expect(find.text('Copy cURL'), findsOneWidget);
  });

  testWidgets('copy options can hide only the copy all action', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vigil = Vigil.instance..init();
    _recordJsonCall(vigil, path: '/api/no-all', responseFields: 2);

    await tester.pumpWidget(MaterialApp(
      home: VigilInspector(
        vigil: vigil,
        copyOptions: const VigilCopyOptions(all: false),
      ),
    ));
    await tester.tap(find.textContaining('/api/no-all'));
    await tester.pumpAndSettle();

    expect(find.text('Copy all'), findsNothing);
    expect(find.text('Copy endpoint'), findsOneWidget);
    expect(find.text('Copy request'), findsOneWidget);
    expect(find.text('Copy response'), findsOneWidget);
  });

  testWidgets('detail header collapses to icons on scroll and re-expands',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vigil = Vigil.instance..init();
    _recordJsonCall(vigil, path: '/api/long', responseFields: 40);

    await tester.pumpWidget(MaterialApp(home: VigilInspector(vigil: vigil)));
    await tester.tap(find.textContaining('/api/long'));
    await tester.pumpAndSettle();

    // Expanded: labelled buttons.
    expect(find.text('Copy lifecycle'), findsOneWidget);
    expect(find.byTooltip('Collapse header'), findsOneWidget);
    expect(find.byTooltip('Expand header'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'Response'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();

    // Collapsed: icon-only actions with tooltips and an expand button.
    expect(find.text('Copy lifecycle'), findsNothing);
    expect(find.byTooltip('Copy lifecycle'), findsOneWidget);
    expect(find.byTooltip('Copy endpoint'), findsOneWidget);
    expect(find.byTooltip('Copy request'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.byTooltip('Copy all'), findsOneWidget);
    expect(find.text('/api/long'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand header'));
    await tester.pumpAndSettle();
    expect(find.text('Copy lifecycle'), findsOneWidget);
    expect(find.byTooltip('Expand header'), findsNothing);

    // The header can also be collapsed manually.
    await tester.tap(find.byTooltip('Collapse header'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand header'), findsOneWidget);
  });
}

String _clock(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// Scrolls the visible request-detail tab until [finder] is on screen.
Future<void> _scrollDetailTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void _recordJsonCall(
  Vigil vigil, {
  required String path,
  required int responseFields,
}) {
  final startedAt = DateTime.utc(2026, 10, 3, 8, 30);
  final id = vigil.startCall(
    VigilHttpRequest(
      method: 'POST',
      uri: Uri.parse('https://example.com$path'),
      headers: const {'content-type': 'application/json'},
      body: const VigilBodySummary(
        kind: VigilBodyKind.json,
        text: '{"username":"vigil"}',
        contentType: 'application/json',
      ),
      timestamp: startedAt,
      traceContext: VigilTraceContext.generate(),
    ),
  );
  vigil.completeCall(
    id,
    VigilHttpResponse(
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: VigilBodySummary(
        kind: VigilBodyKind.json,
        text: jsonEncode({
          for (var i = 0; i < responseFields; i++) 'field$i': 'value $i',
        }),
        contentType: 'application/json',
      ),
      timestamp: startedAt.add(const Duration(milliseconds: 80)),
    ),
  );
}
