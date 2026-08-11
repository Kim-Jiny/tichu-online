import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import 'player_profile_header.dart';
import 'game_type_icon.dart';

/// The pseudo game type that means "all four at once".
///
/// Not a game the server knows about — it only ever reaches [PlayerProfileBody]
/// and the selector — so it is deliberately not a value any payload uses.
const String kProfileAllGamesTab = 'all';

/// How a match ended for the person whose profile this is.
enum _MatchOutcome { win, loss, draw, desertion, midLeave }

/// The player whose profile this is, and whoever was on their side.
///
/// Dark enough to read at 13px on white — a paler sky blue is the colour of a
/// disabled control, which is the opposite of what this marks.
const Color _kMineColor = Color(0xFF0288D1);

/// One game's line in the combined view.
class _GameTally {
  final String key;
  final String label;
  final int games;
  final int wins;
  final int losses;

  const _GameTally({
    required this.key,
    required this.label,
    required this.games,
    required this.wins,
    required this.losses,
  });

  /// Rounded the same way the server rounds each game's own rate, so the
  /// combined figure cannot disagree with the per-game ones by a decimal.
  int get winRate => games == 0 ? 0 : ((wins * 100) / games).round();
}

/// Body of the player-profile popup: manner/desertion, a game selector, that
/// game's season and overall records, and recent matches.
///
/// One implementation for all six popups — lobby, the four game screens and the
/// spectator screen. They had drifted badly: Skull King showed a bare "Lv.N" box
/// where the others showed a level/exp strip, Tichu's body hard-coded Tichu's
/// stats with no way to see another game's, and Love Letter's and Mighty's each
/// had their own subset. The same person's profile looked like a different
/// feature depending on which screen you opened it from.
///
/// This is the lobby's version, which was the only complete one: all four games,
/// recent matches filtered by the selected game, and both the team-based (Tichu)
/// and rank-based (Skull King / Love Letter / Mighty) match layouts.
class PlayerProfileBody extends StatefulWidget {
  final Map<String, dynamic> data;
  final GameService game;

  /// Which game's records to show first. The screen the popup was opened from —
  /// looking someone up mid-game and being shown a different game's record was
  /// the old Tichu-only behaviour in reverse.
  final String initialGame;

  const PlayerProfileBody({
    super.key,
    required this.data,
    required this.game,
    this.initialGame = 'tichu',
  });

  @override
  State<PlayerProfileBody> createState() => _PlayerProfileBodyState();
}

// Stateful, not stateless, for two reasons: the selected game lives here so no
// caller has to thread it through a StatefulBuilder, and the helpers below use
// `context` the way they did as State methods in the lobby — keeping them
// unchanged is what makes this a move rather than a rewrite.
class _PlayerProfileBodyState extends State<PlayerProfileBody> {
  late String _tab = widget.initialGame;

  @override
  Widget build(BuildContext context) => _buildProfileContent(
    widget.data,
    widget.game,
    dialogContext: context,
    selectedTab: _tab,
    onTabChanged: (g) => setState(() => _tab = g),
  );

  Widget _buildProfileContent(
    Map<String, dynamic> data,
    GameService game, {
    required BuildContext dialogContext,
    required String selectedTab,
    required ValueChanged<String> onTabChanged,
  }) {
    final profile = data['profile'] as Map<String, dynamic>?;
    final nickname = data['nickname'] as String? ?? '';

    final l10n = L10n.of(context);
    if (profile == null) {
      return Text(l10n.lobbyProfileNotFound);
    }

    // Privacy pass: the server sends identity and nothing that counts as a
    // record, so there is nothing here to lay out. Say why the numbers are
    // missing — an empty stats panel reads as a bug.
    if (profile['isPrivate'] == true) {
      return _buildPrivateNotice(l10n);
    }

    final totalGames = profile['totalGames'] ?? 0;
    final wins = profile['wins'] ?? 0;
    final losses = profile['losses'] ?? 0;
    final winRate = profile['winRate'] ?? 0;
    final seasonRating = profile['seasonRating'] ?? 1000;
    final seasonGames = profile['seasonGames'] ?? 0;
    final seasonWins = profile['seasonWins'] ?? 0;
    final seasonLosses = profile['seasonLosses'] ?? 0;
    final seasonWinRate = profile['seasonWinRate'] ?? 0;
    final leaveCount = profile['leaveCount'] ?? 0;
    final reportCount = profile['reportCount'] ?? 0;
    final skGames = profile['skTotalGames'] ?? 0;
    final skWins = profile['skWins'] ?? 0;
    final skLosses = profile['skLosses'] ?? 0;
    final skWinRate = profile['skWinRate'] ?? 0;
    final skSeasonRating = profile['skSeasonRating'] ?? 1000;
    final skSeasonGames = profile['skSeasonGames'] ?? 0;
    final skSeasonWins = profile['skSeasonWins'] ?? 0;
    final skSeasonLosses = profile['skSeasonLosses'] ?? 0;
    final skSeasonWinRate = profile['skSeasonWinRate'] ?? 0;
    final llGames = profile['llTotalGames'] ?? 0;
    final llWins = profile['llWins'] ?? 0;
    final llLosses = profile['llLosses'] ?? 0;
    final llWinRate = profile['llWinRate'] ?? 0;
    final recentMatches = data['recentMatches'] as List<dynamic>? ?? [];
    final isAll = selectedTab == kProfileAllGamesTab;
    final filteredMatches = isAll
        ? recentMatches
        : recentMatches.where((m) {
            final gameType = m['gameType']?.toString() ?? 'tichu';
            return gameType == selectedTab;
          }).toList();
    final profileNickname = data['nickname']?.toString() ?? nickname;
    final isMe = profileNickname == game.playerName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMe && profile['hasProfilePrivate'] == true) ...[
          _buildPrivateOwnerPanel(l10n, game),
          const SizedBox(height: 10),
        ],
        _buildMannerLeaveRow(
          // Every game they have played, not Tichu's count. The desertions and
          // reports on the other side of this score are account-wide, so a
          // Mighty regular used to be judged on walk-outs from games that were
          // never counted as played. It also has to agree with the 전체 tab
          // sitting right underneath it.
          totalGames:
              (totalGames as int) +
              (skGames as int) +
              ((profile['mightyTotalGames'] ?? 0) as int) +
              (llGames as int),
          reportCount: reportCount as int,
          leaveCount: leaveCount as int,
        ),
        const SizedBox(height: 10),
        // Game selector button
        Builder(
          builder: (_) {
            // One palette with the room-creation picker: that is where people
            // learn which colour means which game.
            final isAllTab = selectedTab == kProfileAllGamesTab;
            final gameLabel = isAllTab
                ? l10n.profileAllGames
                : gameTypeLabel(l10n, selectedTab);
            final gameBgColor = isAllTab
                ? const Color(0xFF5A4038)
                : gameTypeColor(selectedTab);
            final gameFgColor = isAllTab
                ? Colors.white
                : gameTypeOnColor(selectedTab);
            final gameIcon = isAllTab
                ? Icons.apps_rounded
                : gameTypeIcon(selectedTab);
            return InkWell(
              onTap: () {
                showModalBottomSheet(
                  context: dialogContext,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  builder: (bCtx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          leading: const Icon(
                            Icons.apps_rounded,
                            size: 20,
                            color: Color(0xFF5A4038),
                          ),
                          title: Text(l10n.profileAllGames),
                          trailing: selectedTab == kProfileAllGamesTab
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF5A4038),
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(bCtx);
                            onTabChanged(kProfileAllGamesTab);
                          },
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: Icon(
                            gameTypeIcon('tichu'),
                            size: 20,
                            color: gameTypeColor('tichu'),
                          ),
                          title: Text(l10n.lobbyTichu),
                          trailing: selectedTab == 'tichu'
                              ? Icon(Icons.check, color: gameTypeColor('tichu'))
                              : null,
                          onTap: () {
                            Navigator.pop(bCtx);
                            onTabChanged('tichu');
                          },
                        ),
                        ListTile(
                          leading: Icon(
                            gameTypeIcon('skull_king'),
                            size: 20,
                            color: gameTypeColor('skull_king'),
                          ),
                          title: Text(l10n.lobbySkullKing),
                          trailing: selectedTab == 'skull_king'
                              ? Icon(
                                  Icons.check,
                                  color: gameTypeColor('skull_king'),
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(bCtx);
                            onTabChanged('skull_king');
                          },
                        ),
                        ListTile(
                          leading: Icon(
                            gameTypeIcon('mighty'),
                            size: 20,
                            color: gameTypeColor('mighty'),
                          ),
                          title: Text(l10n.rankingMighty),
                          trailing: selectedTab == 'mighty'
                              ? Icon(
                                  Icons.check,
                                  color: gameTypeColor('mighty'),
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(bCtx);
                            onTabChanged('mighty');
                          },
                        ),
                        ListTile(
                          leading: Icon(
                            gameTypeIcon('love_letter'),
                            size: 20,
                            color: gameTypeColor('love_letter'),
                          ),
                          title: Text(l10n.lobbyLoveLetter),
                          trailing: selectedTab == 'love_letter'
                              ? Icon(
                                  Icons.check,
                                  color: gameTypeColor('love_letter'),
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(bCtx);
                            onTabChanged('love_letter');
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: gameBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(gameIcon, size: 20, color: gameFgColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        gameLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: gameFgColor,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: gameFgColor),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        if (isAll) ...[
          _buildAllGamesCards(l10n, profile),
        ] else if (selectedTab == 'tichu') ...[
          _buildProfileSectionCard(
            title: l10n.lobbyTichuSeasonRanked,
            accent: _cardAccent('tichu'),
            background: _cardTint('tichu'),
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFD54F),
            mainText: '$seasonRating',
            chips: [
              _buildStatChip(
                l10n.lobbyStatRecord,
                l10n.lobbyRecordFormat(
                  seasonGames as int,
                  seasonWins as int,
                  seasonLosses as int,
                ),
              ),
              _buildStatChip(l10n.lobbyStatWinRate, '$seasonWinRate%'),
            ],
          ),
          const SizedBox(height: 10),
          _buildProfileSectionCard(
            title: l10n.lobbyTichuRecord,
            accent: _cardAccent('tichu'),
            background: _cardTint('tichu'),
            icon: Icons.style,
            iconColor: gameTypeColor('tichu'),
            mainText: '',
            chips: [
              _buildStatChip(
                l10n.lobbyStatRecord,
                l10n.lobbyRecordFormat(totalGames, wins, losses),
              ),
              _buildStatChip(l10n.lobbyStatWinRate, '$winRate%'),
            ],
          ),
        ] else if (selectedTab == 'skull_king') ...[
          _buildProfileSectionCard(
            title: l10n.lobbySkullKingSeasonRanked,
            accent: _cardAccent('skull_king'),
            background: _cardTint('skull_king'),
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFD54F),
            mainText: '$skSeasonRating',
            chips: [
              _buildStatChip(
                l10n.lobbyStatRecord,
                l10n.lobbyRecordFormat(
                  skSeasonGames as int,
                  skSeasonWins as int,
                  skSeasonLosses as int,
                ),
              ),
              _buildStatChip(l10n.lobbyStatWinRate, '$skSeasonWinRate%'),
            ],
          ),
          const SizedBox(height: 10),
          _buildProfileSectionCard(
            title: l10n.lobbySkullKingRecord,
            accent: _cardAccent('skull_king'),
            background: _cardTint('skull_king'),
            icon: Icons.anchor,
            iconColor: gameTypeColor('skull_king'),
            mainText: '',
            chips: [
              _buildStatChip(
                l10n.lobbyStatRecord,
                l10n.lobbyRecordFormat(skGames, skWins as int, skLosses as int),
              ),
              _buildStatChip(l10n.lobbyStatWinRate, '$skWinRate%'),
            ],
          ),
        ] else if (selectedTab == 'mighty') ...[
          _buildProfileSectionCard(
            title: l10n.rankingMightySeasonRanked,
            accent: _cardAccent('mighty'),
            background: _cardTint('mighty'),
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFD54F),
            mainText: '${profile['mightySeasonRating'] ?? 1000}',
            chips: [
              _buildStatChip(
                l10n.lobbyStatRecord,
                l10n.lobbyRecordFormat(
                  (profile['mightySeasonGames'] ?? 0) as int,
                  (profile['mightySeasonWins'] ?? 0) as int,
                  (profile['mightySeasonLosses'] ?? 0) as int,
                ),
              ),
              _buildStatChip(
                l10n.lobbyStatWinRate,
                '${profile['mightySeasonWinRate'] ?? 0}%',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildProfileSectionCard(
            title: l10n.rankingMightyRecord,
            accent: _cardAccent('mighty'),
            background: _cardTint('mighty'),
            icon: Icons.military_tech,
            iconColor: gameTypeColor('mighty'),
            mainText: '',
            chips: [
              _buildStatChip(
                l10n.lobbyStatRecord,
                l10n.lobbyRecordFormat(
                  (profile['mightyTotalGames'] ?? 0) as int,
                  (profile['mightyWins'] ?? 0) as int,
                  (profile['mightyLosses'] ?? 0) as int,
                ),
              ),
              _buildStatChip(
                l10n.lobbyStatWinRate,
                '${profile['mightyWinRate'] ?? 0}%',
              ),
            ],
          ),
        ] else ...[
          _buildProfileSectionCard(
            title: l10n.lobbyLoveLetterRecord,
            accent: _cardAccent('love_letter'),
            background: _cardTint('love_letter'),
            icon: Icons.favorite,
            iconColor: gameTypeColor('love_letter'),
            mainText: '',
            chips: [
              _buildStatChip(
                l10n.lobbyStatRecord,
                l10n.lobbyRecordFormat(llGames, llWins as int, llLosses as int),
              ),
              _buildStatChip(l10n.lobbyStatWinRate, '$llWinRate%'),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _buildRecentMatches(filteredMatches, profileNickname, mixed: isAll),
      ],
    );
  }

  /// The combined view: the four games added up, then each one on its own line.
  ///
  /// No season rating here. Each game keeps its own, on its own scale, and an
  /// average of four ratings would be a number that means nothing — the tab is
  /// for "how is this player doing overall", which is the win/loss record.
  Widget _buildAllGamesCards(L10n l10n, Map<String, dynamic> profile) {
    int n(String key) => (profile[key] ?? 0) as int;
    final tallies = <_GameTally>[
      _GameTally(
        key: 'tichu',
        label: l10n.lobbyTichu,
        games: n('totalGames'),
        wins: n('wins'),
        losses: n('losses'),
      ),
      _GameTally(
        key: 'skull_king',
        label: l10n.lobbySkullKing,
        games: n('skTotalGames'),
        wins: n('skWins'),
        losses: n('skLosses'),
      ),
      _GameTally(
        key: 'mighty',
        label: l10n.rankingMighty,
        games: n('mightyTotalGames'),
        wins: n('mightyWins'),
        losses: n('mightyLosses'),
      ),
      _GameTally(
        key: 'love_letter',
        label: l10n.lobbyLoveLetter,
        games: n('llTotalGames'),
        wins: n('llWins'),
        losses: n('llLosses'),
      ),
    ];
    final total = _GameTally(
      key: kProfileAllGamesTab,
      label: l10n.profileAllGames,
      games: tallies.fold(0, (a, t) => a + t.games),
      wins: tallies.fold(0, (a, t) => a + t.wins),
      losses: tallies.fold(0, (a, t) => a + t.losses),
    );

    return Column(
      children: [
        _buildProfileSectionCard(
          title: l10n.gameOverallRecord,
          accent: const Color(0xFF4A3A32),
          background: const Color(0xFFF7F2EF),
          icon: Icons.leaderboard_rounded,
          iconColor: const Color(0xFF8D6E63),
          // The rate is the headline, so it is not repeated as a chip beside
          // the record the way the per-game cards do it.
          mainText: total.games == 0 ? '' : '${total.winRate}%',
          chips: [
            _buildStatChip(
              l10n.lobbyStatRecord,
              l10n.lobbyRecordFormat(total.games, total.wins, total.losses),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0D8D4)),
          ),
          child: Column(
            children: [for (final t in tallies) _buildGameTallyRow(l10n, t)],
          ),
        ),
      ],
    );
  }

  Widget _buildGameTallyRow(L10n l10n, _GameTally t) {
    // A game they have never played is still worth a line: "0전" is the answer
    // to "do they play Skull King", and a missing row is not.
    final faded = t.games == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            gameTypeIcon(t.key),
            size: 18,
            color: faded ? const Color(0xFFBDB3AE) : gameTypeColor(t.key),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 66,
            child: Text(
              t.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: faded
                    ? const Color(0xFFA79E99)
                    : const Color(0xFF5A4038),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              l10n.lobbyRecordFormat(t.games, t.wins, t.losses),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: faded
                    ? const Color(0xFFA79E99)
                    : const Color(0xFF6A5A52),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              faded ? '-' : '${t.winRate}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: faded
                    ? const Color(0xFFA79E99)
                    : const Color(0xFF5A4038),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMannerLeaveRow({
    required int totalGames,
    required int reportCount,
    required int leaveCount,
  }) {
    final l10n = L10n.of(context);
    final manner = _calcMannerScore(totalGames, leaveCount, reportCount);
    final color = _mannerColor(manner);
    final icon = _mannerIcon(manner);
    final compact = MediaQuery.of(context).size.width < 400;
    final boxDeco = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0D8D4)),
    );
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: boxDeco,
            child: compact
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: color, size: 17),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              l10n.rankingMannerScore,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8A8A8A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$manner',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: color, size: 17),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${l10n.rankingMannerScore} $manner',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: boxDeco,
            child: compact
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFE57373),
                            size: 17,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              l10n.gameDesertionLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8A8A8A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$leaveCount',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9A6A6A),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFE57373),
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          l10n.lobbyDesertions(leaveCount),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF9A6A6A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  static int _calcMannerScore(int totalGames, int leaveCount, int reportCount) {
    int score = 1000;
    score -= leaveCount * 5;
    score -= reportCount * 3;
    score += (totalGames ~/ 10) * 5;
    return score.clamp(0, 1000);
  }

  static Color _mannerColor(int score) {
    if (score >= 800) return const Color(0xFF4CAF50);
    if (score >= 500) return const Color(0xFFFF9800);
    return const Color(0xFFE53935);
  }

  static IconData _mannerIcon(int score) {
    if (score >= 800) return Icons.sentiment_very_satisfied;
    if (score >= 500) return Icons.sentiment_neutral;
    return Icons.sentiment_very_dissatisfied;
  }

  /// A game's colour, dark enough to be read as text on its own tint.
  static Color _cardAccent(String gameType) =>
      Color.lerp(gameTypeColor(gameType), Colors.black, 0.45)!;

  /// The same colour as a wash behind the card.
  static Color _cardTint(String gameType) => Color.alphaBlend(
    gameTypeColor(gameType).withValues(alpha: 0.10),
    Colors.white,
  );

  Widget _buildProfileSectionCard({
    required String title,
    required Color accent,
    required Color background,
    required IconData icon,
    required Color iconColor,
    required String mainText,
    required List<Widget> chips,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (mainText.isNotEmpty)
                Text(
                  mainText,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: chips,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A)),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }

  /// How many matches the popup itself lists before "더보기" takes over.
  static const int _recentMatchesShown = 5;

  Widget _buildRecentMatches(
    List<dynamic> recentMatches,
    String profileNickname, {
    required bool mixed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                L10n.of(context).lobbyRecentMatches(_recentMatchesShown),
                style: const TextStyle(fontSize: 13, color: Color(0xFF8A8A8A)),
              ),
              const Spacer(),
              if (recentMatches.length > _recentMatchesShown)
                TextButton(
                  onPressed: () => _showRecentMatchesDialog(
                    recentMatches,
                    profileNickname,
                    mixed: mixed,
                  ),
                  child: Text(L10n.of(context).lobbySeeMore),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (recentMatches.isEmpty)
            Text(
              L10n.of(context).lobbyNoRecentMatches,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9A8E8A)),
            )
          else
            Column(
              children: recentMatches
                  .take(_recentMatchesShown)
                  .map<Widget>(
                    (match) =>
                        _buildMatchRow(match, profileNickname, mixed: mixed),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  /// The whole history behind "더보기".
  ///
  /// The popup's five rows are a glance; this is the list you actually read, so
  /// it gets the width and the height the screen can give it, a tally across
  /// the top, one card per match, and the rest of the history as you scroll.
  void _showRecentMatchesDialog(
    List<dynamic> recentMatches,
    String profileNickname, {
    required bool mixed,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _MatchHistoryDialog(
        nickname: profileNickname,
        gameType: _tab,
        game: widget.game,
        initial: recentMatches,
        mixed: mixed,
        cardBuilder: (match) =>
            _buildMatchCard(match, profileNickname, mixed: mixed),
        tallyBuilder: (l10n, matches) =>
            _buildOutcomeTally(l10n, _tallyOf(matches, profileNickname)),
      ),
    );
  }

  static Map<_MatchOutcome, int> _tallyOf(
    List<dynamic> matches,
    String profileNickname,
  ) {
    final tally = <_MatchOutcome, int>{};
    for (final m in matches) {
      final o = _outcomeOf(m, profileNickname);
      tally[o] = (tally[o] ?? 0) + 1;
    }
    return tally;
  }

  /// The list in one line: how many of each result it holds.
  ///
  /// Only the outcomes that actually occur get a chip. A row of four counters
  /// where three read 0 is noise, and desertions in particular should not be
  /// advertised on a record that has none.
  Widget _buildOutcomeTally(L10n l10n, Map<_MatchOutcome, int> tally) {
    const order = [
      _MatchOutcome.win,
      _MatchOutcome.loss,
      _MatchOutcome.draw,
      _MatchOutcome.desertion,
      _MatchOutcome.midLeave,
    ];
    final present = order.where((o) => (tally[o] ?? 0) > 0).toList();
    if (present.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final o in present) ...[
          Expanded(child: _outcomeTallyChip(l10n, o, tally[o]!)),
          if (o != present.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _outcomeTallyChip(L10n l10n, _MatchOutcome outcome, int count) {
    final color = _outcomeColor(outcome);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              // The fill is the pale version of this; the number needs to hold
              // its own against it.
              color: Color.lerp(color, Colors.black, 0.32),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            _outcomeLabel(l10n, outcome),
            style: const TextStyle(fontSize: 11, color: Color(0xFF8A7C76)),
          ),
        ],
      ),
    );
  }

  /// One match as a card, with the result carried by a stripe down its left
  /// edge as well as by the badge — a page of rows all the same colour is what
  /// made the old list hard to skim.
  Widget _buildMatchCard(
    dynamic match,
    String profileNickname, {
    required bool mixed,
  }) {
    final color = _outcomeColor(_outcomeOf(match, profileNickname));
    return Container(
      // Clipped, or the stripe paints over the rounded corner and the card
      // looks like it has a square notch cut out of its left edge.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE4DF)),
      ),
      // The stripe takes its height from the row rather than carrying a fixed
      // one, so a larger system text size cannot leave it short of the card.
      // IntrinsicHeight and not `stretch`: a list item is handed an unbounded
      // height, which is the one case stretch cannot resolve.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
                child: _buildMatchRow(
                  match,
                  profileNickname,
                  mixed: mixed,
                  padded: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How a match ended, from this profile's side.
  ///
  /// One reading of the payload for everyone who needs it — the badge on a row
  /// and the tally over the list. They used to be two separate readings waiting
  /// to disagree, and "3승 2패" over five rows that showed something else is
  /// the kind of wrong nobody reports.
  static _MatchOutcome _outcomeOf(dynamic match, String profileNickname) {
    // A walk-out from a match that kept running. It has no score and no final
    // roster — the match may not even be over — so it is an event in the
    // history, not a result. Checked before the win/loss cases because those
    // would otherwise label it a plain loss.
    if (match['isMidGameLeave'] == true) return _MatchOutcome.midLeave;
    final deserter = match['deserterNickname']?.toString();
    if (match['isDesertionLoss'] == true ||
        (deserter != null &&
            deserter.isNotEmpty &&
            deserter == profileNickname)) {
      return _MatchOutcome.desertion;
    }
    if (match['isDraw'] == true) return _MatchOutcome.draw;
    return match['won'] == true ? _MatchOutcome.win : _MatchOutcome.loss;
  }

  static Color _outcomeColor(_MatchOutcome outcome) {
    switch (outcome) {
      // Same glyph as a desertion — it IS one — with orange standing in for the
      // difference. The badge is a small circle, so the distinction has to be
      // carried by colour; the word itself is on the detail line.
      case _MatchOutcome.midLeave:
        return const Color(0xFFFF8A65);
      case _MatchOutcome.desertion:
        return const Color(0xFFFFB74D);
      case _MatchOutcome.draw:
        return const Color(0xFFBDBDBD);
      case _MatchOutcome.win:
        return const Color(0xFF81C784);
      case _MatchOutcome.loss:
        return const Color(0xFFE57373);
    }
  }

  /// The glyph inside the round badge on a row. One character, because that is
  /// all a 27px circle holds — a walk-out and a desertion share it and are told
  /// apart by colour.
  static String _outcomeBadge(L10n l10n, _MatchOutcome outcome) {
    switch (outcome) {
      case _MatchOutcome.midLeave:
      case _MatchOutcome.desertion:
        return l10n.lobbyMatchDesertion;
      case _MatchOutcome.draw:
        return l10n.lobbyMatchDraw;
      case _MatchOutcome.win:
        return l10n.lobbyMatchWin;
      case _MatchOutcome.loss:
        return l10n.lobbyMatchLoss;
    }
  }

  /// The word under a tally chip. Here the two kinds of walk-out sit side by
  /// side, so they cannot both be "탈" — two identical counters reading
  /// different numbers is a puzzle, not a summary.
  static String _outcomeLabel(L10n l10n, _MatchOutcome outcome) {
    return outcome == _MatchOutcome.midLeave
        ? l10n.lobbyMatchMidLeave
        : _outcomeBadge(l10n, outcome);
  }

  /// [mixed] — the list spans more than one game, so each row has to say which
  /// one it was. Within a single game's tab that mark would be the same on
  /// every row and only takes width from the names.
  ///
  /// [padded] — the popup's own list separates rows with the row's own bottom
  /// padding. Inside the full-history cards that gap belongs to the card.
  Widget _buildMatchRow(
    dynamic match,
    String profileNickname, {
    bool mixed = false,
    bool padded = true,
  }) {
    final gameType = match['gameType']?.toString() ?? 'tichu';
    final isSK = gameType == 'skull_king';
    final isLL = gameType == 'love_letter';
    final l10n = L10n.of(context);

    final outcome = _outcomeOf(match, profileNickname);
    final isDesertionLoss =
        outcome == _MatchOutcome.desertion || outcome == _MatchOutcome.midLeave;
    final isMidGameLeave = outcome == _MatchOutcome.midLeave;
    final date = _formatShortDate(match['createdAt']);
    final isRanked = match['isRanked'] == true;

    final badgeColor = _outcomeColor(outcome);
    final badgeText = _outcomeBadge(l10n, outcome);

    // Score / player info
    final isMighty = gameType == 'mighty';
    final String scoreText;
    final List<InlineSpan> playerSpans;
    if (isMidGameLeave) {
      // No score exists. The useful detail is which room, and whether they
      // chose to go or ran out the clock three times.
      // No score exists, and the row reads like every other one: who you were
      // playing with. The room name and how it ended said nothing you'd
      // recognise the game by; the names do.
      scoreText = '';
      // Same shape as every other game type: [{nickname: ...}]. The server
      // sends it that way on purpose — clients already shipped read
      // p['nickname'] here, and bare strings would throw on them.
      final players = match['players'] as List<dynamic>? ?? [];
      playerSpans = _nameSpans(
        players
            .map((p) => (p is Map ? p['nickname'] : p)?.toString() ?? '?')
            .toList(),
        profileNickname,
        // A walk-out has no sides: it is simply who was at the table.
        mine: const {},
      );
    } else if (isMighty || isSK || isLL) {
      final players = match['players'] as List<dynamic>? ?? [];
      final myRank = match['myRank'] ?? '-';
      final myScore = match['myScore'] ?? 0;
      scoreText = isDesertionLoss
          ? ''
          : l10n.lobbyRankAndScore(myRank.toString(), myScore as int);
      // Free-for-all: no fixed teams, so only the profile's own name is on
      // "my side".
      playerSpans = _nameSpans(
        players.map((p) => (p['nickname'] ?? '?').toString()).toList(),
        profileNickname,
        mine: const {},
      );
    } else {
      final teamAScore = match['teamAScore'] ?? 0;
      final teamBScore = match['teamBScore'] ?? 0;
      scoreText = '$teamAScore : $teamBScore';
      final a1 = match['playerA1']?.toString() ?? '-';
      final a2 = match['playerA2']?.toString() ?? '-';
      final b1 = match['playerB1']?.toString() ?? '-';
      final b2 = match['playerB2']?.toString() ?? '-';
      // Fixed partnerships, so the partner is coloured too — the point of the
      // colour is "this side was mine", which one name cannot say.
      final onA = a1 == profileNickname || a2 == profileNickname;
      final mine = onA ? {a1, a2} : {b1, b2};
      playerSpans = [
        ..._nameSpans([a1, a2], profileNickname, mine: mine, separator: '·'),
        const TextSpan(text: ' : '),
        ..._nameSpans([b1, b2], profileNickname, mine: mine, separator: '·'),
      ];
    }

    return Padding(
      padding: EdgeInsets.only(bottom: padded ? 6 : 0),
      child: Row(
        children: [
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              badgeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Spelled out, not an icon: four small glyphs all in the
                    // same weight are something you decode, and the name is
                    // shorter to read than the icon is to recognise.
                    if (mixed) ...[
                      Text(
                        gameTypeLabel(l10n, gameType),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: gameTypeColor(gameType),
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A8A8A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (!isLL)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isRanked
                              ? const Color(0xFFFFF3E0)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isRanked
                              ? l10n.lobbyMatchTypeRanked
                              : l10n.lobbyMatchTypeNormal,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isRanked
                                ? const Color(0xFFE65100)
                                : const Color(0xFF9E9E9E),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: playerSpans),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Text(
            scoreText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              // Won or lost, readable without finding the badge first. Draws
              // and walk-outs keep the neutral ink: there is nothing to win.
              color: switch (outcome) {
                _MatchOutcome.win => _kMineColor,
                _MatchOutcome.loss => const Color(0xFFE53935),
                _ => const Color(0xFF5A4038),
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Names for one side of a match row.
  ///
  /// The profile's owner is bold, and everyone on their side — themselves
  /// included — takes the sky blue. Reading a row used to mean finding your own
  /// name in a run of four before the score meant anything.
  List<InlineSpan> _nameSpans(
    List<String> names,
    String profileNickname, {
    required Set<String> mine,
    String separator = ', ',
  }) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < names.length; i++) {
      if (i > 0) spans.add(TextSpan(text: separator));
      final name = names[i];
      final isMe = name == profileNickname;
      spans.add(
        TextSpan(
          text: name,
          style: TextStyle(
            color: isMe || mine.contains(name) ? _kMineColor : null,
            fontWeight: isMe ? FontWeight.w900 : null,
          ),
        ),
      );
    }
    return spans;
  }

  /// What a stranger sees instead of the records.
  Widget _buildPrivateNotice(L10n l10n) => privateProfileNotice(l10n);

  /// The holder's own view of the pass: one switch for how far it reaches.
  ///
  /// No paragraph explaining the pass — that belongs on the shop page, where the
  /// decision to buy is made. Here it is a setting, and a setting needs a label
  /// and a switch; the "?" carries the detail for anyone who wants it.
  Widget _buildPrivateOwnerPanel(L10n l10n, GameService game) {
    // No expiry anywhere in here — the shop and the inventory both show it, and
    // in this row it read as if the SWITCH expired on that date.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F3FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4DCEF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, size: 16, color: Color(0xFF7E57C2)),
          const SizedBox(width: 6),
          Text(
            l10n.profilePrivateHidePhoto,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF5A4038),
            ),
          ),
          // Tap, read, gone — a bubble over the popup instead of two lines of
          // small print sitting under the switch forever.
          Tooltip(
            message: l10n.profilePrivateHidePhotoDesc,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 4),
            preferBelow: false,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 12, color: Colors.white),
            decoration: BoxDecoration(
              color: const Color(0xE6473A55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.help_outline_rounded,
                size: 15,
                color: Color(0xFF9C8FAE),
              ),
            ),
          ),
          const Spacer(),
          Switch(
            value: game.profilePrivateHidePhoto,
            activeThumbColor: const Color(0xFF7E57C2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => game.setProfilePrivateHidePhoto(v),
          ),
        ],
      ),
    );
  }

  String _formatShortDate(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }
}

/// The full match history, a page at a time.
///
/// The profile popup is handed a capped list — twenty per game, so no tab looks
/// wiped — and that list is not a prefix of the history in time order: a Tichu
/// regular's 21st Tichu game can be newer than another mode's 20th. So this
/// shows the popup's rows for an instant, then asks the server for page zero
/// and replaces them. Everything after that appends as you reach the bottom.
class _MatchHistoryDialog extends StatefulWidget {
  final String nickname;

  /// The tab being read, or [kProfileAllGamesTab].
  final String gameType;
  final GameService game;

  /// What the popup already had, shown until the first page lands.
  final List<dynamic> initial;
  final bool mixed;
  final Widget Function(dynamic match) cardBuilder;
  final Widget Function(L10n l10n, List<dynamic> matches) tallyBuilder;

  const _MatchHistoryDialog({
    required this.nickname,
    required this.gameType,
    required this.game,
    required this.initial,
    required this.mixed,
    required this.cardBuilder,
    required this.tallyBuilder,
  });

  @override
  State<_MatchHistoryDialog> createState() => _MatchHistoryDialogState();
}

class _MatchHistoryDialogState extends State<_MatchHistoryDialog> {
  static const int _pageSize = 20;

  /// Start fetching this far from the bottom, so the next page is usually
  /// already there when the last card scrolls into view.
  static const double _prefetchGap = 400;

  final ScrollController _scroll = ScrollController();
  late List<dynamic> _matches = List<dynamic>.from(widget.initial);

  /// How many rows the server has actually given us. Not `_matches.length`
  /// until the first page replaces the popup's capped list.
  int _fromServer = 0;
  bool _loading = false;
  bool _hasMore = true;

  /// A request that never comes back must not wedge the list. The socket can
  /// drop mid-page, and without this `_loading` would stay true forever and
  /// every later scroll would decline to ask again.
  Timer? _requestTimeout;

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_onServiceChanged);
    _scroll.addListener(_onScroll);
    // Page zero replaces the capped list rather than adding to it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _requestTimeout?.cancel();
    widget.game.removeListener(_onServiceChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || !_hasMore) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - _prefetchGap) _load();
  }

  void _load() {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    _requestTimeout?.cancel();
    _requestTimeout = Timer(const Duration(seconds: 8), () {
      if (mounted && _loading) setState(() => _loading = false);
    });
    widget.game.requestMatchHistory(
      widget.nickname,
      gameType: widget.gameType,
      offset: _fromServer,
      limit: _pageSize,
    );
  }

  void _onServiceChanged() {
    if (!mounted || !_loading) return;
    final page = widget.game.lastMatchHistoryPage;
    if (page == null) return;
    // A page for another profile, another tab, or an offset we are no longer
    // waiting on is one that arrived late.
    if (page['nickname'] != widget.nickname ||
        page['gameType'] != widget.gameType ||
        page['offset'] != _fromServer) {
      return;
    }
    _requestTimeout?.cancel();
    final rows = (page['matches'] as List<dynamic>? ?? []);
    setState(() {
      if (_fromServer == 0) {
        _matches = List<dynamic>.from(rows);
      } else {
        _matches.addAll(rows);
      }
      _fromServer += rows.length;
      _hasMore = page['hasMore'] == true && rows.isNotEmpty;
      _loading = false;
    });
    // Consumed, so a rebuild for some unrelated reason cannot replay it.
    widget.game.lastMatchHistoryPage = null;
    // A page that did not fill the viewport leaves nothing to scroll, and the
    // scroll listener would never ask for the next one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasMore || _loading) return;
      if (_scroll.hasClients && _scroll.position.maxScrollExtent <= 0) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final media = MediaQuery.of(context).size;
    final width = math.max(240.0, math.min(media.width - 64, 520.0));
    final height = (media.height * 0.66).clamp(240.0, 620.0);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(8, 0, 14, 10),
      // No card around the title. It sat inside the dialog's own frame — a
      // border drawn just inside a border — the same thing the profile popup's
      // header had before it was taken off.
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(
              color: Color(0xFFF2EBE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history,
              size: 20,
              color: Color(0xFF6A5A52),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.lobbyRecentMatchesTitle,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3E312A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.lobbyRecentMatchesDesc(_matches.length),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF84766E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            widget.tallyBuilder(l10n, _matches),
            const SizedBox(height: 12),
            Expanded(
              child: _matches.isEmpty
                  ? Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : Text(
                              l10n.lobbyNoRecentMatches,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF9A8E8A),
                              ),
                            ),
                    )
                  // No explicit Scrollbar: Material already puts one on desktop
                  // and the web through its ScrollBehavior.
                  : ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.only(right: 2),
                      itemCount: _matches.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        if (index >= _matches.length) return _buildFooter();
                        return widget.cardBuilder(_matches[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  /// The row under the last card while the next page is on its way.
  Widget _buildFooter() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 14),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
