import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vigil_backend/vigil_backend.dart';
import 'package:vigil_core/vigil_core.dart';

void main() {
  test('uploads completed calls as a JSON batch', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{"ok":true}', 202);
    });
    final vigil = Vigil.instance..init();
    final connection = VigilBackendConnection(
      config: VigilBackendConfig(
        endpoint: Uri.parse('https://collector.example.com/vigil'),
        flushInterval: Duration.zero,
        clientInfo: const {'app': 'demo'},
      ),
      vigil: vigil,
      client: client,
    )..start();

    final id = vigil.startCall(_request('/ok'));
    vigil.completeCall(id, _response(200));
    await _settleEvents();

    expect(connection.queuedCount, 1);

    await connection.flush();

    expect(connection.queuedCount, 0);
    expect(requests, hasLength(1));
    expect(requests.single.headers['Content-Type'], 'application/json');

    final body = jsonDecode(requests.single.body) as Map<String, Object?>;
    expect(body['version'], 1);
    expect(body['client'], {'app': 'demo'});

    final calls = body['calls'] as List<Object?>;
    final call = calls.single as Map<String, Object?>;
    expect(call['state'], 'completed');
    expect((call['request'] as Map<String, Object?>)['url'],
        'https://api.example.com/ok');
    expect((call['response'] as Map<String, Object?>)['statusCode'], 200);

    await connection.dispose(flushPending: false);
  });

  test('adds ingest key and keeps queue when upload fails', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('nope', 500);
    });
    final vigil = Vigil.instance..init();
    final connection = VigilBackendConnection(
      config: VigilBackendConfig(
        endpoint: Uri.parse('https://collector.example.com/vigil'),
        flushInterval: Duration.zero,
        ingestKey: 'dev-key',
      ),
      vigil: vigil,
      client: client,
    )..start();

    final id = vigil.startCall(_request('/error'));
    vigil.failCall(
      id,
      VigilHttpError(message: 'boom', timestamp: DateTime.now()),
      response: _response(500),
    );
    await _settleEvents();

    await connection.flush();

    expect(connection.queuedCount, 1);
    expect(requests.single.headers['Vigil-Ingest-Key'], 'dev-key');

    await connection.dispose(flushPending: false);
  });

  test('evicts oldest calls when queue exceeds maxQueueSize', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final calls = body['calls'] as List<Object?>;
      expect(calls, hasLength(2));
      final first = calls.first as Map<String, Object?>;
      final firstRequest = first['request'] as Map<String, Object?>;
      expect(firstRequest['url'], 'https://api.example.com/middle');
      return http.Response('{"ok":true}', 200);
    });
    final vigil = Vigil.instance..init();
    final connection = VigilBackendConnection(
      config: VigilBackendConfig(
        endpoint: Uri.parse('https://collector.example.com/vigil'),
        flushInterval: Duration.zero,
        batchSize: 10,
        maxQueueSize: 2,
      ),
      vigil: vigil,
      client: client,
    )..start();

    for (final path in ['/oldest', '/middle', '/latest']) {
      final id = vigil.startCall(_request(path));
      vigil.completeCall(id, _response(200));
    }
    await _settleEvents();

    expect(connection.queuedCount, 2);
    await connection.flush();
    expect(connection.queuedCount, 0);

    await connection.dispose(flushPending: false);
  });
}

Future<void> _settleEvents() => Future<void>.delayed(Duration.zero);

VigilHttpRequest _request(String path) {
  final trace = VigilTraceContext.generate();
  return VigilHttpRequest(
    method: 'GET',
    uri: Uri.parse('https://api.example.com$path'),
    headers: {'traceparent': trace.toHeader()},
    body: VigilBodySummary.empty,
    timestamp: DateTime.now(),
    traceContext: trace,
  );
}

VigilHttpResponse _response(int statusCode) {
  return VigilHttpResponse(
    statusCode: statusCode,
    statusMessage: statusCode == 200 ? 'OK' : 'Error',
    headers: const {'content-type': 'application/json'},
    body: const VigilBodySummary(
      kind: VigilBodyKind.json,
      text: '{"ok":true}',
      byteLength: 11,
      contentType: 'application/json',
    ),
    timestamp: DateTime.now(),
    serverTimings: const [
      VigilServerTiming(name: 'db', duration: 4, description: 'Fetch'),
    ],
  );
}
