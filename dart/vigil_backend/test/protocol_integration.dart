import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:vigil_backend/vigil_backend.dart';
import 'package:vigil_core/vigil_core.dart';
import 'package:vigil_dio/vigil_dio.dart';

void main() {
  late Process server;
  late Uri baseUrl;

  setUpAll(() async {
    server = await Process.start(
      'node',
      ['test/integration/server.mjs'],
      workingDirectory: '../..',
    );
    final ready = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));
    baseUrl = Uri.parse('http://127.0.0.1:${jsonDecode(ready)['port']}');
  });

  tearDownAll(() async {
    server.kill();
    await server.exitCode;
  });

  test('Dio, Express, and ingest agree on successful call protocol', () async {
    final vigil = Vigil.instance
      ..init(config: const VigilConfig(debugKey: 'debug-secret'));
    final dio = Dio(BaseOptions(baseUrl: baseUrl.toString()))
      ..interceptors.add(VigilDioInterceptor(vigil: vigil));
    final connection = VigilBackendConnection.connect(
      config: VigilBackendConfig(
        endpoint: baseUrl.resolve('/vigil/ingest'),
        ingestKey: 'ingest-secret',
        flushInterval: Duration.zero,
        clientInfo: const {'device': 'test-phone'},
      ),
      vigil: vigil,
    );
    try {
      final response = await dio.post<Object?>(
        '/ok',
        data: {'password': 'private', 'value': 'safe'},
        options: Options(headers: {'Authorization': 'Bearer private'}),
      );
      await Future<void>.delayed(Duration.zero);
      await connection.flush();
      final batches =
          jsonDecode((await http.get(baseUrl.resolve('/batches'))).body)
              as List;
      final call =
          (batches.last['calls'] as List).single as Map<String, dynamic>;
      final captured = vigil.calls.single;

      expect(response.statusCode, 200);
      expect(captured.state, VigilCallState.completed);
      expect(captured.request.traceContext.toHeader(),
          response.headers.value('traceparent'));
      expect(captured.response!.serverTimings.map((metric) => metric.name),
          containsAll(['total', 'db']));
      expect(captured.response!.serverDebug?.context['logs'], [
        containsPair('message', 'Loaded result'),
      ]);
      expect(captured.request.headers['Authorization'], '[redacted]');
      expect(captured.request.body.text, contains('"password":"[redacted]"'));
      expect(call['trace']['traceparent'],
          captured.request.traceContext.toHeader());
      expect(call['request']['headers']['Authorization'], '[redacted]');
      expect(
          call['request']['body']['text'], contains('"password":"[redacted]"'));
      expect(call['response']['statusCode'], 200);
      expect(connection.queuedCount, 0);

      final inspector = baseUrl.resolve('/vigil/inspector');
      final page = await http.get(inspector);
      expect(page.statusCode, 200);
      expect(page.headers['content-security-policy'],
          contains("script-src 'sha256-"));
      final captures = baseUrl.resolve('/vigil/inspector/captures');
      final denied = await http
          .get(captures, headers: {'Vigil-Read-Key': 'ingest-secret'});
      expect(denied.statusCode, 403);
      final allowed =
          await http.get(captures, headers: {'Vigil-Read-Key': 'read-secret'});
      final entry = (jsonDecode(allowed.body)['captures'] as List).first;
      expect(entry['client']['device'], 'test-phone');
      expect(entry['call']['id'], captured.id);
      expect(
          entry['call']['response']['serverDebug']['context']['logs'][0]
              ['message'],
          'Loaded result');
    } finally {
      await connection.dispose(flushPending: false);
      dio.close();
    }
  });

  test('backend error details require the matching key and failed calls ingest',
      () async {
    final vigil = Vigil.instance
      ..init(config: const VigilConfig(debugKey: 'debug-secret'));
    final dio = Dio(BaseOptions(baseUrl: baseUrl.toString()))
      ..interceptors.add(VigilDioInterceptor(vigil: vigil));
    final connection = VigilBackendConnection.connect(
      config: VigilBackendConfig(
        endpoint: baseUrl.resolve('/vigil/ingest'),
        ingestKey: 'ingest-secret',
        flushInterval: Duration.zero,
      ),
      vigil: vigil,
    );
    try {
      await expectLater(
          dio.get<Object?>('/error'), throwsA(isA<DioException>()));
      final captured = vigil.calls.single;
      expect(captured.state, VigilCallState.failed);
      expect(captured.response!.statusCode, 500);
      expect(captured.response!.serverDebug?.error, 'Backend failure');
      expect(captured.response!.serverDebug?.context['logs'], [
        containsPair('message', 'Result missing'),
      ]);
      expect(captured.response!.serverTimings.map((metric) => metric.name),
          contains('total'));
      await Future<void>.delayed(Duration.zero);
      await connection.flush();
      final batches =
          jsonDecode((await http.get(baseUrl.resolve('/batches'))).body)
              as List;
      final call =
          (batches.last['calls'] as List).single as Map<String, dynamic>;
      expect(call['state'], 'failed');
      expect(call['response']['serverDebug']['error'], 'Backend failure');

      final denied = await http.get(baseUrl.resolve('/error'));
      expect(denied.headers['vigil-debug'], isNull);
    } finally {
      await connection.dispose(flushPending: false);
      dio.close();
    }
  });

  test('Express simulations produce real Dio failures and allow recovery',
      () async {
    final vigil = Vigil.instance
      ..init(config: const VigilConfig(debugKey: 'debug-secret'));
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl.toString(),
      receiveTimeout: const Duration(milliseconds: 100),
    ))
      ..interceptors.add(VigilDioInterceptor(vigil: vigil));
    final controlUri = baseUrl.resolve('/vigil/inspector/simulation');
    const headers = {
      'Content-Type': 'application/json',
      'Vigil-Control-Key': 'control-secret',
    };
    Future<void> simulate(Map<String, Object?> rule) async {
      final response = await http.post(
        controlUri,
        headers: headers,
        body: jsonEncode({'method': 'GET', 'path': '/ok', 'times': 1, ...rule}),
      );
      expect(response.statusCode, 201);
    }

    try {
      await simulate({
        'effect': 'httpError',
        'statusCode': 503,
        'body': {'error': 'Server temporarily unavailable'},
      });
      await expectLater(dio.get<Object?>('/ok'), throwsA(isA<DioException>()));
      var captured = vigil.calls.last;
      expect(captured.state, VigilCallState.failed);
      expect(captured.response?.statusCode, 503);
      expect(captured.response?.body.text,
          contains('Server temporarily unavailable'));
      expect(captured.response?.headers['vigil-simulation'], 'httpError');
      expect(captured.response?.serverDebug?.context['logs'], [
        containsPair('message', 'Vigil server failure simulation'),
      ]);
      expect(captured.request.traceContext.toHeader(),
          captured.response?.headers['traceparent']);

      await simulate({'effect': 'exception'});
      await expectLater(dio.get<Object?>('/ok'), throwsA(isA<DioException>()));
      expect(vigil.calls.last.response?.serverDebug?.stack,
          contains('Vigil simulated backend exception'));

      await simulate({'effect': 'disconnect'});
      await expectLater(dio.get<Object?>('/ok'), throwsA(isA<DioException>()));
      expect(vigil.calls.last.response, isNull);
      expect(vigil.calls.last.state, VigilCallState.failed);

      await simulate({'effect': 'timeout', 'delayMs': 500});
      await expectLater(dio.get<Object?>('/ok'), throwsA(isA<DioException>()));
      captured = vigil.calls.last;
      expect(captured.error?.type, 'receiveTimeout');
      expect(captured.response, isNull);

      final recovered = await dio.get<Object?>('/ok');
      expect(recovered.statusCode, 200);
      expect(vigil.calls.last.state, VigilCallState.completed);
    } finally {
      await http.delete(controlUri, headers: headers);
      dio.close(force: true);
    }
  });

  test('ingest rejects a wrong key and the client retains the batch', () async {
    final vigil = Vigil.instance..init();
    final dio = Dio(BaseOptions(baseUrl: baseUrl.toString()))
      ..interceptors.add(VigilDioInterceptor(vigil: vigil));
    final connection = VigilBackendConnection.connect(
      config: VigilBackendConfig(
        endpoint: baseUrl.resolve('/vigil/ingest'),
        ingestKey: 'wrong-key',
        flushInterval: Duration.zero,
      ),
      vigil: vigil,
    );
    try {
      final before =
          jsonDecode((await http.get(baseUrl.resolve('/batches'))).body)
              as List;
      await dio.get<Object?>('/ok');
      await Future<void>.delayed(Duration.zero);
      await connection.flush();
      final after =
          jsonDecode((await http.get(baseUrl.resolve('/batches'))).body)
              as List;

      expect(connection.queuedCount, 1);
      expect(after.length, before.length);
    } finally {
      await connection.dispose(flushPending: false);
      dio.close();
    }
  });
}
