import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_navigation.dart';
import '../l10n/app_localizations.dart';
import '../screens/missions_screen.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import '../utils/mission_text.dart';
import 'token_widgets.dart';

/// 미션을 깬 걸 로비로 돌아왔을 때 한 번 알려 준다.
///
/// 게임 중에는 알림이 판을 가리지 않도록 모아 두고, 로비(대기실)로 나오면 그동안 깬
/// 미션을 합쳐서 위에서 내려오는 알림 한 번으로 보여 준다. 알림을 누르면 미션 화면이
/// 열린다. 앱 전체를 한 번 감싸 두면 된다.
class MissionToastHost extends StatefulWidget {
  const MissionToastHost({super.key, required this.child});
  final Widget child;

  @override
  State<MissionToastHost> createState() => _MissionToastHostState();
}

class _MissionToastHostState extends State<MissionToastHost> {
  GameService? _game;
  OverlayEntry? _entry;
  Timer? _timer;
  bool _checkQueued = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final game = context.read<GameService>();
    if (!identical(game, _game)) {
      _game?.removeListener(_onGameChanged);
      _game = game;
      game.addListener(_onGameChanged);
    }
  }

  /// 게임 상태가 바뀔 때마다 불린다. 빌드 도중일 수 있으니 한 프레임 뒤에 확인한다.
  void _onGameChanged() {
    if (_checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (mounted) _maybeShow();
    });
  }

  static bool _isOutsideGame(AppDestination d) =>
      d == AppDestination.lobby || d == AppDestination.waitingRoom;

  void _maybeShow() {
    final game = _game;
    if (game == null || _entry != null || !game.hasPendingMissionToasts) return;
    if (!game.isLoggedIn || !_isOutsideGame(game.currentDestination)) return;
    final overlay = appNavigatorKey.currentState?.overlay;
    final ctx = appNavigatorKey.currentContext;
    if (overlay == null || ctx == null) return;

    final batch = game.takePendingMissionCompletions();
    if (batch.isEmpty) return;
    final l10n = L10n.of(ctx);
    final tokens = batch.fold<int>(0, (n, c) => n + c.tokens);
    final bonus = batch.fold<int>(0, (n, c) => n + c.streakBonus);
    final title = batch.length == 1
        ? l10n.missionCompletedToast(missionTitle(l10n, batch.first.key))
        : l10n.missionCompletedMulti(batch.length.toString());
    final lines = <String>[
      l10n.missionCompletedTokens(tokens.toString()),
      if (bonus > 0) l10n.missionCompletedStreak(bonus.toString()),
    ];
    _entry = OverlayEntry(
      builder: (_) => _ToastView(
        title: title,
        lines: lines,
        onTap: () {
          _dismiss();
          appNavigatorKey.currentState?.push(
            MaterialPageRoute<void>(builder: (_) => const MissionsScreen()),
          );
        },
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(const Duration(milliseconds: 4200), _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    _entry?.remove();
    _entry = null;
    // 알림이 떠 있는 동안 새로 쌓인 게 있으면 이어서 보여 준다.
    if (mounted) _onGameChanged();
  }

  @override
  void dispose() {
    _game?.removeListener(_onGameChanged);
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
                    color: Cartoon.surface(
                      Cartoon.surface(const Color(0xFFFFF6D8)),
                    ),
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
