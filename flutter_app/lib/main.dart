import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/network_service.dart';
import 'services/game_service.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  kakao.KakaoSdk.init(nativeAppKey: 'd9b4b3cfc86537fed9a80a659641ad30');

  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('Foreground push: ${message.notification?.title} - ${message.notification?.body}');
  });

  runApp(const TichuApp());
}

class TichuApp extends StatelessWidget {
  const TichuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NetworkService()),
        ChangeNotifierProxyProvider<NetworkService, GameService>(
          create: (context) => GameService(context.read<NetworkService>()),
          update: (context, network, previous) =>
              previous ?? GameService(network),
        ),
      ],
      child: MaterialApp(
        title: 'Tichu Online',
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final platform = Theme.of(context).platform;
          final adjustedScale = platform == TargetPlatform.android
              ? (media.textScaleFactor * 0.92).clamp(0.9, 1.0)
              : media.textScaleFactor;
          return MediaQuery(
            data: media.copyWith(textScaleFactor: adjustedScale),
            child: child ?? const SizedBox.shrink(),
          );
        },
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFF28C26),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const _EntryScreen(),
      ),
    );
  }
}

class _EntryScreen extends StatefulWidget {
  const _EntryScreen();

  @override
  State<_EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<_EntryScreen> {
  bool _checking = true;
  bool _eulaAccepted = false;
  bool _agreed = false;
  bool _loading = false;
  String? _eulaText;

  @override
  void initState() {
    super.initState();
    _checkEula();
  }

  Future<void> _checkEula() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('eula_accepted') ?? false;
    if (accepted) {
      setState(() {
        _eulaAccepted = true;
        _checking = false;
      });
      return;
    }
    // Need to show EULA — connect and fetch
    setState(() {
      _checking = false;
      _loading = true;
    });
    _fetchEula();
  }

  void _fetchEula() {
    final network = context.read<NetworkService>();
    final game = context.read<GameService>();

    // Listen for eulaContent change
    game.addListener(_onEulaReceived);

    if (network.isConnected) {
      game.requestAppConfig();
    } else {
      network.connect().then((_) {
        if (mounted) game.requestAppConfig();
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _eulaText = '';
          });
        }
      });
    }
  }

  void _onEulaReceived() {
    final game = context.read<GameService>();
    if (game.eulaContent != null) {
      game.removeListener(_onEulaReceived);
      if (mounted) {
        setState(() {
          _eulaText = game.eulaContent;
          _loading = false;
        });
      }
    }
  }

  Future<void> _acceptEula() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('eula_accepted', true);
    setState(() {
      _eulaAccepted = true;
    });
  }

  @override
  void dispose() {
    // Safety: remove listener if still attached
    try {
      context.read<GameService>().removeListener(_onEulaReceived);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_eulaAccepted) {
      return const LoginScreen();
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 24),
              // App logo
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/icon.png',
                  width: 80,
                  height: 80,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tichu Online',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '이용약관',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              // EULA text area
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          child: Text(
                            _eulaText ?? '이용약관을 불러올 수 없습니다. 네트워크 연결을 확인해주세요.',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // Checkbox
              GestureDetector(
                onTap: () => setState(() => _agreed = !_agreed),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _agreed,
                        onChanged: (v) => setState(() => _agreed = v ?? false),
                        activeColor: const Color(0xFFF28C26),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '이용약관에 동의합니다',
                      style: TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Start button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _agreed ? _acceptEula : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF28C26),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '시작하기',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
