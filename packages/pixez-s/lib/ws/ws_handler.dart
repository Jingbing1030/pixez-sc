import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../service/download_engine.dart';

class WsHandler {
  final DownloadEngine downloadEngine;
  final List<WebSocketChannel> _clients = [];

  WsHandler({required this.downloadEngine}) {
    downloadEngine.progressStream.listen((event) {
      broadcast(event);
    });
  }

  Handler get handler {
    return webSocketHandler((WebSocketChannel socket) {
      _clients.add(socket);
      socket.sink.add(jsonEncode({
        'type': 'connected',
        'message': 'Connected to Pixez-s real-time events',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));

      socket.stream.listen(
        (message) {
          // Client incoming ping or commands
          try {
            final data = jsonDecode(message.toString());
            if (data['type'] == 'ping') {
              socket.sink.add(jsonEncode({'type': 'pong'}));
            }
          } catch (_) {}
        },
        onDone: () {
          _clients.remove(socket);
        },
        onError: (_) {
          _clients.remove(socket);
        },
      );
    });
  }

  void broadcast(Map<String, dynamic> data) {
    final payload = jsonEncode(data);
    for (final client in List.of(_clients)) {
      try {
        client.sink.add(payload);
      } catch (_) {
        _clients.remove(client);
      }
    }
  }
}
