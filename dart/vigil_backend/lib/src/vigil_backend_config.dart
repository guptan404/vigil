/// Configures batching and delivery to a Vigil ingest endpoint.
class VigilBackendConfig {
  /// Creates backend upload configuration.
  const VigilBackendConfig({
    required this.endpoint,
    this.enabled = true,
    this.headers = const {},
    this.ingestKey,
    this.batchSize = 20,
    this.maxQueueSize = 500,
    this.flushInterval = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 8),
    this.includePendingCalls = false,
    this.clientInfo = const {},
  })  : assert(batchSize > 0, 'batchSize must be positive'),
        assert(maxQueueSize > 0, 'maxQueueSize must be positive'),
        assert(
            requestTimeout > Duration.zero, 'requestTimeout must be positive');

  /// HTTP endpoint that accepts Vigil version 1 ingest batches.
  final Uri endpoint;

  /// Whether the connection should subscribe and upload calls.
  final bool enabled;

  /// Additional request headers sent with each batch.
  final Map<String, String> headers;

  /// Optional value sent in the `Vigil-Ingest-Key` header.
  final String? ingestKey;

  /// Maximum calls sent in one request.
  final int batchSize;

  /// Maximum calls retained while uploads are unavailable.
  final int maxQueueSize;

  /// Interval between automatic flush attempts.
  final Duration flushInterval;

  /// Timeout applied to an ingest request.
  final Duration requestTimeout;

  /// Whether call-start events should also be uploaded.
  final bool includePendingCalls;

  /// Application-defined metadata included with every batch.
  final Map<String, Object?> clientInfo;

  /// Builds HTTP headers for an ingest request.
  Map<String, String> requestHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...headers,
      if (ingestKey != null && ingestKey!.isNotEmpty)
        'Vigil-Ingest-Key': ingestKey!,
    };
  }
}
