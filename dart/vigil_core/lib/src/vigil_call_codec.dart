import 'body_summary.dart';
import 'server_timing.dart';
import 'trace_context.dart';
import 'vigil_call.dart';
import 'vigil_debug_payload.dart';
import 'vigil_http_error.dart';
import 'vigil_http_request.dart';
import 'vigil_http_response.dart';

/// Converts captured calls into the version 1 lifecycle wire format.
class VigilCallCodec {
  const VigilCallCodec._();

  /// Serializes [call] for backend ingestion.
  static Map<String, Object?> callToJson(VigilHttpCall call) => {
        'id': call.id,
        'state': call.state.name,
        'startedAt': call.startedAt.toUtc().toIso8601String(),
        'completedAt': call.completedAt?.toUtc().toIso8601String(),
        'durationMs': call.duration?.inMicroseconds == null
            ? null
            : call.duration!.inMicroseconds / 1000,
        'trace': {
          'traceparent': call.request.traceContext.toHeader(),
          'traceId': call.request.traceContext.traceId,
          'parentId': call.request.traceContext.parentId,
          'flags': call.request.traceContext.flags,
        },
        'request': _requestToJson(call.request),
        'response':
            call.response == null ? null : _responseToJson(call.response!),
        'error': call.error == null ? null : _errorToJson(call.error!),
      };

  /// Reads a captured lifecycle from version 1 JSON.
  static VigilHttpCall callFromJson(Map<String, dynamic> json) {
    final request = json['request'] as Map<String, dynamic>;
    final trace = VigilTraceContext.tryParse(
      (json['trace'] as Map<String, dynamic>)['traceparent'] as String?,
    );
    if (trace == null) throw const FormatException('Invalid trace context');
    final response = json['response'] as Map<String, dynamic>?;
    final error = json['error'] as Map<String, dynamic>?;
    final debug = response?['serverDebug'] as Map<String, dynamic>?;
    return VigilHttpCall(
      id: json['id'] as String,
      state: VigilCallState.values.byName(json['state'] as String),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      request: VigilHttpRequest(
        method: request['method'] as String,
        uri: Uri.parse(request['url'] as String),
        headers: _readHeaders(request),
        body: _readBody(request),
        timestamp: DateTime.parse(request['timestamp'] as String),
        traceContext: trace,
      ),
      response: response == null
          ? null
          : VigilHttpResponse(
              statusCode: response['statusCode'] as int,
              statusMessage: response['statusMessage'] as String?,
              headers: _readHeaders(response),
              body: _readBody(response),
              timestamp: DateTime.parse(response['timestamp'] as String),
              serverTimings:
                  (response['serverTimings'] as List? ?? []).map((metric) {
                final json = metric as Map<String, dynamic>;
                return VigilServerTiming(
                  name: json['name'] as String,
                  duration: (json['duration'] as num?)?.toDouble(),
                  description: json['description'] as String?,
                );
              }).toList(growable: false),
              serverDebug: debug == null
                  ? null
                  : VigilDebugPayload(
                      error: debug['error'] as String?,
                      stack: debug['stack'] as String?,
                      context: Map.unmodifiable(debug['context'] as Map? ?? {}),
                      truncated: debug['truncated'] == true,
                    ),
            ),
      error: error == null
          ? null
          : VigilHttpError(
              message: error['message'] as String,
              type: error['type'] as String?,
              stackTrace: error['stackTrace'] == null
                  ? null
                  : StackTrace.fromString(error['stackTrace'] as String),
              timestamp: DateTime.parse(error['timestamp'] as String),
            ),
    );
  }

  static Map<String, String> _readHeaders(Map<String, dynamic> json) =>
      Map.unmodifiable((json['headers'] as Map).cast<String, String>());

  static VigilBodySummary _readBody(Map<String, dynamic> json) {
    final body = json['body'] as Map<String, dynamic>;
    return VigilBodySummary(
      kind: VigilBodyKind.values.byName(body['kind'] as String),
      text: body['text'] as String?,
      byteLength: body['byteLength'] as int,
      truncated: body['truncated'] as bool,
      contentType: body['contentType'] as String?,
    );
  }

  static Map<String, Object?> _requestToJson(VigilHttpRequest request) => {
        'method': request.method,
        'url': request.uri.toString(),
        'headers': request.headers,
        'body': request.body.toJson(),
        'timestamp': request.timestamp.toUtc().toIso8601String(),
      };

  static Map<String, Object?> _responseToJson(VigilHttpResponse response) => {
        'statusCode': response.statusCode,
        'statusMessage': response.statusMessage,
        'headers': response.headers,
        'body': response.body.toJson(),
        'timestamp': response.timestamp.toUtc().toIso8601String(),
        'serverTimings':
            response.serverTimings.map((timing) => timing.toJson()).toList(),
        'serverDebug': response.serverDebug?.toJson(),
      };

  static Map<String, Object?> _errorToJson(VigilHttpError error) => {
        'message': error.message,
        'type': error.type,
        'stackTrace': error.stackTrace?.toString(),
        'timestamp': error.timestamp.toUtc().toIso8601String(),
      };
}
