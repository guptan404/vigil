import 'dart:convert';

class VigilDebugPayload {
  const VigilDebugPayload({
    this.error,
    this.stack,
    this.context = const {},
    this.truncated = false,
  });

  final String? error;
  final String? stack;
  final Map<String, Object?> context;
  final bool truncated;

  Map<String, Object?> toJson() => {
        'error': error,
        'stack': stack,
        'context': context,
        'truncated': truncated,
      };

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
