import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vigil_core/vigil_core.dart';

import 'vigil_backend_config.dart';
import 'vigil_backend_payload.dart';

class VigilBackendConnection {
  VigilBackendConnection({
    required VigilBackendConfig config,
    Vigil? vigil,
    http.Client? client,
  })  : _config = config,
        _vigil = vigil ?? Vigil.instance,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final VigilBackendConfig _config;
  final Vigil _vigil;
  final http.Client _client;
  final bool _ownsClient;
  final List<VigilHttpCall> _queue = [];

  StreamSubscription<VigilEvent>? _subscription;
  Timer? _flushTimer;
  var _isFlushing = false;
  var _isDisposed = false;

  bool get isRunning => _subscription != null;
  bool get isDisposed => _isDisposed;
  int get queuedCount => _queue.length;

  static VigilBackendConnection connect({
    required VigilBackendConfig config,
    Vigil? vigil,
    http.Client? client,
  }) {
    final connection = VigilBackendConnection(
      config: config,
      vigil: vigil,
      client: client,
    );
    connection.start();
    return connection;
  }

  void start() {
    if (_isDisposed || !_config.enabled || _subscription != null) return;

    _subscription = _vigil.events.listen(_handleEvent);
    if (_config.flushInterval > Duration.zero) {
      _flushTimer = Timer.periodic(_config.flushInterval, (_) {
        unawaited(flush());
      });
    }
  }

  Future<void> flush() async {
    if (_isDisposed ||
        !_config.enabled ||
        _isFlushing ||
        _queue.isEmpty) {
      return;
    }

    _isFlushing = true;
    try {
      final batch = _queue.take(_config.batchSize).toList(growable: false);
      final payload = VigilBackendPayload(
        sentAt: DateTime.now(),
        calls: batch,
        clientInfo: _config.clientInfo,
      );
      final response = await _client
          .post(
            _config.endpoint,
            headers: _config.requestHeaders(),
            body: jsonEncode(payload.toJson()),
          )
          .timeout(_config.requestTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _queue.removeRange(0, batch.length);
      }
    } on Object {
      // Keep the queued batch for the next flush attempt.
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> dispose({bool flushPending = true}) async {
    if (_isDisposed) return;
    _isDisposed = true;
    _flushTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;

    try {
      if (!flushPending) return;
      _isDisposed = false;
      await flush();
    } finally {
      _isDisposed = true;

      if (_ownsClient) {
        _client.close();
      }
    }
  }

  void _handleEvent(VigilEvent event) {
    final call = event.call;
    if (call == null) return;

    final shouldUpload = switch (event.type) {
      VigilEventType.callStarted => _config.includePendingCalls,
      VigilEventType.callCompleted => true,
      VigilEventType.callFailed => true,
      VigilEventType.callsCleared => false,
    };
    if (!shouldUpload) return;

    _queue.add(call);
    while (_queue.length > _config.maxQueueSize) {
      _queue.removeAt(0);
    }

    if (_queue.length >= _config.batchSize) {
      unawaited(flush());
    }
  }
}
