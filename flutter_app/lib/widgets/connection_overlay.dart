import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../services/session_service.dart';

class ConnectionOverlay extends StatefulWidget {
  final Widget child;

  const ConnectionOverlay({super.key, required this.child});

  @override
  State<ConnectionOverlay> createState() => _ConnectionOverlayState();
}

class _ConnectionOverlayState extends State<ConnectionOverlay>
    with WidgetsBindingObserver {
  static bool _globalReconnecting = false;
  static int _reconnectAttemptId = 0;

  bool _inForeground = true;
  NetworkService? _networkService;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _networkService = context.read<NetworkService>();
      _networkService!.addListener(_onNetworkChanged);
    });
  }

  @override
  void dispose() {
    _networkService?.removeListener(_onNetworkChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pausedAt ??= DateTime.now();
      _inForeground = false;
    } else if (state == AppLifecycleState.resumed) {
      _inForeground = true;
      if (_globalReconnecting) return;

      final network = context.read<NetworkService>();
      final wasPausedLong = _pausedAt != null &&
          DateTime.now().difference(_pausedAt!).inSeconds >= 2;
      _pausedAt = null;

      if (Platform.isAndroid) {
        if (network.shouldAutoReconnect &&
            !network.isConnected &&
            !network.isConnecting) {
          _startReconnect();
        } else if (wasPausedLong &&
            network.shouldAutoReconnect &&
            !network.isConnected) {
          _startReconnect();
        }
      } else {
        if (network.shouldAutoReconnect &&
            !network.isConnected &&
            !network.isConnecting) {
          _startReconnect();
        }
      }
    }
  }

  void _onNetworkChanged() {
    if (!mounted || !_inForeground || _globalReconnecting) return;
    final network = context.read<NetworkService>();
    if (network.shouldAutoReconnect &&
        !network.isConnected &&
        !network.isConnecting) {
      _startReconnect();
    }
  }

  Future<void> _startReconnect() async {
    if (_globalReconnecting) return;
    _globalReconnecting = true;
    final myAttemptId = ++_reconnectAttemptId;

    try {
      // If we're in a known maintenance window, skip reconnect and go to login
      // so MaintenanceScreen shows immediately.
      final game = context.read<GameService>();
      if (game.isInKnownMaintenanceWindow) {
        if (myAttemptId != _reconnectAttemptId) return;
        if (!mounted) return;
        _goToLogin();
        return;
      }

      final session = context.read<SessionService>();
      final success = await session.reconnectAndRestore()
          .timeout(const Duration(seconds: 30), onTimeout: () => false);

      // If a newer attempt was started (e.g. timeout triggered _goToLogin then retry),
      // this zombie result should be ignored
      if (myAttemptId != _reconnectAttemptId) return;
      if (!mounted) return;
      if (!success) {
        _goToLogin();
      }
    } finally {
      if (myAttemptId == _reconnectAttemptId) {
        _globalReconnecting = false;
      }
    }
  }

  void _goToLogin() {
    if (!mounted) return;
    // Invalidate any in-flight zombie reconnection
    ++_reconnectAttemptId;
    _globalReconnecting = false;
    context.read<SessionService>().resetToLoginState(suppressAutoRestore: true);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
