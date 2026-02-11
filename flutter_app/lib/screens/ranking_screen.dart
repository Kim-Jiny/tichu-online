import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import 'lobby_screen.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  int? _selectedSeasonId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final game = context.read<GameService>();
      game.requestSeasons();
      game.requestRankings();
    });
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
                  _buildSeasonSelector(game),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _buildBody(game),
                  ),
                ],
              );
            },
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
        color: Colors.white.withOpacity(0.95),
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
          const Text(
            '랭킹',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => context.read<GameService>().requestRankings(),
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
        color: Colors.white.withOpacity(0.95),
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
                  if (seasons.firstWhere((s) => s['id'] == value)['status'] ==
                      'active') {
                    game.requestRankings();
                  } else {
                    game.requestRankingsForSeason(value);
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
          game.rankingsError!,
          style: const TextStyle(color: Color(0xFFCC6666)),
        ),
      );
    }
    if (game.rankings.isEmpty) {
      return const Center(
        child: Text(
          '랭킹 데이터가 없어요',
          style: TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: game.rankings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = game.rankings[index];
        return _buildRankItem(index + 1, row);
      },
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
          color: banner.gradient == null ? Colors.white.withOpacity(0.95) : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0D8D4)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD9CCC8).withOpacity(0.35),
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
                    '전적 $total전 $wins승 $losses패 · 승률 $winRate%',
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
                const Text(
                  '시즌점수',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9A8E8A)),
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
        color: Colors.white.withOpacity(0.95),
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
        final profile = game.profileData;
        final isLoading = profile == null || profile['nickname'] != widget.nickname;
        if (isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: _ProfileContent(data: profile),
        );
      },
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile == null) {
      return const Center(child: Text('프로필을 찾을 수 없습니다'));
    }

    final nickname = data['nickname'] as String? ?? '';
    final totalGames = profile['totalGames'] ?? 0;
    final wins = profile['wins'] ?? 0;
    final losses = profile['losses'] ?? 0;
    final rating = profile['rating'] ?? 1000;
    final winRate = profile['winRate'] ?? 0;
    final seasonRating = profile['seasonRating'] ?? 1000;
    final seasonGames = profile['seasonGames'] ?? 0;
    final seasonWins = profile['seasonWins'] ?? 0;
    final seasonLosses = profile['seasonLosses'] ?? 0;
    final seasonWinRate = profile['seasonWinRate'] ?? 0;
    final level = profile['level'] ?? 1;
    final expTotal = profile['expTotal'] ?? 0;
    final gold = profile['gold'] ?? 0;
    final leaveCount = profile['leaveCount'] ?? 0;
    final bannerKey = profile['bannerKey']?.toString();
    final recentMatches = data['recentMatches'] as List<dynamic>? ?? [];

    return Column(
      children: [
        _ProfileHeader(
          nickname: nickname,
          level: level,
          expTotal: expTotal,
          bannerKey: bannerKey,
        ),
        const SizedBox(height: 8),
        _ProfileMiniStatRow(gold: gold, leaveCount: leaveCount),
        const SizedBox(height: 10),
        _ProfileSectionCard(
          title: '시즌 랭킹전',
          accent: const Color(0xFF7A6A95),
          background: const Color(0xFFF6F3FA),
          icon: Icons.emoji_events,
          iconColor: const Color(0xFFFFD54F),
          mainText: '$seasonRating',
          chips: [
            _ProfileStatChip('전적', '$seasonGames전 ${seasonWins}승 ${seasonLosses}패'),
            _ProfileStatChip('승률', '$seasonWinRate%'),
          ],
        ),
        const SizedBox(height: 10),
        _ProfileSectionCard(
          title: '전체 전적',
          accent: const Color(0xFF5A4038),
          background: const Color(0xFFF5F5F5),
          icon: Icons.star,
          iconColor: const Color(0xFFFFB74D),
          mainText: '',
          chips: [
            _ProfileStatChip('전적', '$totalGames전 ${wins}승 ${losses}패'),
            _ProfileStatChip('승률', '$winRate%'),
          ],
        ),
        const SizedBox(height: 12),
        _ProfileRecentMatches(recentMatches: recentMatches),
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
        color: banner.gradient == null ? Colors.white.withOpacity(0.95) : null,
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
        border: Border.all(color: background.withOpacity(0.6)),
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
        color: Colors.white.withOpacity(0.9),
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
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '최근 전적 (3)',
                style: TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
              ),
              const Spacer(),
              if (recentMatches.length > 3)
                TextButton(
                  onPressed: () => _showRecentMatchesDialog(context, recentMatches),
                  child: const Text('더보기'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (recentMatches.isEmpty)
            const Text(
              '최근 전적이 없습니다',
              style: TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)),
            )
          else
            Column(
              children: recentMatches.take(3).map<Widget>((match) {
                final won = match['won'] == true;
                final teamAScore = match['teamAScore'] ?? 0;
                final teamBScore = match['teamBScore'] ?? 0;
                final teamA = _formatTeam(match['playerA1'], match['playerA2']);
                final teamB = _formatTeam(match['playerB1'], match['playerB2']);
                final date = _formatShortDate(match['createdAt']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: won ? const Color(0xFF81C784) : const Color(0xFFE57373),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          won ? 'W' : 'L',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              date,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8A8A8A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$teamA : $teamB',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5A4038),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$teamAScore : $teamBScore',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5A4038),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
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
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('최근 전적'),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: ListView.separated(
          itemCount: recentMatches.length,
          separatorBuilder: (_, __) => const Divider(height: 16),
          itemBuilder: (_, index) {
            final match = recentMatches[index];
            final won = match['won'] == true;
            final teamAScore = match['teamAScore'] ?? 0;
            final teamBScore = match['teamBScore'] ?? 0;
            final teamA = _formatTeam(match['playerA1'], match['playerA2']);
            final teamB = _formatTeam(match['playerB1'], match['playerB2']);
            final date = _formatShortDateGlobal(match['createdAt']);
            return Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: won ? const Color(0xFF81C784) : const Color(0xFFE57373),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    won ? 'W' : 'L',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8A8A8A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$teamA : $teamB',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5A4038),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  '$teamAScore : $teamBScore',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('닫기'),
        ),
      ],
    ),
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
  const _ProfileMiniStatRow({required this.gold, required this.leaveCount});

  final int gold;
  final int leaveCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.monetization_on, color: Color(0xFFFFB74D), size: 16),
                const SizedBox(width: 6),
                Text(
                  '$gold 골드',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
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
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE57373), size: 16),
                const SizedBox(width: 6),
                Text(
                  '탈주 $leaveCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9A6A6A),
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
