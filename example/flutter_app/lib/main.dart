import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vigil/vigil.dart';

void main() {
  Vigil.instance.init(config: const VigilConfig(debugKey: 'dev-vigil'));
  runApp(const VigilExampleApp());
}

class VigilExampleApp extends StatefulWidget {
  const VigilExampleApp({super.key});

  @override
  State<VigilExampleApp> createState() => _VigilExampleAppState();
}

class _VigilExampleAppState extends State<VigilExampleApp> {
  late final VigilBackendConnection _backendConnection =
      VigilBackendConnection.connect(
    config: VigilBackendConfig(
      endpoint: Uri.parse('http://localhost:4010/vigil/ingest'),
      ingestKey: 'dev-vigil',
      flushInterval: const Duration(seconds: 1),
      clientInfo: const {'app': 'vigil_example'},
    ),
  );

  late final Dio _dio = Dio(BaseOptions(baseUrl: 'http://localhost:4010'))
    ..interceptors.add(VigilDioInterceptor());

  String _lastResult = 'No request yet';

  @override
  void dispose() {
    unawaited(_backendConnection.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: VigilOverlay(
        child: Scaffold(
          appBar: AppBar(title: const Text('Vigil Example')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: () => _call('/ok'),
                      child: const Text('/ok'),
                    ),
                    FilledButton(
                      onPressed: () => _call('/slow'),
                      child: const Text('/slow'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _call('/error'),
                      child: const Text('/error'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(_lastResult),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _call(String path) async {
    try {
      final response = await _dio.get<Object?>(path);
      setState(
        () => _lastResult = '$path -> ${response.statusCode}: ${response.data}',
      );
    } on DioException catch (error) {
      setState(
        () => _lastResult =
            '$path -> ${error.response?.statusCode ?? error.type}: ${error.message}',
      );
    }
  }
}
