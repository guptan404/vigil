import 'dart:async';
import 'dart:math';

import 'curl_exporter.dart';
import 'vigil_call.dart';
import 'vigil_config.dart';
import 'vigil_event.dart';
import 'vigil_http_error.dart';
import 'vigil_http_request.dart';
import 'vigil_http_response.dart';

/// In-memory recorder and event source for Vigil HTTP calls.
///
/// Applications normally use the process-wide [instance] and initialize it
/// once before attaching transport interceptors.
class Vigil {
  Vigil._();

  /// The process-wide Vigil recorder.
  static final Vigil instance = Vigil._();

  VigilConfig _config = const VigilConfig();
  final _calls = <VigilHttpCall>[];
  final _events = StreamController<VigilEvent>.broadcast();
  final _idRandom = Random.secure();

  /// Active capture configuration.
  VigilConfig get config => _config;

  /// Whether new calls are currently retained.
  bool get enabled => _config.enabled;

  /// An immutable snapshot of retained calls in capture order.
  List<VigilHttpCall> get calls => List.unmodifiable(_calls);

  /// Lifecycle events emitted when calls change or are cleared.
  Stream<VigilEvent> get events => _events.stream;

  /// Applies [config] and clears previously captured calls.
  void init({VigilConfig? config}) {
    _config = config ?? const VigilConfig();
    clear();
  }

  /// Starts retaining [request] and returns its generated call identifier.
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

  /// Marks the call matching [id] as successfully completed.
  void completeCall(String id, VigilHttpResponse response) {
    if (!_config.enabled) return;
    final index = _calls.indexWhere((call) => call.id == id);
    if (index == -1) return;
    final call = _calls[index].complete(response);
    _calls[index] = call;
    _events.add(VigilEvent(type: VigilEventType.callCompleted, call: call));
  }

  /// Marks the call matching [id] as failed.
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

  /// Exports [call] as a shell-safe cURL command using captured values.
  String toCurl(VigilHttpCall call) => VigilCurlExporter.export(call);

  /// Removes all retained calls and emits a clear event.
  void clear() {
    _calls.clear();
    if (!_events.isClosed) {
      _events.add(const VigilEvent(type: VigilEventType.callsCleared));
    }
  }

  /// Permanently closes the event stream.
  ///
  /// The singleton cannot be reinitialized after disposal. Most applications
  /// should leave it alive for the process lifetime.
  void dispose() {
    _events.close();
  }

  String _newId() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final suffix = _idRandom.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$micros$suffix';
  }
}
