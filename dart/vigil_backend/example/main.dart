import 'package:vigil_backend/vigil_backend.dart';
import 'package:vigil_core/vigil_core.dart';

Future<void> main() async {
  Vigil.instance.init();

  final connection = VigilBackendConnection.connect(
    config: VigilBackendConfig(
      enabled: false,
      endpoint: Uri.parse('https://dev-api.example.com/vigil/ingest'),
      ingestKey: const String.fromEnvironment('VIGIL_INGEST_KEY'),
      clientInfo: const {'app': 'example'},
    ),
  );

  await connection.dispose();
}
