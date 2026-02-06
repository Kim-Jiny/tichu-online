import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_service.dart';
import '../services/game_service.dart';
import 'lobby_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nicknameController = TextEditingController();
  final _serverController = TextEditingController(
    text: NetworkService.defaultUrl,
  );
  bool _isConnecting = false;
  String? _error;
  bool _isWaitingLogin = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = '닉네임을 입력하세요');
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final network = context.read<NetworkService>();
      await network.connect(_serverController.text.trim());

      if (!mounted) return;

      final game = context.read<GameService>();
      game.login(nickname);

      // Wait for login success signal
      _isWaitingLogin = true;
      await _waitForLoginSuccess(game);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LobbyScreen()),
      );
    } catch (e) {
      setState(() {
        _error = '서버 접속 실패: $e';
        _isConnecting = false;
      });
    }
  }

  Future<void> _waitForLoginSuccess(GameService game) async {
    final completer = Completer<void>();

    void listener() {
      if (game.playerId.isNotEmpty) {
        completer.complete();
      } else if (game.errorMessage != null && _isWaitingLogin) {
        completer.completeError(game.errorMessage!);
      }
    }

    game.addListener(listener);
    try {
      await completer.future.timeout(const Duration(seconds: 6));
    } finally {
      _isWaitingLogin = false;
      game.removeListener(listener);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background with content
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF8F4F6),
                  Color(0xFFF0E8F0),
                  Color(0xFFE8F0F8),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🐥', style: TextStyle(fontSize: 60)),
                      const SizedBox(height: 8),
                      const Text(
                        'TICHU',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5A4038),
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '팀 카드게임',
                        style: TextStyle(fontSize: 16, color: Color(0xFF8A7A72)),
                      ),
                      const SizedBox(height: 48),
                      // Login card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD9CCC8).withOpacity(0.6),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _nicknameController,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18),
                              decoration: InputDecoration(
                                hintText: '닉네임',
                                hintStyle: const TextStyle(color: Color(0xFFAA9A92)),
                                filled: true,
                                fillColor: const Color(0xFFF8F4F2),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _serverController,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF8A7A72)),
                              decoration: InputDecoration(
                                hintText: '서버 주소',
                                hintStyle: const TextStyle(color: Color(0xFFAA9A92)),
                                filled: true,
                                fillColor: const Color(0xFFF8F4F2),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isConnecting ? null : _connect,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF28C26),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  '게임 시작',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                style: const TextStyle(color: Colors.red, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text('v1.0', style: TextStyle(color: Color(0xFFB0A8A4), fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Connecting overlay
          if (_isConnecting)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
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
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
