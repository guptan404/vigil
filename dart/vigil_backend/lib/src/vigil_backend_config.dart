class VigilBackendConfig {
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
        assert(maxQueueSize > 0, 'maxQueueSize must be positive');

  final Uri endpoint;
  final bool enabled;
  final Map<String, String> headers;
  final String? ingestKey;
  final int batchSize;
  final int maxQueueSize;
  final Duration flushInterval;
  final Duration requestTimeout;
  final bool includePendingCalls;
  final Map<String, Object?> clientInfo;

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
