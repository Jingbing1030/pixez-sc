import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:pixez_s/config/server_config.dart';
import 'package:pixez_s/pixez_server.dart';
import 'package:test/test.dart';

void main() {
  group('Embedded PixezServer Lifecycle Tests', () {
    late Directory tempDir;
    late PixezServer server;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pixez_embedded_');
      final config = ServerConfig(
        dataDir: tempDir.path,
        port: 48950,
        discoveryPort: 41295,
      );
      server = PixezServer(config: config);
    });

    tearDown(() async {
      await server.stop();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('can start, serve health check, and stop gracefully', () async {
      expect(server.isRunning, isFalse);

      final boundPort = await server.start(
        host: '127.0.0.1',
        preferredPort: 48950,
        enableDiscovery: false,
      );

      expect(server.isRunning, isTrue);
      expect(boundPort, equals(48950));
      expect(server.port, equals(48950));

      // Query health endpoint
      final dio = Dio();
      final resp = await dio.get('http://127.0.0.1:$boundPort/health');
      expect(resp.statusCode, equals(200));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      expect(data['mode'], equals('embedded'));
      expect(data['service'], equals('Pixez-s'));

      // Stop server
      await server.stop();
      expect(server.isRunning, isFalse);

      // Verify server is no longer accepting connections
      expect(
        dio.get('http://127.0.0.1:$boundPort/health', options: Options(sendTimeout: const Duration(milliseconds: 500))),
        throwsA(anything),
      );
    });

    test('automatically increments port if candidate port is occupied', () async {
      // 1. Bind a dummy socket on 48950
      final dummySocket = await ServerSocket.bind('127.0.0.1', 48950);

      // 2. Start PixezServer requesting 48950 -> should automatically bind 48951
      final boundPort = await server.start(
        host: '127.0.0.1',
        preferredPort: 48950,
        enableDiscovery: false,
      );

      expect(boundPort, equals(48951));
      expect(server.port, equals(48951));

      final dio = Dio();
      final resp = await dio.get('http://127.0.0.1:$boundPort/health');
      expect(resp.statusCode, equals(200));

      await dummySocket.close();
      await server.stop();
    });
  });
}
