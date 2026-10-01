import 'body_summary.dart';
import 'server_timing.dart';
import 'vigil_debug_payload.dart';

/// Response data captured at the end of an HTTP call.
class VigilHttpResponse {
  /// Creates an immutable captured response.
  const VigilHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.timestamp,
    this.statusMessage,
    this.serverTimings = const [],
    this.serverDebug,
  });

  /// HTTP status code, or `0` when unavailable.
  final int statusCode;

  /// Transport-provided status message, when available.
  final String? statusMessage;

  /// Masked response headers.
  final Map<String, String> headers;

  /// Bounded response body summary.
  final VigilBodySummary body;

  /// Time at which the response was captured.
  final DateTime timestamp;

  /// Metrics parsed from the response `Server-Timing` header.
  final List<VigilServerTiming> serverTimings;

  /// Gated backend diagnostics parsed from `Vigil-Debug`.
  final VigilDebugPayload? serverDebug;
}
