import 'package:dio/dio.dart';
import 'package:vigil_core/vigil_core.dart';
import 'package:vigil_dio/vigil_dio.dart';

void main() {
  Vigil.instance.init(
    config: const VigilConfig(
      debugKey: String.fromEnvironment('VIGIL_DEBUG_KEY'),
    ),
  );

  final dio = Dio()..interceptors.add(VigilDioInterceptor());
  print('Vigil is attached to ${dio.options.baseUrl}');
}
