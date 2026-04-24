import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'app_navigation.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'services/network_service.dart';
import 'services/game_service.dart';
import 'services/invite_link_service.dart';
import 'services/session_service.dart';
import 'services/locale_service.dart';
import 'screens/game_screen.dart';
import 'screens/login_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/spectator_screen.dart';
import 'screens/sk_game_screen.dart';
import 'screens/ll_game_screen.dart';
import 'screens/mighty_game_screen.dart';
import 'screens/maintenance_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  kakao.KakaoSdk.init(nativeAppKey: 'd9b4b3cfc86537fed9a80a659641ad30');
  await InviteLinkService.instance.initialize();
  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(testDeviceIds: ['45b45cb9d1be2ccb4c01a54eea9a0a64']),
  );
  await MobileAds.instance.initialize();
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  await FirebaseMessaging.instance.setAutoInitEnabled(true);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint(
      'Foreground push: ${message.notification?.title} - ${message.notification?.body}',
    );
  });

  runApp(const TichuApp());
}

ThemeData _buildTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFF28C26),
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontSize: 14,
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.outline),
      ),
    ),
  );
}

class TichuApp extends StatelessWidget {
  const TichuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final localeService = LocaleService();
            localeService.loadSaved();
            return localeService;
          },
        ),
        ChangeNotifierProvider(create: (_) => NetworkService()),
        ChangeNotifierProxyProvider<NetworkService, GameService>(
          create: (context) => GameService(context.read<NetworkService>()),
          update: (context, network, previous) =>
              previous ?? GameService(network),
        ),
        ChangeNotifierProvider(
          create: (context) => SessionService(
            context.read<NetworkService>(),
            context.read<GameService>(),
          ),
        ),
      ],
      child: Consumer<LocaleService>(
        builder: (context, localeService, _) => MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Tichu Online',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: localeService.userSelectedLocale,
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            if (deviceLocale != null) {
              for (final supported in supportedLocales) {
                if (supported.languageCode == deviceLocale.languageCode) {
                  return supported;
                }
              }
            }
            return const Locale('en');
          },
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final platform = Theme.of(context).platform;
            final currentScale = media.textScaler.scale(1.0);
            final adjustedScale = platform == TargetPlatform.android
                ? (currentScale * 0.92).clamp(0.9, 1.0)
                : currentScale;
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(adjustedScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          theme: _buildTheme(),
          home: const _OrientationGate(child: _EntryScreen()),
        ),
      ),
    );
  }
}

class _OrientationGate extends StatefulWidget {
  const _OrientationGate({required this.child});

  final Widget child;

  @override
  State<_OrientationGate> createState() => _OrientationGateState();
}

class _OrientationGateState extends State<_OrientationGate>
    with WidgetsBindingObserver {
  bool? _allowLandscape;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncOrientationPolicy();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncOrientationPolicy();
      }
    });
  }

  Future<void> _syncOrientationPolicy() async {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return;

    final allowLandscape = media.size.shortestSide >= 600;
    if (_allowLandscape == allowLandscape) return;
    _allowLandscape = allowLandscape;

    if (allowLandscape) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AppFlowScreen extends StatelessWidget {
  const _AppFlowScreen();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final game = context.watch<GameService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InviteLinkService.instance.processPendingInvite(session, game);
    });

    Widget child;
    if (session.isRestoring && !game.isLoggedIn) {
      child = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (!game.isLoggedIn) {
      child = game.isInKnownMaintenanceWindow
          ? const MaintenanceScreen()
          : const LoginScreen();
    } else if (game.isUnderMaintenance) {
      // Server broadcast maintenance while logged in — kick to maintenance screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        session.resetToLoginState(suppressAutoRestore: true);
      });
      child = const MaintenanceScreen();
    } else {
      switch (game.currentDestination) {
        case AppDestination.game:
          child = const GameScreen();
          break;
        case AppDestination.skGame:
          child = const SKGameScreen();
          break;
        case AppDestination.llGame:
          child = const LLGameScreen();
          break;
        case AppDestination.mightyGame:
          child = const MightyGameScreen();
          break;
        case AppDestination.spectator:
          child = const SpectatorScreen();
          break;
        case AppDestination.lobby:
        case AppDestination.waitingRoom:
          child = const LobbyScreen();
          break;
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(
        key: ValueKey(
          '${game.isLoggedIn}-${(!game.isLoggedIn && game.isInKnownMaintenanceWindow) || game.isUnderMaintenance ? 'maintenance' : _flowKeyForDestination(game.currentDestination)}',
        ),
        child: child,
      ),
    );
  }

  String _flowKeyForDestination(AppDestination destination) {
    switch (destination) {
      case AppDestination.lobby:
      case AppDestination.waitingRoom:
        return 'lobby';
      case AppDestination.game:
        return 'game';
      case AppDestination.skGame:
        return 'skGame';
      case AppDestination.llGame:
        return 'llGame';
      case AppDestination.mightyGame:
        return 'mightyGame';
      case AppDestination.spectator:
        return 'spectator';
    }
  }
}

class _EntryScreen extends StatefulWidget {
  const _EntryScreen();

  @override
  State<_EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<_EntryScreen> {
  bool _showSplash = true;
  bool _checking = true;
  bool _eulaAccepted = false;
  bool _agreed = false;
  bool _loading = false;
  String? _eulaText;
  GameService? _gameService;
  bool _eulaListenerAttached = false;
  bool _forceUpdate = false;
  bool _forceUpdateListenerAttached = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        setState(() => _showSplash = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestATT();
    });
    _checkEula();
  }

  Future<void> _requestATT() async {
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    debugPrint('[ATT] current status: $status');
    if (status == TrackingStatus.notDetermined) {
      final result =
          await AppTrackingTransparency.requestTrackingAuthorization();
      debugPrint('[ATT] request result: $result');
    }
    // Request push permission AFTER ATT to avoid overlapping iOS system dialogs
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
      '[FCM] Notification permission: ${settings.authorizationStatus}',
    );
  }

  Future<void> _checkEula() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final accepted = prefs.getBool('eula_accepted') ?? false;
    if (accepted) {
      setState(() {
        _eulaAccepted = true;
        _checking = false;
      });
      _startForceUpdateCheck();
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
    _gameService ??= context.read<GameService>();
    final game = _gameService!;
    // Pass the effective UI locale so the pre-login EULA/privacy fetch
    // matches the device language (ws.locale isn't set yet at this point).
    final locale = context.read<LocaleService>().effectiveLocale.languageCode;

    _attachEulaListener();

    if (network.isConnected) {
      game.requestAppConfig(locale: locale);
    } else {
      network
          .connect()
          .then((_) {
            if (mounted) game.requestAppConfig(locale: locale);
          })
          .catchError((e) {
            _detachEulaListener();
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
    final game = _gameService;
    if (game == null) return;
    if (game.eulaContent != null) {
      _detachEulaListener();
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
    if (!mounted) return;
    setState(() {
      _eulaAccepted = true;
    });
    _startForceUpdateCheck();
  }

  void _startForceUpdateCheck() {
    _gameService ??= context.read<GameService>();
    final game = _gameService!;
    // If minVersion already available (from EULA fetch), check immediately
    if (game.minVersion != null && game.minVersion!.isNotEmpty) {
      _checkForceUpdate(game.minVersion!);
    } else {
      _attachForceUpdateListener();
      // If EULA was already accepted, we need to fetch app_config ourselves
      final network = context.read<NetworkService>();
      final locale = context.read<LocaleService>().effectiveLocale.languageCode;
      if (network.isConnected) {
        game.requestAppConfig(locale: locale);
      } else {
        network
            .connect()
            .then((_) {
              if (mounted) game.requestAppConfig(locale: locale);
            })
            .catchError((_) {});
      }
    }
  }

  @override
  void dispose() {
    _detachEulaListener();
    _detachForceUpdateListener();
    super.dispose();
  }

  void _attachEulaListener() {
    if (_eulaListenerAttached) return;
    _gameService?.addListener(_onEulaReceived);
    _eulaListenerAttached = true;
  }

  void _detachEulaListener() {
    if (!_eulaListenerAttached) return;
    _gameService?.removeListener(_onEulaReceived);
    _eulaListenerAttached = false;
  }

  void _attachForceUpdateListener() {
    if (_forceUpdateListenerAttached) return;
    _gameService?.addListener(_onForceUpdateCheck);
    _forceUpdateListenerAttached = true;
  }

  void _detachForceUpdateListener() {
    if (!_forceUpdateListenerAttached) return;
    _gameService?.removeListener(_onForceUpdateCheck);
    _forceUpdateListenerAttached = false;
  }

  void _onForceUpdateCheck() {
    final game = _gameService;
    if (game == null || game.minVersion == null || game.minVersion!.isEmpty) {
      return;
    }
    _detachForceUpdateListener();
    _checkForceUpdate(game.minVersion!);
  }

  Future<void> _checkForceUpdate(String minVersion) async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (_compareVersions(info.version, minVersion) < 0) {
        if (mounted) setState(() => _forceUpdate = true);
      }
    } catch (_) {}
  }

  /// Returns negative if a < b, 0 if equal, positive if a > b
  int _compareVersions(String a, String b) {
    final partsA = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (int i = 0; i < len; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  Future<void> _openStore() async {
    final uri = Uri.parse(
      Platform.isIOS
          ? 'https://apps.apple.com/app/tichu-online/id6759035151'
          : 'https://play.google.com/store/apps/details?id=com.jiny.tichuOnline',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // fallback: try without mode
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Image.asset('assets/splash.png', fit: BoxFit.cover),
        ),
      );
    }

    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_eulaAccepted && _forceUpdate) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset('assets/icon.png', width: 80, height: 80),
                ),
                const SizedBox(height: 24),
                Text(
                  L10n.of(context).appForceUpdateTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.of(context).appForceUpdateBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _openStore,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      L10n.of(context).appForceUpdateButton,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_eulaAccepted) {
      return const _AppFlowScreen();
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
                child: Image.asset('assets/icon.png', width: 80, height: 80),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tichu Online',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                L10n.of(context).appEulaSubtitle,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
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
                            _eulaText ?? L10n.of(context).appEulaLoadFailed,
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
                    Text(
                      L10n.of(context).appEulaAgree,
                      style: const TextStyle(fontSize: 15),
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
                  child: Text(
                    L10n.of(context).appEulaStart,
                    style: const TextStyle(
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
