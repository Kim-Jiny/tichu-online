import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import '../utils/gold_format.dart';
import 'gold_icon.dart';

// 골드 내역 + "골드 얻는 법" 팝업. 상점과 로비 둘 다 골드를 누르면 같은 팝업이 뜬다.

/// 팝업 머리: 금화 칩 · 제목(+부제) · 닫기. 골드 내역과 골드 안내가 같이 쓴다.
Widget _goldDialogHeader(
  BuildContext dialogContext, {
  required String title,
  String? subtitle,
}) {
  return Row(
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Cartoon.cream,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Cartoon.ink, width: 2),
          boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
        ),
        child: const Center(child: GoldIcon(size: 28)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Cartoon.text(size: 22)),
            if (subtitle != null) ...[
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: Cartoon.text(
                  size: 15,
                  color: Cartoon.ink.withValues(alpha: 0.78),
                ),
              ),
            ],
          ],
        ),
      ),
      CartoonPressable(
        scale: 0.88,
        onTap: () => Navigator.pop(dialogContext),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Cartoon.paper,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Cartoon.ink, width: 2),
            boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
          ),
          child: Icon(Icons.close_rounded, color: Cartoon.ink),
        ),
      ),
    ],
  );
}

/// 골드 내역 + 얻는 법을 한 팝업의 두 탭으로. (예전엔 내역 팝업 위에 안내 팝업이
/// 한 겹 더 쌓였다.) [earnTab] 이 true 면 "얻는 법" 탭으로 바로 연다.
void showGoldHistoryDialog(
  BuildContext context,
  GameService game, {
  bool earnTab = false,
}) {
  game.requestGoldHistory();
  game.requestWallet(); // 보유 골드도 최신으로
  showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: _GoldDialogBody(
            dialogContext: dialogContext,
            initialTab: earnTab ? 1 : 0,
          ),
        ),
      ),
    ),
  );
}

class _GoldDialogBody extends StatefulWidget {
  const _GoldDialogBody({
    required this.dialogContext,
    required this.initialTab,
  });

  final BuildContext dialogContext;
  final int initialTab;

  @override
  State<_GoldDialogBody> createState() => _GoldDialogBodyState();
}

class _GoldDialogBodyState extends State<_GoldDialogBody> {
  late int _tab = widget.initialTab;
  // 0 전체, 1 획득, 2 사용
  int _filter = 0;

  static int _delta(Map<String, dynamic> e) =>
      (e['goldDelta'] as num?)?.toInt() ?? 0;

  /// 오늘 / 어제 / 날짜. 로컬 날짜 기준.
  String _dayLabel(L10n l10n, dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    // 날짜 차이는 달력으로 센다. 로컬 자정끼리 difference().inDays 를 쓰면
    // 서머타임 전환일에 틀어진다 — 봄에 하루가 23시간이 되는 날은 어제와의
    // 간격이 0 일로 내려가 "어제"가 "오늘"로 표시된다(독일어 사용자).
    // UTC 로 날짜만 세우면 그 하루가 언제나 24시간이다.
    final today = DateTime.utc(now.year, now.month, now.day);
    final day = DateTime.utc(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return l10n.goldDateToday;
    if (diff == 1) return l10n.goldDateYesterday;
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameService>();
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _goldDialogHeader(
          widget.dialogContext,
          title: l10n.shopGoldHistory,
          subtitle: game.walletLoaded ? l10n.shopGoldCurrent(game.gold) : '…',
        ),
        const SizedBox(height: 14),
        _tabToggle(l10n),
        const SizedBox(height: 12),
        Expanded(child: _tab == 0 ? _historyTab(game, l10n) : _earnTab(l10n)),
      ],
    );
  }

  Widget _tabToggle(L10n l10n) {
    Widget seg(int i, String label, IconData icon) {
      final on = _tab == i;
      return Expanded(
        child: CartoonPressable(
          scale: 0.95,
          onTap: () => setState(() => _tab = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 42,
            decoration: BoxDecoration(
              color: on ? Cartoon.orange : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: on ? Cartoon.ink : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: on ? Colors.white : Cartoon.ink),
                const SizedBox(width: 6),
                on
                    ? Cartoon.outlinedText(label, size: 17)
                    : Text(label, style: Cartoon.text(size: 17)),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Cartoon.ink, width: 2),
      ),
      child: Row(
        children: [
          seg(0, l10n.goldTabHistory, Icons.receipt_long_rounded),
          const SizedBox(width: 4),
          seg(1, l10n.goldTabEarn, Icons.lightbulb_rounded),
        ],
      ),
    );
  }

  // ───────────────────────── 내역 탭 ─────────────────────────

  Widget _historyTab(GameService game, L10n l10n) {
    Widget status(String text, {bool sleepy = false}) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sleepy)
            CartoonFloat(
              amplitude: 6,
              child: Image.asset(
                'assets/dragon_head.webp',
                width: 72,
                height: 72,
                color: Colors.white.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.modulate,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Cartoon.userText(
              size: 15,
              color: Cartoon.ink.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );

    if (game.goldHistoryLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Cartoon.orange, strokeWidth: 4),
      );
    }
    if (game.goldHistoryError != null) {
      return status(localizeServiceMessage(game.goldHistoryError!, l10n));
    }
    final all = game.goldHistory;
    if (all.isEmpty) return status(l10n.shopGoldHistoryEmpty, sleepy: true);

    var gain = 0;
    var spend = 0;
    for (final e in all) {
      final d = _delta(e);
      if (d >= 0) {
        gain += d;
      } else {
        spend += -d;
      }
    }
    final shown = all.where((e) {
      final d = _delta(e);
      return _filter == 0 || (_filter == 1 ? d >= 0 : d < 0);
    }).toList();

    // 날짜 머리글을 끼워 넣은 한 줄 목록.
    final rows = <Object>[];
    String? lastDay;
    for (final e in shown) {
      final day = _dayLabel(l10n, e['createdAt']);
      if (day != lastDay) {
        rows.add(day);
        lastDay = day;
      }
      rows.add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _statChip(
                label: l10n.goldFilterGain,
                value: '+${formatGold(gain)}',
                color: Cartoon.onSurface(const Color(0xFF2E9E4F)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statChip(
                label: l10n.goldFilterSpend,
                value: '-${formatGold(spend)}',
                color: Cartoon.onSurface(const Color(0xFFE5791A)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.goldSummaryRecent(all.length),
          style: Cartoon.userText(
            size: 11.5,
            weight: FontWeight.w500,
            color: Cartoon.ink.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final (i, label) in [
              l10n.goldFilterAll,
              l10n.goldFilterGain,
              l10n.goldFilterSpend,
            ].indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              _filterChip(label, i),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: shown.isEmpty
              ? status(l10n.shopGoldHistoryEmpty, sleepy: true)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 6),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
                        child: Text(row, style: Cartoon.text(size: 15)),
                      );
                    }
                    return CartoonEntrance(
                      key: ValueKey('gh-${row.hashCode}'),
                      delay: Duration(milliseconds: 30 * i.clamp(0, 8)),
                      from: const Offset(0, 12),
                      pop: false,
                      child: _historyCard(
                        context,
                        l10n,
                        row as Map<String, dynamic>,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _statChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Cartoon.ink, width: 1.6),
      ),
      child: Row(
        children: [
          Text(label, style: Cartoon.text(size: 14)),
          const Spacer(),
          Text(value, style: Cartoon.text(size: 19, color: color)),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int i) {
    final on = _filter == i;
    return CartoonPressable(
      onTap: () => setState(() => _filter = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: on ? Cartoon.blue : Cartoon.paper,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Cartoon.ink, width: 1.6),
          boxShadow: [
            BoxShadow(color: Cartoon.ink, offset: Offset(0, on ? 3 : 2)),
          ],
        ),
        child: Text(
          label,
          style: Cartoon.text(size: 14, color: on ? Colors.white : Cartoon.ink),
        ),
      ),
    );
  }

  Widget _historyCard(
    BuildContext context,
    L10n l10n,
    Map<String, dynamic> item,
  ) {
    final delta = _delta(item);
    final positive = delta >= 0;
    final tone = positive
        ? Cartoon.onSurface(const Color(0xFF2E9E4F))
        : Cartoon.onSurface(const Color(0xFFE5791A));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Cartoon.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Cartoon.ink, width: 1.6),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Cartoon.ink, width: 1.5),
            ),
            child: Icon(
              positive ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 18,
              color: tone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  localizeGoldTitle(
                    item['title']?.toString(),
                    item['source']?.toString(),
                    l10n,
                    Localizations.localeOf(context).languageCode,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Cartoon.userText(size: 14.5, weight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${localizeGoldDescription(item['description']?.toString(), item['source']?.toString(), l10n)}'
                  ' · ${_formatHistoryDate(item['createdAt'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Cartoon.userText(
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: Cartoon.ink.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Cartoon.ink, width: 1.5),
            ),
            child: Text(
              '${positive ? '+' : ''}${formatGold(delta)}',
              style: Cartoon.text(size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 얻는 법 탭 ─────────────────────────

  Widget _earnTab(L10n l10n) {
    final items = <Widget>[
      _buildGoldGuideItem(
        title: l10n.shopGuideNormalWin,
        value: l10n.shopGuideNormalWinValue,
        description: l10n.shopGuideNormalWinDesc,
        color: Cartoon.surface(const Color(0xFFE8F5E9)),
        accent: Cartoon.onSurface(const Color(0xFF43A047)),
        icon: Icons.emoji_events_outlined,
      ),
      _buildGoldGuideItem(
        title: l10n.shopGuideNormalLoss,
        value: l10n.shopGuideNormalLossValue,
        description: l10n.shopGuideNormalLossDesc,
        color: Cartoon.surface(const Color(0xFFE3F2FD)),
        accent: Cartoon.onSurface(const Color(0xFF1E88E5)),
        icon: Icons.sports_esports_outlined,
      ),
      _buildGoldGuideItem(
        title: l10n.shopGuideRankedWin,
        value: l10n.shopGuideRankedWinValue,
        description: l10n.shopGuideRankedWinDesc,
        color: Cartoon.surface(const Color(0xFFFFF8E1)),
        accent: const Color(0xFFF9A825),
        icon: Icons.military_tech_outlined,
      ),
      _buildGoldGuideItem(
        title: l10n.shopGuideRankedLoss,
        value: l10n.shopGuideRankedLossValue,
        description: l10n.shopGuideRankedLossDesc,
        color: Cartoon.surface(const Color(0xFFFFF3E0)),
        accent: Cartoon.onSurface(const Color(0xFFEF6C00)),
        icon: Icons.shield_outlined,
      ),
      _buildGoldGuideItem(
        title: l10n.shopGuideAdReward,
        value: l10n.shopGuideAdRewardValue,
        description: l10n.shopGuideAdRewardDesc,
        color: Cartoon.surface(const Color(0xFFFFF3E0)),
        accent: const Color(0xFFFB8C00),
        icon: Icons.ondemand_video_outlined,
      ),
      _buildGoldGuideItem(
        title: l10n.shopGuideSeasonReward,
        value: l10n.shopGuideSeasonRewardValue,
        description: l10n.shopGuideSeasonRewardDesc,
        color: Cartoon.surface(const Color(0xFFF3E5F5)),
        accent: Cartoon.onSurface(const Color(0xFF8E24AA)),
        icon: Icons.workspace_premium_outlined,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 6),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.shopGoldGuideDesc,
            style: Cartoon.userText(
              size: 13,
              weight: FontWeight.w500,
              color: Cartoon.ink.withValues(alpha: 0.78),
              height: 1.45,
            ),
          ),
        ),
        for (final (i, w) in items.indexed)
          CartoonEntrance(
            delay: Duration(milliseconds: 40 * i),
            from: const Offset(0, 14),
            pop: false,
            child: w,
          ),
      ],
    );
  }
}

/// One way to earn gold: what it is, how much, and the condition.
///
/// Was a bordered card with a 42dp icon tile and a wrapped description — six
/// of them made the popup scroll on a phone for what is a short price list.
Widget _buildGoldGuideItem({
  required String title,
  required String value,
  required String description,
  required Color color,
  required Color accent,
  required IconData icon,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Cartoon.ink, width: 1.6),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Cartoon.paper,
            shape: BoxShape.circle,
            border: Border.all(color: Cartoon.ink, width: 1.5),
          ),
          child: Icon(icon, size: 21, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cartoon.userText(size: 14.5, weight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Cartoon.userText(
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: Cartoon.ink.withValues(alpha: 0.78),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: Cartoon.text(size: 17, color: accent)),
      ],
    ),
  );
}

String _formatHistoryDate(dynamic value) {
  if (value == null) return '';
  try {
    final dt = DateTime.parse(value.toString()).toLocal();
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}.$mm.$dd $hh:$min';
  } catch (_) {
    return value.toString();
  }
}
