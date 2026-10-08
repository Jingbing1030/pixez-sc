import 'dart:io';
import 'package:path/path.dart' as p;

class ServerConfig {
  final String host;
  final int port;
  final int discoveryPort;
  final String dataDir;
  final String? upstreamProxy; // e.g. "http://127.0.0.1:7890"

  ServerConfig({
    this.host = '0.0.0.0',
    this.port = 8080,
    this.discoveryPort = 41234,
    required this.dataDir,
    this.upstreamProxy,
  });

  String get dbDir => p.join(dataDir, 'db');
  String get cacheDir => p.join(dataDir, 'cache');
  String get archiveDir => p.join(dataDir, 'archives');
  String get downloadDir => p.join(dataDir, 'downloads');

  void ensureDirectories() {
    Directory(dbDir).createSync(recursive: true);
    Directory(cacheDir).createSync(recursive: true);
    Directory(archiveDir).createSync(recursive: true);
    Directory(downloadDir).createSync(recursive: true);
  }

  factory ServerConfig.fromEnv() {
    final env = Platform.environment;
    final host = env['PIXEZ_HOST'] ?? '0.0.0.0';
    final port = int.tryParse(env['PIXEZ_PORT'] ?? '') ?? 8080;
    final discoveryPort = int.tryParse(env['PIXEZ_DISCOVERY_PORT'] ?? '') ?? 41234;
    final dataDir = env['PIXEZ_DATA_DIR'] ?? p.join(Directory.current.path, 'data');
    final proxy = env['PIXEZ_PROXY'] ?? env['HTTP_PROXY'] ?? env['http_proxy'];

    final config = ServerConfig(
      host: host,
      port: port,
      discoveryPort: discoveryPort,
      dataDir: dataDir,
      upstreamProxy: proxy,
    );
    config.ensureDirectories();
    return config;
  }
}
