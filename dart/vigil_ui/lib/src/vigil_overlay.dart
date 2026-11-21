import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vigil_core/vigil_core.dart';

import 'vigil_copy_options.dart';
import 'vigil_inspector.dart';
import 'inspector_surface.dart';

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
    this.replay,
    this.mocks,
    this.copyOptions = const VigilCopyOptions(),
  });

  /// Which selective copy actions (endpoint, request content, response
  /// content) the inspector offers. All are enabled by default.
  final VigilCopyOptions copyOptions;

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

  /// Optional app-provided development transport for replay.
  final VigilReplay? replay;

  /// Optional rules shared with the app's Dio interceptor.
  final VigilMockController? mocks;

  @override
  State<VigilOverlay> createState() => _VigilOverlayState();
}

class _VigilOverlayState extends State<VigilOverlay> {
  bool _isInspectorOpen = false;
  StreamSubscription<UserAccelerometerEvent>? _shakeSubscription;
  DateTime? _lastShakeAt;
  final _childKey = GlobalKey();
  Route<void>? _inspectorRoute;

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
    if (!widget.enabled) _removeInspectorRoute();
  }

  @override
  void dispose() {
    _shakeSubscription?.cancel();
    _removeInspectorRoute();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (!widget.enabled) return child;

    return Stack(
      children: [
        child,
        if (widget.showFloatingButton && !_isInspectorOpen)
          Positioned(
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: FloatingActionButton.small(
                tooltip: Overlay.maybeOf(context) == null
                    ? null
                    : 'Open network inspector',
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
    final navigator = _applicationNavigator();
    if (navigator == null) return;

    final panel = InheritedTheme.captureAll(
      context,
      _InspectorPanel(
        navigatorKey: GlobalKey<NavigatorState>(),
        onClose: () => navigator.pop(),
        replay: widget.replay,
        mocks: widget.mocks,
        copyOptions: widget.copyOptions,
      ),
    );
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => panel,
    );
    _inspectorRoute = route;
    setState(() => _isInspectorOpen = true);
    unawaited(navigator.push(route).whenComplete(() {
      if (_inspectorRoute != route) return;
      _inspectorRoute = null;
      if (mounted) setState(() => _isInspectorOpen = false);
    }));
  }

  NavigatorState? _applicationNavigator() {
    final ancestor = Navigator.maybeOf(context, rootNavigator: true);
    if (ancestor != null) return ancestor;

    // MaterialApp.builder places this widget above the application's Navigator
    // (or Router), so find its first Navigator in the application child only.
    NavigatorState? navigator;
    void visit(Element element) {
      if (navigator != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        navigator = element.state as NavigatorState;
        return;
      }
      element.visitChildElements(visit);
    }

    _childKey.currentContext?.visitChildElements(visit);
    return navigator;
  }

  void _removeInspectorRoute() {
    final route = _inspectorRoute;
    if (route == null) return;
    _inspectorRoute = null;
    _isInspectorOpen = false;
    // Configuration changes/disposal can happen during the Navigator's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.navigatorKey,
    required this.onClose,
    required this.copyOptions,
    this.replay,
    this.mocks,
  });

  final VoidCallback onClose;
  final VigilReplay? replay;
  final VigilMockController? mocks;
  final VigilCopyOptions copyOptions;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return InspectorSurface(
      child: HeroControllerScope.none(
        child: NavigatorPopHandler<void>(
          onPopWithResult: (_) => navigatorKey.currentState?.pop(),
          child: Navigator(
            key: navigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => VigilInspector(
                onClose: onClose,
                replay: replay,
                mocks: mocks,
                copyOptions: copyOptions,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
