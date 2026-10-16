import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/missions.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import '../widgets/token_cosmetics.dart';
import '../widgets/token_widgets.dart';

/// 상점 탭 순서. 새 종류(배너·테마 등)는 여기에 이름을 더하면 탭이 생긴다.
const _categoryOrder = ['bubble', 'room_highlight'];

/// 토큰 상점. 토큰은 미션으로만 얻고 여기서만 쓴다 — 돈으로도 골드로도 못 산다.
/// 전부 30일짜리 기간제이고, 다시 사면 기간이 늘어난다.
class TokenShopScreen extends StatefulWidget {
  const TokenShopScreen({super.key});

  @override
  State<TokenShopScreen> createState() => _TokenShopScreenState();
}

class _TokenShopScreenState extends State<TokenShopScreen> {
  int _seenResultSeq = 0;
  String _category = _categoryOrder.first;

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
    // 상품을 종류(말풍선·방 강조, 앞으로는 배너·테마도)로 묶는다. 종류가 늘어도 위의 탭만
    // 한 칸 늘어나고, 각 종류 안은 격자라서 길게 스크롤하지 않아도 한눈에 보인다.
    final categories = [
      for (final c in _categoryOrder)
        if (shop.products.any((p) => p.slot == c)) c,
      for (final c in {for (final p in shop.products) p.slot})
        if (!_categoryOrder.contains(c)) c,
    ];
    if (categories.isEmpty) return const SizedBox.shrink();
    final current = categories.contains(_category)
        ? _category
        : categories.first;
    final products = shop.products.where((p) => p.slot == current).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Container(
            width: double.infinity,
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
        ),
        _categoryTabs(l10n, categories, current),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(
                  tokenCategoryDesc(l10n, current),
                  style: Cartoon.userText(
                    size: 12,
                    color: Cartoon.ink.withValues(alpha: 0.6),
                  ),
                ),
              ),
              _grid(context, game, shop, products),
            ],
          ),
        ),
      ],
    );
  }

  /// 종류 탭 — 가로로 밀 수 있어서 종류가 늘어도 줄이 깨지지 않는다.
  Widget _categoryTabs(L10n l10n, List<String> categories, String current) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = categories[i];
          final selected = c == current;
          return CartoonPressable(
            onTap: () => setState(() => _category = c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Cartoon.orange : Cartoon.paper,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Cartoon.ink, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Cartoon.ink,
                    offset: Offset(0, selected ? 4 : 2),
                  ),
                ],
              ),
              child: Text(
                tokenCategoryName(l10n, c),
                style: Cartoon.text(
                  size: 15,
                  color: selected ? Colors.white : Cartoon.ink,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 상품 격자: 폭에 따라 2칸(폰) 또는 3칸(태블릿·웹).
  Widget _grid(
    BuildContext context,
    GameService game,
    TokenShopState shop,
    List<TokenProduct> products,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final cols = c.maxWidth >= 560 ? 3 : 2;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final p in products)
              SizedBox(width: w, child: _productCard(context, game, shop, p)),
          ],
        );
      },
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
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tokenProductName(l10n, p.key),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Cartoon.text(size: 15),
          ),
          const SizedBox(height: 8),
          // 미리보기 칸은 높이를 맞춰서 카드가 가지런히 서게 한다.
          Container(
            height: 52,
            alignment: Alignment.center,
            child: p.kind == 'room_highlight'
                ? RoomHighlightPreview(
                    styleKey: p.key,
                    name: l10n.tokenShopRoomPreviewName,
                  )
                : BubblePreview(
                    styleKey: p.key,
                    text: l10n.tokenShopPreviewText,
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const TokenCoin(size: 20),
              const SizedBox(width: 4),
              Text('${p.price}', style: Cartoon.text(size: 16)),
              const Spacer(),
              Text(
                l10n.tokenShopDays(p.days.toString()),
                style: Cartoon.userText(
                  size: 11.5,
                  color: Cartoon.ink.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          // 보유 기간 줄은 안 가졌어도 자리를 비워 둔다 — 샀다고 카드 높이가 달라지지 않게.
          SizedBox(
            height: 16,
            child: p.owned
                ? Text(
                    l10n.tokenShopOwnedUntil(_date(p.ownedUntil!)),
                    style: Cartoon.userText(
                      size: 11,
                      color: Cartoon.ink.withValues(alpha: 0.55),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 6),
          // 버튼은 늘 두 개 — 안 가진 상품은 '장착'이 흐리게 비활성이라, 사기 전후로
          // 카드 크기가 변하지 않는다.
          Row(
            children: [
              Expanded(
                child: CartoonButton(
                  height: 36,
                  radius: 12,
                  color: canAfford ? Cartoon.orange : const Color(0xFF9AA5B1),
                  onPressed: canAfford ? () => game.buyTokenItem(p.key) : null,
                  child: CartoonButton.label(
                    p.owned ? l10n.tokenShopExtend : l10n.tokenShopBuy,
                    size: 14,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: _equipButton(l10n, game, p)),
            ],
          ),
        ],
      ),
    );
  }

  /// 장착 버튼 — 가진 상품만 눌린다. 장착 중이면 초록, 아니면 크림색, 안 가졌으면 흐리게.
  Widget _equipButton(L10n l10n, GameService game, TokenProduct p) {
    final enabled = p.owned;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: CartoonPressable(
        scale: enabled ? 0.95 : 1.0,
        onTap: enabled
            ? () => game.equipTokenItem(p.slot, p.equipped ? null : p.key)
            : null,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.equipped ? const Color(0xFF3DBE6A) : Cartoon.paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Cartoon.ink, width: 1.8),
          ),
          child: Text(
            p.equipped ? l10n.tokenShopEquipped : l10n.tokenShopEquip,
            maxLines: 1,
            style: Cartoon.text(
              size: 13.5,
              color: p.equipped ? Colors.white : Cartoon.ink,
            ),
          ),
        ),
      ),
    );
  }

  String _date(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}
