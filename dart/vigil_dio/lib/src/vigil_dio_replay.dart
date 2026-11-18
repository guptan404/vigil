import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:vigil_core/vigil_core.dart';

/// Manual replay using a caller-provided Dio client and explicit dev origins.
/// Configure the client with any app-specific authentication it needs.
class VigilDioReplay {
  VigilDioReplay(this.dio, {required Set<String> allowedOrigins})
      : allowedOrigins = Set.unmodifiable(allowedOrigins);

  final Dio dio;
  final Set<String> allowedOrigins;

  Future<int?> send(VigilReplayRequest request) async {
    if (!vigilMatchesOrigin(request.originalUri, allowedOrigins) ||
        !vigilMatchesOrigin(request.uri, allowedOrigins) ||
        request.originalUri.origin != request.uri.origin) {
      throw const FormatException(
          'Replay requires the original development origin.');
    }
    if (!RegExp(r'^[A-Z]+$').hasMatch(request.method)) {
      throw const FormatException('Enter a valid HTTP method.');
    }
    if (Uri.decodeFull(request.uri.toString()).contains('[redacted]') ||
        (request.jsonBody?.contains('[redacted]') ?? false)) {
      throw const FormatException('Replace redacted values before replaying.');
    }
    final headers = <String, String>{};
    for (final entry in request.headers.entries) {
      if (reservedHeaders.contains(entry.key.toLowerCase()) ||
          entry.value.contains('[redacted]')) {
        throw const FormatException('Remove reserved or redacted headers.');
      }
      headers[entry.key] = entry.value;
    }
    final body = request.jsonBody;
    if (body != null) jsonDecode(body);
    final response = await dio.requestUri<Object?>(
      request.uri,
      data: body,
      options: Options(
        method: request.method,
        headers: headers,
        contentType: body == null ? null : Headers.jsonContentType,
        followRedirects: false,
        validateStatus: (status) => status != null,
      ),
    );
    return response.statusCode;
  }

  static const reservedHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'host',
    'content-length',
    'transfer-encoding',
    'connection',
    'traceparent',
    'tracestate',
    'vigil-key',
    'vigil-ingest-key',
  };
}
