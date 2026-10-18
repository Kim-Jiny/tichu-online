import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../services/ad_service.dart';
import '../theme/cartoon.dart';
import '../utils/banner_ink.dart';
import '../widgets/game_type_icon.dart';
import '../widgets/host_crown.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/profile_avatar.dart';

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
    _bannerAd = kIsWeb
        ? null
        : AdService.createBannerAd(
            AdService.rankingBannerId,
            onAdLoaded: (_) {
              if (mounted) setState(() => _bannerAdLoaded = true);
            },
            onAdFailedToLoad: (_, _) {
              if (mounted) {
                setState(() {
                  _bannerAd = null;
                  _bannerAdLoaded = false;
                });
              }
            },
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
    return Theme(
      data: cartoonTheme(Theme.of(context)),
      child: Scaffold(
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
            bottom: false,
            child: Consumer<GameService>(
              builder: (context, game, _) {
                return Column(
                  children: [
                    _buildTopBar(context),
                    _buildGameTypeToggle(game),
                    const SizedBox(height: 10),
                    _buildSeasonSelector(game),
                    const SizedBox(height: 8),
                    Expanded(child: _buildBody(game)),
                    // 내 순위는 목록 맨 위 카드로 스크롤과 함께 사라지던 것을 아래에
                    // 붙박이로 — 어디를 보고 있든 내가 몇 등인지 보인다.
                    if (game.myRankData != null) _buildMyRankBar(game),
                    if (_bannerAd != null && _bannerAdLoaded)
                      SizedBox(
                        height: _bannerAd!.size.height.toDouble(),
                        width: _bannerAd!.size.width.toDouble(),
                        child: AdWidget(
                          ad: _bannerAd!,
                          key: ValueKey(_bannerAd!.hashCode),
                        ),
                      ),
                    SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameTypeToggle(GameService game) {
    final l10n = L10n.of(context);
    final tabs = [
      ('tichu', l10n.rankingTichu),
      ('skull_king', l10n.rankingSkullKing),
      ('mighty', l10n.rankingMighty),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          for (final (i, (key, label)) in tabs.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: CartoonPressable(
                onTap: () {
                  setState(() {
                    _rankingGameType = key;
                    _selectedSeasonId = null;
                  });
                  if (key == 'skull_king') {
                    game.requestSKRankings();
                  } else if (key == 'mighty') {
                    game.requestMightyRankings();
                  } else {
                    game.requestRankings();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _rankingGameType == key
                        ? gameTypeColor(key)
                        : Cartoon.paper,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Cartoon.ink, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Cartoon.ink,
                        offset: Offset(0, _rankingGameType == key ? 4 : 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: _rankingGameType == key ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.elasticOut,
                        child: gameTypeSymbol(key, size: 30),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Cartoon.text(
                          size: 14,
                          color: _rankingGameType == key
                              ? Colors.white
                              : Cartoon.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return CartoonEntrance(
      from: const Offset(0, -30),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            CartoonPressable(
              scale: 0.88,
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Cartoon.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Cartoon.ink, width: 2),
                  boxShadow: [
                    BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                  ],
                ),
                child: Icon(Icons.arrow_back_rounded, color: Cartoon.ink),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Cartoon.outlinedText(
                L10n.of(context).rankingTitle,
                size: 28,
                maxLines: 1,
              ),
            ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: Cartoon.paper,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Cartoon.ink, width: 1.6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 20,
                    color: Cartoon.ink,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedSeasonId,
                        isExpanded: true,
                        dropdownColor: Cartoon.paper,
                        borderRadius: BorderRadius.circular(16),
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Cartoon.ink,
                        ),
                        style: Cartoon.userText(size: 15),
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
                          final isActive =
                              seasons.firstWhere(
                                (s) => s['id'] == value,
                              )['status'] ==
                              'active';
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
            ),
          ),
          const SizedBox(width: 8),
          // 새로고침은 시즌 선택 옆 — 이 목록을 새로고침한다는 게 보이는 자리.
          CartoonPressable(
            scale: 0.88,
            onTap: _refreshRankings,
            child: Container(
              width: 44,
              height: 42,
              margin: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                color: Cartoon.paper,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Cartoon.ink, width: 1.6),
              ),
              child: Icon(Icons.refresh_rounded, color: Cartoon.ink),
            ),
          ),
        ],
      ),
    );
  }

  /// 지금 화면에 선택된 시즌 그대로 다시 받는다. 예전엔 무조건 "이번 시즌" 을
  /// 요청해서, 지난 시즌을 보다가 새로고침하면 목록은 이번 시즌 것으로 바뀌는데
  /// 선택 칸은 지난 시즌을 가리켰다 (이번 시즌에 아직 기록이 없으면 빈 목록).
  void _refreshRankings() {
    final game = context.read<GameService>();
    final id = _selectedSeasonId;
    final seasons = game.seasons;
    final isActive =
        id == null ||
        seasons.isEmpty ||
        seasons.any((s) => s['id'] == id && s['status'] == 'active');
    if (_rankingGameType == 'skull_king') {
      isActive ? game.requestSKRankings() : game.requestSKRankingsForSeason(id);
    } else if (_rankingGameType == 'mighty') {
      isActive
          ? game.requestMightyRankings()
          : game.requestMightyRankingsForSeason(id);
    } else {
      isActive ? game.requestRankings() : game.requestRankingsForSeason(id);
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
    final l10n = L10n.of(context);
    if (game.rankingsLoading) {
      return _fillScrollable(
        const CircularProgressIndicator(color: Cartoon.orange, strokeWidth: 4),
      );
    }
    if (game.rankingsError != null) {
      return _fillScrollable(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              localizeServiceMessage(game.rankingsError!, l10n),
              textAlign: TextAlign.center,
              style: Cartoon.userText(
                size: 14,
                color: Cartoon.onSurface(const Color(0xFFCC4444)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _refreshRankings,
              child: Text(l10n.noticeRetry),
            ),
          ],
        ),
      );
    }
    if (game.rankings.isEmpty) {
      return _fillScrollable(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CartoonFloat(
              amplitude: 8,
              child: Image.asset(
                'assets/dragon_head.webp',
                width: 88,
                height: 88,
                color: Colors.white.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.modulate,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.rankingNoData,
              style: Cartoon.userText(
                size: 15,
                color: Cartoon.ink.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      );
    }

    final rows = game.rankings;
    final rest = rows.length > 3
        ? rows.sublist(3)
        : const <Map<String, dynamic>>[];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
      children: [
        _buildPodium(rows.take(3).toList()),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            decoration: Cartoon.panelDecoration(radius: 20, shadowOffset: 2.5),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, row) in rest.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1.5,
                      color: Cartoon.ink.withValues(alpha: 0.1),
                    ),
                  _buildRankItem(i + 4, row),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 1·2·3등 시상대: 가운데가 1등(왕관), 양옆이 2·3등. 막대 높이가 순위를 말한다.
  Widget _buildPodium(List<Map<String, dynamic>> top) {
    final order = <int>[1, 0, 2]; // 화면 왼쪽부터 2등, 1등, 3등
    final heights = {0: 92.0, 1: 66.0, 2: 48.0};
    final colors = {
      0: const Color(0xFFFFD54F),
      1: const Color(0xFFCFD8DC),
      2: const Color(0xFFD9A07A),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
      decoration: Cartoon.panelDecoration(
        color: Cartoon.surface(const Color(0xFFFFF6DD)),
        radius: 22,
        shadowOffset: 2.5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final idx in order)
            Expanded(
              child: idx < top.length
                  ? _podiumSlot(
                      rank: idx + 1,
                      row: top[idx],
                      height: heights[idx]!,
                      color: colors[idx]!,
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _podiumSlot({
    required int rank,
    required Map<String, dynamic> row,
    required double height,
    required Color color,
  }) {
    final nickname = row['nickname']?.toString() ?? '';
    final rating = row['rating'] ?? 0;
    final game = context.read<GameService>();
    return CartoonEntrance(
      key: ValueKey('podium-$rank-$nickname'),
      delay: Duration(
        milliseconds: 120 * (rank == 1 ? 2 : (rank == 2 ? 0 : 1)),
      ),
      from: const Offset(0, 40),
      child: CartoonPressable(
        scale: 0.96,
        onTap: nickname.isEmpty
            ? null
            : () => showPlayerProfileDialog(
                context,
                nickname,
                game,
                initialGame: _rankingGameType,
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rank == 1)
              CartoonFloat(amplitude: 3, child: const HostCrown(size: 38))
            else
              const SizedBox(height: 34),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Cartoon.ink, width: 2),
                boxShadow: [
                  BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: DefaultAvatar(size: rank == 1 ? 62 : 52),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Cartoon.userText(size: 13.5, weight: FontWeight.w900),
            ),
            Text('$rating', style: Cartoon.text(size: 17)),
            const SizedBox(height: 4),
            Container(
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                border: Border.all(color: Cartoon.ink, width: 2),
              ),
              child: Cartoon.outlinedText('$rank', size: 26),
            ),
          ],
        ),
      ),
    );
  }

  /// 아래에 붙박이로 놓이는 내 순위.
  Widget _buildMyRankBar(GameService game) {
    final data = game.myRankData!;
    final rank = game.myRank ?? 0;
    final nickname = data['nickname']?.toString() ?? '';
    final rating = data['rating'] ?? 0;
    final wins = data['wins'] ?? 0;
    final losses = data['losses'] ?? 0;
    final total = data['total_games'] ?? 0;
    final winRate = data['win_rate'] ?? 0;
    return CartoonEntrance(
      from: const Offset(0, 40),
      child: CartoonPressable(
        scale: 0.97,
        onTap: nickname.isEmpty
            ? null
            : () => showPlayerProfileDialog(
                context,
                nickname,
                game,
                initialGame: _rankingGameType,
              ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 6, 14, 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          decoration: Cartoon.panelDecoration(
            color: Cartoon.surface(const Color(0xFFE9E1FF)),
            radius: 20,
            shadowOffset: 2.5,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Cartoon.onSurface(const Color(0xFF7E57C2)),
                  shape: BoxShape.circle,
                  border: Border.all(color: Cartoon.ink, width: 2),
                ),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      '$rank',
                      style: Cartoon.text(size: 18, color: Colors.white),
                    ),
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
                        Flexible(
                          child: Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Cartoon.userText(
                              size: 16,
                              weight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Cartoon.onSurface(const Color(0xFF7E57C2)),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Cartoon.ink, width: 1.4),
                          ),
                          child: const Text(
                            'ME',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      L10n.of(
                        context,
                      ).rankingRecordWithWinRate(total, wins, losses, winRate),
                      style: Cartoon.userText(
                        size: 12,
                        weight: FontWeight.w600,
                        color: Cartoon.ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    L10n.of(context).rankingSeasonScore,
                    style: Cartoon.userText(
                      size: 11,
                      weight: FontWeight.w600,
                      color: Cartoon.ink.withValues(alpha: 0.78),
                    ),
                  ),
                  Text('$rating', style: Cartoon.text(size: 24)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 4등부터의 한 줄. 상자가 아니라 패널 안 구분선 목록의 한 칸이다.
  Widget _buildRankItem(int rank, Map<String, dynamic> row) {
    final nickname = row['nickname']?.toString() ?? '';
    final rating = row['rating'] ?? 0;
    final wins = row['wins'] ?? 0;
    final losses = row['losses'] ?? 0;
    final total = row['total_games'] ?? 0;
    final winRate = row['win_rate'] ?? 0;
    final bannerKey = row['banner_key']?.toString();

    final game = context.read<GameService>();
    final bannerGradient = game.bannerGradient(bannerKey);
    final bannerOverride = game.bannerTextColor(bannerKey);
    // 글자는 읽히기만 하면 된다 — 배너가 어두우면 흰색으로 뒤집는다.
    // 관리자가 그 배너에 색을 지정했으면 그 값이 이긴다.
    final bannerTextOverride = profileBannerInk(bannerGradient, bannerOverride);
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        // 장착한 배너는 그 줄의 배경으로 — 내가 산 걸 남이 알아본다.
        decoration: BoxDecoration(gradient: bannerGradient),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: Cartoon.text(
                  size: 18,
                  color: bannerTextOverride.withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Cartoon.userText(
                      size: 15.5,
                      weight: FontWeight.w900,
                      color: bannerTextOverride,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    L10n.of(
                      context,
                    ).rankingRecordWithWinRate(total, wins, losses, winRate),
                    style: Cartoon.userText(
                      size: 12,
                      weight: FontWeight.w600,
                      color: bannerTextOverride.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$rating',
              style: Cartoon.text(
                size: 20,
                // 순위 숫자의 보라는 뜻이 있는 색이다. 밝은 배너에서는
                // 그대로 두고, 어두운 배너에서만 읽히게 바꾼다.
                color: onBannerAccent(
                  bannerGradient,
                  bannerOverride,
                  light: Cartoon.onSurface(const Color(0xFF4A4080)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
