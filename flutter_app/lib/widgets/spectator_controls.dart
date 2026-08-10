import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/ll_game_state.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import 'mid_game_join.dart';
import 'player_profile_dialog.dart';
import 'profile_avatar.dart';

/// Shared spectator control widgets used across all four game spectator
/// screens (Tichu / Skull King / Love Letter / Mighty) so the top-bar
/// buttons, sound panel, spectator list and score-history dialogs stay
/// visually and behaviourally consistent.

const Color _kTextPrimary = Color(0xFF5A4038);
const Color _kTextSubtle = Color(0xFF8A7A72);

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
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: active
                  ? _kTextPrimary.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 19,
              color: active ? Colors.white : (iconColor ?? _kTextPrimary),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
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

  const SpectatorSoundPanel({
    super.key,
    required this.game,
    this.width = 190,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final title =
        game.isSpectator ? l10n.spectatorSoundEffects : l10n.gameSoundEffects;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _kTextPrimary,
            ),
          ),
          Slider(
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
      // Watched, not snapshotted: people arrive and leave while this is open.
      final spectators = context.select<GameService, List<Map<String, dynamic>>>(
        (g) => g.spectators,
      );
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        title: Row(
          children: [
            const Icon(Icons.visibility, size: 20, color: Color(0xFF4A4080)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                spectators.isEmpty
                    ? l10n.spectatorListTitle
                    : '${l10n.spectatorListTitle} ${spectators.length}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: spectators.isEmpty
            ? SizedBox(
                width: 260,
                height: 72,
                child: Center(
                  child: Text(
                    l10n.spectatorNoSpectators,
                    style: const TextStyle(color: Color(0xFF9A8E8A), fontSize: 13),
                  ),
                ),
              )
            : SizedBox(
                width: 280,
                // Grows with the list up to five rows, then scrolls — a fixed
                // 220 left a lot of white space under a single watcher.
                height: (spectators.length.clamp(1, 5)) * 52.0,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: spectators.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
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
            child: Text(l10n.spectatorClose),
          ),
        ],
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
    final initial = nickname.isEmpty ? '?' : nickname.characters.first;
    return Material(
      color: const Color(0xFFF7F5FB),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: nickname.isEmpty
            ? null
            : () => showPlayerProfileDialog(context, nickname, game),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ProfileAvatar(
                photoUrl: photoUrl.isEmpty
                    ? null
                    : game.resolvePhotoUrl(photoUrl),
                size: 30,
                fallback: Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0D8F5),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4A4080),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kTextPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFFB5A9A3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _tichuScoreTotal({
  required String label,
  required int score,
  required Color color,
  required bool leading,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '$score',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: leading ? color : _kTextPrimary,
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
  const myColor = Color(0xFF4A90D9);
  const enemyColor = Color(0xFFD24B4B);

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, size: 20, color: _kTextPrimary),
                  const SizedBox(width: 8),
                  Text(
                    L10n.of(context).gameScoreHistory,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  // The finish line belongs here rather than beside the running
                  // score on the board, where it read as "25 / 1000" — a
                  // fraction, not a goal.
                  if (targetScore != null)
                    Text(
                      L10n.of(context).spectatorTargetScore(targetScore),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kTextSubtle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    L10n.of(context).gameNoCompletedRounds,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: _kTextSubtle),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 36,
                        child: Text(
                          'R',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _kTextSubtle,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'TEAM $myLabel',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: myColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'TEAM $enemyLabel',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: enemyColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 12, thickness: 1, color: Color(0xFFEDE5E0)),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF2EAE5),
                    ),
                    itemBuilder: (_, i) {
                      final r = history[i];
                      final round = r['round'] ?? i + 1;
                      final rawA = r['teamA'] ?? 0;
                      final rawB = r['teamB'] ?? 0;
                      final rMy = myTeam == 'A' ? rawA : rawB;
                      final rEnemy = myTeam == 'A' ? rawB : rawA;
                      final myWon = rMy > rEnemy;
                      final enemyWon = rEnemy > rMy;
                      return Container(
                        color: i.isOdd ? const Color(0xFFF6F8FB) : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 36,
                              child: Text(
                                'R$round',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _kTextSubtle,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                rMy >= 0 ? '+$rMy' : '$rMy',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: myWon ? myColor : _kTextPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                rEnemy >= 0 ? '+$rEnemy' : '$rEnemy',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: enemyWon ? enemyColor : _kTextPrimary,
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
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(L10n.of(context).gameClose),
              ),
            ],
          ),
        ),
      ),
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
  const accent = Color(0xFFD24B7A);
  final l10n = L10n.of(context);
  final sorted = [...players]..sort((a, b) => b.tokens.compareTo(a.tokens));
  final topTokens = sorted.isNotEmpty ? sorted.first.tokens : 0;

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, size: 20, color: _kTextPrimary),
                  const SizedBox(width: 8),
                  Text(
                    l10n.gameScoreHistory,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.favorite, size: 14, color: accent),
                  const SizedBox(width: 3),
                  Text(
                    '$targetTokens',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _kTextPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.favorite,
                        size: 14,
                        color: isLeader ? accent : _kTextSubtle,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${p.tokens}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isLeader ? accent : _kTextPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
              const Divider(height: 12, thickness: 1, color: Color(0xFFEDE5E0)),
              if (roundHistory.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    l10n.gameNoCompletedRounds,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: _kTextSubtle),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: roundHistory.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF2EAE5),
                    ),
                    itemBuilder: (_, i) {
                      final r = roundHistory[i];
                      final names = r.winnerNames.isNotEmpty
                          ? r.winnerNames.join(', ')
                          : (r.winnerName ?? '-');
                      return Container(
                        color: i.isOdd ? const Color(0xFFFBF4F7) : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                'R${r.round}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _kTextSubtle,
                                ),
                              ),
                            ),
                            const Icon(Icons.favorite, size: 13, color: accent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                names,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _kTextPrimary,
                                ),
                              ),
                            ),
                            if (r.isShared) ...[
                              const SizedBox(width: 6),
                              Text(
                                l10n.llRoundSharedWinners,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(l10n.gameClose),
              ),
            ],
          ),
        ),
      ),
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
      decoration: const BoxDecoration(
        color: Color(0xFFFDFBFA),
        border: Border(bottom: BorderSide(color: Color(0xFFEDE4E0))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                // Spectators leave immediately — there is no game state of
                // theirs to protect with a confirm.
                onPressed: () => game.leaveRoom(),
                icon: const Icon(Icons.arrow_back, color: Color(0xFF6A5A52)),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 36, height: 36),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  game.currentRoomName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4E3A34),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ...actions,
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // The badge lives on the status line, not the title row: four
              // action buttons plus the badge left the room name a few
              // characters ("러...") on Love Letter.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E0F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.visibility,
                      size: 12,
                      color: Color(0xFF4A4080),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      L10n.of(context).spectatorWatching,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4A4080),
                      ),
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
                  style: const TextStyle(
                    color: Color(0xFF8A7E78),
                    fontSize: 12,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE6DDD8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: _kTextSubtle),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _kTextSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
