/// Controls capture, retention, masking, and gated diagnostics.
class VigilConfig {
  /// Creates a Vigil configuration.
  const VigilConfig({
    this.enabled = true,
    this.maxCalls = 500,
    this.maxBodyBytes = 64 * 1024,
    this.captureBody = true,
    this.debugKey,
    this.maskHeaders = const {
      'authorization',
      'cookie',
      'set-cookie',
      'vigil-key',
    },
    this.maskBodyFields = const {
      'password',
      'token',
      'access_token',
      'refresh_token',
      'secret',
      'ssn',
      'credit_card',
    },
  })  : assert(maxCalls > 0, 'maxCalls must be positive'),
        assert(maxBodyBytes >= 0, 'maxBodyBytes must not be negative');

  /// Whether calls should be captured.
  final bool enabled;

  /// Maximum number of calls retained in memory.
  final int maxCalls;

  /// Maximum number of body bytes retained for display.
  final int maxBodyBytes;

  /// Whether request and response body capture is enabled.
  final bool captureBody;

  /// Optional value sent as `Vigil-Key` to request gated backend diagnostics.
  final String? debugKey;

  /// Lowercase HTTP header names whose captured values are redacted.
  final Set<String> maskHeaders;

  /// Lowercase JSON field names whose captured values are redacted.
  final Set<String> maskBodyFields;
}
