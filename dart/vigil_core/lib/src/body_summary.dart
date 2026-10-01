import 'dart:convert';
import 'dart:typed_data';

import 'data_masker.dart';
import 'vigil_config.dart';

/// The representation retained for a captured request or response body.
enum VigilBodyKind {
  /// No body was supplied.
  empty,

  /// JSON-compatible text was captured.
  json,

  /// Plain text was captured.
  text,

  /// Binary data was detected and its contents were not retained.
  binary,

  /// The body exceeded the configured limit without displayable content.
  oversized,

  /// The body could not or should not be captured.
  unavailable,
}

/// A bounded, display-safe description of an HTTP body.
class VigilBodySummary {
  /// Creates an immutable body summary.
  const VigilBodySummary({
    required this.kind,
    this.text,
    this.byteLength = 0,
    this.truncated = false,
    this.contentType,
  });

  /// The retained representation.
  final VigilBodyKind kind;

  /// Captured text, when [kind] is [VigilBodyKind.json] or
  /// [VigilBodyKind.text].
  final String? text;

  /// Original body size in bytes when known.
  final int byteLength;

  /// Whether captured text was shortened to the configured byte limit.
  final bool truncated;

  /// Normalized HTTP content type when one was supplied.
  final String? contentType;

  /// A summary representing an absent body.
  static const empty = VigilBodySummary(kind: VigilBodyKind.empty);

  /// A summary representing a body that was intentionally not inspected.
  static const unavailable = VigilBodySummary(kind: VigilBodyKind.unavailable);

  /// Whether [text] can be displayed by an inspector.
  bool get isDisplayable =>
      kind == VigilBodyKind.json || kind == VigilBodyKind.text;

  /// Converts this summary into the Vigil ingest wire representation.
  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'text': text,
        'byteLength': byteLength,
        'truncated': truncated,
        'contentType': contentType,
      };

  /// Produces a masked and size-limited summary of [value].
  static VigilBodySummary summarize(
    Object? value, {
    required Map<String, String> headers,
    required VigilConfig config,
  }) {
    if (!config.captureBody) return unavailable;
    if (value == null) return empty;

    final contentType = _contentType(headers);

    if (value is Map || value is List) {
      final masked = VigilDataMasker.maskJson(value, config.maskBodyFields);
      return _fromText(
        jsonEncode(masked),
        contentType: contentType ?? 'application/json',
        preferredKind: VigilBodyKind.json,
        config: config,
      );
    }

    if (value is String) {
      final kind =
          _isJson(contentType) ? VigilBodyKind.json : VigilBodyKind.text;
      return _fromText(
        value,
        contentType: contentType,
        preferredKind: kind,
        config: config,
      );
    }

    if (value is List<int>) {
      if (!_isText(contentType) && !_isJson(contentType)) {
        return VigilBodySummary(
          kind: VigilBodyKind.binary,
          byteLength: value.length,
          contentType: contentType,
        );
      }
      return _fromBytes(value, contentType: contentType, config: config);
    }

    if (value is ByteBuffer) {
      return VigilBodySummary(
        kind: VigilBodyKind.binary,
        byteLength: value.lengthInBytes,
        contentType: contentType,
      );
    }

    return _fromText(
      value.toString(),
      contentType: contentType,
      config: config,
    );
  }

  static VigilBodySummary _fromBytes(
    List<int> bytes, {
    String? contentType,
    required VigilConfig config,
  }) {
    final truncated = bytes.length > config.maxBodyBytes;
    final capped = truncated ? bytes.take(config.maxBodyBytes).toList() : bytes;
    return _fromText(
      utf8.decode(capped, allowMalformed: true),
      contentType: contentType,
      preferredKind:
          _isJson(contentType) ? VigilBodyKind.json : VigilBodyKind.text,
      config: config,
      byteLengthOverride: bytes.length,
      alreadyTruncated: truncated,
    );
  }

  static VigilBodySummary _fromText(
    String text, {
    String? contentType,
    VigilBodyKind preferredKind = VigilBodyKind.text,
    required VigilConfig config,
    int? byteLengthOverride,
    bool alreadyTruncated = false,
  }) {
    final bytes = utf8.encode(text);
    final truncated = alreadyTruncated || bytes.length > config.maxBodyBytes;
    final display = bytes.length > config.maxBodyBytes
        ? utf8.decode(
            bytes.take(config.maxBodyBytes).toList(),
            allowMalformed: true,
          )
        : text;
    return VigilBodySummary(
      kind: truncated && display.isEmpty
          ? VigilBodyKind.oversized
          : preferredKind,
      text: display,
      byteLength: byteLengthOverride ?? bytes.length,
      truncated: truncated,
      contentType: contentType,
    );
  }

  static String? _contentType(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') {
        return entry.value.toLowerCase();
      }
    }
    return null;
  }

  static bool _isJson(String? contentType) =>
      contentType != null && contentType.contains('json');

  static bool _isText(String? contentType) {
    if (contentType == null) {
      return false;
    }
    return contentType.startsWith('text/') ||
        contentType.contains('xml') ||
        contentType.contains('form-urlencoded');
  }
}
