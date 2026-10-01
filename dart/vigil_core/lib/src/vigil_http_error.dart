/// Client-side transport failure captured for an HTTP call.
class VigilHttpError {
  /// Creates a captured transport error.
  const VigilHttpError({
    required this.message,
    required this.timestamp,
    this.type,
    this.stackTrace,
  });

  /// Human-readable error message.
  final String message;

  /// Transport-specific error category, when available.
  final String? type;

  /// Client stack trace, when available.
  final StackTrace? stackTrace;

  /// Time at which the call failed.
  final DateTime timestamp;
}
