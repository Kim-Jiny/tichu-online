import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.construction,
                  color: Color(0xFFE65100),
                  size: 64,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.maintenanceTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100),
                  ),
                ),
                const SizedBox(height: 12),
                if (game.maintenanceMessage.isNotEmpty)
                  Text(
                    game.maintenanceMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                if (timeText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    timeText,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFFBF360C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (isEnded && _reconnecting)
                  Column(
                    children: [
                      Text(
                        l10n.maintenanceEnded,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  )
                else if (!isEnded && _remaining > Duration.zero) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFB74D)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          l10n.maintenanceCountdown(_formatCountdown(_remaining)),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_reconnectError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _reconnectError!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.red,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _reconnecting ? null : _attemptReconnect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF28C26),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _reconnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            l10n.maintenanceRetry,
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
      ),
    );
  }
}
