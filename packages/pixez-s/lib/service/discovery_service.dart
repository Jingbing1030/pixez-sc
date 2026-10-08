import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/server_config.dart';

class DiscoveryService {
  final ServerConfig config;
  final int discoveryPort;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  bool _isRunning = false;

  static const String serviceTag = 'pixez-s';
  static const int defaultDiscoveryPort = 41234;

  DiscoveryService({
    required this.config,
    this.discoveryPort = defaultDiscoveryPort,
  });

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _socket!.broadcastEnabled = true;
      _isRunning = true;

      // Listen for incoming discovery probe queries from clients
      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            _handleIncomingDatagram(datagram);
          }
        }
      });

      // Periodically broadcast presence beacon to the entire subnet
      _broadcastTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        _broadcastBeacon();
      });

      // Send initial beacon immediately
      _broadcastBeacon();
      print('[Discovery] LAN discovery broadcast started on UDP port $discoveryPort');
    } catch (e) {
      print('[Discovery] Warning: Failed to start UDP broadcast on port $discoveryPort: $e');
    }
  }

  Future<List<String>> _getLocalIpv4Addresses() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    return ips;
  }

  Future<Map<String, dynamic>> _buildAnnouncementPacket() async {
    final localIps = await _getLocalIpv4Addresses();
    return {
      'service': serviceTag,
      'version': '0.1.0',
      'host_name': Platform.localHostname,
      'port': config.port,
      'ips': localIps,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<void> _broadcastBeacon() async {
    if (_socket == null || !_isRunning) return;
    try {
      final packet = await _buildAnnouncementPacket();
      final data = utf8.encode(jsonEncode(packet));
      final broadcastTarget = InternetAddress('255.255.255.255');
      _socket?.send(data, broadcastTarget, discoveryPort);
    } catch (_) {}
  }

  void _handleIncomingDatagram(Datagram datagram) async {
    try {
      final text = utf8.decode(datagram.data);
      final json = jsonDecode(text);
      // If client sent a discovery probe
      if (json is Map && (json['action'] == 'discover' || json['service'] == serviceTag)) {
        final packet = await _buildAnnouncementPacket();
        final responseData = utf8.encode(jsonEncode(packet));
        _socket?.send(responseData, datagram.address, datagram.port);
      }
    } catch (_) {
      // Ignore invalid datagrams
    }
  }

  void stop() {
    _isRunning = false;
    _broadcastTimer?.cancel();
    _socket?.close();
    _socket = null;
    print('[Discovery] LAN discovery broadcast stopped');
  }
}
