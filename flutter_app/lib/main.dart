import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/network_service.dart';
import 'services/game_service.dart';
import 'screens/login_screen.dart';

void main() {
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
        home: const LoginScreen(),
      ),
    );
  }
}
