import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

/// Thin wrapper around a single user-scoped WebSocket connection.
class WsClient {
  static final WsClient instance = WsClient();
  
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  String? _token;
  Timer? _reconnectTimer;

  Stream<Map<String, dynamic>> get events => _controller.stream;

  bool get isConnected => _channel != null;

  void connect(String token) {
    if (_channel != null) return;
    _token = token;
    _reconnectTimer?.cancel();
    
    final uri = Uri.parse(ApiConfig.wsUrl(token));
    final ch = WebSocketChannel.connect(uri);
    _channel = ch;
    _sub = ch.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(msg);
        } catch (_) {}
      },
      onDone: () {
        _channel = null;
        _scheduleReconnect();
      },
      onError: (_) {
        _channel = null;
        _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    if (_token == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_token != null) connect(_token!);
    });
  }

  Future<void> disconnect() async {
    _token = null;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _sub = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
