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
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController(
    text: NetworkService.defaultUrl,
  );

  bool _isConnecting = false;
  bool _showRegister = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      setState(() => _error = '아이디를 입력하세요');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '비밀번호를 입력하세요');
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
      game.loginWithCredentials(username, password);

      await _waitForLoginResult(game);

      if (!mounted) return;

      if (game.playerId.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LobbyScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = '$e';
        _isConnecting = false;
      });
    }
  }

  Future<void> _waitForLoginResult(GameService game) async {
    final completer = Completer<void>();

    void listener() {
      if (game.playerId.isNotEmpty) {
        completer.complete();
      } else if (game.loginError != null) {
        completer.completeError(game.loginError!);
      }
    }

    game.addListener(listener);
    try {
      await completer.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      setState(() {
        _error = '서버 응답 시간 초과';
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isConnecting = false;
      });
    } finally {
      game.removeListener(listener);
    }
  }

  void _showRegisterDialog() {
    setState(() => _showRegister = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
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
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD9CCC8).withValues(alpha: 0.6),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: _usernameController,
                              hint: '아이디',
                              icon: Icons.person_outline,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _passwordController,
                              hint: '비밀번호',
                              icon: Icons.lock_outline,
                              obscure: true,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _serverController,
                              hint: '서버 주소',
                              icon: Icons.dns_outlined,
                              fontSize: 14,
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isConnecting ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF28C26),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  '로그인',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _showRegisterDialog,
                              child: const Text(
                                '회원가입',
                                style: TextStyle(
                                  color: Color(0xFF8A7A72),
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'v1.0',
                        style: TextStyle(color: Color(0xFFB0A8A4), fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isConnecting) _buildConnectingOverlay(),
          if (_showRegister) _buildRegisterDialog(),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    double fontSize = 18,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(fontSize: fontSize),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFAA9A92)),
        prefixIcon: Icon(icon, color: const Color(0xFFAA9A92)),
        filled: true,
        fillColor: const Color(0xFFF8F4F2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  Widget _buildConnectingOverlay() {
    return Container(
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
                '로그인 중...',
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
    );
  }

  Widget _buildRegisterDialog() {
    return RegisterDialog(
      serverUrl: _serverController.text.trim(),
      onClose: () => setState(() => _showRegister = false),
      onSuccess: () {
        setState(() => _showRegister = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('회원가입이 완료되었습니다. 로그인해주세요.'),
            backgroundColor: Colors.green,
          ),
        );
      },
    );
  }
}

class RegisterDialog extends StatefulWidget {
  final String serverUrl;
  final VoidCallback onClose;
  final VoidCallback onSuccess;

  const RegisterDialog({
    super.key,
    required this.serverUrl,
    required this.onClose,
    required this.onSuccess,
  });

  @override
  State<RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<RegisterDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String? _nicknameStatus;
  bool _nicknameChecked = false;
  bool _nicknameAvailable = false;
  Timer? _nicknameDebounce;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    _nicknameDebounce?.cancel();
    super.dispose();
  }

  void _onNicknameChanged(String value) {
    _nicknameDebounce?.cancel();
    setState(() {
      _nicknameChecked = false;
      _nicknameAvailable = false;
      _nicknameStatus = null;
    });

    if (value.trim().isEmpty) return;

    _nicknameDebounce = Timer(const Duration(milliseconds: 500), () {
      _checkNickname();
    });
  }

  Future<void> _checkNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;

    final game = context.read<GameService>();
    game.checkNickname(nickname);

    // Wait for response
    await Future.delayed(const Duration(milliseconds: 100));
    for (int i = 0; i < 30; i++) {
      if (game.nicknameCheckMessage != null) {
        setState(() {
          _nicknameChecked = true;
          _nicknameAvailable = game.nicknameAvailable ?? false;
          _nicknameStatus = game.nicknameCheckMessage;
        });
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final nickname = _nicknameController.text.trim();

    // Validate
    if (username.length < 2) {
      setState(() => _error = '아이디는 2글자 이상이어야 합니다');
      return;
    }
    if (username.contains(' ')) {
      setState(() => _error = '아이디에 공백을 사용할 수 없습니다');
      return;
    }
    if (password.length < 4) {
      setState(() => _error = '비밀번호는 4글자 이상이어야 합니다');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = '비밀번호가 일치하지 않습니다');
      return;
    }
    if (nickname.isEmpty) {
      setState(() => _error = '닉네임을 입력해주세요');
      return;
    }
    if (!_nicknameChecked || !_nicknameAvailable) {
      setState(() => _error = '닉네임 중복확인을 해주세요');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final network = context.read<NetworkService>();
      if (!network.isConnected) {
        await network.connect(widget.serverUrl);
      }

      if (!mounted) return;

      final game = context.read<GameService>();
      game.register(username, password, nickname);

      // Wait for result
      await Future.delayed(const Duration(milliseconds: 100));
      for (int i = 0; i < 50; i++) {
        if (game.registerResult != null) {
          if (game.registerResult!.contains('완료')) {
            widget.onSuccess();
            return;
          } else {
            setState(() {
              _error = game.registerResult;
              _isLoading = false;
            });
            return;
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      setState(() {
        _error = '서버 응답 시간 초과';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '회원가입',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildInputField(
                  controller: _usernameController,
                  label: '아이디',
                  hint: '2글자 이상, 공백 불가',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 16),
                _buildInputField(
                  controller: _passwordController,
                  label: '비밀번호',
                  hint: '4글자 이상',
                  icon: Icons.lock_outline,
                  obscure: true,
                ),
                const SizedBox(height: 16),
                _buildInputField(
                  controller: _confirmPasswordController,
                  label: '비밀번호 확인',
                  hint: '비밀번호를 다시 입력',
                  icon: Icons.lock_outline,
                  obscure: true,
                ),
                const SizedBox(height: 16),
                _buildNicknameField(),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5A9E6F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            '가입하기',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
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
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A4038),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFAA9A92), fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFFAA9A92)),
            filled: true,
            fillColor: const Color(0xFFF8F4F2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildNicknameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '닉네임',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A4038),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nicknameController,
                onChanged: _onNicknameChanged,
                decoration: InputDecoration(
                  hintText: '게임에서 표시될 이름',
                  hintStyle: const TextStyle(color: Color(0xFFAA9A92), fontSize: 14),
                  prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFFAA9A92)),
                  filled: true,
                  fillColor: const Color(0xFFF8F4F2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_nicknameChecked)
              Icon(
                _nicknameAvailable ? Icons.check_circle : Icons.cancel,
                color: _nicknameAvailable ? Colors.green : Colors.red,
                size: 28,
              ),
          ],
        ),
        if (_nicknameStatus != null) ...[
          const SizedBox(height: 4),
          Text(
            _nicknameStatus!,
            style: TextStyle(
              fontSize: 12,
              color: _nicknameAvailable ? Colors.green : Colors.red,
            ),
          ),
        ],
      ],
    );
  }
}
