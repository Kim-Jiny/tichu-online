import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../services/ad_service.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  int? _selectedSeasonId;
  String _rankingGameType = 'tichu';
  BannerAd? _bannerAd;
  bool _bannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _bannerAd = AdService.createBannerAd(
      AdService.rankingBannerId,
      onAdLoaded: (_) { if (mounted) setState(() => _bannerAdLoaded = true); },
      onAdFailedToLoad: (_, _) { if (mounted) setState(() { _bannerAd = null; _bannerAdLoaded = false; }); },
    );
    _bannerAd!.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final game = context.read<GameService>();
      game.requestSeasons();
      game.requestRankings();
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeColors,
          ),
        ),
        child: SafeArea(
          child: Consumer<GameService>(
            builder: (context, game, _) {
              return Column(
                children: [
                  _buildTopBar(context),
                  const SizedBox(height: 6),
                  _buildGameTypeToggle(game),
                  const SizedBox(height: 6),
                  _buildSeasonSelector(game),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _buildBody(game),
                  ),
                  if (_bannerAd != null && _bannerAdLoaded)
                    SizedBox(
                      height: _bannerAd!.size.height.toDouble(),
                      width: _bannerAd!.size.width.toDouble(),
                      child: AdWidget(ad: _bannerAd!, key: ValueKey(_bannerAd!.hashCode)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGameTypeToggle(GameService game) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'tichu', label: Text(L10n.of(context).rankingTichu, overflow: TextOverflow.ellipsis, maxLines: 1)),
            ButtonSegment(value: 'skull_king', label: Text(L10n.of(context).rankingSkullKing, overflow: TextOverflow.ellipsis, maxLines: 1)),
            ButtonSegment(value: 'mighty', label: Text(L10n.of(context).rankingMighty, overflow: TextOverflow.ellipsis, maxLines: 1)),
          ],
          selected: {_rankingGameType},
          onSelectionChanged: (v) {
            setState(() {
              _rankingGameType = v.first;
              _selectedSeasonId = null;
            });
            if (_rankingGameType == 'skull_king') {
              game.requestSKRankings();
            } else if (_rankingGameType == 'mighty') {
              game.requestMightyRankings();
            } else {
              game.requestRankings();
            }
          },
          style: SegmentedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.7),
            selectedBackgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            color: const Color(0xFF8A7A72),
          ),
          const SizedBox(width: 4),
          Text(
            L10n.of(context).rankingTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              final game = context.read<GameService>();
              if (_rankingGameType == 'skull_king') {
                game.requestSKRankings();
              } else if (_rankingGameType == 'mighty') {
                game.requestMightyRankings();
              } else {
                game.requestRankings();
              }
            },
            icon: const Icon(Icons.refresh),
            color: const Color(0xFF8A7A72),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonSelector(GameService game) {
    final seasons = game.seasons;
    if (seasons.isEmpty) {
      return const SizedBox.shrink();
    }
    final active = seasons.firstWhere(
      (s) => s['status'] == 'active',
      orElse: () => seasons.first,
    );
    _selectedSeasonId ??= active['id'] as int;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, size: 16, color: Color(0xFF8A7A72)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedSeasonId,
                isExpanded: true,
                items: seasons.map((s) {
                  final name = s['name']?.toString() ?? '';
                  final id = s['id'] as int;
                  return DropdownMenuItem(
                    value: id,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedSeasonId = value);
                  final isActive = seasons.firstWhere((s) => s['id'] == value)['status'] == 'active';
                  if (_rankingGameType == 'skull_king') {
                    if (isActive) {
                      game.requestSKRankings();
                    } else {
                      game.requestSKRankingsForSeason(value);
                    }
                  } else if (_rankingGameType == 'mighty') {
                    if (isActive) {
                      game.requestMightyRankings();
                    } else {
                      game.requestMightyRankingsForSeason(value);
                    }
                  } else {
                    if (isActive) {
                      game.requestRankings();
                    } else {
                      game.requestRankingsForSeason(value);
                    }
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(GameService game) {
    if (game.rankingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.rankingsError != null) {
      return Center(
        child: Text(
          localizeServiceMessage(game.rankingsError!, L10n.of(context)),
          style: const TextStyle(color: Color(0xFFCC6666)),
        ),
      );
    }
    if (game.rankings.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).rankingNoData,
          style: const TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: game.rankings.length + (game.myRankData != null ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        // First item: my rank card
        if (game.myRankData != null && index == 0) {
          return _buildMyRankCard(game);
        }
        final rankIndex = game.myRankData != null ? index - 1 : index;
        final row = game.rankings[rankIndex];
        return _buildRankItem(rankIndex + 1, row);
      },
    );
  }

  Widget _buildMyRankCard(GameService game) {
    final data = game.myRankData!;
    final rank = game.myRank ?? 0;
    final nickname = data['nickname']?.toString() ?? '';
    final rating = data['rating'] ?? 0;
    final wins = data['wins'] ?? 0;
    final losses = data['losses'] ?? 0;
    final total = data['total_games'] ?? 0;
    final winRate = data['win_rate'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEDE7F6), Color(0xFFF3E5F5)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCE93D8)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF7E57C2),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      nickname,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7E57C2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'ME',
                        style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  L10n.of(context).rankingRecordWithWinRate(total, wins, losses, winRate),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(L10n.of(context).rankingSeasonScore, style: const TextStyle(fontSize: 11, color: Color(0xFF9A8E8A))),
              Text(
                '$rating',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4A4080),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRankItem(int rank, Map<String, dynamic> row) {
    final nickname = row['nickname']?.toString() ?? '';
    final rating = row['rating'] ?? 0;
    final wins = row['wins'] ?? 0;
    final losses = row['losses'] ?? 0;
    final total = row['total_games'] ?? 0;
    final winRate = row['win_rate'] ?? 0;
    final bannerKey = row['banner_key']?.toString();

    final isTop3 = rank <= 3;
    final badgeColor = switch (rank) {
      1 => const Color(0xFFFFD54F),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFC58B6B),
      _ => const Color(0xFFE8E0DC),
    };

    final banner = _bannerStyle(bannerKey);
    return InkWell(
      onTap: nickname.isEmpty
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileViewScreen(nickname: nickname),
                ),
              );
            },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: banner.gradient,
          color: banner.gradient == null ? Colors.white.withValues(alpha: 0.95) : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0D8D4)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD9CCC8).withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isTop3 ? const Color(0xFF5A4038) : const Color(0xFF6A5A52),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A4038),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    L10n.of(context).rankingRecordWithWinRate(total, wins, losses, winRate),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A7A72),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  L10n.of(context).rankingSeasonScore,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9A8E8A)),
                ),
                Text(
                  '$rating',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A4080),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileViewScreen extends StatelessWidget {
  const ProfileViewScreen({super.key, required this.nickname});

  final String nickname;

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeColors,
          ),
        ),
        child: SafeArea(
          child: Consumer<GameService>(
            builder: (context, game, _) {
              return Column(
                children: [
                  _ProfileTopBar(nickname: nickname),
                  Expanded(
                    child: _ProfileBody(nickname: nickname),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({required this.nickname});

  final String nickname;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            color: const Color(0xFF8A7A72),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              nickname,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody({required this.nickname});

  final String nickname;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GameService>().requestProfile(widget.nickname);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameService>(
      builder: (context, game, _) {
        final profile = game.profileFor(widget.nickname);
        final isLoading = profile == null || profile['nickname'] != widget.nickname;
        if (isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: _ProfileContent(data: profile),
        );
      },
    );
  }
}

class _ProfileContent extends StatefulWidget {
  const _ProfileContent({required this.data});

  final Map<String, dynamic> data;

  @override
  State<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<_ProfileContent> {
  String _selectedGame = 'tichu';

  void _showGameSelector() {
    final l10n = L10n.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            ListTile(
              leading: const Text('🃏', style: TextStyle(fontSize: 20)),
              title: Text(l10n.rankingTichu),
              trailing: _selectedGame == 'tichu' ? const Icon(Icons.check, color: Color(0xFF7E57C2)) : null,
              onTap: () { Navigator.pop(ctx); setState(() => _selectedGame = 'tichu'); },
            ),
            ListTile(
              leading: const Text('⚓', style: TextStyle(fontSize: 20)),
              title: Text(l10n.rankingSkullKing),
              trailing: _selectedGame == 'skull_king' ? const Icon(Icons.check, color: Color(0xFF2D2D3D)) : null,
              onTap: () { Navigator.pop(ctx); setState(() => _selectedGame = 'skull_king'); },
            ),
            ListTile(
              leading: const Text('🎯', style: TextStyle(fontSize: 20)),
              title: Text(l10n.rankingMighty),
              trailing: _selectedGame == 'mighty' ? const Icon(Icons.check, color: Color(0xFF2E7D32)) : null,
              onTap: () { Navigator.pop(ctx); setState(() => _selectedGame = 'mighty'); },
            ),
            ListTile(
              leading: const Text('❤️', style: TextStyle(fontSize: 20)),
              title: Text(l10n.lobbyLoveLetter),
              trailing: _selectedGame == 'love_letter' ? const Icon(Icons.check, color: Color(0xFFE91E63)) : null,
              onTap: () { Navigator.pop(ctx); setState(() => _selectedGame = 'love_letter'); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile == null) {
      return Center(child: Text(L10n.of(context).rankingProfileNotFound));
    }

    final l10n = L10n.of(context);
    final nickname = data['nickname'] as String? ?? '';
    final totalGames = profile['totalGames'] ?? 0;
    final wins = profile['wins'] ?? 0;
    final losses = profile['losses'] ?? 0;
    final winRate = profile['winRate'] ?? 0;
    final seasonRating = profile['seasonRating'] ?? 1000;
    final seasonGames = profile['seasonGames'] ?? 0;
    final seasonWins = profile['seasonWins'] ?? 0;
    final seasonLosses = profile['seasonLosses'] ?? 0;
    final seasonWinRate = profile['seasonWinRate'] ?? 0;
    final skTotalGames = profile['skTotalGames'] ?? 0;
    final skWins = profile['skWins'] ?? 0;
    final skLosses = profile['skLosses'] ?? 0;
    final skWinRate = profile['skWinRate'] ?? 0;
    final skSeasonRating = profile['skSeasonRating'] ?? 1000;
    final skSeasonGames = profile['skSeasonGames'] ?? 0;
    final skSeasonWins = profile['skSeasonWins'] ?? 0;
    final skSeasonLosses = profile['skSeasonLosses'] ?? 0;
    final skSeasonWinRate = profile['skSeasonWinRate'] ?? 0;
    final mightyTotalGames = profile['mightyTotalGames'] ?? 0;
    final mightyWins = profile['mightyWins'] ?? 0;
    final mightyLosses = profile['mightyLosses'] ?? 0;
    final mightyWinRate = profile['mightyWinRate'] ?? 0;
    final mightySeasonRating = profile['mightySeasonRating'] ?? 1000;
    final mightySeasonGames = profile['mightySeasonGames'] ?? 0;
    final mightySeasonWins = profile['mightySeasonWins'] ?? 0;
    final mightySeasonLosses = profile['mightySeasonLosses'] ?? 0;
    final mightySeasonWinRate = profile['mightySeasonWinRate'] ?? 0;
    final level = profile['level'] ?? 1;
    final expTotal = profile['expTotal'] ?? 0;
    final leaveCount = profile['leaveCount'] ?? 0;
    final bannerKey = profile['bannerKey']?.toString();
    final recentMatches = data['recentMatches'] as List<dynamic>? ?? [];
    final filteredMatches = recentMatches.where((m) {
      final gameType = m['gameType']?.toString() ?? 'tichu';
      return gameType == _selectedGame;
    }).toList();

    // Game selector button config
    String gameLabel;
    String gameEmoji;
    Color gameBgColor;
    Color gameFgColor;
    switch (_selectedGame) {
      case 'skull_king':
        gameLabel = l10n.rankingSkullKing;
        gameEmoji = '⚓';
        gameBgColor = const Color(0xFF2D2D3D);
        gameFgColor = const Color(0xFFFFD54F);
        break;
      case 'mighty':
        gameLabel = l10n.rankingMighty;
        gameEmoji = '🎯';
        gameBgColor = const Color(0xFF2E7D32);
        gameFgColor = Colors.white;
        break;
      case 'love_letter':
        gameLabel = l10n.lobbyLoveLetter;
        gameEmoji = '❤️';
        gameBgColor = const Color(0xFFE91E63);
        gameFgColor = Colors.white;
        break;
      default:
        gameLabel = l10n.rankingTichu;
        gameEmoji = '🃏';
        gameBgColor = const Color(0xFF7E57C2);
        gameFgColor = Colors.white;
    }

    return Column(
      children: [
        _ProfileHeader(
          nickname: nickname,
          level: level,
          expTotal: expTotal,
          bannerKey: bannerKey,
        ),
        const SizedBox(height: 8),
        _ProfileMiniStatRow(
          leaveCount: leaveCount,
          reportCount: profile['reportCount'] ?? 0,
          totalGames: totalGames + skTotalGames + mightyTotalGames + (profile['llTotalGames'] ?? 0),
        ),
        const SizedBox(height: 10),
        // Game selector button
        InkWell(
          onTap: _showGameSelector,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: gameBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(gameEmoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gameLabel,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: gameFgColor),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: gameFgColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_selectedGame == 'tichu') ...[
          _ProfileSectionCard(
            title: l10n.rankingTichuSeasonRanked,
            accent: const Color(0xFF7A6A95),
            background: const Color(0xFFF6F3FA),
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFD54F),
            mainText: '$seasonRating',
            chips: [
              _ProfileStatChip(l10n.rankingStatRecord, l10n.rankingRecordFormat(seasonGames, seasonWins, seasonLosses)),
              _ProfileStatChip(l10n.rankingStatWinRate, '$seasonWinRate%'),
            ],
          ),
          const SizedBox(height: 10),
          _ProfileSectionCard(
            title: l10n.rankingTichuRecord,
            accent: const Color(0xFF5A4038),
            background: const Color(0xFFF5F5F5),
            icon: Icons.star,
            iconColor: const Color(0xFFFFB74D),
            mainText: '',
            chips: [
              _ProfileStatChip(l10n.rankingStatRecord, l10n.rankingRecordFormat(totalGames, wins, losses)),
              _ProfileStatChip(l10n.rankingStatWinRate, '$winRate%'),
            ],
          ),
        ] else if (_selectedGame == 'skull_king') ...[
          _ProfileSectionCard(
            title: l10n.rankingSkullKingSeasonRanked,
            accent: const Color(0xFF2D2D3D),
            background: const Color(0xFFECEFF6),
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFD54F),
            mainText: '$skSeasonRating',
            chips: [
              _ProfileStatChip(l10n.rankingStatRecord, l10n.rankingRecordFormat(skSeasonGames, skSeasonWins, skSeasonLosses)),
              _ProfileStatChip(l10n.rankingStatWinRate, '$skSeasonWinRate%'),
            ],
          ),
          const SizedBox(height: 10),
          _ProfileSectionCard(
            title: l10n.rankingSkullKingRecord,
            accent: const Color(0xFF3F51B5),
            background: const Color(0xFFF0F0FA),
            icon: Icons.sailing,
            iconColor: const Color(0xFF5C6BC0),
            mainText: '',
            chips: [
              _ProfileStatChip(l10n.rankingStatRecord, l10n.rankingRecordFormat(skTotalGames, skWins, skLosses)),
              _ProfileStatChip(l10n.rankingStatWinRate, '$skWinRate%'),
            ],
          ),
        ] else if (_selectedGame == 'mighty') ...[
          _ProfileSectionCard(
            title: l10n.rankingMightySeasonRanked,
            accent: const Color(0xFF2E7D32),
            background: const Color(0xFFE8F5E9),
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFD54F),
            mainText: '$mightySeasonRating',
            chips: [
              _ProfileStatChip(l10n.rankingStatRecord, l10n.rankingRecordFormat(mightySeasonGames, mightySeasonWins, mightySeasonLosses)),
              _ProfileStatChip(l10n.rankingStatWinRate, '$mightySeasonWinRate%'),
            ],
          ),
          const SizedBox(height: 10),
          _ProfileSectionCard(
            title: l10n.rankingMightyRecord,
            accent: const Color(0xFF1B5E20),
            background: const Color(0xFFF1F8E9),
            icon: Icons.military_tech,
            iconColor: const Color(0xFF4CAF50),
            mainText: '',
            chips: [
              _ProfileStatChip(l10n.rankingStatRecord, l10n.rankingRecordFormat(mightyTotalGames, mightyWins, mightyLosses)),
              _ProfileStatChip(l10n.rankingStatWinRate, '$mightyWinRate%'),
            ],
          ),
        ] else ...[
          Builder(builder: (_) {
            final llTotalGames = profile['llTotalGames'] ?? 0;
            final llWins = profile['llWins'] ?? 0;
            final llLosses = profile['llLosses'] ?? 0;
            final llWinRate = profile['llWinRate'] ?? 0;
            return _ProfileSectionCard(
              title: l10n.rankingLoveLetterRecord,
              accent: const Color(0xFFAD1457),
              background: const Color(0xFFFCE4EC),
              icon: Icons.favorite,
              iconColor: const Color(0xFFE91E63),
              mainText: '',
              chips: [
                _ProfileStatChip(l10n.rankingStatRecord, l10n.rankingRecordFormat(llTotalGames, llWins, llLosses)),
                _ProfileStatChip(l10n.rankingStatWinRate, '$llWinRate%'),
              ],
            );
          }),
        ],
        const SizedBox(height: 12),
        _ProfileRecentMatches(recentMatches: filteredMatches),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.nickname,
    required this.level,
    required this.expTotal,
    required this.bannerKey,
  });

  final String nickname;
  final int level;
  final int expTotal;
  final String? bannerKey;

  @override
  Widget build(BuildContext context) {
    final expInLevel = expTotal % 100;
    final expPercent = expInLevel / 100;
    final banner = _bannerStyle(bannerKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: banner.gradient,
        color: banner.gradient == null ? Colors.white.withValues(alpha: 0.95) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFFE8E0DC),
            child: Text(
              nickname.isNotEmpty ? nickname[0] : '?',
              style: const TextStyle(fontSize: 14, color: Color(0xFF5A4038)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nickname,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Lv.$level',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 70,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: expPercent,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEFE7E3),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF64B5F6)),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$expInLevel/100 EXP',
                style: const TextStyle(fontSize: 9, color: Color(0xFF9A8E8A)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

_BannerStyle _bannerStyle(String? key) {
  switch (key) {
    case 'banner_pastel':
      return const _BannerStyle(
        gradient: LinearGradient(
          colors: [Color(0xFFF6C1C9), Color(0xFFF3E7EA)],
        ),
      );
    case 'banner_blossom':
      return const _BannerStyle(
        gradient: LinearGradient(
          colors: [Color(0xFFF7D6D0), Color(0xFFF3E9E6)],
        ),
      );
    case 'banner_mint':
      return const _BannerStyle(
        gradient: LinearGradient(
          colors: [Color(0xFFCDEBD8), Color(0xFFEFF8F2)],
        ),
      );
    case 'banner_sunset_7d':
      return const _BannerStyle(
        gradient: LinearGradient(
          colors: [Color(0xFFFFC3A0), Color(0xFFFFE5B4)],
        ),
      );
    case 'banner_season_gold':
      return const _BannerStyle(
        gradient: LinearGradient(
          colors: [Color(0xFFFFE082), Color(0xFFFFF3C0)],
        ),
      );
    case 'banner_season_silver':
      return const _BannerStyle(
        gradient: LinearGradient(
          colors: [Color(0xFFCFD8DC), Color(0xFFF1F3F4)],
        ),
      );
    case 'banner_season_bronze':
      return const _BannerStyle(
        gradient: LinearGradient(
          colors: [Color(0xFFD7B59A), Color(0xFFF4E8DC)],
        ),
      );
    default:
      return const _BannerStyle();
  }
}

class _BannerStyle {
  const _BannerStyle({this.gradient});
  final LinearGradient? gradient;
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({
    required this.title,
    required this.accent,
    required this.background,
    required this.icon,
    required this.iconColor,
    required this.mainText,
    required this.chips,
  });

  final String title;
  final Color accent;
  final Color background;
  final IconData icon;
  final Color iconColor;
  final String mainText;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: background.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (mainText.isNotEmpty)
                Text(
                  mainText,
                  style: TextStyle(
                    fontSize: 18,
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
}

class _ProfileStatChip extends StatelessWidget {
  const _ProfileStatChip(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF8A8A8A))),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRecentMatches extends StatelessWidget {
  const _ProfileRecentMatches({required this.recentMatches});

  final List<dynamic> recentMatches;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                L10n.of(context).rankingRecentMatchesHeader,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
              ),
              const Spacer(),
              if (recentMatches.length > 3)
                TextButton(
                  onPressed: () => _showRecentMatchesDialog(context, recentMatches),
                  child: Text(L10n.of(context).rankingSeeMore),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (recentMatches.isEmpty)
            Text(
              L10n.of(context).rankingNoRecentMatches,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)),
            )
          else
            Column(
              children: recentMatches.take(3).map<Widget>((match) {
                return _buildMatchRow(context, match);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildMatchRow(BuildContext context, dynamic match) {
    final l10n = L10n.of(context);
    final gameType = match['gameType']?.toString() ?? 'tichu';
    final isSK = gameType == 'skull_king';
    final isLL = gameType == 'love_letter';
    final isMighty = gameType == 'mighty';
    final isDraw = match['isDraw'] == true;
    final isDesertionLoss = match['isDesertionLoss'] == true;
    final won = match['won'] == true;
    final date = _formatShortDate(match['createdAt']);

    String badge;
    Color badgeColor;
    if (isDesertionLoss) {
      badge = l10n.rankingBadgeDesertion;
      badgeColor = const Color(0xFFFF8A65);
    } else if (isDraw) {
      badge = l10n.rankingBadgeDraw;
      badgeColor = const Color(0xFFBDBDBD);
    } else if (won) {
      badge = 'W';
      badgeColor = const Color(0xFF81C784);
    } else {
      badge = 'L';
      badgeColor = const Color(0xFFE57373);
    }

    String detail;
    String score;
    if (isMighty) {
      final players = (match['players'] as List<dynamic>?)?.map((p) => p['nickname']?.toString() ?? '').join(', ') ?? '';
      detail = players;
      final declarer = match['declarerNickname']?.toString() ?? '?';
      final bid = match['bidPoints'] ?? 0;
      final trump = match['trumpSuit']?.toString() ?? '?';
      score = l10n.rankingMightyMatchDetail(declarer, bid, trump);
    } else if (isSK || isLL) {
      final players = (match['players'] as List<dynamic>?)?.map((p) => p['nickname']?.toString() ?? '').join(', ') ?? '';
      detail = players;
      final rank = match['myRank'] ?? '-';
      final myScore = match['myScore'] ?? 0;
      score = l10n.rankingSkRankScore(rank.toString(), myScore);
    } else {
      final teamA = _formatTeam(match['playerA1'], match['playerA2']);
      final teamB = _formatTeam(match['playerB1'], match['playerB2']);
      detail = '$teamA : $teamB';
      final teamAScore = match['teamAScore'] ?? 0;
      final teamBScore = match['teamBScore'] ?? 0;
      score = '$teamAScore : $teamBScore';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!isLL) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: match['isRanked'] == true
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              match['isRanked'] == true
                  ? l10n.lobbyMatchTypeRanked
                  : l10n.lobbyMatchTypeNormal,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: match['isRanked'] == true
                    ? const Color(0xFFE65100)
                    : const Color(0xFF9E9E9E),
              ),
            ),
          ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A))),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            score,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038)),
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

void _showRecentMatchesDialog(BuildContext context, List<dynamic> recentMatches) {
  final l10n = L10n.of(context);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(l10n.rankingRecentMatchesTitle),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: ListView.separated(
          itemCount: recentMatches.length,
          separatorBuilder: (_, _) => const Divider(height: 16),
          itemBuilder: (_, index) {
            final match = recentMatches[index];
            return _buildMatchRowDialog(l10n, match);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
}

Widget _buildMatchRowDialog(L10n l10n, dynamic match) {
  final gameType = match['gameType']?.toString() ?? 'tichu';
  final isSK = gameType == 'skull_king';
  final isLL = gameType == 'love_letter';
  final isDraw = match['isDraw'] == true;
  final isDesertionLoss = match['isDesertionLoss'] == true;
  final won = match['won'] == true;
  final date = _formatShortDateGlobal(match['createdAt']);

  String badge;
  Color badgeColor;
  if (isDesertionLoss) {
    badge = l10n.rankingBadgeDesertion;
    badgeColor = const Color(0xFFFF8A65);
  } else if (isDraw) {
    badge = l10n.rankingBadgeDraw;
    badgeColor = const Color(0xFFBDBDBD);
  } else if (won) {
    badge = 'W';
    badgeColor = const Color(0xFF81C784);
  } else {
    badge = 'L';
    badgeColor = const Color(0xFFE57373);
  }

  String detail;
  String score;
  if (isSK || isLL) {
    final players = (match['players'] as List<dynamic>?)?.map((p) => p['nickname']?.toString() ?? '').join(', ') ?? '';
    detail = players;
    final rank = match['myRank'] ?? '-';
    final myScore = match['myScore'] ?? 0;
    score = l10n.rankingSkRankScore(rank.toString(), myScore);
  } else {
    final teamA = _formatTeam(match['playerA1'], match['playerA2']);
    final teamB = _formatTeam(match['playerB1'], match['playerB2']);
    detail = '$teamA : $teamB';
    final teamAScore = match['teamAScore'] ?? 0;
    final teamBScore = match['teamBScore'] ?? 0;
    score = '$teamAScore : $teamBScore';
  }

  return Row(
    children: [
      Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
        child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      if (!isLL) ...[
      const SizedBox(width: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: match['isRanked'] == true
              ? const Color(0xFFFFF3E0)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          match['isRanked'] == true
              ? l10n.lobbyMatchTypeRanked
              : l10n.lobbyMatchTypeNormal,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: match['isRanked'] == true
                ? const Color(0xFFE65100)
                : const Color(0xFF9E9E9E),
          ),
        ),
      ),
      ],
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(date, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A))),
            const SizedBox(height: 2),
            Text(detail, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038)), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      Text(score, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
    ],
  );
}

String _formatShortDateGlobal(dynamic value) {
  try {
    final dt = DateTime.parse(value.toString()).toLocal();
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return '-';
  }
}

String _formatTeam(dynamic p1, dynamic p2) {
  final a = p1?.toString() ?? '-';
  final b = p2?.toString() ?? '-';
  return '$a·$b';
}

class _ProfileMiniStatRow extends StatelessWidget {
  const _ProfileMiniStatRow({
    required this.leaveCount,
    required this.reportCount,
    required this.totalGames,
  });

  final int leaveCount;
  final int reportCount;
  final int totalGames;

  static int calcMannerScore(int totalGames, int leaveCount, int reportCount) {
    int score = 1000;
    score -= leaveCount * 5;
    score -= reportCount * 3;
    score += (totalGames ~/ 10) * 5;
    return score.clamp(0, 1000);
  }

  static Color mannerColorFor(int score) {
    if (score >= 800) return const Color(0xFF4CAF50);
    if (score >= 500) return const Color(0xFFFF9800);
    return const Color(0xFFE53935);
  }

  static IconData mannerIconFor(int score) {
    if (score >= 800) return Icons.sentiment_very_satisfied;
    if (score >= 500) return Icons.sentiment_neutral;
    return Icons.sentiment_very_dissatisfied;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final manner = calcMannerScore(totalGames, leaveCount, reportCount);
    final mannerColor = mannerColorFor(manner);
    final mannerIcon = mannerIconFor(manner);

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(mannerIcon, color: mannerColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${l10n.rankingMannerScore} $manner',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: mannerColor,
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
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE57373), size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l10n.rankingDesertions(leaveCount),
                    style: const TextStyle(
                      fontSize: 12,
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
}
