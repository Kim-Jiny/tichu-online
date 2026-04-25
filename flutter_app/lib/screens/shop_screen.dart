import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../models/shop_visual.dart';
import '../services/game_service.dart';
import '../services/ad_service.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _inventoryTabController = ValueNotifier<int>(0);
  int _todayAdCount = 0;
  bool _adLoading = false;
  RewardedAd? _rewardedAd;
  bool _rewardedAdReady = false;
  TabController? _inventoryTabs;

  String _getLocalizedItemName(Map<String, dynamic> item) {
    final locale = Localizations.localeOf(context).languageCode;
    return item['name_$locale']?.toString().isNotEmpty == true
        ? item['name_$locale'].toString()
        : item['name_ko']?.toString() ?? '';
  }

  String _getLocalizedItemDescription(Map<String, dynamic> item) {
    final locale = Localizations.localeOf(context).languageCode;
    final localized = item['description_$locale']?.toString();
    if (localized != null && localized.isNotEmpty) return localized;
    return item['description_ko']?.toString() ?? '';
  }

  bool _isOnSale(Map<String, dynamic> item) {
    final start = item['sale_start'];
    final end = item['sale_end'];
    if (start == null && end == null) return false;
    final now = DateTime.now();
    if (start != null) {
      final st = DateTime.tryParse(start.toString());
      if (st != null && now.isBefore(st)) return false;
    }
    if (end != null) {
      final et = DateTime.tryParse(end.toString());
      if (et != null && now.isAfter(et)) return false;
    }
    return true;
  }

  // Returns a compact sale-window string for the row trailing slot:
  // "10/01 ~ 10/15" if both bounds set, "~10/15" if only end, "10/01~" if
  // only start. Returns null when neither is set so the caller can hide
  // the slot entirely.
  String? _saleWindowText(Map<String, dynamic> item) {
    final s = item['sale_start'];
    final e = item['sale_end'];
    if (s == null && e == null) return null;
    String? fmt(dynamic raw) {
      if (raw == null) return null;
      final dt = DateTime.tryParse(raw.toString())?.toLocal();
      if (dt == null) return null;
      return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    }
    final sf = fmt(s);
    final ef = fmt(e);
    if (sf != null && ef != null) return '$sf ~ $ef';
    if (ef != null) return '~$ef';
    if (sf != null) return '$sf~';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadAdCount();
    _preloadRewardedAd();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final game = context.read<GameService>();
      game.requestWallet();
      game.requestShopItems();
      game.requestInventory();
    });
  }

  Future<void> _loadAdCount() async {
    final count = await AdService.getTodayRewardCount();
    if (mounted) setState(() => _todayAdCount = count);
  }

  void _preloadRewardedAd() {
    RewardedAd.load(
      adUnitId: AdService.rewardedAdId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          if (mounted) setState(() => _rewardedAdReady = true);
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdService] Rewarded FAILED: ${error.message}');
          _rewardedAdReady = false;
        },
      ),
    );
  }

  @override
  void dispose() {
    _inventoryTabs?.removeListener(_handleInventoryTabChanged);
    _rewardedAd?.dispose();
    _inventoryTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final baseScale = MediaQuery.of(context).textScaler.scale(1.0);
    final adjustedScale = isAndroid
        ? (baseScale * 0.92).clamp(0.9, 1.0)
        : baseScale;
    return DefaultTabController(
      length: 2,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(adjustedScale)),
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
              child: Consumer<GameService>(
                builder: (context, game, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _maybeShowShopActionResult(context, game);
                    _maybeShowPurchaseDialog(context, game);
                    _maybeShowNicknameChangeResult(context, game);
                    _maybeShowAdRewardResult(context, game);
                  });
                  return Column(
                    children: [
                      _buildTopBar(context, game),
                      _buildWalletBar(game),
                      if (_rewardedAdReady) _buildAdRewardButton(game),
                      const SizedBox(height: 8),
                      _buildTabs(),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildShopTab(game),
                            _buildInventoryTab(game),
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
      ),
    );
  }

  void _handleInventoryTabChanged() {
    final tabController = _inventoryTabs;
    if (tabController == null || tabController.indexIsChanging) return;
    _inventoryTabController.value = tabController.index;
  }

  Widget _buildTopBar(BuildContext context, GameService game) {
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
            L10n.of(context).shopTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              game.requestWallet();
              game.requestShopItems();
              game.requestInventory();
            },
            icon: const Icon(Icons.refresh),
            color: const Color(0xFF8A7A72),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletBar(GameService game) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showGoldHistoryDialog(game),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.monetization_on, color: Color(0xFFFFB74D)),
                  const SizedBox(width: 6),
                  Text(
                    L10n.of(context).shopGoldAmount(game.gold),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A4038),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Color(0xFFB89C76),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _showGoldGuideDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF0D6A6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: Color(0xFFB67C1D),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    L10n.of(context).shopHowToEarn,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8B6220),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE57373), size: 18),
          const SizedBox(width: 4),
          Text(
            L10n.of(context).shopDesertionCount(game.leaveCount),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9A6A6A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showGoldHistoryDialog(GameService game) {
    game.requestGoldHistory();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Consumer<GameService>(
              builder: (context, game, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.monetization_on,
                            color: Color(0xFFFFB74D),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                L10n.of(context).shopGoldHistory,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF5A4038),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                L10n.of(context).shopGoldCurrent(game.gold),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF8A7A72),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                          color: const Color(0xFF8A7A72),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.of(context).shopGoldHistoryDesc,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF8A7A72),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          if (game.goldHistoryLoading) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (game.goldHistoryError != null) {
                            return Center(
                              child: Text(
                                localizeServiceMessage(game.goldHistoryError!, L10n.of(context)),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF8A7A72),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }
                          if (game.goldHistory.isEmpty) {
                            return Center(
                              child: Text(
                                L10n.of(context).shopGoldHistoryEmpty,
                                style: const TextStyle(
                                  color: Color(0xFF8A7A72),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: game.goldHistory.length,
                            separatorBuilder: (_, separatorIndex) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = game.goldHistory[index];
                              final delta = (item['goldDelta'] as num?)?.toInt() ?? 0;
                              final positive = delta >= 0;
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE6DEDA)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: positive
                                            ? const Color(0xFFE8F5E9)
                                            : const Color(0xFFFFF3E0),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        positive ? Icons.south_west : Icons.north_east,
                                        color: positive
                                            ? const Color(0xFF43A047)
                                            : const Color(0xFFFB8C00),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            localizeGoldTitle(item['title']?.toString(), item['source']?.toString(), L10n.of(context), Localizations.localeOf(context).languageCode),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF5A4038),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            localizeGoldDescription(item['description']?.toString(), item['source']?.toString(), L10n.of(context)),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF8A7A72),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _formatHistoryDate(item['createdAt']),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFFB0A39E),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${positive ? '+' : ''}$delta',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: positive
                                            ? const Color(0xFF43A047)
                                            : const Color(0xFFFB8C00),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
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

  void _showGoldGuideDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => LayoutBuilder(
        builder: (context, constraints) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.monetization_on,
                            color: Color(0xFFFFB74D),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            L10n.of(context).shopGoldGuideTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF5A4038),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                          color: const Color(0xFF8A7A72),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.of(context).shopGoldGuideDesc,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF8A7A72),
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
                    const SizedBox(height: 10),
                    _buildGoldGuideItem(
                      title: L10n.of(context).shopGuideNormalLoss,
                      value: L10n.of(context).shopGuideNormalLossValue,
                      description: L10n.of(context).shopGuideNormalLossDesc,
                      color: const Color(0xFFE3F2FD),
                      accent: const Color(0xFF1E88E5),
                      icon: Icons.sports_esports_outlined,
                    ),
                    const SizedBox(height: 10),
                    _buildGoldGuideItem(
                      title: L10n.of(context).shopGuideRankedWin,
                      value: L10n.of(context).shopGuideRankedWinValue,
                      description: L10n.of(context).shopGuideRankedWinDesc,
                      color: const Color(0xFFFFF8E1),
                      accent: const Color(0xFFF9A825),
                      icon: Icons.military_tech_outlined,
                    ),
                    const SizedBox(height: 10),
                    _buildGoldGuideItem(
                      title: L10n.of(context).shopGuideRankedLoss,
                      value: L10n.of(context).shopGuideRankedLossValue,
                      description: L10n.of(context).shopGuideRankedLossDesc,
                      color: const Color(0xFFFFF3E0),
                      accent: const Color(0xFFEF6C00),
                      icon: Icons.shield_outlined,
                    ),
                    const SizedBox(height: 10),
                    _buildGoldGuideItem(
                      title: L10n.of(context).shopGuideAdReward,
                      value: L10n.of(context).shopGuideAdRewardValue,
                      description: L10n.of(context).shopGuideAdRewardDesc,
                      color: const Color(0xFFFFF3E0),
                      accent: const Color(0xFFFB8C00),
                      icon: Icons.ondemand_video_outlined,
                    ),
                    const SizedBox(height: 10),
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

  Widget _buildGoldGuideItem({
    required String title,
    required String value,
    required String description,
    required Color color,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6DEDA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF5A4038),
                        ),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Color(0xFF8A7A72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        labelColor: const Color(0xFF5A4038),
        unselectedLabelColor: const Color(0xFF9A8E8A),
        indicatorColor: const Color(0xFFB9A8A1),
        tabs: [
          Tab(text: L10n.of(context).shopTabShop),
          Tab(text: L10n.of(context).shopTabInventory),
        ],
      ),
    );
  }

  Widget _buildShopTab(GameService game) {
    if (game.shopLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.shopError != null) {
      return Center(
        child: Text(
          localizeServiceMessage(game.shopError!, L10n.of(context)),
          style: const TextStyle(color: Color(0xFFCC6666)),
        ),
      );
    }
    if (game.shopItems.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).shopNoItems,
          style: const TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildCategoryTabs([
            L10n.of(context).shopCategoryBanner,
            L10n.of(context).shopCategoryTitle,
            L10n.of(context).shopCategoryTheme,
            L10n.of(context).shopCategoryUtil,
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _buildShopList(context, game, _filterShop(game.shopItems, 'banner')),
                _buildShopList(context, game, _filterShop(game.shopItems, 'title')),
                _buildShopList(context, game, _filterShop(game.shopItems, 'theme')),
                _buildShopList(context, game, _filterShop(game.shopItems, 'utility')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopList(
    BuildContext context,
    GameService game,
    List<Map<String, dynamic>> items,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).shopItemEmpty,
          style: const TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildShopRow(context, game, items[index]),
    );
  }

  // Row-style item with inline action: visual square left, content + CTA on
  // the right. Tap CTA = buy/extend immediately (no double-tap). Tap card =
  // open detail bottom sheet (drag-dismissable, less heavy than a dialog).
  Widget _buildShopRow(
    BuildContext context,
    GameService game,
    Map<String, dynamic> item,
  ) {
    final l10n = L10n.of(context);
    final name = _getLocalizedItemName(item);
    final description = _getLocalizedItemDescription(item);
    final price = item['price'] ?? 0;
    final isSeason = item['is_season'] == true;
    final isPermanent = item['is_permanent'] == true;
    final durationDays = item['duration_days'];
    final itemKey = item['item_key']?.toString() ?? '';
    final owned = game.inventoryItems.any((i) => i['item_key'] == itemKey);
    final ownedPermanent = owned && isPermanent;
    final onSale = _isOnSale(item);
    final saleWindow = _saleWindowText(item);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _showItemDetailSheet(context, item),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE7E0DC)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildShopRowVisual(item, 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4A3A33)),
                          ),
                        ),
                        if (ownedPermanent)
                          _badge(l10n.shopItemOwned, const Color(0xFF7E57C2), const Color(0xFFEDE7F6))
                        else if (isSeason)
                          _badge(l10n.shopTagSeason, const Color(0xFF1565C0), const Color(0xFFE3F2FD))
                        else if (onSale)
                          _badge('SALE', const Color(0xFFD32F2F), const Color(0xFFFFEBEE)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description.isNotEmpty
                          ? description
                          : _buildItemTag(context, isSeason, isPermanent, durationDays),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A7A72), height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    // Bottom row: gold price on the left, sale window on the
                    // right (replaces the inline buy button — purchasing now
                    // happens in the detail sheet so it's an explicit choice).
                    Row(
                      children: [
                        if (!ownedPermanent) ...[
                          const Icon(Icons.monetization_on, size: 14, color: Color(0xFFF0B400)),
                          const SizedBox(width: 3),
                          Text('$price', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF4A4080))),
                        ],
                        const Spacer(),
                        if (saleWindow != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule, size: 12, color: onSale ? const Color(0xFFD32F2F) : const Color(0xFF9A8E8A)),
                              const SizedBox(width: 3),
                              Text(
                                saleWindow,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: onSale ? const Color(0xFFD32F2F) : const Color(0xFF9A8E8A),
                                ),
                              ),
                            ],
                          )
                        else if (!isPermanent && durationDays != null)
                          Text(
                            '$durationDays일',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9A8E8A), fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 20, color: Color(0xFFB0A8A2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShopRowVisual(Map<String, dynamic> item, double size) {
    final category = item['category']?.toString() ?? '';
    final itemKey = item['item_key']?.toString() ?? '';
    final visual = _resolveThumbnailStyle(itemKey, category, item);
    final gradient = (visual['gradient'] as List<Color>?) ?? [Colors.white, Colors.grey.shade100];
    final iconData = (visual['icon'] as IconData?) ?? Icons.flag;
    final iconColor = (visual['iconColor'] as Color?) ?? const Color(0xFF888888);
    final borderColor = (visual['borderColor'] as Color?) ?? const Color(0xFFE0D8D4);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.7)),
      ),
      child: Center(child: Icon(iconData, color: iconColor, size: size * 0.45)),
    );
  }

  Widget _badge(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w700)),
    );
  }

  void _showExtendConfirmDialog(BuildContext context, GameService game, Map<String, dynamic> item) {
    final name = _getLocalizedItemName(item);
    final itemKey = item['item_key']?.toString() ?? '';
    final price = item['price'] ?? 0;
    final durationDays = item['duration_days'] ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(L10n.of(context).shopExtendTitle),
        content: Text(
          L10n.of(context).shopExtendConfirm(name, durationDays as int, price as int),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.buyItem(itemKey);
            },
            child: Text(L10n.of(context).shopExtendAction),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab(GameService game) {
    if (game.inventoryLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.inventoryError != null) {
      return Center(
        child: Text(
          localizeServiceMessage(game.inventoryError!, L10n.of(context)),
          style: const TextStyle(color: Color(0xFFCC6666)),
        ),
      );
    }
    if (game.inventoryItems.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).shopNoInventoryItems,
          style: const TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      initialIndex: _inventoryTabController.value,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          if (!identical(_inventoryTabs, tabController)) {
            _inventoryTabs?.removeListener(_handleInventoryTabChanged);
            _inventoryTabs = tabController;
            _inventoryTabs?.addListener(_handleInventoryTabChanged);
          }
          return Column(
            children: [
              const SizedBox(height: 8),
              _buildCategoryTabs([
                L10n.of(context).shopCategoryBanner,
                L10n.of(context).shopCategoryTitle,
                L10n.of(context).shopCategoryTheme,
                L10n.of(context).shopCategoryUtil,
                L10n.of(context).shopCategorySeason,
              ]),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildInventoryList(_filterInventory(game.inventoryItems, 'banner')),
                    _buildInventoryList(_filterInventory(game.inventoryItems, 'title')),
                    _buildInventoryList(_filterInventory(game.inventoryItems, 'theme')),
                    _buildInventoryList(_filterInventory(game.inventoryItems, 'utility')),
                    _buildInventoryList(_filterInventory(game.inventoryItems, 'season')),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInventoryList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).shopItemEmpty,
          style: const TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildInventoryItem(context, items[index]),
    );
  }

  Widget _buildInventoryItem(BuildContext context, Map<String, dynamic> item) {
    final l10n = L10n.of(context);
    final game = context.read<GameService>();
    final name = _getLocalizedItemName(item);
    final description = _getLocalizedItemDescription(item);
    final category = item['category']?.toString() ?? '';
    final isActive = item['is_active'] == true;
    final itemKey = item['item_key']?.toString() ?? '';
    final effectType = item['effect_type']?.toString() ?? '';
    final isPassiveUtility = itemKey.startsWith('top_card_counter')
        || itemKey.startsWith('mighty_trump_counter')
        || itemKey.startsWith('mighty_prev_trick');
    final isConsumable = category == 'utility' && !isPassiveUtility;
    final expiresAt = item['expires_at'];
    final expiresText = expiresAt != null ? _formatExpire(context, expiresAt) : null;
    final equipped = isActive && !isPassiveUtility;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _showItemDetailSheet(context, item),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: equipped ? const Color(0xFF5C9DD6) : const Color(0xFFE7E0DC),
              width: equipped ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildShopRowVisual(item, 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4A3A33)),
                          ),
                        ),
                        if (equipped)
                          _badge(l10n.shopStatusInUse, const Color(0xFF1565C0), const Color(0xFFDDECF7))
                        else if (isPassiveUtility)
                          _badge(l10n.shopStatusActivated, const Color(0xFF1565C0), const Color(0xFFDDECF7)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description.isNotEmpty
                          ? description
                          : (expiresText ?? l10n.shopPermanentOwned),
                      maxLines: description.isNotEmpty ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A7A72), height: 1.3),
                    ),
                    if (description.isNotEmpty && expiresText != null) ...[
                      const SizedBox(height: 2),
                      Text(expiresText, style: const TextStyle(fontSize: 10.5, color: Color(0xFFA0938C))),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Spacer(),
                        if (!isPassiveUtility)
                          SizedBox(
                            height: 30,
                            child: ElevatedButton(
                              onPressed: () {
                                if (effectType == 'nickname_change') {
                                  _showNicknameChangeDialog(context, game);
                                } else if (isConsumable) {
                                  game.useItem(itemKey);
                                } else {
                                  game.equipItem(itemKey);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isConsumable
                                    ? const Color(0xFFFFE0B2)
                                    : (equipped ? const Color(0xFFE3F2FD) : const Color(0xFFB3E5FC)),
                                foregroundColor: const Color(0xFF4A3A33),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                isConsumable ? l10n.shopButtonUse : l10n.shopButtonEquip,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Fallback chain: server-driven visual (admin-editable) → legacy hardcoded
  // switch (kept so v2.3.0+26 items still render even if a backfill row is
  // missing) → category default.
  Map<String, Object> _resolveThumbnailStyle(String itemKey, String category, Map<String, dynamic>? item) {
    final serverVisual = ShopVisual.fromItemMap(item);
    final fromServer = serverVisual?.thumbnailLegacyMap();
    if (fromServer != null) return fromServer;
    return _thumbnailStyleByKey(itemKey, category);
  }

  Map<String, Object> _thumbnailStyleByKey(String itemKey, String category) {
    // Item-specific thumbnails
    switch (itemKey) {
      // Banners
      case 'banner_pastel':
        return {
          'icon': Icons.auto_awesome,
          'iconColor': const Color(0xFFD4A0C0),
          'gradient': [const Color(0xFFFCE4EC), const Color(0xFFF3E5F5)],
          'borderColor': const Color(0xFFF8BBD0),
        };
      case 'banner_blossom':
        return {
          'icon': Icons.local_florist,
          'iconColor': const Color(0xFFE91E63),
          'gradient': [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)],
          'borderColor': const Color(0xFFF48FB1),
        };
      case 'banner_mint':
        return {
          'icon': Icons.spa,
          'iconColor': const Color(0xFF26A69A),
          'gradient': [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)],
          'borderColor': const Color(0xFF80CBC4),
        };
      case 'banner_sunset_7d':
        return {
          'icon': Icons.wb_twilight,
          'iconColor': const Color(0xFFFF6F00),
          'gradient': [const Color(0xFFFFE0B2), const Color(0xFFFFCC80)],
          'borderColor': const Color(0xFFFFB74D),
        };
      case 'banner_season_gold':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFFFF8F00),
          'gradient': [const Color(0xFFFFF8E1), const Color(0xFFFFECB3)],
          'borderColor': const Color(0xFFFFD54F),
        };
      case 'banner_season_silver':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFF78909C),
          'gradient': [const Color(0xFFECEFF1), const Color(0xFFCFD8DC)],
          'borderColor': const Color(0xFFB0BEC5),
        };
      case 'banner_season_bronze':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFF8D6E63),
          'gradient': [const Color(0xFFEFEBE9), const Color(0xFFD7CCC8)],
          'borderColor': const Color(0xFFBCAAA4),
        };
      // Titles
      case 'title_sweet':
        return {
          'icon': Icons.cake,
          'iconColor': const Color(0xFFEC407A),
          'gradient': [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)],
          'borderColor': const Color(0xFFF48FB1),
        };
      case 'title_steady':
        return {
          'icon': Icons.shield,
          'iconColor': const Color(0xFF5C6BC0),
          'gradient': [const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)],
          'borderColor': const Color(0xFF9FA8DA),
        };
      case 'title_flash_30d':
        return {
          'icon': Icons.flash_on,
          'iconColor': const Color(0xFFFFA000),
          'gradient': [const Color(0xFFFFF8E1), const Color(0xFFFFECB3)],
          'borderColor': const Color(0xFFFFD54F),
        };
      case 'title_dragon':
        return {
          'icon': Icons.local_fire_department,
          'iconColor': const Color(0xFFD32F2F),
          'gradient': [const Color(0xFFFFEBEE), const Color(0xFFFFCDD2)],
          'borderColor': const Color(0xFFEF9A9A),
        };
      case 'title_phoenix':
        return {
          'icon': Icons.local_fire_department,
          'iconColor': const Color(0xFFFF6F00),
          'gradient': [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
          'borderColor': const Color(0xFFFFCC80),
        };
      case 'title_pirate':
        return {
          'icon': Icons.anchor,
          'iconColor': const Color(0xFF37474F),
          'gradient': [const Color(0xFFECEFF1), const Color(0xFFCFD8DC)],
          'borderColor': const Color(0xFF90A4AE),
        };
      case 'title_tactician':
        return {
          'icon': Icons.psychology,
          'iconColor': const Color(0xFF00695C),
          'gradient': [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)],
          'borderColor': const Color(0xFF80CBC4),
        };
      case 'title_lucky':
        return {
          'icon': Icons.star,
          'iconColor': const Color(0xFFFFD600),
          'gradient': [const Color(0xFFFFFDE7), const Color(0xFFFFF9C4)],
          'borderColor': const Color(0xFFFFF176),
        };
      case 'title_bluffer':
        return {
          'icon': Icons.theater_comedy,
          'iconColor': const Color(0xFF6A1B9A),
          'gradient': [const Color(0xFFF3E5F5), const Color(0xFFE1BEE7)],
          'borderColor': const Color(0xFFCE93D8),
        };
      case 'title_ace':
        return {
          'icon': Icons.military_tech,
          'iconColor': const Color(0xFFC62828),
          'gradient': [const Color(0xFFFFEBEE), const Color(0xFFFFCDD2)],
          'borderColor': const Color(0xFFEF9A9A),
        };
      case 'title_king':
        return {
          'icon': Icons.workspace_premium,
          'iconColor': const Color(0xFFFF8F00),
          'gradient': [const Color(0xFFFFF8E1), const Color(0xFFFFE082)],
          'borderColor': const Color(0xFFFFD54F),
        };
      case 'title_rookie':
        return {
          'icon': Icons.emoji_nature,
          'iconColor': const Color(0xFF66BB6A),
          'gradient': [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          'borderColor': const Color(0xFFA5D6A7),
        };
      case 'title_veteran':
        return {
          'icon': Icons.security,
          'iconColor': const Color(0xFF1565C0),
          'gradient': [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)],
          'borderColor': const Color(0xFF90CAF9),
        };
      case 'title_sensitive':
        return {
          'icon': Icons.sentiment_very_dissatisfied,
          'iconColor': const Color(0xFFE91E63),
          'gradient': [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)],
          'borderColor': const Color(0xFFF48FB1),
        };
      case 'title_shadow':
        return {
          'icon': Icons.visibility_off,
          'iconColor': const Color(0xFF424242),
          'gradient': [const Color(0xFFF5F5F5), const Color(0xFFE0E0E0)],
          'borderColor': const Color(0xFFBDBDBD),
        };
      case 'title_flame':
        return {
          'icon': Icons.whatshot,
          'iconColor': const Color(0xFFFF5722),
          'gradient': [const Color(0xFFFBE9E7), const Color(0xFFFFCCBC)],
          'borderColor': const Color(0xFFFF8A65),
        };
      case 'title_ice':
        return {
          'icon': Icons.ac_unit,
          'iconColor': const Color(0xFF0288D1),
          'gradient': [const Color(0xFFE1F5FE), const Color(0xFFB3E5FC)],
          'borderColor': const Color(0xFF81D4FA),
        };
      case 'title_crown':
        return {
          'icon': Icons.diamond,
          'iconColor': const Color(0xFFE65100),
          'gradient': [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
          'borderColor': const Color(0xFFFFB74D),
        };
      case 'title_diamond':
        return {
          'icon': Icons.diamond,
          'iconColor': const Color(0xFF00BCD4),
          'gradient': [const Color(0xFFE0F7FA), const Color(0xFFB2EBF2)],
          'borderColor': const Color(0xFF80DEEA),
        };
      case 'title_ghost':
        return {
          'icon': Icons.blur_on,
          'iconColor': const Color(0xFF78909C),
          'gradient': [const Color(0xFFECEFF1), const Color(0xFFCFD8DC)],
          'borderColor': const Color(0xFFB0BEC5),
        };
      case 'title_thunder':
        return {
          'icon': Icons.bolt,
          'iconColor': const Color(0xFFFFAB00),
          'gradient': [const Color(0xFFFFF8E1), const Color(0xFFFFECB3)],
          'borderColor': const Color(0xFFFFD54F),
        };
      case 'title_topcard':
        return {
          'icon': Icons.style,
          'iconColor': const Color(0xFF00897B),
          'gradient': [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)],
          'borderColor': const Color(0xFF80CBC4),
        };
      case 'title_legend':
        return {
          'icon': Icons.auto_awesome,
          'iconColor': const Color(0xFFFF6D00),
          'gradient': [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
          'borderColor': const Color(0xFFFFAB40),
        };
      case 'title_boomer':
        return {
          'icon': Icons.elderly,
          'iconColor': const Color(0xFF795548),
          'gradient': [const Color(0xFFEFEBE9), const Color(0xFFD7CCC8)],
          'borderColor': const Color(0xFFBCAAA4),
        };
      // Themes
      case 'theme_cotton':
        return {
          'icon': Icons.cloud,
          'iconColor': const Color(0xFF90A4AE),
          'gradient': [const Color(0xFFF5F5F5), const Color(0xFFE0E0E0)],
          'borderColor': const Color(0xFFBDBDBD),
        };
      case 'theme_sky':
        return {
          'icon': Icons.wb_sunny,
          'iconColor': const Color(0xFF42A5F5),
          'gradient': [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)],
          'borderColor': const Color(0xFF90CAF9),
        };
      case 'theme_mocha_30d':
        return {
          'icon': Icons.coffee,
          'iconColor': const Color(0xFF6D4C41),
          'gradient': [const Color(0xFFEFEBE9), const Color(0xFFD7CCC8)],
          'borderColor': const Color(0xFFBCAAA4),
        };
      case 'theme_lavender':
        return {
          'icon': Icons.local_florist,
          'iconColor': const Color(0xFF9C27B0),
          'gradient': [const Color(0xFFF3E5F5), const Color(0xFFE1BEE7)],
          'borderColor': const Color(0xFFCE93D8),
        };
      case 'theme_cherry':
        return {
          'icon': Icons.filter_vintage,
          'iconColor': const Color(0xFFE91E63),
          'gradient': [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)],
          'borderColor': const Color(0xFFF48FB1),
        };
      case 'theme_midnight':
        return {
          'icon': Icons.nights_stay,
          'iconColor': const Color(0xFF303F9F),
          'gradient': [const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)],
          'borderColor': const Color(0xFF9FA8DA),
        };
      case 'theme_sunset':
        return {
          'icon': Icons.wb_twilight,
          'iconColor': const Color(0xFFF57C00),
          'gradient': [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
          'borderColor': const Color(0xFFFFCC80),
        };
      case 'theme_forest':
        return {
          'icon': Icons.park,
          'iconColor': const Color(0xFF2E7D32),
          'gradient': [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          'borderColor': const Color(0xFFA5D6A7),
        };
      case 'theme_rose':
        return {
          'icon': Icons.spa,
          'iconColor': const Color(0xFFD4A08A),
          'gradient': [const Color(0xFFFBE9E7), const Color(0xFFFFCCBC)],
          'borderColor': const Color(0xFFFFAB91),
        };
      case 'theme_ocean':
        return {
          'icon': Icons.waves,
          'iconColor': const Color(0xFF0097A7),
          'gradient': [const Color(0xFFE0F7FA), const Color(0xFFB2EBF2)],
          'borderColor': const Color(0xFF80DEEA),
        };
      case 'theme_aurora':
        return {
          'icon': Icons.auto_awesome,
          'iconColor': const Color(0xFF26A69A),
          'gradient': [const Color(0xFFE0F7FA), const Color(0xFFE8F5E9)],
          'borderColor': const Color(0xFF80CBC4),
        };
      case 'theme_mintchoco_30d':
        return {
          'icon': Icons.icecream,
          'iconColor': const Color(0xFF00897B),
          'gradient': [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)],
          'borderColor': const Color(0xFF80CBC4),
        };
      case 'theme_peach_30d':
        return {
          'icon': Icons.brightness_7,
          'iconColor': const Color(0xFFFF8A65),
          'gradient': [const Color(0xFFFFF3E0), const Color(0xFFFFCCBC)],
          'borderColor': const Color(0xFFFFAB91),
        };
      // Utility
      case 'leave_reduce_1':
        return {
          'icon': Icons.healing,
          'iconColor': const Color(0xFF66BB6A),
          'gradient': [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          'borderColor': const Color(0xFFA5D6A7),
        };
      case 'top_card_counter_7d':
        return {
          'icon': Icons.analytics,
          'iconColor': const Color(0xFF5C6BC0),
          'gradient': [const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)],
          'borderColor': const Color(0xFF9FA8DA),
        };
      case 'leave_reduce_3':
        return {
          'icon': Icons.local_hospital,
          'iconColor': const Color(0xFF43A047),
          'gradient': [const Color(0xFFE8F5E9), const Color(0xFFA5D6A7)],
          'borderColor': const Color(0xFF81C784),
        };
      case 'stats_reset':
        return {
          'icon': Icons.restart_alt,
          'iconColor': const Color(0xFF757575),
          'gradient': [const Color(0xFFF5F5F5), const Color(0xFFE0E0E0)],
          'borderColor': const Color(0xFFBDBDBD),
        };
      case 'season_stats_reset':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFF7B1FA2),
          'gradient': [const Color(0xFFF3E5F5), const Color(0xFFCE93D8)],
          'borderColor': const Color(0xFFBA68C8),
        };
      case 'tichu_season_stats_reset':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFF355D89),
          'gradient': [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)],
          'borderColor': const Color(0xFF90CAF9),
        };
      case 'sk_season_stats_reset':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFF424242),
          'gradient': [const Color(0xFFECEFF1), const Color(0xFFB0BEC5)],
          'borderColor': const Color(0xFF90A4AE),
        };
      case 'mighty_season_stats_reset':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFF1565C0),
          'gradient': [const Color(0xFFE1F5FE), const Color(0xFFB3E5FC)],
          'borderColor': const Color(0xFF81D4FA),
        };
    }

    // Fallback by category
    switch (category) {
      case 'banner':
        return {
          'icon': Icons.flag,
          'iconColor': const Color(0xFFB24B5A),
          'gradient': [const Color(0xFFF6C1C9), const Color(0xFFF3E7EA)],
          'borderColor': const Color(0xFFE6DDD8),
        };
      case 'title':
        return {
          'icon': Icons.badge,
          'iconColor': const Color(0xFF6B5CA5),
          'gradient': [const Color(0xFFD9D0F2), const Color(0xFFF1ECFA)],
          'borderColor': const Color(0xFFE6DDD8),
        };
      case 'theme':
        return {
          'icon': Icons.palette,
          'iconColor': const Color(0xFF3A7D5C),
          'gradient': [const Color(0xFFCDEBD8), const Color(0xFFEFF8F2)],
          'borderColor': const Color(0xFFE6DDD8),
        };
      case 'utility':
        return {
          'icon': Icons.handyman,
          'iconColor': const Color(0xFFB46B00),
          'gradient': [const Color(0xFFFFD79E), const Color(0xFFFFF2DF)],
          'borderColor': const Color(0xFFE6DDD8),
        };
      default:
        return {
          'icon': Icons.category,
          'iconColor': const Color(0xFF7A7A7A),
          'gradient': [const Color(0xFFE0E0E0), const Color(0xFFF5F5F5)],
          'borderColor': const Color(0xFFE6DDD8),
        };
    }
  }

  void _maybeShowNicknameChangeResult(BuildContext context, GameService game) {
    final msg = game.nicknameChangeResult;
    if (msg == null) return;
    final ok = game.nicknameChangeSuccess == true;
    game.nicknameChangeResult = null;
    game.nicknameChangeSuccess = null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localizeServiceMessage(msg, L10n.of(context))),
        backgroundColor: ok ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
      ),
    );
  }

  void _maybeShowPurchaseDialog(BuildContext context, GameService game) {
    if (game.lastPurchaseItemKey == null || game.lastPurchaseSuccess != true) {
      return;
    }
    final itemKey = game.lastPurchaseItemKey!;
    final extended = game.lastPurchaseExtended;
    final item = game.shopItems.firstWhere(
      (i) => i['item_key'] == itemKey,
      orElse: () => {},
    );
    game.clearLastPurchaseResult();
    if (item.isEmpty) return;

    final name = _getLocalizedItemName(item);
    final category = item['category']?.toString() ?? '';
    final isPassiveUtility = itemKey.startsWith('top_card_counter')
        || itemKey.startsWith('mighty_trump_counter')
        || itemKey.startsWith('mighty_prev_trick');
    final isConsumable = category == 'utility' && !isPassiveUtility;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(extended ? L10n.of(context).shopExtendComplete : L10n.of(context).shopPurchaseComplete),
        content: Text(
          extended
              ? L10n.of(context).shopExtendDone(name)
              : isConsumable
                  ? L10n.of(context).shopPurchaseDoneConsumable
                  : isPassiveUtility
                      ? L10n.of(context).shopPurchaseDonePassive
                      : L10n.of(context).shopPurchaseDoneEquip,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).commonClose),
          ),
          if (!extended && !isConsumable && !isPassiveUtility)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                game.equipItem(itemKey);
              },
              child: Text(L10n.of(context).shopEquipNow),
            ),
        ],
      ),
    );
  }

  void _maybeShowShopActionResult(BuildContext context, GameService game) {
    if (game.shopActionMessage == null) return;
    final ok = game.shopActionSuccess == true;
    final msg = game.shopActionMessage!;
    game.clearShopActionResult();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
      ),
    );
  }

  void _showItemDetailSheet(BuildContext context, Map<String, dynamic> item) {
    final l10n = L10n.of(context);
    final game = context.read<GameService>();
    final name = _getLocalizedItemName(item);
    final description = _getLocalizedItemDescription(item);
    final price = (item['price'] ?? 0) as int;
    final isSeason = item['is_season'] == true;
    final isPermanent = item['is_permanent'] == true;
    final durationDays = item['duration_days'];
    final category = item['category']?.toString() ?? '';
    final itemKey = item['item_key']?.toString() ?? '';
    final canBuy = game.gold >= price;
    final owned = game.inventoryItems.any((i) => i['item_key'] == itemKey);
    final ownedPermanent = owned && isPermanent;
    final onSale = _isOnSale(item);

    final visual = _resolveThumbnailStyle(itemKey, category, item);
    final gradient = (visual['gradient'] as List<Color>?) ?? [Colors.white, Colors.grey.shade100];
    final iconData = (visual['icon'] as IconData?) ?? Icons.flag;
    final iconColor = (visual['iconColor'] as Color?) ?? const Color(0xFF888888);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtl) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFAF6F2),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              controller: scrollCtl,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8CEC8),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: gradient,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(child: Icon(iconData, color: iconColor, size: 64)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4A3A33))),
                      ),
                      if (ownedPermanent)
                        _badge(l10n.shopItemOwned, const Color(0xFF7E57C2), const Color(0xFFEDE7F6))
                      else if (isSeason)
                        _badge(l10n.shopTagSeason, const Color(0xFF1565C0), const Color(0xFFE3F2FD))
                      else if (onSale)
                        _badge('SALE', const Color(0xFFD32F2F), const Color(0xFFFFEBEE)),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(description,
                        style: const TextStyle(fontSize: 13.5, color: Color(0xFF5A4038), height: 1.5)),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      _chip(_categoryLabel(context, category)),
                      _chip(isPermanent ? l10n.shopDetailPermanent
                          : (durationDays != null ? l10n.shopDetailDuration(durationDays as int) : l10n.shopTagDurationOnly)),
                      if (isSeason) _chip(l10n.shopTagSeason),
                    ],
                  ),
                  if (_saleWindowText(item) != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: onSale ? const Color(0xFFD32F2F) : const Color(0xFF9A8E8A)),
                        const SizedBox(width: 4),
                        Text(
                          '판매기간 ${_saleWindowText(item)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: onSale ? const Color(0xFFD32F2F) : const Color(0xFF9A8E8A),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(Icons.monetization_on, size: 18, color: Color(0xFFF0B400)),
                      const SizedBox(width: 4),
                      Text('$price G',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4A4080))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: ownedPermanent
                          ? null
                          : (canBuy
                              ? () {
                                  Navigator.pop(ctx);
                                  if (owned) {
                                    _showExtendConfirmDialog(context, game, item);
                                  } else {
                                    game.buyItem(itemKey);
                                  }
                                }
                              : null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: owned ? const Color(0xFFBBDEFB) : const Color(0xFFC7E6D0),
                        foregroundColor: owned ? const Color(0xFF1565C0) : const Color(0xFF2E5A3A),
                        disabledBackgroundColor: const Color(0xFFE5E5E5),
                        disabledForegroundColor: const Color(0xFF9A9A9A),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        ownedPermanent
                            ? l10n.shopItemOwned
                            : (owned ? l10n.shopButtonExtend : l10n.shopButtonPurchase),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE7E3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6A5A52), fontWeight: FontWeight.w600)),
    );
  }


  void _showNicknameChangeDialog(BuildContext context, GameService game) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(L10n.of(context).shopNicknameChangeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L10n.of(context).shopNicknameChangeDesc,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6A5A52)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 10,
              decoration: InputDecoration(
                hintText: L10n.of(context).shopNicknameChangeHint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              final nick = controller.text.trim();
              if (nick.length < 2 || nick.length > 10) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(L10n.of(context).shopNicknameChangeValidation)),
                );
                return;
              }
              Navigator.pop(ctx);
              game.changeNickname(nick);
            },
            child: Text(L10n.of(context).shopNicknameChangeButton),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(BuildContext context, String category) {
    final l10n = L10n.of(context);
    switch (category) {
      case 'banner':
        return l10n.shopDetailCategoryBanner;
      case 'title':
        return l10n.shopDetailCategoryTitle;
      case 'theme':
        return l10n.shopDetailCategoryThemeSkin;
      case 'utility':
        return l10n.shopDetailCategoryUtility;
      default:
        return l10n.shopDetailCategoryItem;
    }
  }

  Widget _buildCategoryTabs(List<String> labels) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        isScrollable: true,
        labelColor: const Color(0xFF5A4038),
        unselectedLabelColor: const Color(0xFF9A8E8A),
        indicatorColor: const Color(0xFFB9A8A1),
        tabs: labels.map((t) => Tab(text: t)).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _filterShop(
    List<Map<String, dynamic>> items,
    String category,
  ) {
    if (category == 'all') return items;
    return items.where((i) => (i['category']?.toString() ?? '') == category).toList();
  }

  List<Map<String, dynamic>> _filterInventory(
    List<Map<String, dynamic>> items,
    String category,
  ) {
    if (category == 'all') return items;
    if (category == 'season') {
      return items.where((i) => i['is_season'] == true).toList();
    }
    return items.where((i) => (i['category']?.toString() ?? '') == category).toList();
  }

  String _buildItemTag(BuildContext context, bool isSeason, bool isPermanent, dynamic durationDays) {
    final l10n = L10n.of(context);
    if (isSeason) {
      return l10n.shopTagSeason;
    }
    if (isPermanent) {
      return l10n.shopTagPermanent;
    }
    if (durationDays != null) {
      return l10n.shopTagDuration(durationDays as int);
    }
    return l10n.shopTagDurationOnly;
  }

  String _formatExpire(BuildContext context, dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return L10n.of(context).shopExpireDate('${dt.year}.${dt.month}.${dt.day}');
    } catch (_) {
      return L10n.of(context).shopExpireSoon;
    }
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

  Widget _buildAdRewardButton(GameService game) {
    final canWatch = _todayAdCount < AdService.maxDailyRewards;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton.icon(
          onPressed: (canWatch && !_adLoading)
              ? () {
                  final ad = _rewardedAd;
                  if (ad == null) return;
                  setState(() {
                    _adLoading = true;
                    _rewardedAd = null;
                    _rewardedAdReady = false;
                  });
                  ad.fullScreenContentCallback = FullScreenContentCallback(
                    onAdDismissedFullScreenContent: (ad) {
                      ad.dispose();
                      _preloadRewardedAd(); // 다음 광고 미리 로드
                    },
                    onAdFailedToShowFullScreenContent: (ad, error) {
                      ad.dispose();
                      if (mounted) {
                        setState(() => _adLoading = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(L10n.of(context).shopAdCannotShow)),
                        );
                      }
                      _preloadRewardedAd();
                    },
                  );
                  ad.show(
                    onUserEarnedReward: (ad, reward) async {
                      await AdService.incrementRewardCount();
                      game.claimAdReward();
                      await _loadAdCount();
                      if (mounted) setState(() => _adLoading = false);
                    },
                  );
                }
              : null,
          icon: _adLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.play_circle_fill, size: 20),
          label: Text(
            canWatch
                ? L10n.of(context).shopAdWatchForGold(_todayAdCount, AdService.maxDailyRewards)
                : L10n.of(context).shopAdRewardDone,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: canWatch ? const Color(0xFF7E57C2) : Colors.grey,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  void _maybeShowAdRewardResult(BuildContext context, GameService game) {
    final msg = game.adRewardResult;
    if (msg == null) return;
    game.adRewardResult = null;
    final success = game.adRewardSuccess == true;
    game.adRewardSuccess = null;
    final l10n = L10n.of(context);
    final displayMsg = (msg == 'ad_reward_success')
        ? localizeAdRewardSuccess(game.adRewardRemaining, l10n)
        : localizeServiceMessage(msg, l10n);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(displayMsg),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }
}
