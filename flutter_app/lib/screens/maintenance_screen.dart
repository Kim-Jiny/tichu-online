import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/cartoon.dart';
import '../widgets/game_chrome.dart' show gameButton, gamePillDecoration;
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import '../services/session_service.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _reconnecting = false;
  String? _reconnectError;
  bool _autoReconnectTriggered = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    final game = context.read<GameService>();
    if (game.maintenanceEnd == null) return;
    try {
      final end = DateTime.parse(game.maintenanceEnd!);
      _updateRemaining(end);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _updateRemaining(end);
      });
    } catch (_) {}
  }

  void _updateRemaining(DateTime end) {
    final now = DateTime.now().toUtc();
    final diff = end.difference(now);
    if (diff.isNegative && !_autoReconnectTriggered) {
      _autoReconnectTriggered = true;
      _countdownTimer?.cancel();
      setState(() => _remaining = Duration.zero);
      _attemptReconnect();
      return;
    }
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }

  Future<void> _attemptReconnect() async {
    if (_reconnecting) return;
    setState(() {
      _reconnecting = true;
      _reconnectError = null;
    });
    final session = context.read<SessionService>();
    try {
      final success = await session.reconnectAndRestore();
      if (!mounted) return;
      if (!success) {
        setState(() {
          _reconnecting = false;
          _reconnectError = L10n.of(context).loginServerUnavailable;
        });
      }
      // If success, the provider will update isLoggedIn and _AppFlowScreen
      // will navigate away automatically.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reconnecting = false;
        _reconnectError = L10n.of(context).loginServerUnavailable;
      });
    }
  }

  String _formatCountdown(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameService>();
    final l10n = L10n.of(context);

    String timeText = '';
    if (game.maintenanceStart != null && game.maintenanceEnd != null) {
      try {
        final start = DateTime.parse(game.maintenanceStart!).toLocal();
        final end = DateTime.parse(game.maintenanceEnd!).toLocal();
        String fmt(DateTime d) =>
            '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        timeText = '${fmt(start)} ~ ${fmt(end)}';
      } catch (_) {}
    }

    final isEnded = _remaining == Duration.zero && _autoReconnectTriggered;

    return Scaffold(
      body: CartoonBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: CartoonEntrance(
                  from: const Offset(0, 24),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                    decoration: Cartoon.panelDecoration(
                      radius: 28,
                      shadowOffset: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CartoonFloat(
                          amplitude: 4,
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: Cartoon.yellow,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Cartoon.ink,
                                width: 2.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.construction_rounded,
                              color: Cartoon.ink,
                              size: 46,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          l10n.maintenanceTitle,
                          textAlign: TextAlign.center,
                          style: Cartoon.text(size: 24),
                        ),
                        const SizedBox(height: 12),
                        if (game.maintenanceMessage.isNotEmpty)
                          Text(
                            game.maintenanceMessage,
                            textAlign: TextAlign.center,
                            style: Cartoon.userText(
                              size: 15,
                              weight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        if (timeText.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: gamePillDecoration(radius: 99),
                            child: Text(
                              timeText,
                              style: Cartoon.text(size: 14),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (isEnded && _reconnecting)
                          Column(
                            children: [
                              Text(
                                l10n.maintenanceEnded,
                                style: Cartoon.text(
                                  size: 16,
                                  color: Cartoon.green,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const CartoonLoader(size: 36),
                            ],
                          )
                        else if (!isEnded && _remaining > Duration.zero)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 10,
                            ),
                            decoration: gamePillDecoration(
                              radius: 18,
                              color: const Color(0xFFFFF1B8),
                            ),
                            child: Text(
                              l10n.maintenanceCountdown(
                                _formatCountdown(_remaining),
                              ),
                              style: Cartoon.text(size: 19),
                            ),
                          ),
                        if (_reconnectError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _reconnectError!,
                            textAlign: TextAlign.center,
                            style: Cartoon.userText(
                              size: 13.5,
                              color: Cartoon.red,
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        gameButton(
                          l10n.maintenanceRetry,
                          _reconnecting ? null : _attemptReconnect,
                          height: 52,
                          size: 19,
                          expand: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
