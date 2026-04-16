import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NetworkService extends ChangeNotifier {
  static const _debugIp = String.fromEnvironment('DEBUG_SERVER_IP', defaultValue: '127.0.0.1');
  static String get defaultUrl =>
      kDebugMode ? 'ws://$_debugIp:8080' : 'wss://tichu.jiny.shop';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  int _connectionId = 0;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _serverUrl = defaultUrl;
  bool _shouldAutoReconnect = true;
  Completer<void>? _connectCompleter;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get shouldAutoReconnect => _shouldAutoReconnect;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Future<void> connect([String? url]) async {
    if (_isConnected) return;
    if (_isConnecting) {
      await waitForConnection();
      return;
    }

    await _subscription?.cancel();
    _subscription = null;

    _serverUrl = url ?? defaultUrl;
    _shouldAutoReconnect = true;
    _isConnecting = true;
    _connectCompleter = Completer<void>();
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      await _channel!.ready;

      _isConnecting = false;
      _isConnected = true;
      final myId = ++_connectionId;
      _connectCompleter?.complete();
      _connectCompleter = null;
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
      _connectCompleter?.completeError(e);
      _connectCompleter = null;
      _handleDisconnect();
      rethrow;
    }
  }

  Future<void> waitForConnection({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isConnected) return;
    if (!_isConnecting) {
      throw Exception('Not connecting');
    }
    final completer = _connectCompleter;
    if (completer == null) {
      throw Exception('Connection state unavailable');
    }
    await completer.future.timeout(timeout);
  }

  Future<void> ensureConnected([String? url]) async {
    if (_isConnected) return;
    if (_isConnecting) {
      await waitForConnection();
      return;
    }
    await connect(url);
  }

  void _handleDisconnect({bool intentional = false}) {
    final wasConnected = _isConnected;
    _isConnected = false;
    _isConnecting = false;
    _channel = null;
    _shouldAutoReconnect = !intentional;
    if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
      _connectCompleter!.completeError(Exception('Connection closed'));
    }
    _connectCompleter = null;
    if (wasConnected) {
      debugPrint('[Network] _handleDisconnect (was connected, id=$_connectionId)');
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
