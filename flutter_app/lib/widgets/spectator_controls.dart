import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/ll_game_state.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import 'game_chrome.dart';
import 'cartoon_icons.dart';
import 'mid_game_join.dart';
import 'player_profile_dialog.dart';
import 'profile_avatar.dart';

/// Shared spectator control widgets used across all four game spectator
/// screens (Tichu / Skull King / Love Letter / Mighty) so the top-bar
/// buttons, sound panel, spectator list and score-history dialogs stay
/// visually and behaviourally consistent.

/// A rounded icon action button. Matches the original `_buildTopActionButton`
/// implementation that SK/LL/Mighty each duplicated, and replaces Tichu's
/// bespoke circular buttons so every spectator top bar looks the same.
class SpectatorActionButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final int badgeCount;
  final Color? iconColor;

  const SpectatorActionButton({
    super.key,
    required this.icon,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SpectatorActionSurface(
        icon: icon,
        active: active,
        badgeCount: badgeCount,
        iconColor: iconColor,
      ),
    );
  }
}

/// The visual of a spectator-bar action, without the tap.
///
/// Split out so a menu anchor can look exactly like the buttons beside it —
/// PopupMenuButton wants to own the gesture, and a hand-copied style drifted
/// immediately (a bordered circle next to rounded squares).
class SpectatorActionSurface extends StatelessWidget {
  final IconData icon;
  final bool active;
  final int badgeCount;
  final Color? iconColor;

  const SpectatorActionSurface({
    super.key,
    required this.icon,
    required this.active,
    this.badgeCount = 0,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(9),
          // 불투명 크림 바탕 + 갈색 테두리(그림자 없음). 켜져 있으면 주황.
          decoration: BoxDecoration(
            color: active ? Cartoon.orange : Cartoon.paper,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Cartoon.ink, width: 1.8),
          ),
          child: Icon(icon, size: 21, color: iconColor ?? Cartoon.ink),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Cartoon.red,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Cartoon.inkOn(Cartoon.red),
                  width: 1.5,
                ),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: Cartoon.text(size: 11, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

/// The SFX volume slider panel. Callers wrap this in a `Positioned` so each
/// screen controls its own anchor point. The title adapts to player vs
/// spectator automatically via [GameService.isSpectator].
class SpectatorSoundPanel extends StatelessWidget {
  final GameService game;
  final double width;

  const SpectatorSoundPanel({super.key, required this.game, this.width = 190});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final title = game.isSpectator
        ? l10n.spectatorSoundEffects
        : l10n.gameSoundEffects;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Cartoon.text(size: 15)),
          Slider(
            activeColor: Cartoon.orange,
            inactiveColor: Cartoon.ink.withValues(alpha: 0.15),
            thumbColor: Cartoon.orange,
            value: game.sfxVolume,
            onChanged: (v) => game.setSfxVolume(v),
            onChangeEnd: (v) => game.setSfxVolume(v, persist: true),
            min: 0,
            max: 1,
          ),
        ],
      ),
    );
  }
}

/// Who is watching, and who they are.
///
/// Takes the [GameService] rather than a plain list so a row can open the
/// viewer's profile — the list used to be four near-identical copies across
/// the game screens, each rendering a nickname you could not do anything with.
///
/// Photos come from the room state with the viewer's block/report filter
/// already applied server-side; an initial stands in when someone has no
/// photo or the viewer may not see it.
void showSpectatorListDialog(BuildContext context, GameService game) {
  showDialog(
    context: context,
    builder: (ctx) {
      final l10n = L10n.of(ctx);
      // Consumer, not context.select. select() has to run inside a build, and
      // a dialog builder is not one — reaching for the *calling* context here
      // tripped 'widget is LayoutBuilder || debugDoingBuild' and took the
      // screen down. Consumer gives the subtree its own element to rebuild,
      // which is what keeps the list live while the dialog is open.
      return Consumer<GameService>(
        builder: (ctx, gs, _) {
          final spectators = gs.spectators;
          return AlertDialog(
            backgroundColor: Cartoon.paper,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
              side: BorderSide(color: Cartoon.ink, width: 2.5),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Cartoon.blue,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: Cartoon.inkOn(Cartoon.blue),
                      width: 2,
                    ),
                  ),
                  child: const EyeIcon(width: 26, height: 20),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    spectators.isEmpty
                        ? l10n.spectatorListTitle
                        : '${l10n.spectatorListTitle} ${spectators.length}',
                    overflow: TextOverflow.ellipsis,
                    style: Cartoon.text(size: 22),
                  ),
                ),
              ],
            ),
            content: spectators.isEmpty
                ? SizedBox(
                    width: 260,
                    height: 80,
                    child: Center(
                      child: Text(
                        l10n.spectatorNoSpectators,
                        style: Cartoon.text(
                          size: 16,
                          color: Cartoon.ink.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  )
                : SizedBox(
                    width: 280,
                    // Grows with the list up to five rows, then scrolls — a fixed
                    // 220 left a lot of white space under a single watcher.
                    height: (spectators.length.clamp(1, 5)) * 56.0,
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: spectators.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        thickness: 1.5,
                        color: Cartoon.ink.withValues(alpha: 0.12),
                      ),
                      itemBuilder: (_, i) {
                        final sp = spectators[i];
                        return _SpectatorRow(
                          nickname: (sp['nickname'] ?? '').toString(),
                          photoUrl: (sp['photoUrl'] ?? '').toString(),
                          game: game,
                        );
                      },
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  foregroundColor: Cartoon.ink,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                ),
                child: Text(l10n.spectatorClose, style: Cartoon.text(size: 17)),
              ),
            ],
          );
        },
      );
    },
  );
}

class _SpectatorRow extends StatelessWidget {
  final String nickname;
  final String photoUrl;
  final GameService game;

  const _SpectatorRow({
    required this.nickname,
    required this.photoUrl,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: nickname.isEmpty
          ? null
          // The spectator list only exists inside a match, so the popup opens
          // on that match's game rather than on the combined record.
          : () => showPlayerProfileDialog(
              context,
              nickname,
              game,
              initialGame: game.currentGameType,
            ),
      child: SizedBox(
        height: 55,
        child: Row(
          children: [
            ProfileAvatar(
              photoUrl: photoUrl.isEmpty
                  ? null
                  : game.resolvePhotoUrl(photoUrl),
              size: 36,
              fallback: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Cartoon.yellow,
                  borderRadius: BorderRadius.circular(avatarCornerRadius(36)),
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: Cartoon.inkOn(Cartoon.yellow),
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cartoon.userText(size: 16),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Cartoon.ink),
          ],
        ),
      ),
    );
  }
}

/// 점수 기록 팝업 공통 틀: 카툰 패널 + 제목 줄(아이콘 칩·제목·오른쪽 보조 글자) + 닫기 버튼.
Widget _historyShell(
  BuildContext ctx, {
  required String title,
  required String closeLabel,
  Widget? trailing,
  required List<Widget> children,
}) {
  return Dialog(
    backgroundColor: Cartoon.paper,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
      side: BorderSide(color: Cartoon.ink, width: 2.5),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 560),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Cartoon.yellow,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: Cartoon.inkOn(Cartoon.yellow),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: Cartoon.inkOn(Cartoon.yellow),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Cartoon.text(
                      size: 22,
                      color: Cartoon.inkOn(Cartoon.yellow),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Cartoon.ink,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text(closeLabel, style: Cartoon.text(size: 17)),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _historyRule() => Divider(
  height: 1,
  thickness: 1.5,
  color: Cartoon.ink.withValues(alpha: 0.12),
);

Widget _historyEmpty(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 28),
  child: Text(
    text,
    textAlign: TextAlign.center,
    style: Cartoon.text(size: 16, color: Cartoon.ink.withValues(alpha: 0.78)),
  ),
);

Widget _tichuScoreTotal({
  required String label,
  required int score,
  required Color color,
  required bool leading,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: Cartoon.text(size: 13, color: Cartoon.surface(Colors.white)),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '$score',
        style: Cartoon.text(
          size: leading ? 34 : 28,
          color: leading ? color : Cartoon.ink,
        ),
      ),
    ],
  );
}

/// Tichu round-by-round score history. Used by both the player game screen
/// and the spectator screen. [myTeam] orients which team is shown first/in the
/// "my" colour; pass 'A' for a neutral (spectator) view.
void showTichuScoreHistoryDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> history,
  required int totalA,
  required int totalB,
  String myTeam = 'A',
  int? targetScore,
}) {
  final myTotal = myTeam == 'A' ? totalA : totalB;
  final enemyTotal = myTeam == 'A' ? totalB : totalA;
  final myLabel = myTeam;
  final enemyLabel = myTeam == 'A' ? 'B' : 'A';
  const myColor = Cartoon.blue;
  const enemyColor = Cartoon.red;
  final l10n = L10n.of(context);

  showDialog(
    context: context,
    builder: (ctx) => _historyShell(
      ctx,
      title: l10n.gameScoreHistory,
      closeLabel: l10n.gameClose,
      // The finish line belongs here rather than beside the running
      // score on the board, where it read as "25 / 1000" — a
      // fraction, not a goal.
      trailing: targetScore == null
          ? null
          : Text(
              l10n.spectatorTargetScore(targetScore),
              style: Cartoon.text(
                size: 14,
                color: Cartoon.ink.withValues(alpha: 0.78),
              ),
            ),
      children: [
        Row(
          children: [
            Expanded(
              child: _tichuScoreTotal(
                label: 'TEAM $myLabel',
                score: myTotal,
                color: myColor,
                leading: myTotal >= enemyTotal,
              ),
            ),
            Expanded(
              child: _tichuScoreTotal(
                label: 'TEAM $enemyLabel',
                score: enemyTotal,
                color: enemyColor,
                leading: enemyTotal >= myTotal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (history.isEmpty)
          _historyEmpty(l10n.gameNoCompletedRounds)
        else ...[
          Row(
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: Text(
                  'TEAM $myLabel',
                  textAlign: TextAlign.right,
                  style: Cartoon.text(size: 13, color: myColor),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'TEAM $enemyLabel',
                  textAlign: TextAlign.right,
                  style: Cartoon.text(size: 13, color: enemyColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _historyRule(),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: history.length,
              separatorBuilder: (_, _) => _historyRule(),
              itemBuilder: (_, i) {
                final r = history[i];
                final round = r['round'] ?? i + 1;
                final rawA = r['teamA'] ?? 0;
                final rawB = r['teamB'] ?? 0;
                final rMy = myTeam == 'A' ? rawA : rawB;
                final rEnemy = myTeam == 'A' ? rawB : rawA;
                final myWon = rMy > rEnemy;
                final enemyWon = rEnemy > rMy;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          'R$round',
                          style: Cartoon.text(
                            size: 15,
                            color: Cartoon.ink.withValues(alpha: 0.78),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rMy >= 0 ? '+$rMy' : '$rMy',
                          textAlign: TextAlign.right,
                          style: Cartoon.text(
                            size: 18,
                            color: myWon ? myColor : Cartoon.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          rEnemy >= 0 ? '+$rEnemy' : '$rEnemy',
                          textAlign: TextAlign.right,
                          style: Cartoon.text(
                            size: 18,
                            color: enemyWon ? enemyColor : Cartoon.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    ),
  );
}

/// Love Letter score history: current token standings + round-by-round
/// winners. The "score" in Love Letter is the number of affection tokens,
/// and [roundHistory] records who won each round.
void showLLScoreHistoryDialog(
  BuildContext context, {
  required List<LLRoundHistory> roundHistory,
  required List<LLPlayer> players,
  required int targetTokens,
}) {
  final accent = Cartoon.onSurface(const Color(0xFFE0457B));
  final l10n = L10n.of(context);
  final sorted = [...players]..sort((a, b) => b.tokens.compareTo(a.tokens));
  final topTokens = sorted.isNotEmpty ? sorted.first.tokens : 0;

  showDialog(
    context: context,
    builder: (ctx) => _historyShell(
      ctx,
      title: l10n.gameScoreHistory,
      closeLabel: l10n.gameClose,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_rounded, size: 18, color: accent),
          const SizedBox(width: 3),
          Text('$targetTokens', style: Cartoon.text(size: 17, color: accent)),
        ],
      ),
      children: [
        // Current token standings.
        ...sorted.map((p) {
          final isLeader = topTokens > 0 && p.tokens == topTokens;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Cartoon.userText(size: 16),
                  ),
                ),
                Icon(
                  Icons.favorite_rounded,
                  size: 18,
                  color: isLeader
                      ? accent
                      : Cartoon.ink.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 4),
                Text(
                  '${p.tokens}',
                  style: Cartoon.text(
                    size: 20,
                    color: isLeader ? accent : Cartoon.ink,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 6),
        _historyRule(),
        if (roundHistory.isEmpty)
          _historyEmpty(l10n.gameNoCompletedRounds)
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: roundHistory.length,
              separatorBuilder: (_, _) => _historyRule(),
              itemBuilder: (_, i) {
                final r = roundHistory[i];
                final names = r.winnerNames.isNotEmpty
                    ? r.winnerNames.join(', ')
                    : (r.winnerName ?? '-');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 38,
                        child: Text(
                          'R${r.round}',
                          style: Cartoon.text(
                            size: 15,
                            color: Cartoon.ink.withValues(alpha: 0.78),
                          ),
                        ),
                      ),
                      Icon(Icons.favorite_rounded, size: 16, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          names,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Cartoon.userText(size: 15),
                        ),
                      ),
                      if (r.isShared) ...[
                        const SizedBox(width: 6),
                        Text(
                          l10n.llRoundSharedWinners,
                          style: Cartoon.text(size: 12, color: accent),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );
}

/// The spectator top bar, shaped like the Tichu spectator screen's header:
/// a flat full-width strip (no floating card) with a hairline under it.
///
///   ← [👁 관전 중] 방 이름                     [actions…]
///   status line                                [statusTrailing]
///
/// Each game's spectator view had grown its own header — Skull King a dark
/// navy pill card, Love Letter a plain white strip with no room name and no
/// way to tell you were spectating, Mighty a row of chips — so switching games
/// as a spectator felt like switching apps. The game-specific parts (status
/// text, action buttons, an extra chip on the right) come in as parameters;
/// the frame is fixed.
class SpectatorHeader extends StatelessWidget {
  final GameService game;

  /// One line under the title row: round, phase, whose turn — whatever the
  /// game wants to say. Ellipsized, never wraps.
  final String statusLine;

  /// Action buttons for the right side of the title row. Callers include
  /// their own gaps (`SizedBox(width: 6)`) between them.
  final List<Widget> actions;

  /// Optional chip at the right end of the status line (draw pile, target
  /// score…).
  final Widget? statusTrailing;

  const SpectatorHeader({
    super.key,
    required this.game,
    required this.statusLine,
    this.actions = const [],
    this.statusTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CartoonPressable(
                scale: 0.9,
                // Spectators leave immediately — there is no game state of
                // theirs to protect with a confirm.
                onTap: () => game.leaveRoom(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Cartoon.paper,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Cartoon.ink, width: 1.8),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Cartoon.ink,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  game.currentRoomName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Cartoon.userText(size: 15, weight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 6),
              ...actions,
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // The badge lives on the status line, not the title row: four
              // action buttons plus the badge left the room name a few
              // characters ("러...") on Love Letter.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: gamePillDecoration(radius: 99),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_rounded,
                      size: 14,
                      color: Cartoon.ink,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      L10n.of(context).spectatorWatching,
                      style: Cartoon.text(size: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Cartoon.userText(
                    size: 13,
                    weight: FontWeight.w600,
                    color: Cartoon.ink.withValues(alpha: 0.78),
                  ),
                ),
              ),
              ?statusTrailing,
            ],
          ),
          // On its own line, not squeezed into the status row. The badge, the
          // status text and the score chip already fill that row on a narrow
          // phone; adding a labelled button pushed it past the edge. Mounted
          // here rather than passed in by each screen — all four spectator
          // views share this header, and it hides itself when the room does
          // not allow breaking in.
          if (game.canJoinInProgress) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: MidGameJoinButton(game: game),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small tappable chip for the right end of [SpectatorHeader]'s status line —
/// the same slot Tichu uses for its tap-for-history score chips.
class SpectatorStatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const SpectatorStatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: gamePillDecoration(radius: 99),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Cartoon.ink),
            const SizedBox(width: 4),
            Text(label, style: Cartoon.text(size: 12)),
          ],
        ),
      ),
    );
  }
}
