import 'dart:convert';

/// Gated backend error details decoded from a `Vigil-Debug` header.
class VigilDebugPayload {
  /// Creates a decoded debug payload.
  const VigilDebugPayload({
    this.error,
    this.stack,
    this.context = const {},
    this.truncated = false,
  });

  /// Backend error message, when supplied.
  final String? error;

  /// Backend stack trace, when supplied.
  final String? stack;

  /// Additional backend-provided diagnostic context.
  final Map<String, Object?> context;

  /// Whether the backend shortened the payload to fit its header limit.
  final bool truncated;

  /// Converts this payload into the Vigil ingest wire representation.
  Map<String, Object?> toJson() => {
        'error': error,
        'stack': stack,
        'context': context,
        'truncated': truncated,
      };

  /// Decodes a base64url `Vigil-Debug` header, returning `null` if invalid.
  static VigilDebugPayload? tryParse(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    try {
      final normalized = base64Url.normalize(header.trim());
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      if (json is! Map) return null;
      final context = json['context'];
      return VigilDebugPayload(
        error: json['error']?.toString(),
        stack: json['stack']?.toString(),
        context: context is Map
            ? context.map(
                (key, value) => MapEntry(key.toString(), value as Object?),
              )
            : const {},
        truncated: json['truncated'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
