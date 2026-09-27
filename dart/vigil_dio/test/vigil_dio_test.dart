import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil_core/vigil_core.dart';
import 'package:vigil_dio/vigil_dio.dart';

void main() {
  test('injects traceparent and captures successful responses', () async {
    final vigil = Vigil.instance
      ..init(config: const VigilConfig(debugKey: 'dev'));
    final dio = Dio()
      ..interceptors.add(VigilDioInterceptor(vigil: vigil))
      ..httpClientAdapter = _Adapter((request) async {
        expect(request.headers['traceparent'], isNotNull);
        expect(request.headers['Vigil-Key'], 'dev');
        return ResponseBody.fromString(
          '{"ok":true}',
          200,
          headers: {
            'content-type': ['application/json'],
            'server-timing': ['db;dur=4;desc="Fetch"'],
          },
        );
      });

    await dio.get('https://example.com/ok');

    expect(vigil.calls, hasLength(1));
    expect(vigil.calls.single.response!.statusCode, 200);
    expect(vigil.calls.single.response!.serverTimings.single.name, 'db');
  });

  test('captures error responses', () async {
    final vigil = Vigil.instance..init();
    final dio = Dio()
      ..interceptors.add(VigilDioInterceptor(vigil: vigil))
      ..httpClientAdapter = _Adapter((request) async {
        return ResponseBody.fromString('boom', 500);
      });

    await expectLater(
      dio.get('https://example.com/error'),
      throwsA(isA<DioException>()),
    );

    expect(vigil.calls.single.state, VigilCallState.failed);
    expect(vigil.calls.single.response!.statusCode, 500);
  });

  test('disabled mode is a no-op', () async {
    final vigil = Vigil.instance
      ..init(config: const VigilConfig(enabled: false));
    final dio = Dio()
      ..interceptors.add(VigilDioInterceptor(vigil: vigil))
      ..httpClientAdapter = _Adapter((request) async {
        expect(request.headers['traceparent'], isNull);
        return ResponseBody.fromString('ok', 200);
      });

    await dio.get('https://example.com/ok');

    expect(vigil.calls, isEmpty);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions request) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
