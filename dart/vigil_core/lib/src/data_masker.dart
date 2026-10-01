/// Privacy helpers used before HTTP data is retained or exported.
class VigilDataMasker {
  const VigilDataMasker._();

  /// Replaces case-insensitive header names in [maskedNames] with a marker.
  static Map<String, String> maskHeaders(
    Map<String, Object?> headers,
    Set<String> maskedNames,
  ) {
    final masked = <String, String>{};
    for (final entry in headers.entries) {
      final shouldMask = maskedNames.contains(entry.key.toLowerCase());
      masked[entry.key] = shouldMask ? '[redacted]' : '${entry.value}';
    }
    return masked;
  }

  /// Recursively masks map fields whose lowercase names are in [maskedFields].
  static Object? maskJson(Object? value, Set<String> maskedFields) {
    if (value is Map) {
      return value.map((key, child) {
        final keyText = key.toString();
        final shouldMask = maskedFields.contains(keyText.toLowerCase());
        return MapEntry(
          keyText,
          shouldMask ? '[redacted]' : maskJson(child, maskedFields),
        );
      });
    }
    if (value is List) {
      return value.map((child) => maskJson(child, maskedFields)).toList();
    }
    return value;
  }
}
