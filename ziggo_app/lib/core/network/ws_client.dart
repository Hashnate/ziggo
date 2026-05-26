import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

/// Thin wrapper around a single user-scoped WebSocket connection.
///
/// Resilience features (added to fix "driver doesn't receive ride request
/// until app hot-restart"):
///   • Auto-reconnect with exponential backoff (1s → 2s → 4s → 8s → 16s → 30s).
///   • Heartbeat: sends `{"event":"ping"}` every 25 s and expects a pong from
///     the server. Two missed pongs in a row → treat the socket as dead, close
///     it, and let the reconnect loop open a fresh one.
///
/// The public API (`connect`, `disconnect`, `dispose`, `events`, `isConnected`)
/// is unchanged so existing callers (BookingProvider, DriverProvider,
/// RestaurantProvider, MarketVendorProvider) compile and behave the same.
class WsClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  String? _token;
  bool _disposed = false;
  bool _userClosed = false;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _retryAttempt = 0;
  int _missedPongs = 0;

  static const Duration _heartbeatInterval = Duration(seconds: 25);
  static const int _maxMissedPongs = 2;

  Stream<Map<String, dynamic>> get events => _controller.stream;

  bool get isConnected => _channel != null;

  void connect(String token) {
    _userClosed = false;
    _token = token;
    if (_channel != null) return;
    _openChannel();
  }

  void _openChannel() {
    if (_disposed || _userClosed) return;
    final token = _token;
    if (token == null) return;

    WebSocketChannel ch;
    try {
      ch = WebSocketChannel.connect(Uri.parse(ApiConfig.wsUrl(token)));
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _channel = ch;
    _missedPongs = 0;

    _sub = ch.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          // Reset retry counter on any inbound traffic — we know the socket
          // is alive end-to-end.
          _retryAttempt = 0;
          if (msg['event'] == 'pong') {
            _missedPongs = 0;
            return; // don't surface heartbeat replies to listeners
          }
          _controller.add(msg);
        } catch (_) {
          // Malformed frame — ignore.
        }
      },
      onDone: _handleDrop,
      onError: (_) => _handleDrop(),
      cancelOnError: true,
    );

    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final ch = _channel;
      if (ch == null) return;
      _missedPongs++;
      if (_missedPongs > _maxMissedPongs) {
        // Server hasn't replied to our last few pings — treat the socket as
        // dead and force a reconnect. The OS may still think the TCP is
        // alive (common on mobile carriers behind aggressive NATs).
        _handleDrop();
        return;
      }
      try {
        ch.sink.add('{"event":"ping"}');
      } catch (_) {
        _handleDrop();
      }
    });
  }

  void _handleDrop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final sub = _sub;
    _sub = null;
    sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    if (!_userClosed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _userClosed) return;
    _reconnectTimer?.cancel();
    // 1s, 2s, 4s, 8s, 16s, 30s, 30s, …
    final delaySeconds = [1, 2, 4, 8, 16, 30][_retryAttempt.clamp(0, 5)];
    _retryAttempt = (_retryAttempt + 1).clamp(0, 5);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), _openChannel);
  }

  Future<void> disconnect() async {
    _userClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _controller.close();
  }
}
