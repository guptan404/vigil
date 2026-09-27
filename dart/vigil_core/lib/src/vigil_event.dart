import 'vigil_call.dart';

enum VigilEventType { callStarted, callCompleted, callFailed, callsCleared }

class VigilEvent {
  const VigilEvent({required this.type, this.call});

  final VigilEventType type;
  final VigilHttpCall? call;
}
