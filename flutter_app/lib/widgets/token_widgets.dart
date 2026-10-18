import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/missions.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import '../utils/mission_text.dart';
import 'token_cosmetics.dart';

/// 토큰 알약(잔액). 누르면 토큰 내역이 열린다.
class TokenBalanceChip extends StatelessWidget {
  const TokenBalanceChip({super.key, required this.balance});
  final int balance;

  @override
  Widget build(BuildContext context) {
    return CartoonPressable(
      scale: 0.92,
      onTap: () => showTokenHistorySheet(context),
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: Cartoon.surface(Cartoon.surface(const Color(0xFFFFE9A8))),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Cartoon.ink, width: 2),
          boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TokenCoin(size: 24),
            const SizedBox(width: 5),
            Text('$balance', style: Cartoon.text(size: 17)),
            // 눌러 볼 수 있다는 표시 — 내역이 열린다.
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: Cartoon.ink.withValues(alpha: 0.6),
            ),
          ],
        ),
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
        color: Cartoon.surface(const Color(0xFFFFF4C9)),
      ),
    );
  }
}

/// 토큰 내역 시트. 받은 것과 쓴 것이 최신순으로 쌓이고, 더 보기로 이어 받는다.
Future<void> showTokenHistorySheet(BuildContext context) {
  final game = context.read<GameService>();
  game.requestTokenHistory();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<GameService>.value(
      value: game,
      child: const _TokenHistorySheet(),
    ),
  );
}

class _TokenHistorySheet extends StatelessWidget {
  const _TokenHistorySheet();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final game = context.watch<GameService>();
    final rows = game.tokenHistory;
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: Cartoon.panelDecoration(radius: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Cartoon.ink.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const TokenCoin(size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.tokenHistoryTitle,
                    style: Cartoon.text(size: 20),
                  ),
                ),
                Text(
                  l10n.tokenHistoryBalance(game.tokenBalance.toString()),
                  style: Cartoon.text(size: 15, color: Cartoon.orangeDeep),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(child: _body(context, l10n, game, rows)),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    L10n l10n,
    GameService game,
    List<TokenHistoryEntry> rows,
  ) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: game.tokenHistoryLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Cartoon.orange,
                  strokeWidth: 4,
                ),
              )
            : Text(
                game.tokenHistoryFailed
                    ? l10n.missionsLoadFailed
                    : l10n.tokenHistoryEmpty,
                textAlign: TextAlign.center,
                style: Cartoon.userText(
                  size: 13.5,
                  color: Cartoon.ink.withValues(alpha: 0.6),
                ),
              ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        for (final (i, e) in rows.indexed) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1.2,
              color: Cartoon.ink.withValues(alpha: 0.1),
            ),
          _row(l10n, e),
        ],
        if (game.tokenHistoryHasMore)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: CartoonButton(
                expand: false,
                height: 38,
                radius: 13,
                color: Cartoon.onSurface(const Color(0xFF4DA3FF)),
                onPressed: game.tokenHistoryLoading
                    ? null
                    : game.requestMoreTokenHistory,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: CartoonButton.label(l10n.tokenHistoryMore, size: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(L10n l10n, TokenHistoryEntry e) {
    final gain = e.delta > 0;
    final (IconData icon, Color color) = switch (e.reason) {
      'mission' => (Icons.task_alt_rounded, const Color(0xFF3DBE6A)),
      'streak' => (Icons.local_fire_department_rounded, Cartoon.orangeDeep),
      'shop' => (
        Icons.storefront_rounded,
        Cartoon.onSurface(const Color(0xFF4DA3FF)),
      ),
      _ => (
        Icons.admin_panel_settings_rounded,
        Cartoon.onSurface(const Color(0xFF8E7CC3)),
      ),
    };
    final title = switch (e.reason) {
      'mission' => missionTitle(l10n, e.ref ?? ''),
      'streak' => l10n.tokenHistoryStreak,
      'shop' => l10n.tokenHistoryShop(tokenProductName(l10n, e.ref ?? '')),
      'admin_revoke' => l10n.tokenHistoryAdminRevoke,
      _ => l10n.tokenHistoryAdminGrant,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Cartoon.ink, width: 1.8),
            ),
            child: Icon(icon, size: 19, color: Cartoon.surface(Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Cartoon.userText(size: 14),
                ),
                if (e.at != null)
                  Text(
                    _stamp(e.at!),
                    style: Cartoon.userText(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: Cartoon.ink.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${gain ? '+' : ''}${e.delta}',
            style: Cartoon.text(
              size: 18,
              color: gain
                  ? Cartoon.onSurface(const Color(0xFF2E8B57))
                  : Cartoon.onSurface(const Color(0xFFD64550)),
            ),
          ),
        ],
      ),
    );
  }

  /// 'M/D HH:mm' (기기 시간대).
  String _stamp(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
