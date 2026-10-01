import 'package:vigil_core/vigil_core.dart';

void main() {
  Vigil.instance.init(
    config: const VigilConfig(
      maxCalls: 200,
      maskBodyFields: {'password', 'token', 'secret'},
    ),
  );

  final trace = VigilTraceContext.generate();
  final timings = VigilServerTimingParser.parse(
    'db;dur=24.5;desc="Load account", cache;dur=2.1',
  );

  print(trace.toHeader());
  print(timings.map((timing) => timing.name).join(', '));
}
