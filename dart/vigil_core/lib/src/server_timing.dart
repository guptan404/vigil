/// A metric parsed from an HTTP `Server-Timing` response header.
class VigilServerTiming {
  /// Creates a server timing metric.
  const VigilServerTiming({
    required this.name,
    this.duration,
    this.description,
  });

  /// Metric token, such as `db` or `total`.
  final String name;

  /// Duration in milliseconds, when supplied by the server.
  final double? duration;

  /// Human-readable metric description, when supplied by the server.
  final String? description;

  /// Converts this metric into the Vigil ingest wire representation.
  Map<String, Object?> toJson() => {
        'name': name,
        'duration': duration,
        'description': description,
      };
}

/// Parses metrics from the standard HTTP `Server-Timing` header.
class VigilServerTimingParser {
  const VigilServerTimingParser._();

  /// Parses [header], returning an empty list for absent or invalid entries.
  static List<VigilServerTiming> parse(String? header) {
    if (header == null || header.trim().isEmpty) return const [];
    return _splitHeader(
      header,
    ).map(_parseMetric).whereType<VigilServerTiming>().toList(growable: false);
  }

  static VigilServerTiming? _parseMetric(String rawMetric) {
    final parts = rawMetric.split(';').map((part) => part.trim()).toList();
    if (parts.isEmpty || parts.first.isEmpty) return null;
    double? duration;
    String? description;

    for (final param in parts.skip(1)) {
      final equal = param.indexOf('=');
      if (equal == -1) continue;
      final key = param.substring(0, equal).trim().toLowerCase();
      var value = param.substring(equal + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1).replaceAll(r'\"', '"');
      }
      if (key == 'dur') duration = double.tryParse(value);
      if (key == 'desc') description = value;
    }

    return VigilServerTiming(
      name: parts.first,
      duration: duration,
      description: description,
    );
  }

  static List<String> _splitHeader(String header) {
    final segments = <String>[];
    final buffer = StringBuffer();
    var quoted = false;

    for (var i = 0; i < header.length; i++) {
      final char = header[i];
      if (char == '"' && (i == 0 || header[i - 1] != r'\')) quoted = !quoted;
      if (char == ',' && !quoted) {
        segments.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) segments.add(buffer.toString().trim());
    return segments;
  }
}
