import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/social_config.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/network_service.dart';
import '../services/game_service.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../theme/cartoon.dart';
import '../widgets/social_logo.dart';

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

/// Taps outside a text field dismiss the keyboard — but only outside.
///
/// This used to be a GestureDetector wrapping the whole screen with
/// `onTap: unfocus`. On a mobile browser that raced the field's own tap: the
/// field took focus, the keyboard started to rise, and the ancestor tap fired
/// `unfocus()` right behind it, so the keyboard slid back down and no caret
/// ever appeared. The register dialog was fine precisely because it is a
/// separate overlay with no such ancestor.
///
/// TapRegion only reports taps that land outside its group, so a tap on the
/// field never reaches it.
class _DismissKeyboardOnTap extends StatelessWidget {
  const _DismissKeyboardOnTap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isConnecting = false;

  /// Bumped every time a social sign-in starts or is abandoned.
  ///
  /// signInWithPopup is supposed to reject with popup-closed-by-user when the
  /// window goes away, but it does not always notice — closing the popup can
  /// leave the future pending forever, and the spinner with it. The user is
  /// given a way out (see _buildConnectingOverlay); this id is what stops the
  /// abandoned attempt from resolving later and yanking them into a login they
  /// already backed out of.
  int _socialAttempt = 0;
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

  String _mapLoginError(String? error, String fallback) {
    if (error == 'connection_failed') {
      return L10n.of(context).loginServerUnavailable;
    }
    return error ?? fallback;
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
    if (savedUsername != null &&
        savedPassword != null &&
        savedUsername.isNotEmpty) {
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
    FocusScope.of(context).unfocus();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final l10n = L10n.of(context);
    if (username.isEmpty) {
      setState(() => _error = l10n.loginEnterUsername);
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = l10n.loginEnterPassword);
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
          _error = _mapLoginError(result.error, l10n.loginFailed);
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
    final l10n = L10n.of(context);
    final attempt = ++_socialAttempt;
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

      // The popup outlived the user's patience and they dismissed the
      // spinner; whatever it eventually returned is not wanted.
      if (attempt != _socialAttempt || !mounted) return;

      if (result.cancelled) {
        setState(() => _isConnecting = false);
        return;
      }

      _socialProvider = result.provider;
      _socialToken = result.token;
      await _socialLogin(result.provider, result.token);
    } catch (e) {
      if (attempt != _socialAttempt || !mounted) return;
      setState(() {
        _error = l10n.loginSocialFailed('$e');
        _isConnecting = false;
      });
    }
  }

  /// Abandons a social sign-in whose popup never reported back.
  void _cancelSocialSignIn() {
    _socialAttempt++;
    setState(() => _isConnecting = false);
  }

  Future<void> _socialLogin(String provider, String token) async {
    final l10n = L10n.of(context);
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
          _error = _mapLoginError(result.error, l10n.loginSocialFailedGeneric);
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

    final l10n = L10n.of(context);
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
          _error = _mapLoginError(result.error, l10n.loginFailed);
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
      child: _DismissKeyboardOnTap(
        child: Scaffold(
          // On the web the engine has already shrunk its canvas to the visual
          // viewport by the time the keyboard is up, so letting the Scaffold
          // subtract viewInsets on top of that takes the keyboard height off
          // twice and leaves an empty band above the keyboard. Native keeps the
          // default, where the inset is the only thing doing the resizing.
          resizeToAvoidBottomInset: kIsWeb ? false : null,
          body: Stack(
            children: [
              CartoonBackground(
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Deliberately the window, not the box the builder was
                      // handed. Opening the keyboard shrinks that box — on a
                      // phone from ~800 to ~350 — so width overtakes height and
                      // this flipped to the landscape branch mid-focus. The
                      // rebuild swapped the field out, the focus went with it,
                      // and the keyboard that had just started rising dropped
                      // straight back down. MediaQuery.size ignores the
                      // keyboard, so the layout stays put while typing.
                      final windowSize = MediaQuery.of(context).size;
                      final isLandscape = windowSize.width > windowSize.height;
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 28,
                                          ),
                                          child: _buildBrandSection(
                                            compact: true,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: _buildLoginCard(
                                          session,
                                          compact: true,
                                        ),
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
    final l10n = L10n.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        // 로고는 위에서 떨어져 들어와 둥둥 떠다니고, 제목은 이어서 내려앉고,
        // 부제는 살며시 떠오른다.
        CartoonEntrance(
          from: const Offset(0, -70),
          child: CartoonFloat(
            child: Image.asset(
              'assets/dragon_head.webp',
              // 머리 그림은 가로로 길어 정사각 칸에 넣으면 작아 보인다.
              width: compact ? 124 : 156,
            ),
          ),
        ),
        const SizedBox(height: 10),
        CartoonEntrance(
          delay: const Duration(milliseconds: 180),
          from: const Offset(0, -34),
          child: Cartoon.outlinedText(
            'TICHU',
            size: compact ? 46 : 56,
            fill: Cartoon.yellow,
            letterSpacing: compact ? 3 : 5,
          ),
        ),
        const SizedBox(height: 6),
        CartoonEntrance(
          delay: const Duration(milliseconds: 380),
          from: const Offset(0, 10),
          pop: false,
          child: Text(
            l10n.loginSubtitle,
            style: Cartoon.text(size: compact ? 17 : 18),
          ),
        ),
        if (compact) ...[
          const SizedBox(height: 16),
          CartoonEntrance(
            delay: const Duration(milliseconds: 480),
            from: const Offset(0, 10),
            pop: false,
            child: Text(
              l10n.loginTagline,
              style: Cartoon.text(size: 15, height: 1.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoginCard(SessionService session, {required bool compact}) {
    final l10n = L10n.of(context);
    final cardPadding = compact ? 20.0 : 24.0;
    final socialSpacing = compact ? 12.0 : 16.0;
    final loginButtonHeight = compact ? 52.0 : 56.0;

    return CartoonEntrance(
      delay: const Duration(milliseconds: 320),
      from: const Offset(0, 70),
      child: CartoonPanel(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          children: [
            _buildTextField(
              controller: _usernameController,
              hint: l10n.loginUsernameHint,
              icon: Icons.person_outline,
              fontSize: compact ? 16 : 18,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _passwordController,
              hint: l10n.loginPasswordHint,
              icon: Icons.lock_outline,
              obscure: true,
              fontSize: compact ? 16 : 18,
            ),
            if (!_isConnecting && session.hasRestoreError) ...[
              const SizedBox(height: 16),
              _buildAutoLoginNotice(session),
            ],
            const SizedBox(height: 20),
            CartoonButton(
              height: loginButtonHeight,
              onPressed: _isConnecting ? null : _login,
              child: CartoonButton.label(
                l10n.loginButton,
                size: compact ? 20 : 22,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _showRegisterDialog,
              child: Text(
                l10n.loginRegisterButton,
                style: Cartoon.text(size: 17),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              if (context.read<GameService>().loginErrorReason == 'maintenance')
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
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
            ],
            // "간편 로그인" heads a row that can now be empty — a build with no
            // provider keys would otherwise show a divider labelling nothing.
            if (SocialConfig.anyEnabled) ...[
              SizedBox(height: compact ? 20 : 24),
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: const Color(0xFFD9CCC8).withValues(alpha: 0.5),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      l10n.loginQuickLogin,
                      style: const TextStyle(
                        color: Color(0xFFAA9A92),
                        fontSize: 13,
                      ),
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
                // A provider only appears when this build can actually complete
                // it. Google and Kakao used to be unconditional, so on the web
                // they rendered, threw on tap and left the user staring at a
                // button that did nothing. SocialConfig answers off the same
                // keys main() initialises with, so the two can't drift.
                children: [
                  if (SocialConfig.googleEnabled)
                    _buildSocialButton(
                      onTap: () => _handleSocialSignIn('google'),
                      backgroundColor: Colors.white,
                      borderColor: const Color(0xFFDADADA),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset('assets/icons/google_logo.webp'),
                      ),
                    ),
                  // Native Apple sign-in needs the iOS system sheet; on the web it
                  // is an ordinary OAuth popup, so the browser gets it everywhere.
                  if (SocialConfig.appleEnabled)
                    _buildSocialButton(
                      onTap: () => _handleSocialSignIn('apple'),
                      backgroundColor: Colors.black,
                      child: const Icon(
                        Icons.apple,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  if (SocialConfig.kakaoEnabled)
                    _buildSocialButton(
                      onTap: () => _handleSocialSignIn('kakao'),
                      backgroundColor: const Color(0xFFFEE500),
                      child: const KakaoLogo(size: 24),
                    ),
                ],
              ),
            ],
            // Store links, web only. The site root used to be a marketing page
            // whose whole job was pointing at the stores; the web client took
            // that spot, so the install path lives here now. Safari also draws
            // its own Smart App Banner (see web/index.html) — this covers
            // Android and desktop, where no such banner exists.
            if (kIsWeb) ...[
              SizedBox(height: compact ? 18 : 24),
              Text(
                l10n.loginGetTheApp,
                style: const TextStyle(color: Color(0xFFAA9A92), fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStoreButton(
                    label: 'Google Play',
                    url:
                        'https://play.google.com/store/apps/details?id=com.jiny.tichuOnline',
                  ),
                  _buildStoreButton(
                    label: 'App Store',
                    url: 'https://apps.apple.com/app/tichu-online/id6759035151',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStoreButton({required String label, required String url}) {
    return OutlinedButton(
      // New tab: the player may be mid-login, and replacing this tab would
      // throw that away.
      onPressed: () => launchUrl(Uri.parse(url), webOnlyWindowName: '_blank'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF8A7A72),
        side: const BorderSide(color: Color(0xFFE0D8D4)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12.5)),
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
      style: Cartoon.userText(size: fontSize),
      decoration: Cartoon.inputDecoration(hint: hint, icon: icon),
    );
  }

  Widget _buildSocialButton({
    required VoidCallback onTap,
    required Color backgroundColor,
    Color? borderColor,
    required Widget child,
  }) {
    return CartoonPressable(
      onTap: _isConnecting ? null : onTap,
      // Dim while connecting so the disabled state is visible (matches the main
      // login button), preventing confused repeat taps during the handshake.
      child: Opacity(
        opacity: _isConnecting ? 0.5 : 1.0,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Cartoon.ink, width: 2),
            boxShadow: const [
              BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
            ],
          ),
          child: Center(child: child),
        ),
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
    final l10n = L10n.of(context);
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
          Text(
            l10n.loginAutoLoginFailed,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7A4B1F),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            localizeRestoreError(session.restoreErrorRaw, l10n) ??
                l10n.loginCheckSavedInfo,
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
                child: Text(l10n.loginRetry),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _isConnecting
                    ? null
                    : () =>
                          context.read<SessionService>().clearRestoreFeedback(),
                child: Text(l10n.loginManual),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingOverlay(SessionService session) {
    final l10n = L10n.of(context);
    return Container(
      color: Colors.black54,
      child: Center(
        child: CartoonLoadingCard(
          title: session.isRestoring
              ? l10n.loginAutoLoggingIn
              : l10n.loginLoggingIn,
          subtitle: session.isRestoring
              ? localizeRestorePhase(session, l10n)
              : l10n.loginVerifyingAccount,
          // Only for a social popup, and only on the web: closing the
          // provider's window does not reliably reject the pending future,
          // which used to leave this spinner up with no way back to the
          // login form. Session restore is not offered a cancel — it ends
          // on its own.
          action: (kIsWeb && !session.isRestoring)
              ? CartoonButton(
                  expand: false,
                  height: 44,
                  radius: 15,
                  color: const Color(0xFFB9B0A8),
                  onPressed: _cancelSocialSignIn,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: CartoonButton.label(l10n.commonCancel, size: 16),
                  ),
                )
              : null,
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
          SnackBar(
            content: Text(L10n.of(context).loginRegistrationComplete),
            backgroundColor: Cartoon.green,
          ),
        );
      },
    );
  }
}

// ─── 회원가입·닉네임 설정 팝업 공통 부품(카툰) ─────────────────────────────

/// 어두운 배경 위에 뜨는 카툰 패널. 제목 줄(아이콘 칩 + 제목 + 닫기)을 갖는다.
Widget _signupCard({
  required BuildContext context,
  required IconData icon,
  required Color iconColor,
  required String title,
  required VoidCallback onClose,
  required List<Widget> children,
}) {
  return GestureDetector(
    onTap: () => FocusScope.of(context).unfocus(),
    child: Container(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: CartoonPanel(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: iconColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Cartoon.ink, width: 2),
                        ),
                        child: Icon(icon, color: Cartoon.ink, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(title, style: Cartoon.text(size: 24)),
                      ),
                      CartoonPressable(
                        scale: 0.88,
                        onTap: onClose,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Cartoon.cream,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Cartoon.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

InputDecoration _signupDecoration(
  String hint,
  IconData icon, {
  Widget? suffix,
}) {
  return Cartoon.inputDecoration(hint: hint, icon: icon, radius: 14).copyWith(
    counterText: '',
    suffixIcon: suffix,
    hintStyle: Cartoon.userText(
      size: 15,
      color: Cartoon.ink.withValues(alpha: 0.4),
      weight: FontWeight.w500,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

Widget _signupLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6, left: 2),
  child: Text(text, style: Cartoon.text(size: 16)),
);

Widget _signupField({
  required TextEditingController controller,
  required String label,
  required String hint,
  required IconData icon,
  bool obscure = false,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _signupLabel(label),
      TextField(
        controller: controller,
        obscureText: obscure,
        style: Cartoon.userText(size: 17),
        decoration: _signupDecoration(hint, icon),
      ),
    ],
  );
}

/// 닉네임 입력 + 중복 확인 버튼 + 결과 한 줄.
Widget _signupNicknameRow({
  required TextEditingController controller,
  required ValueChanged<String> onChanged,
  required String hint,
  required String checkLabel,
  required bool checking,
  required bool checked,
  required bool available,
  required String? status,
  required VoidCallback onCheck,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              maxLength: 10,
              style: Cartoon.userText(size: 17),
              decoration: _signupDecoration(
                hint,
                Icons.badge_rounded,
                suffix: checked
                    ? Icon(
                        available
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: available ? Cartoon.green : Cartoon.red,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CartoonButton(
            expand: false,
            height: 50,
            radius: 14,
            color: Cartoon.blue,
            onPressed: checking ? null : onCheck,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : CartoonButton.label(checkLabel, size: 16),
            ),
          ),
        ],
      ),
      if (status != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            status,
            style: Cartoon.userText(
              size: 13.5,
              color: available ? const Color(0xFF2E9B52) : Cartoon.red,
            ),
          ),
        ),
    ],
  );
}

Widget _signupSubmit({
  required String label,
  required bool loading,
  required VoidCallback onTap,
  required Color color,
}) {
  return CartoonButton(
    color: color,
    height: 56,
    onPressed: loading ? null : onTap,
    child: loading
        ? const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
            ),
          )
        : CartoonButton.label(label, size: 21),
  );
}

Widget _signupError(String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          error,
          textAlign: TextAlign.center,
          style: Cartoon.userText(size: 14.5, color: Cartoon.red),
        ),
      );

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
    final l10n = L10n.of(context);
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _nicknameStatus = l10n.loginNicknameEmpty);
      return;
    }
    if (nickname.length < 2 || nickname.length > 10) {
      setState(() => _nicknameStatus = l10n.loginNicknameLength);
      return;
    }
    if (nickname.contains(RegExp(r'\s'))) {
      setState(() => _nicknameStatus = l10n.loginNicknameNoSpaces);
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
        _nicknameStatus = l10n.loginServerUnavailable;
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
        _nicknameStatus = l10n.loginServerNoResponse;
      });
    });
    game.addListener(listener);
    game.checkNickname(nickname);
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    final l10n = L10n.of(context);
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final nickname = _nicknameController.text.trim();

    // Validate
    if (username.length < 2) {
      setState(() => _error = l10n.loginUsernameMinLength);
      return;
    }
    if (username.contains(' ')) {
      setState(() => _error = l10n.loginUsernameNoSpaces);
      return;
    }
    if (password.length < 4) {
      setState(() => _error = l10n.loginPasswordMinLength);
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = l10n.loginPasswordMismatch);
      return;
    }
    if (nickname.isEmpty) {
      setState(() => _error = l10n.loginNicknameEmpty);
      return;
    }
    if (nickname.length < 2 || nickname.length > 10) {
      setState(() => _error = l10n.loginNicknameLength);
      return;
    }
    if (nickname.contains(RegExp(r'\s'))) {
      setState(() => _error = l10n.loginNicknameNoSpaces);
      return;
    }
    if (!_nicknameChecked || !_nicknameAvailable) {
      setState(() => _error = l10n.loginNicknameCheckRequired);
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
          if (game.registerSuccess == true) {
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
        _error = l10n.loginServerTimeout;
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
    final l10n = L10n.of(context);
    return _signupCard(
      context: context,
      icon: Icons.person_add_rounded,
      iconColor: Cartoon.green,
      title: l10n.loginRegisterTitle,
      onClose: widget.onClose,
      children: [
        _signupField(
          controller: _usernameController,
          label: l10n.loginUsernameLabel,
          hint: l10n.loginUsernameHintRegister,
          icon: Icons.person_rounded,
        ),
        const SizedBox(height: 14),
        _signupField(
          controller: _passwordController,
          label: l10n.loginPasswordLabel,
          hint: l10n.loginPasswordHintRegister,
          icon: Icons.lock_rounded,
          obscure: true,
        ),
        const SizedBox(height: 14),
        _signupField(
          controller: _confirmPasswordController,
          label: l10n.loginConfirmPasswordLabel,
          hint: l10n.loginConfirmPasswordHint,
          icon: Icons.lock_rounded,
          obscure: true,
        ),
        const SizedBox(height: 14),
        _signupLabel(l10n.loginNicknameLabel),
        _signupNicknameRow(
          controller: _nicknameController,
          onChanged: _onNicknameChanged,
          hint: l10n.loginNicknameHint,
          checkLabel: l10n.loginCheckAvailability,
          checking: _nicknameChecking,
          checked: _nicknameChecked,
          available: _nicknameAvailable,
          status: _nicknameStatus,
          onCheck: _checkNickname,
        ),
        const SizedBox(height: 22),
        _signupSubmit(
          label: l10n.loginSubmitRegister,
          loading: _isLoading,
          onTap: _register,
          color: Cartoon.green,
        ),
        _signupError(_error),
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
    final l10n = L10n.of(context);
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _nicknameStatus = l10n.loginNicknameEmpty);
      return;
    }
    if (nickname.length < 2 || nickname.length > 10) {
      setState(() => _nicknameStatus = l10n.loginNicknameLength);
      return;
    }
    if (nickname.contains(RegExp(r'\s'))) {
      setState(() => _nicknameStatus = l10n.loginNicknameNoSpaces);
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
        _nicknameStatus = l10n.loginServerUnavailable;
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
        _nicknameStatus = l10n.loginServerNoResponse;
      });
    });
    game.addListener(listener);
    game.checkNickname(nickname);
  }

  Future<void> _submit() async {
    final l10n = L10n.of(context);
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = l10n.loginNicknameEmpty);
      return;
    }
    if (nickname.length < 2 || nickname.length > 10) {
      setState(() => _error = l10n.loginNicknameLength);
      return;
    }
    if (nickname.contains(RegExp(r'\s'))) {
      setState(() => _error = l10n.loginNicknameNoSpaces);
      return;
    }
    if (!_nicknameChecked || !_nicknameAvailable) {
      setState(() => _error = l10n.loginNicknameCheckRequired);
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
    final l10n = L10n.of(context);
    return _signupCard(
      context: context,
      icon: Icons.badge_rounded,
      iconColor: Cartoon.yellow,
      title: l10n.loginSetNicknameTitle,
      onClose: widget.onClose,
      children: [
        Text(
          l10n.loginSetNicknameDesc,
          style: Cartoon.text(
            size: 15.5,
            height: 1.4,
            color: Cartoon.ink.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 16),
        _signupNicknameRow(
          controller: _nicknameController,
          onChanged: _onNicknameChanged,
          hint: l10n.loginNicknameHint,
          checkLabel: l10n.loginCheckAvailability,
          checking: _nicknameChecking,
          checked: _nicknameChecked,
          available: _nicknameAvailable,
          status: _nicknameStatus,
          onCheck: _checkNickname,
        ),
        const SizedBox(height: 22),
        _signupSubmit(
          label: l10n.loginGetStarted,
          loading: _isLoading,
          onTap: _submit,
          color: Cartoon.orange,
        ),
        _signupError(_error),
      ],
    );
  }
}
