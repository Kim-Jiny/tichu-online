import 'dart:async';
import '../theme/cartoon.dart';
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

  /// 0 전적(요약·게임별 카드), 1 최근 전적. 한 화면에 다 늘어놓지 않고 나눈다.
  int _view = 0;

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
        _buildSummaryStrip(
          l10n,
          profile,
          reportCount: reportCount as int,
          leaveCount: leaveCount as int,
        ),
        const SizedBox(height: 12),
        _buildViewToggle(l10n),
        const SizedBox(height: 10),
        // 게임 선택: 드롭다운 + 하단 시트 대신 한 줄 칩. 한 번에 바로 전환.
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final key in const [
                kProfileAllGamesTab,
                'tichu',
                'mighty',
                'skull_king',
                'love_letter',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 3),
                  child: Builder(
                    builder: (_) {
                      final on = selectedTab == key;
                      final isAllKey = key == kProfileAllGamesTab;
                      final color = isAllKey ? Cartoon.ink : gameTypeColor(key);
                      final label = isAllKey
                          ? l10n.profileAllGames
                          : gameTypeLabel(l10n, key);
                      return CartoonPressable(
                        onTap: () => onTabChanged(key),
                        child: AnimatedScale(
                          scale: on ? 1.05 : 1.0,
                          duration: const Duration(milliseconds: 380),
                          curve: Curves.elasticOut,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: on ? color : Cartoon.paper,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Cartoon.ink,
                                width: 1.6,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Cartoon.ink,
                                  offset: Offset(0, on ? 3 : 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isAllKey)
                                  Icon(
                                    Icons.apps_rounded,
                                    size: 20,
                                    color: on ? Colors.white : Cartoon.ink,
                                  )
                                else
                                  gameTypeSymbol(key, size: 22),
                                const SizedBox(width: 6),
                                Text(
                                  label,
                                  style: Cartoon.text(
                                    size: 14.5,
                                    color: on ? Colors.white : Cartoon.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_view == 1) ...[
          _buildRecentMatches(filteredMatches, profileNickname),
        ] else ...[
          _statsPanel([
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
              _flatDivider(),
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
              _flatDivider(),
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
                    l10n.lobbyRecordFormat(
                      skGames,
                      skWins as int,
                      skLosses as int,
                    ),
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
              _flatDivider(),
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
                    l10n.lobbyRecordFormat(
                      llGames,
                      llWins as int,
                      llLosses as int,
                    ),
                  ),
                  _buildStatChip(l10n.lobbyStatWinRate, '$llWinRate%'),
                ],
              ),
            ],
          ]),
        ],
      ],
    );
  }

  /// 한 게임의 시즌 랭크·전적을 상자 하나 안에 구분선으로 잇는다.
  Widget _statsPanel(List<Widget> kids) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: Cartoon.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Cartoon.ink.withValues(alpha: 0.35),
          width: 1.8,
        ),
      ),
      child: Column(children: kids),
    );
  }

  Widget _flatDivider() => Divider(
    height: 1,
    thickness: 1.5,
    color: Cartoon.ink.withValues(alpha: 0.1),
  );

  /// 맨 위 한눈에: 승률 · 전적 · 매너. 예전엔 매너/탈주 줄이 따로 있고 승률은
  /// 아래 카드 안에 있어서, 이 사람이 어떤 사람인지 알려면 스크롤해야 했다.
  Widget _buildSummaryStrip(
    L10n l10n,
    Map<String, dynamic> profile, {
    required int reportCount,
    required int leaveCount,
  }) {
    int n(String key) => (profile[key] ?? 0) as int;
    final games =
        n('totalGames') +
        n('skTotalGames') +
        n('mightyTotalGames') +
        n('llTotalGames');
    final wins = n('wins') + n('skWins') + n('mightyWins') + n('llWins');
    final losses =
        n('losses') + n('skLosses') + n('mightyLosses') + n('llLosses');
    // 분모는 games 다. _GameTally.winRate 가 같은 규칙을 쓰고(그 주석대로
    // 서버 반올림과 맞추기 위해), 아래 표시 가드도 `games == 0` 이다.
    // wins+losses 로 재면 합계 승률만 게임별 타일과 다른 값이 되고, 승패가
    // 갈리지 않은 판(이탈 등)이 있을 때 둘이 눈에 띄게 어긋난다.
    final winRate = games == 0 ? 0 : (wins * 100 / games).round();
    final manner = _calcMannerScore(games, leaveCount, reportCount);
    final mannerColor = _mannerColor(manner);

    Widget cell({
      required Widget top,
      required String value,
      required String label,
      required String sub,
      Color? valueColor,
    }) {
      // 세 칸 모두 같은 줄 수(아이콘·값·이름·보조)라 높이가 같다.
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            top,
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: Cartoon.text(size: 26, color: valueColor ?? Cartoon.ink),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Cartoon.userText(
                size: 12,
                weight: FontWeight.w800,
                color: Cartoon.ink.withValues(alpha: 0.7),
              ),
            ),
            Text(
              sub.isEmpty ? ' ' : sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Cartoon.userText(
                size: 10.5,
                weight: FontWeight.w500,
                color: Cartoon.ink.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    Widget divider() => Container(
      width: 2,
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Cartoon.ink.withValues(alpha: 0.12),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: Cartoon.panelDecoration(
        color: Colors.white,
        radius: 20,
        shadowOffset: 2,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            cell(
              top: const Icon(
                Icons.emoji_events_rounded,
                size: 22,
                color: Color(0xFFF5B301),
              ),
              value: games == 0 ? '-' : '$winRate%',
              label: l10n.lobbyStatWinRate,
              sub: '',
            ),
            divider(),
            cell(
              top: const Icon(
                Icons.style_rounded,
                size: 22,
                color: Cartoon.blue,
              ),
              value: '$games',
              label: l10n.lobbyStatRecord,
              sub: games == 0 ? '' : '$wins/$losses',
            ),
            divider(),
            cell(
              top: Icon(_mannerIcon(manner), size: 22, color: mannerColor),
              value: '$manner',
              label: l10n.rankingMannerScore,
              sub: l10n.lobbyDesertions(leaveCount),
              valueColor: mannerColor,
            ),
          ],
        ),
      ),
    );
  }

  /// 전적 ↔ 최근 전적 토글.
  Widget _buildViewToggle(L10n l10n) {
    Widget seg(int i, String label, IconData icon) {
      final on = _view == i;
      return Expanded(
        child: CartoonPressable(
          scale: 0.95,
          onTap: () => setState(() => _view = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 38,
            decoration: BoxDecoration(
              color: on ? Cartoon.orange : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on ? Cartoon.ink : Colors.transparent,
                width: 2.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: on ? Colors.white : Cartoon.ink),
                const SizedBox(width: 5),
                on
                    ? Cartoon.outlinedText(label, size: 15)
                    : Text(label, style: Cartoon.text(size: 15)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Cartoon.cream,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Cartoon.ink, width: 1.6),
      ),
      child: Row(
        children: [
          seg(0, l10n.lobbyStatRecord, Icons.bar_chart_rounded),
          const SizedBox(width: 4),
          seg(1, l10n.lobbyRecentMatchesTitle, Icons.history_rounded),
        ],
      ),
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
        _flatDivider(),
        for (final (i, t) in tallies.indexed) ...[
          if (i > 0) _flatDivider(),
          _buildGameTallyRow(l10n, t),
        ],
      ],
    );
  }

  Widget _buildGameTallyRow(L10n l10n, _GameTally t) {
    // A game they have never played is still worth a line: "0전" is the answer
    // to "do they play Skull King", and a missing row is not.
    final faded = t.games == 0;
    final color = gameTypeColor(t.key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Column(
        children: [
          Row(
            children: [
              // 한 번도 안 한 게임은 지우지 않고 흐리게 둔다.
              Opacity(
                opacity: faded ? 0.35 : 1,
                child: gameTypeSymbol(t.key, size: 24),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text(
                  t.label,
                  style: Cartoon.text(
                    size: 14.5,
                    color: faded
                        ? Cartoon.ink.withValues(alpha: 0.4)
                        : Cartoon.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Text(
                  l10n.lobbyRecordFormat(t.games, t.wins, t.losses),
                  textAlign: TextAlign.right,
                  style: Cartoon.userText(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: Cartoon.ink.withValues(alpha: faded ? 0.35 : 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 46,
                child: Text(
                  faded ? '-' : '${t.winRate}%',
                  textAlign: TextAlign.right,
                  style: Cartoon.text(
                    size: 15,
                    color: faded
                        ? Cartoon.ink.withValues(alpha: 0.35)
                        : Cartoon.ink,
                  ),
                ),
              ),
            ],
          ),
          if (!faded) ...[
            const SizedBox(height: 6),
            // 승률 막대: 승률만큼 게임 색이 차오른다.
            Container(
              height: 9,
              decoration: BoxDecoration(
                color: Cartoon.paper,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Cartoon.ink, width: 1.6),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0,
                  end: (t.winRate / 100).clamp(0.0, 1.0).toDouble(),
                ),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(color: color),
                ),
              ),
            ),
          ],
        ],
      ),
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

  /// 시즌 랭크·전적 한 줄. 상자는 없다 — 바깥 [_statsPanel] 안에서 구분선으로 이어진다.
  Widget _buildProfileSectionCard({
    required String title,
    required Color accent,
    required Color background,
    required IconData icon,
    required Color iconColor,
    required String mainText,
    required List<Widget> chips,
  }) {
    // 시즌 레이팅처럼 정수면 0 에서 올라가며 센다.
    final number = int.tryParse(mainText);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: Cartoon.text(size: 15.5))),
              if (mainText.isNotEmpty)
                number != null
                    ? TweenAnimationBuilder<int>(
                        tween: IntTween(begin: 0, end: number),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Text(
                          '$v',
                          style: Cartoon.text(size: 28, color: accent),
                        ),
                      )
                    : Text(
                        mainText,
                        style: Cartoon.text(size: 28, color: accent),
                      ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 14, runSpacing: 4, children: chips),
          ),
        ],
      ),
    );
  }

  /// "전적 12전 7승 5패" 처럼 이름과 값을 한 줄 글자로. 칩 상자는 두르지 않는다.
  Widget _buildStatChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Cartoon.userText(
            size: 12.5,
            weight: FontWeight.w600,
            color: Cartoon.ink.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(width: 6),
        Text(value, style: Cartoon.text(size: 15)),
      ],
    );
  }

  /// How many matches the popup itself lists before "더보기" takes over.
  static const int _recentMatchesShown = 5;

  Widget _buildRecentMatches(
    List<dynamic> recentMatches,
    String profileNickname,
  ) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                L10n.of(context).lobbyRecentMatches(_recentMatchesShown),
                style: Cartoon.text(size: 15.5),
              ),
              const Spacer(),
              if (recentMatches.length > _recentMatchesShown)
                TextButton(
                  onPressed: () =>
                      _showRecentMatchesDialog(recentMatches, profileNickname),
                  child: Text(L10n.of(context).lobbySeeMore),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (recentMatches.isEmpty)
            Text(
              L10n.of(context).lobbyNoRecentMatches,
              style: TextStyle(
                fontSize: 13,
                color: Cartoon.onSurface(const Color(0xFF9A8E8A)),
              ),
            )
          else
            Column(
              children: [
                for (final (i, match)
                    in recentMatches.take(_recentMatchesShown).indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1.5,
                      color: Cartoon.ink.withValues(alpha: 0.1),
                    ),
                  _buildMatchRow(match, profileNickname),
                ],
              ],
            ),
        ],
      ),
    );
  }

  /// The whole history behind "더보기".
  ///
  /// The popup's five rows are a glance; this is the list you actually read, so
  /// it gets the width and the height the screen can give it, one card per
  /// match, and the rest of the history as you scroll.
  void _showRecentMatchesDialog(
    List<dynamic> recentMatches,
    String profileNickname,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _MatchHistoryDialog(
        nickname: profileNickname,
        gameType: _tab,
        game: widget.game,
        initial: recentMatches,
        cardBuilder: (match) => _buildMatchCard(match, profileNickname),
      ),
    );
  }

  /// One match as a card, tinted by how it went.
  ///
  /// The result used to be a 4px stripe down the left edge — a mark you had to
  /// look for. The whole card carries it now, so a page of history sorts itself
  /// into wins and losses before you read a word of it. Kept pale: the outcome
  /// pill inside is the same colour further up, and it has to stay legible
  /// against this.
  Widget _buildMatchCard(dynamic match, String profileNickname) {
    final outcome = _outcomeOf(match, profileNickname);
    // 카드 상자 대신 한 줄: 왼쪽 가는 막대가 결과 색을 알려 주고, 줄 사이는 호출한
    // 목록이 구분선으로 나눈다. 경기마다 상자를 두르면 한 쪽 가득 상자뿐이라 번잡했다.
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: _outcomeColor(outcome), width: 5),
        ),
      ),
      child: _buildMatchRow(match, profileNickname, padded: false),
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

  /// What happened, in a word.
  ///
  /// Single glyphs ("승", "탈") were what fitted in the round badge the rows
  /// used to open with. That badge is now the game's symbol, so the result has
  /// the space to say itself — and the two kinds of walk-out stop sharing one
  /// character.
  static String _outcomeLabel(L10n l10n, _MatchOutcome outcome) {
    switch (outcome) {
      case _MatchOutcome.midLeave:
        return l10n.profileOutcomeMidLeave;
      case _MatchOutcome.desertion:
        return l10n.profileOutcomeDesertion;
      case _MatchOutcome.draw:
        return l10n.profileOutcomeDraw;
      case _MatchOutcome.win:
        return l10n.profileOutcomeWin;
      case _MatchOutcome.loss:
        return l10n.profileOutcomeLoss;
    }
  }

  /// The outcome colour, dark enough to be read as text on its own tint.
  ///
  /// 0.5 towards black is what it takes: the pale ones (the grey of a draw, the
  /// amber of a desertion) sat at 3.6:1 against their own pill at 0.38, under
  /// the 4.5:1 that 12px text needs. This clears 4.8:1 for all five.
  static Color _outcomeInk(_MatchOutcome outcome) =>
      Color.lerp(_outcomeColor(outcome), Colors.black, 0.5)!;

  /// The outcome colour washed towards white. Two strengths are in use: a pale
  /// one for a whole card, a stronger one for the pill sitting on it.
  static Color _outcomeTint(_MatchOutcome outcome, double amount) =>
      Color.alphaBlend(
        _outcomeColor(outcome).withValues(alpha: amount),
        Colors.white,
      );

  /// One match.
  ///
  /// The symbol says which game, the word says how it went, and neither has to
  /// do the other's job: the row used to open with a coloured circle holding a
  /// single character, and spell the game out beside the date only when the
  /// list happened to be mixed.
  ///
  /// [padded] — the popup's own list separates rows with the row's own bottom
  /// padding. Inside the full-history cards that gap belongs to the card.
  Widget _buildMatchRow(
    dynamic match,
    String profileNickname, {
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
          gameTypeSymbol(gameType, size: 28),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // A filled pill, not coloured text. Pale green words on
                    // white were the least readable thing in the row, and the
                    // one thing every reader looks for first.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _outcomeTint(outcome, 0.42),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        _outcomeLabel(l10n, outcome),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _outcomeInk(outcome),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: 12,
                        color: Cartoon.onSurface(const Color(0xFF8A8A8A)),
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
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Cartoon.onSurface(const Color(0xFF5A4038)),
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
        color: Cartoon.surface(const Color(0xFFF6F3FA)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4DCEF)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_rounded,
            size: 16,
            color: Cartoon.onSurface(const Color(0xFF7E57C2)),
          ),
          const SizedBox(width: 6),
          Text(
            l10n.profilePrivateHidePhoto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Cartoon.onSurface(const Color(0xFF5A4038)),
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
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.help_outline_rounded,
                size: 15,
                color: Cartoon.onSurface(const Color(0xFF9C8FAE)),
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
  final Widget Function(dynamic match) cardBuilder;

  const _MatchHistoryDialog({
    required this.nickname,
    required this.gameType,
    required this.game,
    required this.initial,
    required this.cardBuilder,
  });

  @override
  State<_MatchHistoryDialog> createState() => _MatchHistoryDialogState();
}

class _MatchHistoryDialogState extends State<_MatchHistoryDialog> {
  static const int _pageSize = 50;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfUnfilled());
  }

  /// 화면이 안 찼으면 다음 쪽을 가져온다.
  ///
  /// `_scroll.hasClients` 를 전제로 두면 안 된다. 걸러서 한 줄도 안 남으면
  /// 목록 대신 가운데 스피너가 그려지므로 ScrollController 에 붙은 것이
  /// 없고, 그러면 "스크롤 높이가 0 인가"를 물어볼 수조차 없다. 그 상태는
  /// 화면이 안 찼다는 뜻이 확실하므로 바로 더 가져와야 한다 — 전에는
  /// 여기서 빠져나가, 첫 쪽에 승리가 하나도 없는 사람이 승 필터를 누르면
  /// 영원히 도는 스피너를 보게 됐다.
  void _prefetchIfUnfilled() {
    if (!mounted || !_hasMore || _loading) return;
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) _load();
  }

  /// 0 전체, 1 승리, 2 패배 — 지금까지 불러온 줄에만 적용된다.
  int _filter = 0;

  bool _passes(dynamic m) {
    if (_filter == 0) return true;
    final o = _PlayerProfileBodyState._outcomeOf(m, widget.nickname);
    if (_filter == 1) return o == _MatchOutcome.win;
    return o == _MatchOutcome.loss || o == _MatchOutcome.desertion;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final media = MediaQuery.of(context).size;
    final width = math.max(240.0, math.min(media.width - 32, 540.0));
    final height = (media.height * 0.78).clamp(320.0, 700.0);
    final shown = _matches.where(_passes).toList();

    Widget filterChip(int i, String label, Color color) {
      final on = _filter == i;
      return CartoonPressable(
        onTap: () {
          setState(() => _filter = i);
          // 걸러서 화면이 안 차면 다음 쪽을 더 가져온다.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _prefetchIfUnfilled(),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: on ? color : Cartoon.paper,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Cartoon.ink, width: 1.6),
            boxShadow: [
              BoxShadow(color: Cartoon.ink, offset: Offset(0, on ? 3 : 2)),
            ],
          ),
          child: Text(
            label,
            style: Cartoon.text(
              size: 14.5,
              color: on ? Colors.white : Cartoon.ink,
            ),
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Cartoon.cream,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Cartoon.ink, width: 2),
                      boxShadow: [
                        BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Icon(
                      Icons.history_rounded,
                      size: 26,
                      color: Cartoon.ink,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 제목 밑에 개수는 두지 않는다 — 스크롤하며 쪽이 붙을수록 올라가서
                  // 숫자 자체를 못 믿게 보인다.
                  Expanded(
                    child: Text(
                      l10n.profileMatchHistoryTitle,
                      style: Cartoon.text(size: 22),
                    ),
                  ),
                  CartoonPressable(
                    scale: 0.88,
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Cartoon.paper,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: Cartoon.ink, width: 2),
                        boxShadow: [
                          BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Icon(Icons.close_rounded, color: Cartoon.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                spacing: 8,
                children: [
                  filterChip(0, l10n.profileAllGames, Cartoon.ink),
                  filterChip(1, l10n.profileOutcomeWin, Cartoon.green),
                  filterChip(2, l10n.profileOutcomeLoss, Cartoon.red),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: _loading || _hasMore
                            ? const CircularProgressIndicator(
                                color: Cartoon.orange,
                                strokeWidth: 4,
                              )
                            : Text(
                                l10n.lobbyNoRecentMatches,
                                style: Cartoon.userText(
                                  size: 14,
                                  color: Cartoon.ink.withValues(alpha: 0.6),
                                ),
                              ),
                      )
                    : ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.only(right: 2, bottom: 6),
                        itemCount: shown.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          thickness: 1.5,
                          color: Cartoon.ink.withValues(alpha: 0.1),
                        ),
                        itemBuilder: (_, index) {
                          if (index >= shown.length) return _buildFooter();
                          return CartoonEntrance(
                            key: ValueKey('mh-${shown[index].hashCode}'),
                            delay: Duration(milliseconds: 30 * (index % 8)),
                            from: const Offset(0, 12),
                            pop: false,
                            child: widget.cardBuilder(shown[index]),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The row under the last card while the next page is on its way.
  Widget _buildFooter() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 14),
    child: Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 3, color: Cartoon.orange),
      ),
    ),
  );
}
