import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/ll_game_state.dart';
import '../services/game_service.dart';

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

/// Shared spectator-list dialog. [spectators] is the `game.spectators` list of
/// `{id, nickname}` maps.
void showSpectatorListDialog(
  BuildContext context,
  List<Map<String, dynamic>> spectators,
) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.people_alt, color: _kTextPrimary),
          const SizedBox(width: 8),
          Text(L10n.of(context).spectatorListTitle),
        ],
      ),
      content: spectators.isEmpty
          ? SizedBox(
              height: 60,
              child: Center(
                child: Text(
                  L10n.of(context).spectatorNoSpectators,
                  style: const TextStyle(color: Color(0xFF9A8E8A)),
                ),
              ),
            )
          : SizedBox(
              width: 240,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: spectators.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final name = spectators[i]['nickname'] ?? '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '$name',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _kTextPrimary,
                      ),
                    ),
                  );
                },
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(L10n.of(context).spectatorClose),
        ),
      ],
    ),
  );
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
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E0F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.visibility,
                      size: 14,
                      color: Color(0xFF4A4080),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      L10n.of(context).spectatorWatching,
                      style: const TextStyle(
                        fontSize: 12,
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
        ],
      ),
    );
  }
}

