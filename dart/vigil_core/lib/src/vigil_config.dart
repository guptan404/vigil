class VigilConfig {
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
  });

  final bool enabled;
  final int maxCalls;
  final int maxBodyBytes;
  final bool captureBody;
  final String? debugKey;
  final Set<String> maskHeaders;
  final Set<String> maskBodyFields;
}
