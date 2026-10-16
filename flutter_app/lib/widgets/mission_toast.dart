import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_navigation.dart';
import '../l10n/app_localizations.dart';
import '../models/missions.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import '../utils/mission_text.dart';
import '../screens/missions_screen.dart' show TokenCoin;

/// 서버가 "미션 완료"를 밀어 줄 때 어느 화면에서든 위에서 내려오는 알림을 띄운다.
/// 앱 전체를 한 번 감싸 두면 되고, 게임 중이든 로비든 같은 모양이다.
class MissionToastHost extends StatefulWidget {
  const MissionToastHost({super.key, required this.child});
  final Widget child;

  @override
  State<MissionToastHost> createState() => _MissionToastHostState();
}

class _MissionToastHostState extends State<MissionToastHost> {
  StreamSubscription<MissionCompletion>? _sub;
  GameService? _game;
  OverlayEntry? _entry;
  Timer? _timer;
  final List<MissionCompletion> _queue = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final game = context.read<GameService>();
    if (!identical(game, _game)) {
      _sub?.cancel();
      _game = game;
      _sub = game.missionCompletions.listen(_enqueue);
    }
  }

  void _enqueue(MissionCompletion c) {
    _queue.add(c);
    if (_entry == null) _showNext();
  }

  void _showNext() {
    if (_queue.isEmpty) return;
    final overlay = appNavigatorKey.currentState?.overlay;
    final ctx = appNavigatorKey.currentContext;
    if (overlay == null || ctx == null) {
      _queue.clear();
      return;
    }
    final c = _queue.removeAt(0);
    final l10n = L10n.of(ctx);
    final lines = <String>[
      if (c.tokens > 0)
        l10n.missionCompletedTokens(c.tokens.toString())
      else
        l10n.missionCompletedCapped,
      if (c.streakBonus > 0)
        l10n.missionCompletedStreak(c.streakBonus.toString()),
    ];
    _entry = OverlayEntry(
      builder: (_) => _ToastView(
        title: l10n.missionCompletedToast(missionTitle(l10n, c.key)),
        lines: lines,
        onTap: _dismiss,
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(const Duration(milliseconds: 3600), _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    _entry?.remove();
    _entry = null;
    if (_queue.isNotEmpty) {
      // 이어서 뜰 게 있으면 잠깐 숨을 돌린 뒤 다음 것.
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted && _entry == null) _showNext();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ToastView extends StatelessWidget {
  const _ToastView({
    required this.title,
    required this.lines,
    required this.onTap,
  });

  final String title;
  final List<String> lines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 10;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: Material(
        type: MaterialType.transparency,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.elasticOut,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -24 * (1 - t)),
              child: child,
            ),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  decoration: Cartoon.panelDecoration(
                    radius: 18,
                    color: const Color(0xFFFFF6D8),
                    shadowOffset: 3,
                  ),
                  child: Row(
                    children: [
                      const TokenCoin(size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Cartoon.userText(size: 14),
                            ),
                            for (final l in lines)
                              Text(
                                l,
                                style: Cartoon.text(
                                  size: 13.5,
                                  color: Cartoon.orangeDeep,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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
