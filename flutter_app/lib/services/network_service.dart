import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NetworkService extends ChangeNotifier {
  static String get defaultUrl =>
      kDebugMode ? 'ws://172.30.1.99:8080' : 'wss://tichu.jiny.shop';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  int _connectionId = 0;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _serverUrl = defaultUrl;
  bool _shouldAutoReconnect = true;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get shouldAutoReconnect => _shouldAutoReconnect;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Future<void> connect([String? url]) async {
    if (_isConnected || _isConnecting) return;

    _serverUrl = url ?? defaultUrl;
    _shouldAutoReconnect = true;
    _isConnecting = true;
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      await _channel!.ready;

      _isConnecting = false;
      _isConnected = true;
      final myId = ++_connectionId;
      notifyListeners();

      _subscription = _channel!.stream.listen(
        (data) {
          if (_connectionId != myId) return;
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(json);
          } catch (e) {
            debugPrint('[Network] Failed to parse message: $e');
          }
        },
        onError: (error) {
          if (_connectionId != myId) return;
          debugPrint('[Network] WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          if (_connectionId != myId) return;
          debugPrint('[Network] WebSocket closed');
          _handleDisconnect();
        },
      );

      debugPrint('[Network] Connected to $_serverUrl (id=$myId)');
    } catch (e) {
      debugPrint('[Network] Connection failed: $e');
      _handleDisconnect();
      rethrow;
    }
  }

  void _handleDisconnect({bool intentional = false}) {
    final wasConnected = _isConnected;
    _isConnected = false;
    _isConnecting = false;
    _channel = null;
    _shouldAutoReconnect = !intentional;
    if (wasConnected) {
      debugPrint('[Network] _handleDisconnect (was connected, id=$_connectionId)');
      debugPrint(StackTrace.current.toString().split('\n').take(5).join('\n'));
    }
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
    disconnect(intentional: false);
    const delays = [1, 2, 3, 5, 8]; // seconds – fast initial retries
    for (int i = 0; i < delays.length; i++) {
      try {
        await connect(_serverUrl);
        return true;
      } catch (_) {
        await Future.delayed(Duration(seconds: delays[i]));
      }
    }
    return false;
  }

  void disconnect({bool intentional = true}) {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _handleDisconnect(intentional: intentional);
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    super.dispose();
  }
}
