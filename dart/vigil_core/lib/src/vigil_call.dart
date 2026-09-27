import 'vigil_http_error.dart';
import 'vigil_http_request.dart';
import 'vigil_http_response.dart';

enum VigilCallState { pending, completed, failed }

class VigilHttpCall {
  const VigilHttpCall({
    required this.id,
    required this.request,
    required this.startedAt,
    this.response,
    this.error,
    this.completedAt,
    this.state = VigilCallState.pending,
  });

  final String id;
  final VigilHttpRequest request;
  final VigilHttpResponse? response;
  final VigilHttpError? error;
  final DateTime startedAt;
  final DateTime? completedAt;
  final VigilCallState state;

  Duration? get duration => completedAt?.difference(startedAt);

  VigilHttpCall complete(VigilHttpResponse response) => VigilHttpCall(
        id: id,
        request: request,
        startedAt: startedAt,
        response: response,
        completedAt: response.timestamp,
        state: VigilCallState.completed,
      );

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
