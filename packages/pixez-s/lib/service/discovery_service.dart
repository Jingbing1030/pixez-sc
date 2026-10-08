import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/server_config.dart';

class DiscoveryService {
  final ServerConfig config;
  final int actualHttpPort;
  final int discoveryPort;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  bool _isRunning = false;
  int _activeDiscoveryPort;

  static const String serviceTag = 'pixez-s';
  static const int defaultDiscoveryPort = 41234;

  DiscoveryService({
    required this.config,
    int? actualHttpPort,
    int? discoveryPort,
  })  : actualHttpPort = actualHttpPort ?? config.port,
        discoveryPort = discoveryPort ?? config.discoveryPort,
        _activeDiscoveryPort = discoveryPort ?? config.discoveryPort;

  bool get isRunning => _isRunning;
  int get activeDiscoveryPort => _activeDiscoveryPort;

  Future<void> start() async {
    if (_isRunning) return;

    int candidatePort = discoveryPort;
    const maxAttempts = 20;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          candidatePort,
          reuseAddress: true,
          reusePort: true,
        );
        _activeDiscoveryPort = candidatePort;
        break;
      } on SocketException catch (_) {
        if (attempt == maxAttempts - 1) {
          print('[Discovery] Warning: All UDP ports in range $discoveryPort..$candidatePort are in use.');
          return;
        }
        candidatePort++;
      } catch (e) {
        print('[Discovery] Warning: Failed to bind UDP discovery socket: $e');
        return;
      }
    }

    if (_socket == null) return;

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
    print('[Discovery] LAN discovery broadcast started on UDP port $_activeDiscoveryPort (announcing HTTP port $actualHttpPort)');
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
      'port': actualHttpPort,
      'discovery_port': _activeDiscoveryPort,
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
      // Always broadcast to standard default port so scanning clients receive it
      _socket?.send(data, broadcastTarget, defaultDiscoveryPort);
      // If bound to a shifted port, also broadcast to that shifted port
      if (_activeDiscoveryPort != defaultDiscoveryPort) {
        _socket?.send(data, broadcastTarget, _activeDiscoveryPort);
      }
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
