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
  static Map<String, Object?> callToJson(VigilHttpCall call) =>
      VigilCallCodec.callToJson(call);
}
