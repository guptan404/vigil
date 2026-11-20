import 'package:flutter/foundation.dart';

/// Selects which copy actions the Vigil inspector offers for a request.
///
/// Every option is enabled by default. Pass a customised instance to
/// `VigilOverlay.copyOptions` or `VigilInspector.copyOptions` to hide copy
/// actions that are not appropriate for an app, for example:
///
/// ```dart
/// VigilOverlay(
///   copyOptions: const VigilCopyOptions(responseContent: false),
///   child: child,
/// );
/// ```
///
/// Copied JSON bodies are always pretty-printed with two-space indentation so
/// they stay readable when pasted into notes, chat, or a text editor.
@immutable
class VigilCopyOptions {
  /// Creates copy options. Every action is enabled unless disabled here.
  const VigilCopyOptions({
    this.endpoint = true,
    this.requestContent = true,
    this.responseContent = true,
    this.all = true,
  });

  /// Disables every selective copy action.
  const VigilCopyOptions.none()
      : endpoint = false,
        requestContent = false,
        responseContent = false,
        all = false;

  /// Whether the request endpoint (the full URL) can be copied.
  final bool endpoint;

  /// Whether the formatted request body can be copied.
  final bool requestContent;

  /// Whether the formatted response body can be copied.
  final bool responseContent;

  /// Whether a single "Copy all" action copies the endpoint, request content,
  /// and response content together. It only includes the parts enabled by
  /// [endpoint], [requestContent], and [responseContent], and is hidden when
  /// none of them is enabled.
  final bool all;

  /// Whether at least one of the individually copyable parts is enabled.
  bool get anyContent => endpoint || requestContent || responseContent;

  /// Returns a copy of these options with the given fields replaced.
  VigilCopyOptions copyWith({
    bool? endpoint,
    bool? requestContent,
    bool? responseContent,
    bool? all,
  }) {
    return VigilCopyOptions(
      endpoint: endpoint ?? this.endpoint,
      requestContent: requestContent ?? this.requestContent,
      responseContent: responseContent ?? this.responseContent,
      all: all ?? this.all,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VigilCopyOptions &&
      other.endpoint == endpoint &&
      other.requestContent == requestContent &&
      other.responseContent == responseContent &&
      other.all == all;

  @override
  int get hashCode =>
      Object.hash(endpoint, requestContent, responseContent, all);
}
