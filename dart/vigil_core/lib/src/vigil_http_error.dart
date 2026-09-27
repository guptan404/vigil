class VigilHttpError {
  const VigilHttpError({
    required this.message,
    required this.timestamp,
    this.type,
    this.stackTrace,
  });

  final String message;
  final String? type;
  final StackTrace? stackTrace;
  final DateTime timestamp;
}
