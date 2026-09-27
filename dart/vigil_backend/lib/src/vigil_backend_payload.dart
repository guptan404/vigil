import 'package:vigil_core/vigil_core.dart';

class VigilBackendPayload {
  const VigilBackendPayload({
    required this.sentAt,
    required this.calls,
    this.clientInfo = const {},
  });

  final DateTime sentAt;
  final List<VigilHttpCall> calls;
  final Map<String, Object?> clientInfo;

  Map<String, Object?> toJson() => {
        'version': 1,
        'sentAt': sentAt.toUtc().toIso8601String(),
        if (clientInfo.isNotEmpty) 'client': clientInfo,
        'calls': calls.map(VigilBackendPayloadSerializer.callToJson).toList(),
      };
}

class VigilBackendPayloadSerializer {
  const VigilBackendPayloadSerializer._();

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
