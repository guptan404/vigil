import 'dart:convert';
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
    final vigil = Vigil.instance
      ..init(config: const VigilConfig(debugKey: 'dev'));
    final debugHeader = base64Url.encode(
      utf8.encode('{"error":"backend failed","context":{"statusCode":500}}'),
    );
    final dio = Dio()
      ..interceptors.add(VigilDioInterceptor(vigil: vigil))
      ..httpClientAdapter = _Adapter((request) async {
        expect(request.headers['Vigil-Key'], 'dev');
        return ResponseBody.fromString('boom', 500, headers: {
          'ViGiL-DeBuG': [debugHeader],
        });
      });

    await expectLater(
      dio.get('https://example.com/error'),
      throwsA(isA<DioException>()),
    );

    expect(vigil.calls.single.state, VigilCallState.failed);
    expect(vigil.calls.single.response!.statusCode, 500);
    expect(vigil.calls.single.response!.serverDebug?.error, 'backend failed');
  });

  test('captures FormData fields and file metadata', () async {
    final vigil = Vigil.instance..init();
    final dio = Dio()
      ..interceptors.add(VigilDioInterceptor(vigil: vigil))
      ..httpClientAdapter = _Adapter(
        (request) async => ResponseBody.fromString('ok', 200),
      );
    final form = FormData()
      ..fields.addAll(const [
        MapEntry('name', 'Ada'),
        MapEntry('password', 'hunter2'),
        MapEntry('tag', 'a'),
        MapEntry('tag', 'b'),
      ])
      ..files.add(
        MapEntry(
          'avatar',
          MultipartFile.fromBytes(
            [1, 2, 3],
            filename: 'avatar.png',
            contentType: DioMediaType('image', 'png'),
          ),
        ),
      );
    final uploadLength = form.length;

    await dio.post('https://example.com/upload', data: form);

    final body = vigil.calls.single.request.body;
    expect(body.kind, VigilBodyKind.json);
    expect(body.contentType, 'multipart/form-data');
    expect(body.byteLength, uploadLength);
    expect(body.text, isNot(contains('hunter2')));
    expect(jsonDecode(body.text!), {
      'name': 'Ada',
      'password': '[redacted]',
      'tag': ['a', 'b'],
      'avatar': {
        'filename': 'avatar.png',
        'contentType': 'image/png',
        'bytes': 3,
      },
    });
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
