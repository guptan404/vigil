import 'dart:async';

import 'package:flutter/material.dart';
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

  testWidgets('overlay opens inspector from optional launcher button', (tester) async {
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
    final vigil = Vigil.instance..init();
    final trace = VigilTraceContext.generate();
    final id = vigil.startCall(
      VigilHttpRequest(
        method: 'GET',
        uri: Uri.parse('https://example.com/ok'),
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
  });
}
