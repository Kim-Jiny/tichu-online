import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/network_service.dart';
import '../services/game_service.dart';
import '../screens/login_screen.dart';

class ConnectionOverlay extends StatefulWidget {
  final Widget child;

  const ConnectionOverlay({super.key, required this.child});

  @override
  State<ConnectionOverlay> createState() => _ConnectionOverlayState();
}

class _ConnectionOverlayState extends State<ConnectionOverlay>
    with WidgetsBindingObserver {
  bool _showOverlay = false;
  bool _reconnecting = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NetworkService>().addListener(_onNetworkChanged);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final network = context.read<NetworkService>();
      if (!network.isConnected && !_reconnecting) {
        _startReconnect();
      }
    }
  }

  void _onNetworkChanged() {
    if (!mounted) return;
    final network = context.read<NetworkService>();
    if (!network.isConnected && !network.isConnecting && !_reconnecting) {
      _startReconnect();
    }
  }

  Future<void> _startReconnect() async {
    if (_reconnecting) return;

    setState(() {
      _showOverlay = true;
      _reconnecting = true;
      _failed = false;
    });

    final network = context.read<NetworkService>();
    final success = await network.reconnect();

    if (!mounted) return;

    if (success) {
      await _relogin();
    } else {
      setState(() {
        _reconnecting = false;
        _failed = true;
      });
    }
  }

  Future<void> _relogin() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('saved_username');
    final password = prefs.getString('saved_password');

    if (!mounted) return;

    if (username == null || password == null || username.isEmpty) {
      _goToLogin();
      return;
    }

    final game = context.read<GameService>();
    game.loginWithCredentials(username, password);

    // Wait for login result
    final loggedIn = await _waitForLogin(game);

    if (!mounted) return;

    if (loggedIn) {
      // If server restarted, our old room no longer exists
      // Server sends 'reconnected' only if room recovery succeeded
      // If we still have a roomId but no 'reconnected' came, clear room state
      if (game.currentRoomId.isNotEmpty) {
        // Save old roomId, then clear stale state immediately
        final oldRoomId = game.currentRoomId;
        game.currentRoomId = '';
        game.currentRoomName = '';
        game.roomPlayers = [null, null, null, null];
        game.isHost = false;
        game.isRankedRoom = false;
        game.isSpectator = false;
        game.spectatorGameState = null;
        game.gameState = null;
        game.chatMessages = [];
        game.cardViewers = [];
        game.incomingCardViewRequests = [];
        game.desertedPlayerName = null;
        game.desertedReason = null;
        game.notifyListeners();
        // If server sends 'reconnected', the handler will restore roomId and state
        // Wait briefly so reconnected message can arrive and restore state
        await Future.delayed(const Duration(milliseconds: 800));
      }
      game.requestRoomList();
      game.requestSpectatableRooms();
      game.requestBlockedUsers();
      setState(() {
        _showOverlay = false;
        _reconnecting = false;
        _failed = false;
      });
    } else {
      _goToLogin();
    }
  }

  Future<bool> _waitForLogin(GameService game) async {
    final completer = Completer<bool>();

    void listener() {
      if (game.playerId.isNotEmpty) {
        if (!completer.isCompleted) completer.complete(true);
      } else if (game.loginError != null) {
        if (!completer.isCompleted) completer.complete(false);
      }
    }

    game.addListener(listener);
    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return false;
    } finally {
      game.removeListener(listener);
    }
  }

  void _goToLogin() {
    if (!mounted) return;
    final network = context.read<NetworkService>();
    final game = context.read<GameService>();
    network.disconnect();
    game.reset();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _retry() {
    setState(() {
      _failed = false;
    });
    _startReconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showOverlay)
          Container(
            color: Colors.black54,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _failed ? _buildFailedContent() : _buildConnectingContent(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildConnectingContent() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: Color(0xFFF28C26)),
        SizedBox(height: 20),
        Text(
          '서버에 연결중입니다...',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A4038),
          ),
        ),
      ],
    );
  }

  Widget _buildFailedContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.wifi_off,
          size: 48,
          color: Color(0xFFCC6666),
        ),
        const SizedBox(height: 16),
        const Text(
          '연결 실패',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A4038),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '서버에 연결할 수 없습니다.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF8A7A72),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF28C26),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('재시도'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _goToLogin,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8A7A72),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('로그인 화면'),
            ),
          ],
        ),
      ],
    );
  }
}
