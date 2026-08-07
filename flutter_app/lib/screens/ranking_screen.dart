import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../services/ad_service.dart';
import '../widgets/player_profile_dialog.dart';

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
      // AdMob has no web implementation at all, so this can only fail there.
      // Leaving it to fail was working — the load callbacks null the banner
      // out — but it is a plugin exception per screen to get to the same
      // place. Web ads would be AdSense / H5 Games Ads, a separate product.
    _bannerAd = kIsWeb ? null : AdService.createBannerAd(
      AdService.rankingBannerId,
      onAdLoaded: (_) { if (mounted) setState(() => _bannerAdLoaded = true); },
      onAdFailedToLoad: (_, _) { if (mounted) setState(() { _bannerAd = null; _bannerAdLoaded = false; }); },
    );
    _bannerAd?.load();
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
      // On the web the engine has already shrunk its canvas to the visual
      // viewport by the time the keyboard is up, so letting the Scaffold
      // subtract viewInsets on top of that takes the keyboard height off
      // twice and leaves an empty band above the keyboard. Native keeps the
      // default, where the inset is the only thing doing the resizing.
      resizeToAvoidBottomInset: kIsWeb ? false : null,
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
            onPressed: _refreshRankings,
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

  void _refreshRankings() {
    final game = context.read<GameService>();
    if (_rankingGameType == 'skull_king') {
      game.requestSKRankings();
    } else if (_rankingGameType == 'mighty') {
      game.requestMightyRankings();
    } else {
      game.requestRankings();
    }
  }

  // Scrollable wrapper so RefreshIndicator can pull on non-list states too.
  Widget _fillScrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(GameService game) {
    return RefreshIndicator(
      onRefresh: () async {
        _refreshRankings();
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: _buildRankingContent(game),
    );
  }

  Widget _buildRankingContent(GameService game) {
    if (game.rankingsLoading) {
      return _fillScrollable(const CircularProgressIndicator());
    }
    if (game.rankingsError != null) {
      return _fillScrollable(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              localizeServiceMessage(game.rankingsError!, L10n.of(context)),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFCC6666)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _refreshRankings,
              child: Text(L10n.of(context).noticeRetry),
            ),
          ],
        ),
      );
    }
    if (game.rankings.isEmpty) {
      return _fillScrollable(
        Text(
          L10n.of(context).rankingNoData,
          style: const TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
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

    final game = context.read<GameService>();
    final bannerGradient = game.bannerGradient(bannerKey);
    final bannerTextOverride = game.bannerTextColor(bannerKey);
    return InkWell(
      onTap: nickname.isEmpty
          ? null
          // Opens on the same game whose ranking you tapped, so a Skull King
          // row lands on Skull King records rather than Tichu.
          : () => showPlayerProfileDialog(
              context,
              nickname,
              game,
              initialGame: _rankingGameType,
            ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: bannerGradient,
          color: bannerGradient == null ? Colors.white.withValues(alpha: 0.95) : null,
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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: bannerTextOverride ?? const Color(0xFF5A4038),
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
