import 'package:dio/dio.dart';
import 'package:vigil_core/vigil_core.dart';

const _callIdExtraKey = 'vigil.callId';

class VigilDioInterceptor extends Interceptor {
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
        headers['Server-Timing'] ?? headers['server-timing'],
      ),
      serverDebug: VigilDebugPayload.tryParse(
        headers['Vigil-Debug'] ?? headers['vigil-debug'],
      ),
    );
  }

  Map<String, String> _headersFromDio(Headers headers) {
    return headers.map.map((key, values) => MapEntry(key, values.join(', ')));
  }

  VigilBodySummary _summarizeBody(Object? body, Map<String, String> headers) {
    if (body is ResponseBody || body is Stream) {
      return VigilBodySummary.unavailable;
    }
    return VigilBodySummary.summarize(
      body,
      headers: headers,
      config: _vigil.config,
    );
  }
}
