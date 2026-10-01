import 'dart:math';

/// A W3C trace context propagated through the `traceparent` HTTP header.
class VigilTraceContext {
  /// Creates a trace context from validated hexadecimal components.
  const VigilTraceContext({
    required this.traceId,
    required this.parentId,
    this.version = '00',
    this.flags = '01',
  });

  /// W3C trace context version.
  final String version;

  /// Thirty-two-character trace identifier.
  final String traceId;

  /// Sixteen-character parent identifier.
  final String parentId;

  /// Two-character trace flags.
  final String flags;

  /// Serializes this context as a `traceparent` header value.
  String toHeader() => '$version-$traceId-$parentId-$flags';

  /// Generates a new cryptographically secure trace and parent identifier.
  static VigilTraceContext generate({Random? random}) {
    final rng = random ?? Random.secure();
    return VigilTraceContext(
      traceId: _randomHex(rng, 16),
      parentId: _randomHex(rng, 8),
    );
  }

  /// Parses a W3C `traceparent` value, or returns `null` when it is invalid.
  static VigilTraceContext? tryParse(String? header) {
    if (header == null) return null;
    final parts = header.trim().split('-');
    if (parts.length != 4) return null;
    final version = parts[0];
    final traceId = parts[1];
    final parentId = parts[2];
    final flags = parts[3];
    final hex = RegExp(r'^[0-9a-f]+$');
    if (version.length != 2 ||
        traceId.length != 32 ||
        parentId.length != 16 ||
        flags.length != 2 ||
        !hex.hasMatch(version + traceId + parentId + flags) ||
        traceId == '00000000000000000000000000000000' ||
        parentId == '0000000000000000') {
      return null;
    }
    return VigilTraceContext(
      version: version,
      traceId: traceId,
      parentId: parentId,
      flags: flags,
    );
  }

  static String _randomHex(Random rng, int byteCount) {
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      buffer.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
