import 'body_summary.dart';
import 'server_timing.dart';
import 'vigil_debug_payload.dart';

class VigilHttpResponse {
  const VigilHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.timestamp,
    this.statusMessage,
    this.serverTimings = const [],
    this.serverDebug,
  });

  final int statusCode;
  final String? statusMessage;
  final Map<String, String> headers;
  final VigilBodySummary body;
  final DateTime timestamp;
  final List<VigilServerTiming> serverTimings;
  final VigilDebugPayload? serverDebug;
}
