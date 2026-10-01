import 'package:vigil_core/vigil_core.dart';

/// Versioned request body sent to a Vigil ingest endpoint.
class VigilBackendPayload {
  /// Creates an ingest payload.
  const VigilBackendPayload({
    required this.sentAt,
    required this.calls,
    this.clientInfo = const {},
  });

  /// Time at which this payload was assembled.
  final DateTime sentAt;

  /// Captured calls included in this batch.
  final List<VigilHttpCall> calls;

  /// Application-defined client metadata.
  final Map<String, Object?> clientInfo;

  /// Converts this payload into version 1 ingest JSON.
  Map<String, Object?> toJson() => {
        'version': 1,
        'sentAt': sentAt.toUtc().toIso8601String(),
        if (clientInfo.isNotEmpty) 'client': clientInfo,
        'calls': calls.map(VigilBackendPayloadSerializer.callToJson).toList(),
      };
}

/// Converts captured calls into the version 1 ingest wire format.
class VigilBackendPayloadSerializer {
  const VigilBackendPayloadSerializer._();

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
