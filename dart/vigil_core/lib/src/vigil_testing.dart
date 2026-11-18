import 'dart:convert';

/// A manually edited request for the application's development transport.
class VigilReplayRequest {
  const VigilReplayRequest({
    required this.originalUri,
    required this.uri,
    required this.method,
    required this.headers,
    this.jsonBody,
  });

  final Uri originalUri;
  final Uri uri;
  final String method;
  final Map<String, String> headers;

  /// A complete JSON document, or null for no request body.
  final String? jsonBody;
}

/// Sends a development request and returns its HTTP status when available.
typedef VigilReplay = Future<int?> Function(VigilReplayRequest request);

/// Effect applied by a development mock rule.
enum VigilMockEffect { response, timeout, connectionError, delay }

/// Matches an HTTP method and exact path on a configured development origin.
class VigilMockRule {
  VigilMockRule({
    required this.method,
    required this.path,
    required this.effect,
    this.statusCode = 200,
    this.jsonBody = '{}',
    this.delay = Duration.zero,
  }) {
    if (!RegExp(r'^[A-Z]+$').hasMatch(method) || !path.startsWith('/')) {
      throw const FormatException('Enter a method and an absolute path.');
    }
    if (delay.isNegative || delay > const Duration(seconds: 30)) {
      throw const FormatException('Delay must be between 0 and 30 seconds.');
    }
    if (effect == VigilMockEffect.response) {
      if (statusCode < 200 || statusCode > 599) {
        throw const FormatException('Status must be between 200 and 599.');
      }
      jsonDecode(jsonBody);
    }
  }

  final String method;
  final String path;
  final VigilMockEffect effect;
  final int statusCode;
  final String jsonBody;
  final Duration delay;
}

/// Holds in-memory rules shared by the mock editor and transport.
class VigilMockController {
  VigilMockController({required Set<String> allowedOrigins})
      : allowedOrigins = Set.unmodifiable(allowedOrigins);

  final Set<String> allowedOrigins;
  final List<VigilMockRule> _rules = [];

  List<VigilMockRule> get rules => List.unmodifiable(_rules);

  void put(VigilMockRule rule) {
    _rules.removeWhere(
        (item) => item.method == rule.method && item.path == rule.path);
    _rules.add(rule);
  }

  void remove(VigilMockRule rule) => _rules.remove(rule);

  VigilMockRule? match(String method, Uri uri) {
    if (!vigilMatchesOrigin(uri, allowedOrigins)) return null;
    return _rules
        .where((rule) => rule.method == method && rule.path == uri.path)
        .firstOrNull;
  }
}

/// Checks whether an absolute HTTP(S) URI belongs to a configured origin.
bool vigilMatchesOrigin(Uri uri, Set<String> allowedOrigins) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    allowedOrigins.contains(uri.origin);
