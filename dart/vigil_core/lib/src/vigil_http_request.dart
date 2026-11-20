import 'body_summary.dart';
import 'trace_context.dart';
import 'vigil_session.dart';

/// Request data captured at the start of an HTTP call.
class VigilHttpRequest {
  /// Creates an immutable captured request.
  const VigilHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
    required this.timestamp,
    required this.traceContext,
    this.session,
  });

  /// HTTP method.
  final String method;

  /// Fully resolved request URI.
  final Uri uri;

  /// Masked request headers.
  final Map<String, String> headers;

  /// Bounded request body summary.
  final VigilBodySummary body;

  /// Time at which the request started.
  final DateTime timestamp;

  /// Trace context sent with the request.
  final VigilTraceContext traceContext;

  /// Session at capture time. Absent in older captures.
  final VigilSession? session;

  /// Copies this request with a capture-session identity.
  VigilHttpRequest withSession(VigilSession identity) => VigilHttpRequest(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
        timestamp: timestamp,
        traceContext: traceContext,
        session: identity,
      );
}
