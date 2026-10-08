import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredServer {
  final String service;
  final String version;
  final String hostName;
  final int port;
  final List<String> ips;
  final String primaryUrl;
  final int timestamp;

  DiscoveredServer({
    required this.service,
    required this.version,
    required this.hostName,
    required this.port,
    required this.ips,
    required this.primaryUrl,
    required this.timestamp,
  });

  factory DiscoveredServer.fromJson(Map<String, dynamic> json, String remoteIp) {
    final service = (json['service'] ?? '').toString();
    final version = (json['version'] ?? '0.1.0').toString();
    final hostName = (json['host_name'] ?? 'Pixez Server').toString();
    final port = (json['port'] as num?)?.toInt() ?? 8080;
    final rawIps = json['ips'] as List<dynamic>? ?? [];
    final ips = rawIps.map((e) => e.toString()).toList();

    // Use remote address if available, or first IP reported
    final targetIp = ips.contains(remoteIp) ? remoteIp : (ips.isNotEmpty ? ips.first : remoteIp);
    final primaryUrl = 'http://$targetIp:$port';

    return DiscoveredServer(
      service: service,
      version: version,
      hostName: hostName,
      port: port,
      ips: ips,
      primaryUrl: primaryUrl,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  String toString() => '$hostName ($primaryUrl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredServer &&
          runtimeType == other.runtimeType &&
          primaryUrl == other.primaryUrl;

  @override
  int get hashCode => primaryUrl.hashCode;
}

class LanDiscoveryClient {
  static const int baseDiscoveryPort = 41234;
  static const int maxPortScan = 5;

  RawDatagramSocket? _socket;
  final StreamController<DiscoveredServer> _serverStreamController =
      StreamController<DiscoveredServer>.broadcast();

  Stream<DiscoveredServer> get serverStream => _serverStreamController.stream;

  /// Quick scan LAN for Pixez-s servers (returns deduplicated list after timeout)
  Future<List<DiscoveredServer>> scan({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final discoveredMap = <String, DiscoveredServer>{};
    RawDatagramSocket? clientSocket;

    try {
      clientSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      clientSocket.broadcastEnabled = true;

      final subscription = clientSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = clientSocket?.receive();
          if (datagram != null) {
            try {
              final text = utf8.decode(datagram.data);
              final json = jsonDecode(text) as Map<String, dynamic>;
              if (json['service'] == 'pixez-s') {
                final server = DiscoveredServer.fromJson(json, datagram.address.address);
                discoveredMap[server.primaryUrl] = server;
                _serverStreamController.add(server);
              }
            } catch (_) {}
          }
        }
      });

      // Send probe to candidate discovery ports
      final probeBytes = utf8.encode(jsonEncode({'action': 'discover', 'service': 'pixez-s'}));
      for (int i = 0; i < maxPortScan; i++) {
        final targetPort = baseDiscoveryPort + i;
        try {
          clientSocket.send(probeBytes, InternetAddress('255.255.255.255'), targetPort);
        } catch (_) {}
      }

      await Future.delayed(timeout);
      await subscription.cancel();
    } catch (e) {
      print('[LanDiscoveryClient] Scan error: $e');
    } finally {
      clientSocket?.close();
    }

    return discoveredMap.values.toList();
  }

  /// Start background continuous listening for UDP beacons
  Future<void> startListening() async {
    if (_socket != null) return;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        baseDiscoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _socket!.broadcastEnabled = true;

      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            try {
              final text = utf8.decode(datagram.data);
              final json = jsonDecode(text) as Map<String, dynamic>;
              if (json['service'] == 'pixez-s') {
                final server = DiscoveredServer.fromJson(json, datagram.address.address);
                _serverStreamController.add(server);
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}
  }

  void stopListening() {
    _socket?.close();
    _socket = null;
  }
}

final LanDiscoveryClient lanDiscoveryClient = LanDiscoveryClient();
