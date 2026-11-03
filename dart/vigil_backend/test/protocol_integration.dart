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
      expect(captured.response!.serverDebug, isNull);
      expect(captured.request.headers['Authorization'], '[redacted]');
      expect(captured.request.body.text, contains('"password":"[redacted]"'));
      expect(call['trace']['traceparent'],
          captured.request.traceContext.toHeader());
      expect(call['request']['headers']['Authorization'], '[redacted]');
      expect(
          call['request']['body']['text'], contains('"password":"[redacted]"'));
      expect(call['response']['statusCode'], 200);
      expect(connection.queuedCount, 0);
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
