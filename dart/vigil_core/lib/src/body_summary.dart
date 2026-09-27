import 'dart:convert';
import 'dart:typed_data';

import 'data_masker.dart';
import 'vigil_config.dart';

enum VigilBodyKind { empty, json, text, binary, oversized, unavailable }

class VigilBodySummary {
  const VigilBodySummary({
    required this.kind,
    this.text,
    this.byteLength = 0,
    this.truncated = false,
    this.contentType,
  });

  final VigilBodyKind kind;
  final String? text;
  final int byteLength;
  final bool truncated;
  final String? contentType;

  static const empty = VigilBodySummary(kind: VigilBodyKind.empty);
  static const unavailable = VigilBodySummary(kind: VigilBodyKind.unavailable);

  bool get isDisplayable =>
      kind == VigilBodyKind.json || kind == VigilBodyKind.text;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'text': text,
        'byteLength': byteLength,
        'truncated': truncated,
        'contentType': contentType,
      };

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
