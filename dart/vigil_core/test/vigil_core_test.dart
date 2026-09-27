import 'dart:convert';

import 'package:test/test.dart';
import 'package:vigil_core/vigil_core.dart';

void main() {
  test('generates and parses traceparent', () {
    final trace = VigilTraceContext.generate();
    final parsed = VigilTraceContext.tryParse(trace.toHeader());

    expect(parsed, isNotNull);
    expect(parsed!.traceId, trace.traceId);
    expect(parsed.parentId, trace.parentId);
  });

  test('parses quoted Server-Timing values', () {
    final timings = VigilServerTimingParser.parse(
      'db;dur=42;desc="Fetch user", auth;dur=8;desc="JWT verify"',
    );

    expect(timings, hasLength(2));
    expect(timings.first.name, 'db');
    expect(timings.first.duration, 42);
    expect(timings.first.description, 'Fetch user');
  });

  test('parses base64url debug payload', () {
    final encoded = base64UrlEncode(
      utf8.encode(
        jsonEncode({
          'error': 'boom',
          'stack': 'at test',
          'context': {'route': '/error'},
          'truncated': true,
        }),
      ),
    );

    final payload = VigilDebugPayload.tryParse(encoded);

    expect(payload, isNotNull);
    expect(payload!.error, 'boom');
    expect(payload.context['route'], '/error');
    expect(payload.truncated, isTrue);
  });

  test('masks sensitive headers and JSON fields', () {
    final headers = VigilDataMasker.maskHeaders(
      {'Authorization': 'secret', 'Accept': 'json'},
      {'authorization'},
    );
    final body = VigilDataMasker.maskJson(
      {'email': 'a@example.com', 'password': 'secret'},
      {'password'},
    ) as Map;

    expect(headers['Authorization'], '[redacted]');
    expect(headers['Accept'], 'json');
    expect(body['password'], '[redacted]');
  });

  test('caps body summaries', () {
    final summary = VigilBodySummary.summarize(
      'abcdef',
      headers: {'content-type': 'text/plain'},
      config: const VigilConfig(maxBodyBytes: 3),
    );

    expect(summary.text, 'abc');
    expect(summary.truncated, isTrue);
    expect(summary.byteLength, 6);
  });

  test('evicts old calls from ring buffer', () {
    final vigil = Vigil.instance;
    vigil.init(config: const VigilConfig(maxCalls: 1));

    String start(String path) => vigil.startCall(
          VigilHttpRequest(
            method: 'GET',
            uri: Uri.parse('https://example.com/$path'),
            headers: const {},
            body: VigilBodySummary.empty,
            timestamp: DateTime.now(),
            traceContext: VigilTraceContext.generate(),
          ),
        );

    start('one');
    start('two');

    expect(vigil.calls, hasLength(1));
    expect(vigil.calls.single.request.uri.path, '/two');
  });

  test('escapes cURL body values', () {
    final trace = VigilTraceContext.generate();
    final callId = Vigil.instance.startCall(
      VigilHttpRequest(
        method: 'POST',
        uri: Uri.parse('https://example.com/users'),
        headers: {'traceparent': trace.toHeader()},
        body: const VigilBodySummary(kind: VigilBodyKind.text, text: "it's ok"),
        timestamp: DateTime.now(),
        traceContext: trace,
      ),
    );
    final call = Vigil.instance.calls.firstWhere((item) => item.id == callId);

    expect(Vigil.instance.toCurl(call), contains(r"it'\''s ok"));
  });
}
