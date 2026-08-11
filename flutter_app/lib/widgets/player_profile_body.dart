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

/// One game's line in the combined view.
class _GameTally {
  final String key;
  final String label;
  final Color color;
  final int games;
  final int wins;
  final int losses;

  const _GameTally({
    required this.key,
    required this.label,
    required this.color,
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
            String gameLabel;
            Color gameBgColor;
            Color gameFgColor;
            IconData gameIcon = gameTypeIcon(selectedTab);
            switch (selectedTab) {
              case kProfileAllGamesTab:
                gameLabel = l10n.profileAllGames;
                gameBgColor = const Color(0xFF5A4038);
                gameFgColor = Colors.white;
                gameIcon = Icons.apps_rounded;
                break;
              case 'skull_king':
                gameLabel = l10n.lobbySkullKing;
                gameBgColor = const Color(0xFF2D2D3D);
                gameFgColor = const Color(0xFFFFD54F);
                break;
              case 'mighty':
                gameLabel = l10n.rankingMighty;
                gameBgColor = const Color(0xFF2E7D32);
                gameFgColor = Colors.white;
                break;
              case 'love_letter':
                gameLabel = l10n.lobbyLoveLetter;
                gameBgColor = const Color(0xFFE91E63);
                gameFgColor = Colors.white;
                break;
              default:
                gameLabel = l10n.lobbyTichu;
                gameBgColor = const Color(0xFF7E57C2);
                gameFgColor = Colors.white;
            }
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
                            color: const Color(0xFF7E57C2),
                          ),
                          title: Text(l10n.lobbyTichu),
                          trailing: selectedTab == 'tichu'
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF7E57C2),
                                )
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
                            color: const Color(0xFF2D2D3D),
                          ),
                          title: Text(l10n.lobbySkullKing),
                          trailing: selectedTab == 'skull_king'
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF2D2D3D),
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
                            color: const Color(0xFF2E7D32),
                          ),
                          title: Text(l10n.rankingMighty),
                          trailing: selectedTab == 'mighty'
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF2E7D32),
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
                            color: const Color(0xFFE91E63),
                          ),
                          title: Text(l10n.lobbyLoveLetter),
                          trailing: selectedTab == 'love_letter'
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFFE91E63),
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
            accent: const Color(0xFF3A3058),
            background: const Color(0xFFF6F4FA),
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
            accent: const Color(0xFF3A3058),
            background: const Color(0xFFF6F4FA),
            icon: Icons.style,
            iconColor: const Color(0xFF6C63FF),
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
            accent: const Color(0xFF2D2D3D),
            background: const Color(0xFFECEFF6),
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
            accent: const Color(0xFF2D2D3D),
            background: const Color(0xFFECEFF6),
            icon: Icons.anchor,
            iconColor: const Color(0xFF2D2D3D),
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
            accent: const Color(0xFF2E7D32),
            background: const Color(0xFFE8F5E9),
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
            accent: const Color(0xFF1B5E20),
            background: const Color(0xFFF1F8E9),
            icon: Icons.military_tech,
            iconColor: const Color(0xFF4CAF50),
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
            accent: const Color(0xFFAD1457),
            background: const Color(0xFFFCE4EC),
            icon: Icons.favorite,
            iconColor: const Color(0xFFE91E63),
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
        color: const Color(0xFF7E57C2),
        games: n('totalGames'),
        wins: n('wins'),
        losses: n('losses'),
      ),
      _GameTally(
        key: 'skull_king',
        label: l10n.lobbySkullKing,
        color: const Color(0xFF2D2D3D),
        games: n('skTotalGames'),
        wins: n('skWins'),
        losses: n('skLosses'),
      ),
      _GameTally(
        key: 'mighty',
        label: l10n.rankingMighty,
        color: const Color(0xFF2E7D32),
        games: n('mightyTotalGames'),
        wins: n('mightyWins'),
        losses: n('mightyLosses'),
      ),
      _GameTally(
        key: 'love_letter',
        label: l10n.lobbyLoveLetter,
        color: const Color(0xFFE91E63),
        games: n('llTotalGames'),
        wins: n('llWins'),
        losses: n('llLosses'),
      ),
    ];
    final total = _GameTally(
      key: kProfileAllGamesTab,
      label: l10n.profileAllGames,
      color: const Color(0xFF5A4038),
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
            children: [
              for (final t in tallies) _buildGameTallyRow(l10n, t),
            ],
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
            color: faded ? const Color(0xFFBDB3AE) : t.color,
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

  /// The colour each game is known by across the popup — selector, tally rows
  /// and the mark on a mixed match list all have to agree.
  static Color _gameTypeColor(String gameType) {
    switch (gameType) {
      case 'skull_king':
        return const Color(0xFF2D2D3D);
      case 'mighty':
        return const Color(0xFF2E7D32);
      case 'love_letter':
        return const Color(0xFFE91E63);
      default:
        return const Color(0xFF7E57C2);
    }
  }

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

  void _showRecentMatchesDialog(
    List<dynamic> recentMatches,
    String profileNickname, {
    required bool mixed,
  }) {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        final media = MediaQuery.of(ctx).size;
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          title: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8DDD8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history, color: Color(0xFF6A5A52)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.lobbyRecentMatchesTitle,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3E312A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.lobbyRecentMatchesDesc(recentMatches.length),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF84766E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: media.width > 700 ? 520 : media.width - 40,
            height: media.height * 0.5,
            child: ListView.separated(
              itemCount: recentMatches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                return _buildMatchRow(
                  recentMatches[index],
                  profileNickname,
                  mixed: mixed,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonClose),
            ),
          ],
        );
      },
    );
  }

  /// [mixed] — the list spans more than one game, so each row has to say which
  /// one it was. Within a single game's tab that mark would be the same on
  /// every row and only takes width from the names.
  Widget _buildMatchRow(
    dynamic match,
    String profileNickname, {
    bool mixed = false,
  }) {
    final gameType = match['gameType']?.toString() ?? 'tichu';
    final isSK = gameType == 'skull_king';
    final isLL = gameType == 'love_letter';
    final l10n = L10n.of(context);

    final deserterNickname = match['deserterNickname']?.toString();
    final isDesertionLoss =
        match['isDesertionLoss'] == true ||
        (deserterNickname != null &&
            deserterNickname.isNotEmpty &&
            deserterNickname == profileNickname);
    final isDraw = match['isDraw'] == true;
    final won = !isDraw && match['won'] == true;
    final date = _formatShortDate(match['createdAt']);
    final isRanked = match['isRanked'] == true;

    // A walk-out from a match that kept running. It has no score and no final
    // roster — the match may not even be over — so it is an event in the
    // history, not a result. Checked before the win/loss badges because those
    // would otherwise label it a plain loss.
    final isMidGameLeave = match['isMidGameLeave'] == true;

    final Color badgeColor;
    final String badgeText;
    if (isMidGameLeave) {
      // Same single glyph as a desertion — it IS one — with orange standing in
      // for the difference. The badge is a 24px circle, so the distinction has
      // to be carried by colour; the word itself is on the detail line.
      badgeColor = const Color(0xFFFF8A65);
      badgeText = l10n.lobbyMatchDesertion;
    } else if (isDesertionLoss) {
      badgeColor = const Color(0xFFFFB74D);
      badgeText = l10n.lobbyMatchDesertion;
    } else if (isDraw) {
      badgeColor = const Color(0xFFBDBDBD);
      badgeText = l10n.lobbyMatchDraw;
    } else if (won) {
      badgeColor = const Color(0xFF81C784);
      badgeText = l10n.lobbyMatchWin;
    } else {
      badgeColor = const Color(0xFFE57373);
      badgeText = l10n.lobbyMatchLoss;
    }

    // Score / player info
    final isMighty = gameType == 'mighty';
    final String scoreText;
    final String playerText;
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
      playerText = players
          .map((p) => (p is Map ? p['nickname'] : p)?.toString() ?? '?')
          .join(', ');
    } else if (isMighty || isSK || isLL) {
      final players = match['players'] as List<dynamic>? ?? [];
      final myRank = match['myRank'] ?? '-';
      final myScore = match['myScore'] ?? 0;
      scoreText = isDesertionLoss
          ? ''
          : l10n.lobbyRankAndScore(myRank.toString(), myScore as int);
      playerText = players.map((p) => p['nickname'] ?? '?').join(', ');
    } else {
      final teamAScore = match['teamAScore'] ?? 0;
      final teamBScore = match['teamBScore'] ?? 0;
      scoreText = '$teamAScore : $teamBScore';
      final teamA = _formatTeam(match['playerA1'], match['playerA2']);
      final teamB = _formatTeam(match['playerB1'], match['playerB2']);
      playerText = '$teamA : $teamB';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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
                    if (mixed) ...[
                      Icon(
                        gameTypeIcon(gameType),
                        size: 14,
                        color: _gameTypeColor(gameType),
                      ),
                      const SizedBox(width: 5),
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
                Text(
                  playerText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            scoreText,
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

  String _formatTeam(dynamic p1, dynamic p2) {
    final a = p1?.toString() ?? '-';
    final b = p2?.toString() ?? '-';
    return '$a·$b';
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
