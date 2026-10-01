import 'vigil_http_error.dart';
import 'vigil_http_request.dart';
import 'vigil_http_response.dart';

/// Lifecycle state of a captured HTTP call.
enum VigilCallState { pending, completed, failed }

/// Immutable request lifecycle captured by Vigil.
class VigilHttpCall {
  /// Creates a captured call.
  const VigilHttpCall({
    required this.id,
    required this.request,
    required this.startedAt,
    this.response,
    this.error,
    this.completedAt,
    this.state = VigilCallState.pending,
  });

  /// Vigil-generated call identifier.
  final String id;

  /// Captured request data.
  final VigilHttpRequest request;

  /// Captured response data, when a response was received.
  final VigilHttpResponse? response;

  /// Client-side transport error, when the call failed.
  final VigilHttpError? error;

  /// Time at which the request started.
  final DateTime startedAt;

  /// Time at which the response or failure completed.
  final DateTime? completedAt;

  /// Current lifecycle state.
  final VigilCallState state;

  /// Elapsed client duration, or `null` while the call is pending.
  Duration? get duration => completedAt?.difference(startedAt);

  /// Returns a completed copy containing [response].
  VigilHttpCall complete(VigilHttpResponse response) => VigilHttpCall(
        id: id,
        request: request,
        startedAt: startedAt,
        response: response,
        completedAt: response.timestamp,
        state: VigilCallState.completed,
      );

  /// Returns a failed copy containing [error] and an optional [response].
  VigilHttpCall fail(VigilHttpError error, {VigilHttpResponse? response}) =>
      VigilHttpCall(
        id: id,
        request: request,
        startedAt: startedAt,
        response: response,
        error: error,
        completedAt: error.timestamp,
        state: VigilCallState.failed,
      );
}
