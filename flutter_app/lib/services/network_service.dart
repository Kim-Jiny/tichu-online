import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NetworkService extends ChangeNotifier {
  static const _debugIp = String.fromEnvironment('DEBUG_SERVER_IP', defaultValue: '127.0.0.1');
  static String get defaultUrl =>
      kDebugMode ? 'ws://$_debugIp:8080' : 'wss://tichu.jiny.shop';

  // Messages that we cannot afford to drop when WS is momentarily down
  // (the user paid real money for the IAP grant; the daily attendance grant
  // is similarly per-day and the user already watched an ad). Both are
  // server-side IDEMPOTENT so replaying is safe — verify_iap_purchase keys
  // off transaction_id (UNIQUE), claim_attendance off last_claim_date.
  static const _retryableTypes = <String>{
    'verify_iap_purchase',
    'claim_attendance',
  };
  static const String _kRetryQueueKey = 'tc_ws_retry_queue_v1';
  // Drop entries older than this — Google voids unfinished purchases after a
  // few days anyway, so keeping ancient retries achieves nothing.
  static const int _retryMaxAgeMs = 24 * 60 * 60 * 1000; // 24h
  static const int _retryMaxEntries = 50;

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
      // NOTE: do NOT flush the retry queue here. The server requires a
      // logged-in WS (ws.nickname set) for verify_iap_purchase /
      // claim_attendance, which only happens AFTER the client sends the
      // `login` message. Flushing here would race and the server would
      // reject everything with `login_required`, clearing the queue with
      // nothing actually processed. game_service calls flushRetryQueue()
      // from its login_success handler instead.

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
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(data));
      return;
    }
    // Disconnected. Drop is unsafe for IAP/attendance — persist & retry.
    final type = data['type'] as String?;
    if (type != null && _retryableTypes.contains(type)) {
      // ignore: discarded_futures
      _queueRetryable(data);
      debugPrint('[Network] Queued retryable while offline: $type');
      return;
    }
    debugPrint('[Network] Cannot send (offline, droppable): $type');
  }

  // Serializes all SharedPreferences mutations of the retry queue. Without
  // this, two near-simultaneous _queueRetryable calls would both read-then-
  // write and one would silently clobber the other.
  Future<void> _queueLock = Future<void>.value();
  Future<T> _withQueueLock<T>(Future<T> Function() body) {
    final next = _queueLock.then((_) => body());
    _queueLock = next.then((_) {}, onError: (_) {});
    return next;
  }

  // Persists a single retryable message. Caps the queue so a stuck client
  // can't grow it unbounded.
  Future<void> _queueRetryable(Map<String, dynamic> data) => _withQueueLock(() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kRetryQueueKey) ?? <String>[];
      raw.add(jsonEncode({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'msg': data,
      }));
      while (raw.length > _retryMaxEntries) {
        raw.removeAt(0);
      }
      await prefs.setStringList(_kRetryQueueKey, raw);
    } catch (e) {
      debugPrint('[Network] Queue persist failed: $e');
    }
  });

  // Replays survivors of the IAP/attendance retry queue. PUBLIC because the
  // safe place to call this is AFTER login_success (server requires
  // ws.nickname for the queued message types). game_service hooks it there.
  // Server-side idempotency makes replay safe even if a message had actually
  // gone through on a previous attempt (e.g. response was lost but write was
  // committed).
  Future<void> flushRetryQueue() => _withQueueLock(_doFlushRetryQueue);

  Future<void> _doFlushRetryQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kRetryQueueKey);
      if (raw == null || raw.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Only entries we genuinely couldn't send (e.g. WS dropped mid-flush)
      // survive to the next attempt. Sent and expired entries are removed.
      // Server idempotency handles "sent but never acked" — re-sending the
      // same verify is a no-op (already_granted).
      final survivors = <String>[];
      var sent = 0;
      var expired = 0;
      var malformed = 0;
      for (final entry in raw) {
        Map<String, dynamic>? parsed;
        try {
          parsed = jsonDecode(entry) as Map<String, dynamic>;
        } catch (_) {
          malformed++;
          continue;
        }
        final ts = (parsed['ts'] as num?)?.toInt() ?? 0;
        if (now - ts > _retryMaxAgeMs) {
          expired++;
          continue;
        }
        final msg = parsed['msg'];
        if (msg is! Map<String, dynamic>) {
          malformed++;
          continue;
        }
        if (_isConnected && _channel != null) {
          try {
            _channel!.sink.add(jsonEncode(msg));
            sent++;
          } catch (e) {
            // sink.add can throw if the channel is closing — keep for retry.
            survivors.add(entry);
            debugPrint('[Network] sink.add threw during flush, kept: $e');
          }
        } else {
          // Connection dropped mid-flush. Preserve for next attempt instead
          // of wiping (which would silently lose the message forever).
          survivors.add(entry);
        }
      }
      if (survivors.isEmpty) {
        await prefs.remove(_kRetryQueueKey);
      } else {
        await prefs.setStringList(_kRetryQueueKey, survivors);
      }
      if (sent > 0 || expired > 0 || malformed > 0 || survivors.isNotEmpty) {
        debugPrint('[Network] Retry queue flushed: sent=$sent expired=$expired '
            'malformed=$malformed kept=${survivors.length}');
      }
    } catch (e) {
      debugPrint('[Network] Flush retry queue failed: $e');
    }
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
