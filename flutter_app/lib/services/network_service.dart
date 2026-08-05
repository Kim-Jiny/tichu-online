import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService extends ChangeNotifier {
  static const _debugIp = String.fromEnvironment('DEBUG_SERVER_IP', defaultValue: '127.0.0.1');
  /// Explicit override, e.g. `--dart-define=WS_URL=ws://localhost:8080` when
  /// serving a release web build against a local server.
  static const _wsUrlOverride = String.fromEnvironment('WS_URL');

  static String get defaultUrl {
    if (_wsUrlOverride.isNotEmpty) return _wsUrlOverride;
    if (kIsWeb) {
      // The web build is served from the same host that terminates the socket
      // (/play on tichu.jiny.shop), so derive it rather than hardcoding: that
      // keeps a staging host, a LAN IP and production all working unchanged.
      final base = Uri.base;
      final scheme = base.scheme == 'https' ? 'wss' : 'ws';
      return '$scheme://${base.authority}';
    }
    return kDebugMode ? 'ws://$_debugIp:8080' : 'wss://tichu.jiny.shop';
  }

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
  StreamSubscription? _connectivitySub;
  int _connectionId = 0;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _serverUrl = defaultUrl;
  bool _shouldAutoReconnect = true;
  Completer<void>? _connectCompleter;

  // Client-side connection heartbeat. A socket's onDone/onError do NOT fire on
  // a silent network handoff (WiFi↔cellular), leaving a zombie socket with
  // _isConnected stuck true and the game screen frozen — nothing reconnects.
  // We ping the server every _heartbeatInterval; if no pong arrives within
  // _heartbeatDeadAfter we declare the socket dead and run the normal
  // disconnect→reconnect chain (listeners → ConnectionOverlay → restore).
  Timer? _heartbeatTimer;
  DateTime? _lastPongAt;
  static const Duration _heartbeatInterval = Duration(seconds: 5);
  static const Duration _heartbeatDeadAfter = Duration(seconds: 15);

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get shouldAutoReconnect => _shouldAutoReconnect;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  NetworkService() {
    // Network changed (e.g. WiFi↔cellular handoff). The current socket is very
    // likely a zombie now, so verify it immediately instead of waiting out the
    // ~15s heartbeat. The heartbeat remains the backstop for cases the OS
    // doesn't surface a connectivity event.
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (_) => _probeConnectionNow(),
      onError: (_) {},
    );
  }

  Future<void> connect(
    [String? url,
    Duration handshakeTimeout = const Duration(seconds: 8)]
  ) async {
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
      // Bound the handshake. A stale/half-open socket (e.g. after a long
      // background) can otherwise hang on `.ready` for the OS TCP timeout
      // (tens of seconds), stalling reconnect and leaving the "connecting"
      // overlay stuck. Time out fast so reconnect() retries a fresh socket.
      await _channel!.ready.timeout(handshakeTimeout);

      _isConnecting = false;
      _isConnected = true;
      _lastPongAt = DateTime.now();
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
            if (json['type'] == 'pong') {
              // Heartbeat reply — proof the socket is alive. Consume it.
              _lastPongAt = DateTime.now();
              return;
            }
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

      _startHeartbeat();
      debugPrint('[Network] Connected to $_serverUrl (id=$myId)');
    } catch (e) {
      debugPrint('[Network] Connection failed: $e');
      // Abort the (possibly still-pending) stuck socket so it doesn't leak.
      try {
        _channel?.sink.close();
      } catch (_) {}
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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _lastPongAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _heartbeatTick());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _heartbeatTick() {
    if (!_isConnected || _channel == null) return;
    final last = _lastPongAt;
    if (last != null && DateTime.now().difference(last) > _heartbeatDeadAfter) {
      // No pong within the dead window → zombie socket (e.g. network handoff
      // with no TCP FIN). Tear it down so the normal reconnect chain runs.
      debugPrint('[Network] Heartbeat timeout — treating socket as dead');
      disconnect(intentional: false);
      return;
    }
    try {
      _channel!.sink.add(jsonEncode({'type': 'ping'}));
    } catch (e) {
      debugPrint('[Network] Heartbeat send failed: $e');
      disconnect(intentional: false);
    }
  }

  /// Liveness check to run when the app comes back to the foreground.
  ///
  /// A socket the OS killed while we were suspended never delivers a FIN, so
  /// `isConnected` still reads true and every "reconnect if disconnected"
  /// check declines to act. Nothing then notices until the periodic heartbeat
  /// happens to tick and find a pong older than its 15s dead window — several
  /// seconds of the app looking alive but frozen before recovery even starts.
  ///
  /// Past [assumeDeadAfter] of suspension the socket is almost certainly gone,
  /// so skip the probe and tear it down immediately; below that a ping is
  /// cheap and avoids dropping a connection that actually survived.
  static const Duration assumeDeadAfter = Duration(seconds: 10);

  void checkAliveAfterResume(Duration pausedFor) {
    if (!_isConnected || _channel == null) return;
    if (pausedFor >= assumeDeadAfter) {
      debugPrint('[Network] Resumed after ${pausedFor.inSeconds}s — assuming the socket is dead');
      disconnect(intentional: false);
      return;
    }
    _probeConnectionNow();
  }

  // Fast liveness check after a connectivity change: ping now and, if no fresh
  // pong arrives shortly, declare the socket dead and reconnect. Faster than the
  // periodic heartbeat for the common WiFi↔cellular case.
  void _probeConnectionNow() {
    if (!_isConnected || _channel == null) return;
    final probeAt = DateTime.now();
    try {
      _channel!.sink.add(jsonEncode({'type': 'ping'}));
    } catch (_) {
      disconnect(intentional: false);
      return;
    }
    Timer(const Duration(seconds: 4), () {
      if (!_isConnected) return;
      final last = _lastPongAt;
      if (last == null || last.isBefore(probeAt)) {
        debugPrint('[Network] Connectivity-change probe got no pong — reconnecting');
        disconnect(intentional: false);
      }
    });
  }

  void _handleDisconnect({bool intentional = false}) {
    _stopHeartbeat();
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
    final type = data['type'] as String?;
    final retryable = type != null && _retryableTypes.contains(type);
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
        return;
      } catch (e) {
        // Closing race: _isConnected was still true but the underlying
        // sink had already started tearing down, so sink.add threw. For
        // retryable types we MUST persist instead of letting the message
        // vanish — _isConnected will catch up to false on the next tick.
        debugPrint('[Network] sink.add threw on send: $e');
        if (!retryable) return;
        // fall through to queueing
      }
    }
    if (retryable) {
      // ignore: discarded_futures
      _queueRetryable(data);
      debugPrint('[Network] Queued retryable (offline/sink-fail): $type');
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

  /// HTTP(S) base for the few non-WS endpoints (profile-photo upload, and
  /// resolving relative /media/ avatar URLs). Derived from the active WS URL:
  /// `ws://` -> `http://`, `wss://` -> `https://`.
  String get httpBase => _serverUrl.replaceFirst(RegExp(r'^ws'), 'http');

  /// Resolve a possibly-relative avatar URL (server returns `/media/...` when
  /// MINIO_PUBLIC_BASE is unset) into an absolute URL against [httpBase].
  String? resolveMediaUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$httpBase${url.startsWith('/') ? '' : '/'}$url';
  }

  Future<bool> reconnect() async {
    disconnect(intentional: false);
    const delays = [1, 2, 3, 5, 8]; // seconds – fast initial retries
    for (int i = 0; i < delays.length; i++) {
      try {
        // Give the first try a short leash. A healthy handshake takes well
        // under a second, and the common failure right after a resume is the
        // radio not being ready — waiting the full 8s there just adds 8s of
        // spinner before the retry that was going to work anyway. Later
        // attempts get the longer bound for genuinely slow networks.
        await connect(
          _serverUrl,
          i == 0 ? const Duration(seconds: 3) : const Duration(seconds: 8),
        );
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
    _connectivitySub?.cancel();
    disconnect();
    _messageController.close();
    super.dispose();
  }
}
