import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pixez/main.dart';
import 'package:pixez_s/config/server_config.dart';
import 'package:pixez_s/pixez_server.dart';

class EmbeddedServerManager {
  static final EmbeddedServerManager _instance = EmbeddedServerManager._internal();
  static EmbeddedServerManager get instance => _instance;

  EmbeddedServerManager._internal();

  PixezServer? _server;
  bool _isStarting = false;
  String? _lastError;
  int? _actualPort;
  List<String> _lanIps = [];

  bool get isRunning => _server?.isRunning ?? false;
  bool get isStarting => _isStarting;
  String? get lastError => _lastError;
  int? get actualPort => _actualPort;
  List<String> get lanIps => _lanIps;

  /// Starts the embedded server using the current user settings.
  Future<bool> start() async {
    if (isRunning) return true;
    _isStarting = true;
    _lastError = null;

    try {
      // 1. Resolve application documents directory
      Directory docDir;
      try {
        docDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        docDir = Directory.current;
      }
      final dataDir = '${docDir.path}/pixez_server_data';

      // 2. Fetch local network IPs for LAN sharing display
      _lanIps = await getLocalIpAddresses();

      // 3. Create ServerConfig
      final preferredPort = userSetting.embeddedPort;
      final config = ServerConfig(
        dataDir: dataDir,
        port: preferredPort,
        discoveryPort: 41234,
      );

      _server = PixezServer(config: config);

      final bindHost = userSetting.embeddedLanShare ? '0.0.0.0' : '127.0.0.1';
      _actualPort = await _server!.start(
        host: bindHost,
        preferredPort: preferredPort,
        enableDiscovery: userSetting.embeddedLanShare,
      );

      // 4. Update userSetting to route requests to this embedded server
      await userSetting.setServerUrl('http://127.0.0.1:$_actualPort');
      await userSetting.setServerMode(true);

      _isStarting = false;
      return true;
    } catch (e, stack) {
      _isStarting = false;
      _lastError = e.toString();
      debugPrint('[EmbeddedServerManager] Failed to start server: $e\n$stack');
      return false;
    }
  }

  /// Stops the embedded server.
  Future<void> stop() async {
    try {
      await _server?.stop();
    } catch (e) {
      debugPrint('[EmbeddedServerManager] Error stopping server: $e');
    } finally {
      _server = null;
      _actualPort = null;
    }
  }

  /// Restarts the embedded server.
  Future<bool> restart() async {
    await stop();
    return await start();
  }

  /// Utility to get all non-loopback IPv4 addresses on the device.
  static Future<List<String>> getLocalIpAddresses() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !ips.contains(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    return ips;
  }
}

final embeddedServerManager = EmbeddedServerManager.instance;
