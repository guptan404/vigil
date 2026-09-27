import 'body_summary.dart';
import 'trace_context.dart';

class VigilHttpRequest {
  const VigilHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
    required this.timestamp,
    required this.traceContext,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final VigilBodySummary body;
  final DateTime timestamp;
  final VigilTraceContext traceContext;
}
