import 'vigil_call.dart';

/// Converts captured calls into shell-safe cURL commands.
class VigilCurlExporter {
  const VigilCurlExporter._();

  /// Returns a cURL command for [call] using its masked captured values.
  static String export(VigilHttpCall call) {
    final parts = <String>['curl', '-X', _quote(call.request.method)];

    for (final entry in call.request.headers.entries) {
      parts.add('-H');
      parts.add(_quote('${entry.key}: ${entry.value}'));
    }

    final body = call.request.body.text;
    if (body != null && body.isNotEmpty) {
      parts.add('--data-raw');
      parts.add(_quote(body));
    }

    parts.add(_quote(call.request.uri.toString()));
    return parts.join(' ');
  }

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
}
