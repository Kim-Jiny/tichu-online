import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NetworkService extends ChangeNotifier {
  static String get defaultUrl => kDebugMode
      ? 'ws://172.30.1.80:8080'  // Mac IP for iOS simulator/device
      : 'wss://tichu-server.onrender.com';

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _serverUrl = defaultUrl;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Future<void> connect([String? url]) async {
    if (_isConnected || _isConnecting) return;

    _serverUrl = url ?? defaultUrl;
    _isConnecting = true;
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      await _channel!.ready;

      _isConnecting = false;
      _isConnected = true;
      notifyListeners();

      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(json);
          } catch (e) {
            debugPrint('[Network] Failed to parse message: $e');
          }
        },
        onError: (error) {
          debugPrint('[Network] WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[Network] WebSocket closed');
          _handleDisconnect();
        },
      );

      debugPrint('[Network] Connected to $_serverUrl');
    } catch (e) {
      debugPrint('[Network] Connection failed: $e');
      _handleDisconnect();
      rethrow;
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _channel = null;
    notifyListeners();
  }

  void send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      debugPrint('[Network] Cannot send: not connected');
      return;
    }

    final jsonStr = jsonEncode(data);
    _channel!.sink.add(jsonStr);
  }

  String get serverUrl => _serverUrl;

  Future<bool> reconnect() async {
    disconnect();
    for (int i = 0; i < 5; i++) {
      try {
        await connect(_serverUrl);
        return true;
      } catch (_) {
        await Future.delayed(Duration(seconds: 2 << i)); // 2, 4, 8, 16, 32
      }
    }
    return false;
  }

  void disconnect() {
    _channel?.sink.close();
    _handleDisconnect();
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    super.dispose();
  }
}
