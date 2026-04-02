import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/network_service.dart';
import '../services/game_service.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// Clear saved login credentials
  static Future<void> clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
    await AuthService.clearAuthInfo();
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isConnecting = false;
  bool _showRegister = false;
  bool _showSocialNickname = false;
  bool _autoLoginAttempted = false;
  String? _error;
  String? _socialProvider;
  String? _socialToken;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoLogin();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    await _attemptAutoLogin();
  }

  Future<void> _attemptAutoLogin({bool force = false}) async {
    if (_autoLoginAttempted && !force) return;
    _autoLoginAttempted = true;

    final session = context.read<SessionService>();
    if (session.consumeAutoRestoreSuppression()) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    final success = await session.restoreSavedSession();
    if (!mounted) return;

    if (success) {
      setState(() => _isConnecting = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedUsername = prefs.getString('saved_username');
    final savedPassword = prefs.getString('saved_password');
    if (savedUsername != null && savedPassword != null && savedUsername.isNotEmpty) {
      _usernameController.text = savedUsername;
      _passwordController.text = savedPassword;
    }

    setState(() => _isConnecting = false);
  }

  Future<void> _retryAutoLogin() async {
    context.read<SessionService>().clearAutoRestoreSuppression();
    await _attemptAutoLogin(force: true);
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {}
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
    context.read<SessionService>().clearRestoreFeedback();

    try {
      final session = context.read<SessionService>();
      final result = await session.loginWithCredentials(
        username,
        password,
        url: NetworkService.defaultUrl,
      );

      if (!mounted) return;

      if (result.status == SessionAuthStatus.success) {
        setState(() => _isConnecting = false);
      } else {
        setState(() {
          _error = result.error ?? '로그인 실패';
          _isConnecting = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '$e';
        _isConnecting = false;
      });
    }
  }

  Future<void> _handleSocialSignIn(String providerName) async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });
    context.read<SessionService>().clearRestoreFeedback();

    try {
      SocialAuthResult result;
      switch (providerName) {
        case 'google':
          result = await AuthService.signInWithGoogle();
          break;
        case 'apple':
          result = await AuthService.signInWithApple();
          break;
        case 'kakao':
          result = await AuthService.signInWithKakao();
          break;
        default:
          throw Exception('Unknown provider: $providerName');
      }

      if (result.cancelled) {
        setState(() => _isConnecting = false);
        return;
      }

      if (!mounted) return;

      _socialProvider = result.provider;
      _socialToken = result.token;
      await _socialLogin(result.provider, result.token);
    } catch (e) {
      setState(() {
        _error = '소셜 로그인 실패: $e';
        _isConnecting = false;
      });
    }
  }

  Future<void> _socialLogin(String provider, String token) async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final session = context.read<SessionService>();
      final result = await session.loginWithSocial(
        provider,
        token,
        url: NetworkService.defaultUrl,
      );

      if (!mounted) return;

      if (result.status == SessionAuthStatus.success) {
        setState(() => _isConnecting = false);
      } else if (result.status == SessionAuthStatus.needsNickname) {
        setState(() {
          _isConnecting = false;
          _showSocialNickname = true;
        });
      } else {
        setState(() {
          _error = result.error ?? '소셜 로그인 실패';
          _isConnecting = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '$e';
        _isConnecting = false;
      });
    }
  }

  Future<void> _onSocialNicknameSubmitted(String nickname) async {
    if (_socialProvider == null || _socialToken == null) return;

    setState(() {
      _isConnecting = true;
      _showSocialNickname = false;
    });
    context.read<SessionService>().clearRestoreFeedback();

    try {
      final game = context.read<GameService>();
      final session = context.read<SessionService>();
      final result = await session.completeSocialRegistration(
        _socialProvider!,
        _socialToken!,
        nickname,
        existingUser: game.socialExistingUser,
      );

      if (!mounted) return;

      if (result.status == SessionAuthStatus.success) {
        setState(() => _isConnecting = false);
      } else {
        setState(() {
          _error = result.error ?? '로그인 실패';
          _isConnecting = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '$e';
        _isConnecting = false;
      });
    }
  }

  void _showRegisterDialog() {
    setState(() => _showRegister = true);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return PopScope(
      canPop: false,
      child: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isLandscape =
                      constraints.maxWidth > constraints.maxHeight;
                  final horizontalPadding = isLandscape ? 32.0 : 24.0;
                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(horizontalPadding),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isLandscape ? 960 : 460,
                        ),
                        child: isLandscape
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 28),
                                      child: _buildBrandSection(compact: true),
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildLoginCard(session, compact: true),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildBrandSection(compact: false),
                                  const SizedBox(height: 48),
                                  _buildLoginCard(session, compact: false),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Version display at bottom right
          Positioned(
            bottom: 16,
            right: 16,
            child: SafeArea(
              child: Text(
                _appVersion.isEmpty ? 'v-' : 'v$_appVersion',
                style: TextStyle(
                  color: const Color(0xFFB0A8A4).withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ),
          ),
          if (_isConnecting) _buildConnectingOverlay(session),
          if (_showRegister) _buildRegisterDialog(),
          if (_showSocialNickname) _buildSocialNicknameDialog(),
        ],
      ),
    ),
    ),
    );
  }

  Widget _buildBrandSection({required bool compact}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text('🐥', style: TextStyle(fontSize: compact ? 52 : 60)),
        const SizedBox(height: 8),
        Text(
          'TICHU',
          style: TextStyle(
            fontSize: compact ? 34 : 40,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF5A4038),
            letterSpacing: compact ? 3 : 4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '팀 카드게임',
          style: TextStyle(
            fontSize: compact ? 15 : 16,
            color: const Color(0xFF8A7A72),
          ),
        ),
        if (compact) ...[
          const SizedBox(height: 16),
          const Text(
            '빠르게 다시 접속하고,\n불필요한 화면 왕복 없이 바로 게임으로 돌아가세요.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF8A7A72),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoginCard(SessionService session, {required bool compact}) {
    final cardPadding = compact ? 20.0 : 24.0;
    final socialSpacing = compact ? 12.0 : 16.0;
    final loginButtonHeight = compact ? 52.0 : 56.0;

    return Container(
      padding: EdgeInsets.all(cardPadding),
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
            fontSize: compact ? 16 : 18,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _passwordController,
            hint: '비밀번호',
            icon: Icons.lock_outline,
            obscure: true,
            fontSize: compact ? 16 : 18,
          ),
          if (!_isConnecting && session.hasRestoreError) ...[
            const SizedBox(height: 16),
            _buildAutoLoginNotice(session),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: loginButtonHeight,
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
              child: Text(
                '로그인',
                style: TextStyle(
                  fontSize: compact ? 16 : 18,
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
            if (_error!.contains('점검'))
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFB74D)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.construction,
                      color: Color(0xFFE65100),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFE65100),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
          ],
          SizedBox(height: compact ? 20 : 24),
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: const Color(0xFFD9CCC8).withValues(alpha: 0.5),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '간편 로그인',
                  style: TextStyle(color: Color(0xFFAA9A92), fontSize: 13),
                ),
              ),
              Expanded(
                child: Divider(
                  color: const Color(0xFFD9CCC8).withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: socialSpacing,
            runSpacing: socialSpacing,
            children: [
              _buildSocialButton(
                onTap: () => _handleSocialSignIn('google'),
                backgroundColor: Colors.white,
                borderColor: const Color(0xFFDADADA),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.asset('assets/icons/google_logo.png'),
                ),
              ),
              if (Platform.isIOS)
                _buildSocialButton(
                  onTap: () => _handleSocialSignIn('apple'),
                  backgroundColor: Colors.black,
                  child: const Icon(
                    Icons.apple,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              _buildSocialButton(
                onTap: () => _handleSocialSignIn('kakao'),
                backgroundColor: const Color(0xFFFEE500),
                child: CustomPaint(
                  size: const Size(24, 24),
                  painter: _KakaoLogoPainter(),
                ),
              ),
            ],
          ),
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

  Widget _buildSocialButton({
    required VoidCallback onTap,
    required Color backgroundColor,
    Color? borderColor,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: _isConnecting ? null : onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: borderColor != null ? Border.all(color: borderColor) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _buildSocialNicknameDialog() {
    return SocialNicknameDialog(
      onSubmit: _onSocialNicknameSubmitted,
      onClose: () {
        setState(() => _showSocialNickname = false);
      },
    );
  }

  Widget _buildAutoLoginNotice(SessionService session) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF2C185)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '자동 로그인에 실패했습니다',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7A4B1F),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            session.restoreError ?? '저장된 로그인 정보를 다시 확인해주세요.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF7A4B1F),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton(
                onPressed: _isConnecting ? null : _retryAutoLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF28C26),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: const Text('다시 시도'),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _isConnecting
                    ? null
                    : () => context.read<SessionService>().clearRestoreFeedback(),
                child: const Text('직접 로그인'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingOverlay(SessionService session) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFF28C26)),
              const SizedBox(height: 20),
              Text(
                session.isRestoring ? '자동 로그인 중...' : '로그인 중...',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                session.isRestoring
                    ? session.restoreStatusMessage
                    : '계정 정보를 확인하고 있습니다.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8A746A),
                  height: 1.4,
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
      serverUrl: NetworkService.defaultUrl,
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
  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  bool _nicknameChecking = false;

  void _onNicknameChanged(String value) {
    if (_nicknameChecked) {
      setState(() {
        _nicknameChecked = false;
        _nicknameAvailable = false;
        _nicknameStatus = null;
      });
    }
  }

  Future<void> _checkNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _nicknameStatus = '닉네임을 입력해주세요');
      return;
    }
    setState(() => _nicknameChecking = true);

    try {
      final network = context.read<NetworkService>();
      if (!network.isConnected) {
        await network.connect(widget.serverUrl);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nicknameChecking = false;
        _nicknameStatus = '서버에 연결할 수 없습니다.';
      });
      return;
    }

    if (!mounted) return;
    final game = context.read<GameService>();
    Timer? timeout;
    void listener() {
      if (game.nicknameCheckMessage != null) {
        timeout?.cancel();
        game.removeListener(listener);
        if (!mounted) return;
        setState(() {
          _nicknameChecking = false;
          _nicknameChecked = true;
          _nicknameAvailable = game.nicknameAvailable ?? false;
          _nicknameStatus = game.nicknameCheckMessage;
        });
      }
    }
    timeout = Timer(const Duration(seconds: 5), () {
      game.removeListener(listener);
      if (!mounted) return;
      setState(() {
        _nicknameChecking = false;
        _nicknameStatus = '서버 응답이 없습니다. 다시 시도해주세요.';
      });
    });
    game.addListener(listener);
    game.checkNickname(nickname);
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
      if (!mounted) return;
      for (int i = 0; i < 50; i++) {
        if (!mounted) return;
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
        if (!mounted) return;
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
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
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
                  suffixIcon: _nicknameChecked
                      ? Icon(
                          _nicknameAvailable ? Icons.check_circle : Icons.cancel,
                          color: _nicknameAvailable ? Colors.green : Colors.red,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _nicknameChecking ? null : _checkNickname,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B7355),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: _nicknameChecking
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('중복확인', style: TextStyle(fontSize: 13)),
              ),
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

class SocialNicknameDialog extends StatefulWidget {
  final Future<void> Function(String nickname) onSubmit;
  final VoidCallback onClose;

  const SocialNicknameDialog({
    super.key,
    required this.onSubmit,
    required this.onClose,
  });

  @override
  State<SocialNicknameDialog> createState() => _SocialNicknameDialogState();
}

class _SocialNicknameDialogState extends State<SocialNicknameDialog> {
  final _nicknameController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _nicknameStatus;
  bool _nicknameChecked = false;
  bool _nicknameAvailable = false;
  bool _nicknameChecking = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _onNicknameChanged(String value) {
    if (_nicknameChecked) {
      setState(() {
        _nicknameChecked = false;
        _nicknameAvailable = false;
        _nicknameStatus = null;
      });
    }
  }

  Future<void> _checkNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _nicknameStatus = '닉네임을 입력해주세요');
      return;
    }
    setState(() => _nicknameChecking = true);

    try {
      final network = context.read<NetworkService>();
      if (!network.isConnected) {
        await network.connect();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nicknameChecking = false;
        _nicknameStatus = '서버에 연결할 수 없습니다.';
      });
      return;
    }

    if (!mounted) return;
    final game = context.read<GameService>();
    Timer? timeout;
    void listener() {
      if (game.nicknameCheckMessage != null) {
        timeout?.cancel();
        game.removeListener(listener);
        if (!mounted) return;
        setState(() {
          _nicknameChecking = false;
          _nicknameChecked = true;
          _nicknameAvailable = game.nicknameAvailable ?? false;
          _nicknameStatus = game.nicknameCheckMessage;
        });
      }
    }
    timeout = Timer(const Duration(seconds: 5), () {
      game.removeListener(listener);
      if (!mounted) return;
      setState(() {
        _nicknameChecking = false;
        _nicknameStatus = '서버 응답이 없습니다. 다시 시도해주세요.';
      });
    });
    game.addListener(listener);
    game.checkNickname(nickname);
  }

  Future<void> _submit() async {
    final nickname = _nicknameController.text.trim();
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

    await widget.onSubmit(nickname);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
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
                        '닉네임 설정',
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
                  const SizedBox(height: 8),
                  const Text(
                    '게임에서 사용할 닉네임을 설정해주세요',
                    style: TextStyle(color: Color(0xFF8A7A72), fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nicknameController,
                          onChanged: _onNicknameChanged,
                          decoration: InputDecoration(
                            hintText: '닉네임',
                            hintStyle: const TextStyle(color: Color(0xFFAA9A92), fontSize: 14),
                            prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFFAA9A92)),
                            filled: true,
                            fillColor: const Color(0xFFF8F4F2),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            suffixIcon: _nicknameChecked
                                ? Icon(
                                    _nicknameAvailable ? Icons.check_circle : Icons.cancel,
                                    color: _nicknameAvailable ? Colors.green : Colors.red,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _nicknameChecking ? null : _checkNickname,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B7355),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          child: _nicknameChecking
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('중복확인', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                  if (_nicknameStatus != null) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _nicknameStatus!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _nicknameAvailable ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF28C26),
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
                              '시작하기',
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
      ),
    );
  }
}

class _KakaoLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3C1E1E)
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final rx = size.width * 0.48;
    final ry = size.height * 0.36;

    // Speech bubble body (ellipse)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      paint,
    );

    // Speech bubble tail
    final tail = Path()
      ..moveTo(cx - size.width * 0.1, cy + ry * 0.75)
      ..lineTo(cx - size.width * 0.18, size.height * 0.92)
      ..lineTo(cx + size.width * 0.08, cy + ry * 0.85)
      ..close();
    canvas.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
