import 'package:dio/dio.dart';
import 'package:vigil_core/vigil_core.dart';

const _callIdExtraKey = 'vigil.callId';

/// Captures Dio request lifecycles in a [Vigil] recorder.
///
/// The interceptor also propagates `traceparent` and an optional `Vigil-Key`,
/// then parses `Server-Timing` and `Vigil-Debug` response headers.
class VigilDioInterceptor extends Interceptor {
  /// Creates an interceptor using [vigil] or [Vigil.instance].
  VigilDioInterceptor({Vigil? vigil}) : _vigil = vigil ?? Vigil.instance;

  final Vigil _vigil;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_vigil.enabled) {
      handler.next(options);
      return;
    }

    final trace = VigilTraceContext.generate();
    options.headers['traceparent'] = trace.toHeader();
    final debugKey = _vigil.config.debugKey;
    if (debugKey != null && debugKey.isNotEmpty) {
      options.headers['Vigil-Key'] = debugKey;
    }

    final headers = VigilDataMasker.maskHeaders(
      options.headers,
      _vigil.config.maskHeaders,
    );
    final callId = _vigil.startCall(
      VigilHttpRequest(
        method: options.method,
        uri: options.uri,
        headers: headers,
        body: _summarizeBody(options.data, headers),
        timestamp: DateTime.now(),
        traceContext: trace,
      ),
    );
    options.extra[_callIdExtraKey] = callId;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final callId = response.requestOptions.extra[_callIdExtraKey] as String?;
    if (callId != null) {
      _vigil.completeCall(callId, _responseFromDio(response));
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final callId = err.requestOptions.extra[_callIdExtraKey] as String?;
    if (callId != null) {
      _vigil.failCall(
        callId,
        VigilHttpError(
          message: err.message ?? err.toString(),
          type: err.type.name,
          stackTrace: err.stackTrace,
          timestamp: DateTime.now(),
        ),
        response: err.response == null ? null : _responseFromDio(err.response!),
      );
    }
    handler.next(err);
  }

  VigilHttpResponse _responseFromDio(Response response) {
    final headers = _headersFromDio(response.headers);
    return VigilHttpResponse(
      statusCode: response.statusCode ?? 0,
      statusMessage: response.statusMessage,
      headers: VigilDataMasker.maskHeaders(headers, _vigil.config.maskHeaders),
      body: _summarizeBody(response.data, headers),
      timestamp: DateTime.now(),
      serverTimings: VigilServerTimingParser.parse(
        _headerValue(headers, 'server-timing'),
      ),
      serverDebug: VigilDebugPayload.tryParse(
        _headerValue(headers, 'vigil-debug'),
      ),
    );
  }

  Map<String, String> _headersFromDio(Headers headers) {
    return headers.map.map((key, values) => MapEntry(key, values.join(', ')));
  }

  String? _headerValue(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  VigilBodySummary _summarizeBody(Object? body, Map<String, String> headers) {
    if (body is ResponseBody || body is Stream) {
      return VigilBodySummary.unavailable;
    }
    if (body is FormData) return _summarizeFormData(body);
    return VigilBodySummary.summarize(
      body,
      headers: headers,
      config: _vigil.config,
    );
  }

  /// Describes multipart text fields and file metadata as masked JSON.
  ///
  /// File contents are not read: Dio can consume a [MultipartFile] stream only
  /// once, so reading it here would break the upload. Repeated names, such as
  /// several files under one key, are collected into a list.
  VigilBodySummary _summarizeFormData(FormData form) {
    final description = <String, Object>{};
    void add(String name, Object value) {
      final existing = description[name];
      if (existing == null) {
        description[name] = value;
      } else if (existing is List<Object>) {
        existing.add(value);
      } else {
        description[name] = <Object>[existing, value];
      }
    }

    for (final field in form.fields) {
      add(field.key, field.value);
    }
    for (final file in form.files) {
      add(file.key, {
        'filename': file.value.filename,
        'contentType': file.value.contentType?.toString(),
        'bytes': file.value.length,
      });
    }

    // Dio adds the multipart Content-Type header after interceptors run, so it
    // is usually absent from the captured request headers.
    final summary = VigilBodySummary.summarize(
      description,
      headers: const {'content-type': 'multipart/form-data'},
      config: _vigil.config,
    );
    if (summary.kind == VigilBodyKind.unavailable) return summary;

    // Report the size of the multipart payload Dio uploads rather than the
    // size of this description.
    return VigilBodySummary(
      kind: summary.kind,
      text: summary.text,
      byteLength: form.length,
      truncated: summary.truncated,
      contentType: summary.contentType,
    );
  }
}
