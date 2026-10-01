import 'vigil_call.dart';

/// Change represented by a [VigilEvent].
enum VigilEventType { callStarted, callCompleted, callFailed, callsCleared }

/// Notification emitted by the Vigil recorder.
class VigilEvent {
  /// Creates a recorder event.
  const VigilEvent({required this.type, this.call});

  /// Kind of recorder change.
  final VigilEventType type;

  /// Related call, except for [VigilEventType.callsCleared].
  final VigilHttpCall? call;
}
