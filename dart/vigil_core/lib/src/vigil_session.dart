import 'session_platform.dart' if (dart.library.io) 'session_platform_io.dart'
    as platform;
import 'trace_context.dart';

/// Identity shared by API requests and desktop capture uploads for one app run.
class VigilSession {
  const VigilSession._({
    required this.id,
    required this.startedAt,
    required this.deviceType,
    this.deviceName,
  });

  /// Creates a fresh session, with an optional developer-supplied identity.
  factory VigilSession.create({
    String? sessionId,
    String? deviceType,
    String? deviceName,
    DateTime? startedAt,
  }) {
    final id = sessionId ?? VigilTraceContext.generate().traceId;
    final type = deviceType ?? platform.vigilDeviceType();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(id)) {
      throw const FormatException('Invalid Vigil session ID.');
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(type) ||
        (deviceName != null &&
            (deviceName.isEmpty || deviceName.length > 128))) {
      throw const FormatException('Invalid Vigil device details.');
    }
    return VigilSession._(
      id: id,
      startedAt: (startedAt ?? DateTime.now()).toUtc(),
      deviceType: type,
      deviceName: deviceName,
    );
  }

  /// Reads a saved session identity.
  factory VigilSession.fromJson(Map<String, dynamic> json) =>
      VigilSession.create(
        sessionId: json['sessionId'] as String,
        deviceType: json['deviceType'] as String,
        deviceName: json['deviceName'] as String?,
        startedAt: DateTime.parse(json['sessionStartedAt'] as String),
      );

  final String id;
  final DateTime startedAt;

  /// Automatically detected platform, such as android, ios, web or macos.
  final String deviceType;

  /// Optional friendly label, such as a development phone's model or name.
  final String? deviceName;

  Map<String, Object?> toJson() => {
        'sessionId': id,
        'sessionStartedAt': startedAt.toIso8601String(),
        'deviceType': deviceType,
        if (deviceName != null) 'deviceName': deviceName,
      };
}
