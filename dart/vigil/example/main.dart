import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vigil/vigil.dart';

void main() {
  Vigil.instance.init(config: const VigilConfig(enabled: kDebugMode));
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) => VigilOverlay(
        enabled: kDebugMode,
        showFloatingButton: true,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(
        body: Center(child: Text('Vigil is ready to capture Dio traffic.')),
      ),
    );
  }
}
