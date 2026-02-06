import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NetworkService extends ChangeNotifier {
  static const String defaultUrl = 'wss://tichu-server.onrender.com';

  WebSocketChannel? _channel;
  bool _isConnected = false;
  String _serverUrl = defaultUrl;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _isConnected;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Future<void> connect([String? url]) async {
    if (_isConnected) return;

    _serverUrl = url ?? defaultUrl;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      await _channel!.ready;

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
