import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/missions.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import '../utils/mission_text.dart';
import '../widgets/game_type_icon.dart';
import 'token_shop_screen.dart';

const _games = ['tichu', 'mighty', 'skull_king', 'love_letter'];

Color _tierColor(int tier) {
  switch (tier) {
    case 3:
      return const Color(0xFFE5484D);
    case 2:
      return const Color(0xFF3E8EF7);
    default:
      return const Color(0xFF3DBE6A);
  }
}

/// 미션 화면: 연속 달성, 진행 중인 미션, 오늘의 후보(게임별).
/// 판정은 서버가 한다 — 여기서는 받기·포기·새로고침을 요청하고 결과를 보여 줄 뿐이다.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  String _game = 'tichu';
  int _seenActionSeq = 0;

  @override
  void initState() {
    super.initState();
    final game = context.read<GameService>();
    _seenActionSeq = game.missionActionSeq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) game.requestMissions();
    });
  }

  void _showActionError(GameService game) {
    final reason = game.missionActionReason;
    if (reason == null) return;
    final l10n = L10n.of(context);
    final max = game.missionsState?.maxActive ?? 3;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(missionErrorText(l10n, reason, max))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    return Theme(
      data: cartoonTheme(Theme.of(context)),
      child: Scaffold(
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
                if (game.missionActionSeq != _seenActionSeq) {
                  _seenActionSeq = game.missionActionSeq;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showActionError(game);
                  });
                }
                return Column(
                  children: [
                    _topBar(context, game),
                    Expanded(child: _body(context, game)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, GameService game) {
    final l10n = L10n.of(context);
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
                  boxShadow: const [
                    BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Cartoon.ink),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Cartoon.outlinedText(
                  l10n.missionsTitle,
                  size: 28,
                  maxLines: 1,
                ),
              ),
            ),
            TokenBalanceChip(balance: game.tokenBalance),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: l10n.missionsOpenShop,
              child: CartoonPressable(
                scale: 0.9,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TokenShopScreen()),
                ),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Cartoon.orange,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Cartoon.ink, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                    ],
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, GameService game) {
    final l10n = L10n.of(context);
    final st = game.missionsState;
    if (st == null) {
      return Center(
        child: game.missionsLoading
            ? const CircularProgressIndicator(
                color: Cartoon.orange,
                strokeWidth: 4,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.missionsLoadFailed,
                    style: Cartoon.userText(size: 14),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: game.requestMissions,
                    child: Text(l10n.missionsRetry),
                  ),
                ],
              ),
      );
    }
    final offers = st.offers[_game];
    return RefreshIndicator(
      onRefresh: () async {
        game.requestMissions();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
        children: [
          _streakCard(l10n, st),
          const SizedBox(height: 14),
          _sectionTitle(
            l10n.missionsActiveHeader(
              st.activeCount.toString(),
              st.maxActive.toString(),
            ),
          ),
          if (st.active.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                l10n.missionsActiveEmpty,
                textAlign: TextAlign.center,
                style: Cartoon.userText(
                  size: 13,
                  color: Cartoon.ink.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            for (final m in st.active) _activeCard(context, game, st, m),
          const SizedBox(height: 14),
          _sectionTitle(l10n.missionsOffersHeader),
          _gameTabs(l10n),
          const SizedBox(height: 10),
          if (offers != null) ...[
            for (final o in offers.missions) _offerCard(context, game, st, o),
            const SizedBox(height: 4),
            _rerollButton(context, game, offers),
          ],
          const SizedBox(height: 16),
          Text(
            l10n.missionsRules(st.dailyCap.toString()),
            textAlign: TextAlign.center,
            style: Cartoon.userText(
              size: 12,
              color: Cartoon.ink.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(text, style: Cartoon.text(size: 17)),
  );

  Widget _streakCard(L10n l10n, MissionsState st) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: Cartoon.panelDecoration(radius: 20, shadowOffset: 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: Cartoon.orangeDeep,
                size: 22,
              ),
              const SizedBox(width: 4),
              Text(l10n.missionsStreakTitle, style: Cartoon.text(size: 17)),
              const SizedBox(width: 8),
              Text(
                l10n.missionsStreakProgress(
                  st.streak.toString(),
                  st.streakTarget.toString(),
                ),
                style: Cartoon.text(size: 15, color: Cartoon.orangeDeep),
              ),
              const Spacer(),
              if (st.streakDoneToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3DBE6A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Cartoon.ink, width: 1.4),
                  ),
                  child: Text(
                    l10n.missionsStreakToday,
                    style: Cartoon.text(size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < st.streakTarget; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: i < st.streak
                          ? Cartoon.orange
                          : Cartoon.ink.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Cartoon.ink, width: 1.4),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.missionsStreakHint(
              st.streakTarget.toString(),
              st.streakBonus.toString(),
            ),
            style: Cartoon.userText(
              size: 12,
              color: Cartoon.ink.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.missionsTodayEarned(
              st.todayEarned.toString(),
              st.dailyCap.toString(),
            ),
            style: Cartoon.userText(
              size: 12,
              color: Cartoon.ink.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tokenReward(int tokens, {double size = 14}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE9A8),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Cartoon.ink, width: 1.4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TokenCoin(size: size + 4),
        const SizedBox(width: 3),
        Text(
          L10n.of(context).missionsRewardTokens(tokens.toString()),
          style: Cartoon.text(size: size),
        ),
      ],
    ),
  );

  Widget _tierChip(L10n l10n, int tier) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: _tierColor(tier),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      missionTierName(l10n, tier),
      style: Cartoon.text(size: 11.5, color: Colors.white),
    ),
  );

  Widget _activeCard(
    BuildContext context,
    GameService game,
    MissionsState st,
    ActiveMission m,
  ) {
    final l10n = L10n.of(context);
    final ratio = m.target <= 0 ? 0.0 : (m.progress / m.target).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: Cartoon.panelDecoration(
        radius: 18,
        shadowOffset: 2.5,
        color: m.done ? const Color(0xFFE6F8EA) : Cartoon.paper,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              gameTypeSymbol(m.game, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  missionTitle(l10n, m.key),
                  style: Cartoon.userText(size: 14.5),
                ),
              ),
              const SizedBox(width: 6),
              _tokenReward(m.tokens, size: 13),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: Cartoon.ink.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Cartoon.ink, width: 1.4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5.5),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(
                          color: m.done
                              ? const Color(0xFF3DBE6A)
                              : _tierColor(m.tier),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                m.done ? l10n.missionsDone : '${m.progress}/${m.target}',
                style: Cartoon.text(size: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _tierChip(l10n, m.tier),
              const SizedBox(width: 8),
              if (m.expiresDay != null && !m.done)
                Text(
                  l10n.missionsExpiresOn(_shortDate(m.expiresDay!)),
                  style: Cartoon.userText(
                    size: 11.5,
                    color: Cartoon.ink.withValues(alpha: 0.55),
                  ),
                ),
              const Spacer(),
              if (!m.done)
                CartoonPressable(
                  scale: 0.92,
                  onTap: () => game.dropMission(m.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      l10n.missionsDrop,
                      style: Cartoon.text(
                        size: 13,
                        color: Cartoon.ink.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 'YYYY-MM-DD' → 'M/D'.
  String _shortDate(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return '${int.tryParse(p[1]) ?? p[1]}/${int.tryParse(p[2]) ?? p[2]}';
  }

  Widget _gameTabs(L10n l10n) {
    return Row(
      children: [
        for (final (i, g) in _games.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: CartoonPressable(
              onTap: () => setState(() => _game = g),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _game == g ? gameTypeColor(g) : Cartoon.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Cartoon.ink, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Cartoon.ink,
                      offset: Offset(0, _game == g ? 4 : 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    gameTypeSymbol(g, size: 26),
                    const SizedBox(height: 3),
                    Text(
                      missionGameName(l10n, g),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Cartoon.text(
                        size: 12.5,
                        color: _game == g ? Colors.white : Cartoon.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _offerCard(
    BuildContext context,
    GameService game,
    MissionsState st,
    MissionOffer o,
  ) {
    final l10n = L10n.of(context);
    final full = st.activeCount >= st.maxActive;
    final canPick = !o.picked && !full;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 2.5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  missionTitle(l10n, o.key),
                  style: Cartoon.userText(size: 14.5),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _tierChip(l10n, o.tier),
                    const SizedBox(width: 8),
                    _tokenReward(o.tokens, size: 13),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CartoonButton(
            expand: false,
            height: 38,
            radius: 13,
            color: o.picked ? const Color(0xFF9AA5B1) : Cartoon.orange,
            onPressed: canPick ? () => game.pickMission(o.key) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: CartoonButton.label(
                o.picked ? l10n.missionsPicked : l10n.missionsPick,
                size: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rerollButton(
    BuildContext context,
    GameService game,
    GameOffers offers,
  ) {
    final l10n = L10n.of(context);
    final left = offers.rerollsLeft;
    return Align(
      child: CartoonButton(
        expand: false,
        height: 38,
        radius: 13,
        color: left > 0 ? const Color(0xFF4DA3FF) : const Color(0xFF9AA5B1),
        onPressed: left > 0 ? () => game.rerollMissions(_game) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: CartoonButton.label(
            left > 0
                ? l10n.missionsReroll(left.toString())
                : l10n.missionsRerollUsed,
            size: 14,
          ),
        ),
      ),
    );
  }
}

/// 토큰 알약(잔액).
class TokenBalanceChip extends StatelessWidget {
  const TokenBalanceChip({super.key, required this.balance});
  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9A8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Cartoon.ink, width: 2),
        boxShadow: const [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TokenCoin(size: 24),
          const SizedBox(width: 5),
          Text('$balance', style: Cartoon.text(size: 17)),
        ],
      ),
    );
  }
}

/// 미션 토큰 그림 — 별이 박힌 금화.
class TokenCoin extends StatelessWidget {
  const TokenCoin({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFC43B),
        border: Border.all(color: Cartoon.ink, width: size >= 22 ? 1.8 : 1.4),
      ),
      child: Icon(
        Icons.star_rounded,
        size: size * 0.66,
        color: const Color(0xFFFFF4C9),
      ),
    );
  }
}
