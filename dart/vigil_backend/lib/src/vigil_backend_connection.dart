import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vigil_core/vigil_core.dart';

import 'vigil_backend_config.dart';
import 'vigil_backend_payload.dart';

/// Subscribes to Vigil events and uploads calls in bounded HTTP batches.
class VigilBackendConnection {
  /// Creates a stopped backend connection.
  ///
  /// Call [start] manually, or use [connect] to create and start in one step.
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
  Future<void>? _activeFlush;
  var _isDisposed = false;

  /// Whether the connection currently has an active Vigil event subscription.
  bool get isRunning => _subscription != null;

  /// Whether this connection has been disposed.
  bool get isDisposed => _isDisposed;

  /// Number of calls currently waiting for a successful upload.
  int get queuedCount => _queue.length;

  /// Creates and immediately starts a backend connection.
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

  /// Starts listening for captured calls when upload is enabled.
  void start() {
    if (_isDisposed || !_config.enabled || _subscription != null) return;

    _subscription = _vigil.events.listen(_handleEvent);
    if (_config.flushInterval > Duration.zero) {
      _flushTimer = Timer.periodic(_config.flushInterval, (_) {
        unawaited(flush());
      });
    }
  }

  /// Attempts to upload the next batch.
  ///
  /// Failed and non-2xx batches remain queued for a future attempt.
  Future<void> flush() {
    if (_isDisposed) return Future<void>.value();
    return _flushNextBatch();
  }

  Future<void> _flushNextBatch() {
    if (_activeFlush != null) return _activeFlush!;
    if (!_config.enabled || _queue.isEmpty) {
      return Future<void>.value();
    }
    return _activeFlush = _flushBatch().whenComplete(() => _activeFlush = null);
  }

  Future<void> _flushBatch() async {
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
        for (final call in batch) {
          _queue.remove(call);
        }
      }
    } on Object {
      // Keep the queued batch for the next flush attempt.
    }
  }

  /// Stops capture upload and releases owned resources.
  ///
  /// When [flushPending] is true, one final batch is attempted before the
  /// internally owned HTTP client is closed.
  Future<void> dispose({bool flushPending = true}) async {
    if (_isDisposed) return;
    _isDisposed = true;
    _flushTimer?.cancel();
    try {
      await _subscription?.cancel();
      _subscription = null;
      await _activeFlush;
      if (flushPending) await _flushNextBatch();
    } finally {
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
