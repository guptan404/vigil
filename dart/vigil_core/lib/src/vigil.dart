import 'dart:async';
import 'dart:math';

import 'curl_exporter.dart';
import 'vigil_call.dart';
import 'vigil_config.dart';
import 'vigil_event.dart';
import 'vigil_http_error.dart';
import 'vigil_http_request.dart';
import 'vigil_http_response.dart';

class Vigil {
  Vigil._();

  static final Vigil instance = Vigil._();

  VigilConfig _config = const VigilConfig();
  final _calls = <VigilHttpCall>[];
  final _events = StreamController<VigilEvent>.broadcast();
  final _idRandom = Random.secure();

  VigilConfig get config => _config;
  bool get enabled => _config.enabled;
  List<VigilHttpCall> get calls => List.unmodifiable(_calls);
  Stream<VigilEvent> get events => _events.stream;

  void init({VigilConfig? config}) {
    _config = config ?? const VigilConfig();
    clear();
  }

  String startCall(VigilHttpRequest request) {
    final call = VigilHttpCall(
      id: _newId(),
      request: request,
      startedAt: request.timestamp,
    );
    if (!_config.enabled) return call.id;
    if (_calls.length >= _config.maxCalls) _calls.removeAt(0);
    _calls.add(call);
    _events.add(VigilEvent(type: VigilEventType.callStarted, call: call));
    return call.id;
  }

  void completeCall(String id, VigilHttpResponse response) {
    if (!_config.enabled) return;
    final index = _calls.indexWhere((call) => call.id == id);
    if (index == -1) return;
    final call = _calls[index].complete(response);
    _calls[index] = call;
    _events.add(VigilEvent(type: VigilEventType.callCompleted, call: call));
  }

  void failCall(
    String id,
    VigilHttpError error, {
    VigilHttpResponse? response,
  }) {
    if (!_config.enabled) return;
    final index = _calls.indexWhere((call) => call.id == id);
    if (index == -1) return;
    final call = _calls[index].fail(error, response: response);
    _calls[index] = call;
    _events.add(VigilEvent(type: VigilEventType.callFailed, call: call));
  }

  String toCurl(VigilHttpCall call) => VigilCurlExporter.export(call);

  void clear() {
    _calls.clear();
    if (!_events.isClosed) {
      _events.add(const VigilEvent(type: VigilEventType.callsCleared));
    }
  }

  void dispose() {
    _events.close();
  }

  String _newId() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final suffix = _idRandom.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$micros$suffix';
  }
}
