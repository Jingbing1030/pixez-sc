import 'dart:io';
import '../lib/config/server_config.dart';
import '../lib/pixez_server.dart';

void main(List<String> args) async {
  final config = ServerConfig.fromEnv();
  print('==================================================');
  print('           Pixez-s (Headless Server)              ');
  print('==================================================');
  print('[Config] Data Directory: ${config.dataDir}');
  if (config.upstreamProxy != null) {
    print('[Config] Upstream Proxy: ${config.upstreamProxy}');
  }

  final server = PixezServer(config: config);
  final actualPort = await server.start();
  print('[Server] Running on http://${config.host}:$actualPort');
  print('==================================================');

  ProcessSignal.sigint.watch().listen((_) async {
    print('\n[Server] Shutting down...');
    await server.stop();
    exit(0);
  });
}
