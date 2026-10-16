import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/missions.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import '../widgets/token_cosmetics.dart';
import '../widgets/token_widgets.dart';

const _kinds = ['room_highlight', 'bubble_basic', 'bubble_premium'];

/// 토큰 상점. 토큰은 미션으로만 얻고 여기서만 쓴다 — 돈으로도 골드로도 못 산다.
/// 전부 30일짜리 기간제이고, 다시 사면 기간이 늘어난다.
class TokenShopScreen extends StatefulWidget {
  const TokenShopScreen({super.key});

  @override
  State<TokenShopScreen> createState() => _TokenShopScreenState();
}

class _TokenShopScreenState extends State<TokenShopScreen> {
  int _seenResultSeq = 0;

  @override
  void initState() {
    super.initState();
    final game = context.read<GameService>();
    _seenResultSeq = game.tokenShopResultSeq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) game.requestTokenShop();
    });
  }

  void _showResult(GameService game) {
    final l10n = L10n.of(context);
    final reason = game.tokenShopReason;
    final text = reason == null
        ? l10n.tokenShopBought
        : (reason == 'not_enough'
              ? l10n.tokenShopNotEnough
              : l10n.missionsErrGeneric);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
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
                  l10n.tokenShopTitle,
                  size: 28,
                  maxLines: 1,
                ),
              ),
            ),
            TokenBalanceChip(balance: game.tokenBalance),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, GameService game) {
    final l10n = L10n.of(context);
    final shop = game.tokenShopState;
    if (game.tokenShopResultSeq != _seenResultSeq) {
      _seenResultSeq = game.tokenShopResultSeq;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResult(game);
      });
    }
    if (shop == null) {
      return const Center(
        child: CircularProgressIndicator(color: Cartoon.orange, strokeWidth: 4),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 2.5),
          child: Text(
            l10n.tokenShopHint,
            style: Cartoon.userText(
              size: 12.5,
              color: Cartoon.ink.withValues(alpha: 0.7),
            ),
          ),
        ),
        for (final kind in _kinds) ...[
          const SizedBox(height: 16),
          _kindSection(context, game, shop, kind),
        ],
      ],
    );
  }

  Widget _kindSection(
    BuildContext context,
    GameService game,
    TokenShopState shop,
    String kind,
  ) {
    final l10n = L10n.of(context);
    final products = shop.products.where((p) => p.kind == kind).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
          child: Text(tokenKindName(l10n, kind), style: Cartoon.text(size: 18)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            kind == 'room_highlight'
                ? l10n.tokenShopKindRoomHighlightDesc
                : l10n.tokenShopKindBubbleDesc,
            style: Cartoon.userText(
              size: 12,
              color: Cartoon.ink.withValues(alpha: 0.6),
            ),
          ),
        ),
        for (final p in products) _productCard(context, game, shop, p),
      ],
    );
  }

  Widget _productCard(
    BuildContext context,
    GameService game,
    TokenShopState shop,
    TokenProduct p,
  ) {
    final l10n = L10n.of(context);
    final canAfford = shop.balance >= p.price;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tokenProductName(l10n, p.key),
                  style: Cartoon.text(size: 16),
                ),
              ),
              if (p.owned)
                Text(
                  l10n.tokenShopOwnedUntil(_date(p.ownedUntil!)),
                  style: Cartoon.userText(
                    size: 11.5,
                    color: Cartoon.ink.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (p.kind == 'room_highlight')
            RoomHighlightPreview(
              styleKey: p.key,
              name: l10n.tokenShopRoomPreviewName,
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: BubblePreview(
                styleKey: p.key,
                text: l10n.tokenShopPreviewText,
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              TokenCoin(size: 22),
              const SizedBox(width: 5),
              Text('${p.price}', style: Cartoon.text(size: 17)),
              Text(
                '  ·  ${l10n.tokenShopDays(p.days.toString())}',
                style: Cartoon.userText(
                  size: 12,
                  color: Cartoon.ink.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              if (p.owned)
                CartoonPressable(
                  scale: 0.92,
                  onTap: () =>
                      game.equipTokenItem(p.slot, p.equipped ? null : p.key),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: p.equipped
                          ? const Color(0xFF3DBE6A)
                          : Cartoon.paper,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Cartoon.ink, width: 1.8),
                    ),
                    child: Text(
                      p.equipped ? l10n.tokenShopEquipped : l10n.tokenShopEquip,
                      style: Cartoon.text(
                        size: 13.5,
                        color: p.equipped ? Colors.white : Cartoon.ink,
                      ),
                    ),
                  ),
                ),
              CartoonButton(
                expand: false,
                height: 38,
                radius: 13,
                color: canAfford ? Cartoon.orange : const Color(0xFF9AA5B1),
                onPressed: canAfford ? () => game.buyTokenItem(p.key) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: CartoonButton.label(
                    p.owned ? l10n.tokenShopExtend : l10n.tokenShopBuy,
                    size: 14.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _date(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}
