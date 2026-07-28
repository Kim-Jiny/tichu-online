import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
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
      final pausedFor = _pausedAt == null
          ? Duration.zero
          : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;

      if (!network.shouldAutoReconnect) return;

      if (!network.isConnected) {
        if (!network.isConnecting) _startReconnect();
        return;
      }

      // Still "connected" — but after time in the background that usually
      // means a socket the OS closed without us hearing about it. Both
      // platforms behave the same way here; the old Android-only branch below
      // this check was dead code, since it also required !isConnected.
      //
      // checkAliveAfterResume tears the socket down (or probes it, for a
      // short pause), and the resulting disconnect notification brings us
      // back through _onNetworkChanged to reconnect. Waiting for the periodic
      // heartbeat to work this out instead cost several seconds of a frozen
      // screen before the spinner even appeared.
      network.checkAliveAfterResume(pausedFor);
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

  // Toggle the reconnecting flag AND rebuild so the overlay shows/hides.
  void _setReconnecting(bool v) {
    _globalReconnecting = v;
    if (mounted) setState(() {});
  }

  Future<void> _startReconnect() async {
    if (_globalReconnecting) return;
    _setReconnecting(true);
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
      // Timed so the spinner's length can be attributed rather than guessed at:
      // socket vs. login/restore. Testers report it feeling long and the two
      // halves need very different fixes.
      final startedAt = DateTime.now();
      final network = context.read<NetworkService>();
      final success = await session.reconnectAndRestore()
          .timeout(const Duration(seconds: 30), onTimeout: () => false);
      final ms = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint('[Reconnect] restore took ${ms}ms (success=$success, '
          'connected=${network.isConnected})');

      // If a newer attempt was started (e.g. timeout triggered _goToLogin then retry),
      // this zombie result should be ignored
      if (myAttemptId != _reconnectAttemptId) return;
      if (!mounted) return;
      if (!success) {
        _goToLogin();
      }
    } finally {
      if (myAttemptId == _reconnectAttemptId) {
        _setReconnecting(false);
      }
    }
  }

  void _goToLogin() {
    if (!mounted) return;
    // Invalidate any in-flight zombie reconnection
    ++_reconnectAttemptId;
    _setReconnecting(false);
    context.read<SessionService>().resetToLoginState(suppressAutoRestore: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_globalReconnecting) return widget.child;
    // While reconnecting, dim + block the (frozen) UI and show a clear spinner
    // so the user knows the app is working, not stuck.
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AbsorbPointer(
            // Material provides the text-style baseline so the label doesn't get
            // the yellow "no Material ancestor" debug underline (this overlay
            // sits above the app, outside any Scaffold).
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    L10n.of(context).serviceRestoreConnecting,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
      ],
    );
  }
}
