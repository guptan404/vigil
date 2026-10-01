import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'vigil_inspector.dart';

/// Places the Vigil inspector above an application and optionally opens it by
/// shake gesture or floating action button.
class VigilOverlay extends StatefulWidget {
  /// Creates a Vigil inspector overlay around [child].
  const VigilOverlay({
    super.key,
    required this.child,
    this.enabled = kDebugMode,
    this.enableShake = true,
    this.showFloatingButton = false,
    this.shakeThreshold = 18,
    this.shakeCooldown = const Duration(seconds: 2),
    this.shakeEvents,
  });

  /// Application content rendered below the inspector.
  final Widget child;

  /// Whether inspector launch behavior is active.
  final bool enabled;

  /// Whether device shake gestures open the inspector.
  final bool enableShake;

  /// Whether to render an on-screen inspector launcher.
  final bool showFloatingButton;

  /// Minimum user-acceleration magnitude that counts as a shake.
  final double shakeThreshold;

  /// Minimum interval accepted between shake gestures.
  final Duration shakeCooldown;

  /// Optional acceleration stream, primarily useful for tests or custom input.
  final Stream<UserAccelerometerEvent>? shakeEvents;

  @override
  State<VigilOverlay> createState() => _VigilOverlayState();
}

class _VigilOverlayState extends State<VigilOverlay> {
  bool _isInspectorOpen = false;
  StreamSubscription<UserAccelerometerEvent>? _shakeSubscription;
  DateTime? _lastShakeAt;

  @override
  void initState() {
    super.initState();
    _configureShakeListener();
  }

  @override
  void didUpdateWidget(VigilOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.enableShake != widget.enableShake ||
        oldWidget.shakeEvents != widget.shakeEvents) {
      _configureShakeListener();
    }
  }

  @override
  void dispose() {
    _shakeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Stack(
      children: [
        widget.child,
        if (_isInspectorOpen) _InspectorPanel(onClose: _closeInspector),
        if (widget.showFloatingButton && !_isInspectorOpen)
          Positioned(
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: FloatingActionButton.small(
                onPressed: _openInspector,
                child: const Icon(Icons.network_check),
              ),
            ),
          ),
      ],
    );
  }

  void _configureShakeListener() {
    _shakeSubscription?.cancel();
    _shakeSubscription = null;

    if (!widget.enabled || !widget.enableShake) return;

    final events = widget.shakeEvents ??
        userAccelerometerEventStream(
          samplingPeriod: SensorInterval.gameInterval,
        );
    _shakeSubscription = events.listen(_handleShake, onError: (_) {});
  }

  void _handleShake(UserAccelerometerEvent event) {
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (magnitude < widget.shakeThreshold) return;

    final now = DateTime.now();
    final lastShakeAt = _lastShakeAt;
    if (lastShakeAt != null &&
        now.difference(lastShakeAt) < widget.shakeCooldown) {
      return;
    }

    _lastShakeAt = now;
    _openInspector();
  }

  void _openInspector() {
    if (!mounted) return;
    if (_isInspectorOpen) return;
    setState(() => _isInspectorOpen = true);
  }

  void _closeInspector() {
    if (!mounted) return;
    setState(() => _isInspectorOpen = false);
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: HeroControllerScope.none(
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => VigilInspector(onClose: onClose),
          ),
        ),
      ),
    );
  }
}
