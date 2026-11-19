import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vigil/vigil.dart';

void main() {
  Vigil.instance.init(
    config: const VigilConfig(enabled: kDebugMode, debugKey: 'dev-vigil'),
  );
  runApp(const VigilExampleApp());
}

class VigilExampleApp extends StatefulWidget {
  const VigilExampleApp({super.key});

  @override
  State<VigilExampleApp> createState() => _VigilExampleAppState();
}

class _VigilExampleAppState extends State<VigilExampleApp> {
  late final VigilBackendConnection _backendConnection;

  VigilBackendConnection _connectBackend() => VigilBackendConnection.connect(
        config: VigilBackendConfig(
          enabled: kDebugMode,
          endpoint: Uri.parse('$_origin/vigil/ingest'),
          ingestKey: 'dev-vigil',
          flushInterval: const Duration(seconds: 1),
          includePendingCalls: true,
          clientInfo: {
            'app': 'vigil_example',
          },
        ),
      );

  static final _origin =
      const String.fromEnvironment('VIGIL_API_ORIGIN').isNotEmpty
          ? const String.fromEnvironment('VIGIL_API_ORIGIN')
          : kIsWeb
              ? Uri.base.origin
              : 'http://localhost:4010';
  late final _mocks = VigilMockController(allowedOrigins: {_origin});
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: _origin,
    receiveTimeout: const Duration(seconds: 5),
  ))
    ..interceptors.add(VigilDioInterceptor(mocks: _mocks));
  late final _replay = VigilDioReplay(_dio, allowedOrigins: {_origin});

  String _lastResult = 'Send a request to see the response here.';
  String? _requestRunning;
  int? _lastStatus;

  @override
  void initState() {
    super.initState();
    // Subscribe to completed calls before the first request is made.
    _backendConnection = _connectBackend();
  }

  @override
  void dispose() {
    unawaited(_backendConnection.dispose());
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Builder(
          builder: (context) => VigilOverlay(
                replay: _replay.send,
                mocks: _mocks,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Vigil'),
                    actions: [
                      TextButton.icon(
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => VigilInspector(
                              replay: _replay.send, mocks: _mocks),
                        )),
                        icon: const Icon(Icons.network_check_rounded, size: 19),
                        label: const Text('Open inspector'),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                        child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 20),
                          Text('API playground',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -.7,
                                  )),
                          const SizedBox(height: 8),
                          Text(
                              'Run a request, then inspect its response and backend trace.',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          const SizedBox(height: 28),
                          LayoutBuilder(builder: (context, constraints) {
                            final width = constraints.maxWidth < 650
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 24) / 3;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final (path, label, caption, icon) in [
                                  (
                                    '/ok',
                                    'Load user',
                                    'Fetch a user from the backend.',
                                    Icons.person_outline_rounded
                                  ),
                                  (
                                    '/slow',
                                    'Slow request',
                                    'Inspect cache and database timing.',
                                    Icons.timer_outlined
                                  ),
                                  (
                                    '/error',
                                    'Server error',
                                    'Inspect a backend exception.',
                                    Icons.error_outline_rounded
                                  ),
                                ])
                                  SizedBox(
                                      width: width,
                                      child: _requestCard(
                                          context, path, label, caption, icon)),
                              ],
                            );
                          }),
                          const SizedBox(height: 28),
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLowest,
                              border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  Text('Last response',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const Spacer(),
                                  if (_requestRunning != null)
                                    const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                  if (_lastStatus != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _lastStatus! >= 400
                                            ? Theme.of(context)
                                                .colorScheme
                                                .errorContainer
                                            : Theme.of(context)
                                                .colorScheme
                                                .primaryContainer,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('$_lastStatus',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: _lastStatus! >= 400
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .onErrorContainer
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onPrimaryContainer,
                                          )),
                                    ),
                                ]),
                                const SizedBox(height: 16),
                                SelectableText(_lastResult,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      height: 1.8,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                  ),
                ),
              )),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF137955),
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFF86D9AC) : const Color(0xFF137955),
      surface: dark ? const Color(0xFF0E1512) : const Color(0xFFF5F8F6),
      surfaceContainerLowest: dark ? const Color(0xFF151E19) : Colors.white,
      outlineVariant: dark ? const Color(0xFF2B3B31) : const Color(0xFFDCE5DF),
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
    );
  }

  Widget _requestCard(BuildContext context, String path, String label,
      String caption, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon,
                size: 22,
                color: path == '/error' ? scheme.error : scheme.primary),
            const Spacer(),
            Text('GET $path',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                )),
          ]),
          const SizedBox(height: 18),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(caption,
              style: TextStyle(
                  fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _requestRunning == null ? () => _call(path) : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 17),
            label: Text(_requestRunning == path ? 'Sending…' : 'Send request'),
          ),
        ],
      ),
    );
  }

  String _responseText(Object? value) => value is String
      ? value
      : const JsonEncoder.withIndent('  ').convert(value);

  Future<void> _call(String path) async {
    setState(() {
      _requestRunning = path;
      _lastStatus = null;
      _lastResult = 'Waiting for GET $path…';
    });
    try {
      final response = await _dio.get<Object?>(path);
      if (!mounted) return;
      setState(() {
        _lastStatus = response.statusCode;
        _lastResult = _responseText(response.data);
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _lastStatus = error.response?.statusCode;
        _lastResult = error.response == null
            ? error.message ?? 'The request failed.'
            : _responseText(error.response!.data);
      });
    } finally {
      if (mounted) setState(() => _requestRunning = null);
    }
  }
}
