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
          border: Border.all(color: Cartoon.ink, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Cartoon.ink, offset: Offset(0, 3)),
          ],
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
                  color: Cartoon.ink.withValues(alpha: 0.65),
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
            border: Border.all(color: Cartoon.ink, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Cartoon.ink, offset: Offset(0, 3)),
            ],
          ),
          child: const Icon(Icons.close_rounded, color: Cartoon.ink),
        ),
      ),
    ],
  );
}

void showGoldHistoryDialog(BuildContext context, GameService game) {
  game.requestGoldHistory();
  showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Consumer<GameService>(
            builder: (context, game, _) {
              final l10n = L10n.of(context);
              Widget status(String text, {bool sleepy = false}) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sleepy)
                      CartoonFloat(
                        amplitude: 6,
                        child: Image.asset(
                          'assets/dragonIcon.webp',
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
                        color: Cartoon.ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _goldDialogHeader(
                    dialogContext,
                    title: l10n.shopGoldHistory,
                    subtitle: l10n.shopGoldCurrent(game.gold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.shopGoldHistoryDesc,
                    style: Cartoon.userText(
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: Cartoon.ink.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        if (game.goldHistoryLoading) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Cartoon.orange,
                              strokeWidth: 4,
                            ),
                          );
                        }
                        if (game.goldHistoryError != null) {
                          return status(
                            localizeServiceMessage(
                              game.goldHistoryError!,
                              l10n,
                            ),
                          );
                        }
                        if (game.goldHistory.isEmpty) {
                          return status(
                            l10n.shopGoldHistoryEmpty,
                            sleepy: true,
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.only(bottom: 6),
                          itemCount: game.goldHistory.length,
                          itemBuilder: (context, index) {
                            final item = game.goldHistory[index];
                            final delta =
                                (item['goldDelta'] as num?)?.toInt() ?? 0;
                            final positive = delta >= 0;
                            final tone = positive
                                ? const Color(0xFF2E9E4F)
                                : const Color(0xFFE5791A);
                            return CartoonEntrance(
                              key: ValueKey('gh-$index'),
                              delay: Duration(
                                milliseconds: 35 * index.clamp(0, 8),
                              ),
                              from: const Offset(0, 14),
                              pop: false,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  9,
                                  10,
                                  9,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Cartoon.ink,
                                    width: 2.2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Cartoon.ink,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: tone.withValues(alpha: 0.18),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Cartoon.ink,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        positive
                                            ? Icons.south_west_rounded
                                            : Icons.north_east_rounded,
                                        size: 18,
                                        color: tone,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            localizeGoldTitle(
                                              item['title']?.toString(),
                                              item['source']?.toString(),
                                              l10n,
                                              Localizations.localeOf(
                                                context,
                                              ).languageCode,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Cartoon.userText(
                                              size: 14.5,
                                              weight: FontWeight.w800,
                                            ),
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
                                              color: Cartoon.ink.withValues(
                                                alpha: 0.55,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tone,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Cartoon.ink,
                                          width: 2,
                                        ),
                                      ),
                                      child: Text(
                                        '${positive ? '+' : ''}${formatGold(delta)}',
                                        style: Cartoon.text(
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  CartoonButton(
                    height: 50,
                    color: Cartoon.orange,
                    onPressed: () => _showGoldGuideDialog(dialogContext),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lightbulb_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: CartoonButton.label(
                            l10n.shopHowToEarn,
                            size: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

void _showGoldGuideDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (dialogContext) => LayoutBuilder(
      builder: (context, constraints) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: Cartoon.ink, width: 3),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: constraints.maxHeight * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _goldDialogHeader(
                    dialogContext,
                    title: L10n.of(context).shopGoldGuideTitle,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    L10n.of(context).shopGoldGuideDesc,
                    style: Cartoon.userText(
                      size: 13,
                      weight: FontWeight.w500,
                      color: Cartoon.ink.withValues(alpha: 0.65),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildGoldGuideItem(
                    title: L10n.of(context).shopGuideNormalWin,
                    value: L10n.of(context).shopGuideNormalWinValue,
                    description: L10n.of(context).shopGuideNormalWinDesc,
                    color: const Color(0xFFE8F5E9),
                    accent: const Color(0xFF43A047),
                    icon: Icons.emoji_events_outlined,
                  ),
                  _buildGoldGuideItem(
                    title: L10n.of(context).shopGuideNormalLoss,
                    value: L10n.of(context).shopGuideNormalLossValue,
                    description: L10n.of(context).shopGuideNormalLossDesc,
                    color: const Color(0xFFE3F2FD),
                    accent: const Color(0xFF1E88E5),
                    icon: Icons.sports_esports_outlined,
                  ),
                  _buildGoldGuideItem(
                    title: L10n.of(context).shopGuideRankedWin,
                    value: L10n.of(context).shopGuideRankedWinValue,
                    description: L10n.of(context).shopGuideRankedWinDesc,
                    color: const Color(0xFFFFF8E1),
                    accent: const Color(0xFFF9A825),
                    icon: Icons.military_tech_outlined,
                  ),
                  _buildGoldGuideItem(
                    title: L10n.of(context).shopGuideRankedLoss,
                    value: L10n.of(context).shopGuideRankedLossValue,
                    description: L10n.of(context).shopGuideRankedLossDesc,
                    color: const Color(0xFFFFF3E0),
                    accent: const Color(0xFFEF6C00),
                    icon: Icons.shield_outlined,
                  ),
                  _buildGoldGuideItem(
                    title: L10n.of(context).shopGuideAdReward,
                    value: L10n.of(context).shopGuideAdRewardValue,
                    description: L10n.of(context).shopGuideAdRewardDesc,
                    color: const Color(0xFFFFF3E0),
                    accent: const Color(0xFFFB8C00),
                    icon: Icons.ondemand_video_outlined,
                  ),
                  _buildGoldGuideItem(
                    title: L10n.of(context).shopGuideSeasonReward,
                    value: L10n.of(context).shopGuideSeasonRewardValue,
                    description: L10n.of(context).shopGuideSeasonRewardDesc,
                    color: const Color(0xFFF3E5F5),
                    accent: const Color(0xFF8E24AA),
                    icon: Icons.workspace_premium_outlined,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
      border: Border.all(color: Cartoon.ink, width: 2.2),
      boxShadow: const [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Cartoon.ink, width: 2),
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
                  color: Cartoon.ink.withValues(alpha: 0.65),
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
