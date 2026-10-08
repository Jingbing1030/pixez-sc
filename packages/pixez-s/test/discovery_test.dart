import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:pixez_s/config/server_config.dart';
import 'package:pixez_s/service/discovery_service.dart';
import 'package:test/test.dart';

void main() {
  group('LAN Discovery Service Tests', () {
    test('should respond to client discovery probe over UDP', () async {
      const testPort = 41250;
      final config = ServerConfig(
        dataDir: Directory.systemTemp.path,
        port: 8888,
        discoveryPort: testPort,
      );
      final discoveryService = DiscoveryService(
        config: config,
        actualHttpPort: 8888,
        discoveryPort: testPort,
      );
      await discoveryService.start();

      final clientSocket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final completer = Completer<Map<String, dynamic>>();

      clientSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = clientSocket.receive();
          if (datagram != null) {
            try {
              final payload = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
              if (!completer.isCompleted) {
                completer.complete(payload);
              }
            } catch (_) {}
          }
        }
      });

      // Send probe to server
      final probe = jsonEncode({'action': 'discover', 'service': 'pixez-s'});
      clientSocket.send(utf8.encode(probe), InternetAddress.loopbackIPv4, testPort);

      final response = await completer.future.timeout(const Duration(seconds: 3));
      clientSocket.close();
      discoveryService.stop();

      expect(response['service'], equals('pixez-s'));
      expect(response['port'], equals(8888));
      expect(response['version'], equals('0.1.0'));
      expect(response['host_name'], isNotEmpty);
    });

    test('should automatically increment UDP port if candidate port is occupied', () async {
      const occupiedPort = 41260;
      // Intentionally occupy the port exclusively
      final blockerSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        occupiedPort,
        reuseAddress: false,
        reusePort: false,
      );

      final config = ServerConfig(
        dataDir: Directory.systemTemp.path,
        port: 9090,
        discoveryPort: occupiedPort,
      );

      final fallbackService = DiscoveryService(
        config: config,
        actualHttpPort: 9090,
        discoveryPort: occupiedPort,
      );
      await fallbackService.start();

      // The service should have shifted to occupiedPort + 1
      expect(fallbackService.activeDiscoveryPort, equals(occupiedPort + 1));
      expect(fallbackService.isRunning, isTrue);

      fallbackService.stop();
      blockerSocket.close();
    });
  });
}
