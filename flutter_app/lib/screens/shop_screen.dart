import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../models/shop_visual.dart';
import '../services/game_service.dart';
import '../services/ad_service.dart';
import '../widgets/level_badge.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/title_chip.dart';
import '../widgets/gold_icon.dart';
import 'gold_shop_screen.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _inventoryTabController = ValueNotifier<int>(0);
  // Item keys with an in-flight use/equip action, to disable the button and
  // block rapid double-taps (a consumable could otherwise be spent twice).
  final Set<String> _busyItemKeys = {};
  int _todayAdCount = 0;
  bool _adLoading = false;
  RewardedAd? _rewardedAd;
  bool _rewardedAdReady = false;
  // Attendance has its OWN rewarded ad unit (separate AdMob slot) so it
  // doesn't fight the "ad reward gold" button for a single ad instance.
  RewardedAd? _attendanceAd;
  // ValueNotifier (not a plain bool) so the attendance DIALOG — a separate
  // route that won't rebuild on the ShopScreen's setState — can react to the ad
  // becoming ready and enable its claim button via a ValueListenableBuilder.
  final ValueNotifier<bool> _attendanceAdReady = ValueNotifier(false);
  bool _attendanceAdLoadInFlight = false;
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
    _preloadAttendanceAd();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final game = context.read<GameService>();
      game.requestWallet();
      game.requestShopItems();
      game.requestInventory();
      // Pull own profile so the banner preview can show the real level badge
      // (falls back to Lv.1 when not yet cached).
      if (game.playerName.isNotEmpty) {
        game.requestProfile(game.playerName);
      }
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

  // Dedicated attendance rewarded ad. Separate AdMob slot from the "ad
  // reward gold" rewardedAdId so the two features don't race for one ad
  // instance and we can read attendance-specific impression / revenue
  // numbers in AdMob.
  void _preloadAttendanceAd() {
    if (_attendanceAdLoadInFlight || _attendanceAd != null) return;
    _attendanceAdLoadInFlight = true;
    RewardedAd.load(
      adUnitId: AdService.attendanceRewardedAdId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _attendanceAdLoadInFlight = false;
          if (!mounted) {
            ad.dispose();
            return;
          }
          _attendanceAd = ad;
          _attendanceAdReady.value = true; // enables the dialog claim button
        },
        onAdFailedToLoad: (error) {
          debugPrint(
            '[AdService] Attendance rewarded FAILED: ${error.message}',
          );
          _attendanceAdLoadInFlight = false;
          // The screen may have been disposed (which disposes the notifier)
          // before a late load-failure arrives — don't touch it then.
          if (!mounted) return;
          _attendanceAdReady.value = false;
          // Keep retrying so the (disabled) claim button eventually enables.
          // Backoff avoids hammering AdMob on a persistent no-fill.
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted && _attendanceAd == null) _preloadAttendanceAd();
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _inventoryTabs?.removeListener(_handleInventoryTabChanged);
    _rewardedAd?.dispose();
    _attendanceAd?.dispose();
    _attendanceAdReady.dispose();
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
                  // Header and wallet are one flat bar, the two reward actions
                  // are one short strip, and everything below is a single sheet.
                  // Before this the screen was six stacked white cards with the
                  // item list squeezed into what was left — under half the
                  // screen on a phone.
                  return Column(
                    children: [
                      _buildTopBar(context, game),
                      _buildRewardStrip(game),
                      Expanded(child: _buildContentSheet(game)),
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

  /// Header, wallet and the gold-charge action in one flat row.
  ///
  /// Was two stacked rounded cards (title card, then wallet card), which cost
  /// ~150px of height and read as two unrelated things.
  Widget _buildTopBar(BuildContext context, GameService game) {
    final l10n = L10n.of(context);
    // Transparent: the theme gradient runs behind the header and the white
    // starts at the sheet, so the top of the screen is one colour instead of a
    // white band pasted over it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                color: const Color(0xFF8A7A72),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                l10n.shopTitle,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFE57373),
                size: 16,
              ),
              const SizedBox(width: 3),
              Text(
                l10n.shopDesertionCount(game.leaveCount),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9A6A6A),
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: () {
                  game.requestWallet();
                  game.requestShopItems();
                  game.requestInventory();
                },
                icon: const Icon(Icons.refresh, size: 20),
                color: const Color(0xFF8A7A72),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showGoldHistoryDialog(game),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GoldIcon(size: 20, amount: game.gold),
                          const SizedBox(width: 6),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n.shopGoldAmount(game.gold),
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF5A4038),
                                ),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Color(0xFFB89C76),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GoldShopScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE9B0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_circle,
                          size: 15,
                          color: Color(0xFFB07A12),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          l10n.shopChargeGold,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB07A12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The two daily rewards as one short strip.
  ///
  /// They used to be two full-width blocks stacked on top of each other — a
  /// gradient attendance banner and a purple ad button — about 110px before the
  /// tabs even started. Side by side they cost one 46px row.
  Widget _buildRewardStrip(GameService game) {
    final hasAttendance = _shouldShowAttendanceBanner(game);
    if (!hasAttendance && !_rewardedAdReady) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          if (hasAttendance) Expanded(child: _buildAttendanceTile(game)),
          if (hasAttendance && _rewardedAdReady) const SizedBox(width: 8),
          if (_rewardedAdReady) Expanded(child: _buildAdRewardTile(game)),
        ],
      ),
    );
  }

  /// Shared shape for the two reward tiles so they read as one pair.
  Widget _buildRewardTile({
    required List<Color> gradient,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Widget? leadingOverride,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            leadingOverride ?? Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// White rounded sheet holding the tabs and the item list.
  ///
  /// The list gets everything below the header: one surface instead of a tab
  /// card, a category card and a card per item.
  Widget _buildContentSheet(GameService game) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFDFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildTabs(),
          Expanded(
            child: TabBarView(
              children: [_buildShopTab(game), _buildInventoryTab(game)],
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
                          child: const Center(child: GoldIcon(size: 24)),
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
                                localizeServiceMessage(
                                  game.goldHistoryError!,
                                  L10n.of(context),
                                ),
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
                              final delta =
                                  (item['goldDelta'] as num?)?.toInt() ?? 0;
                              final positive = delta >= 0;
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE6DEDA),
                                  ),
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
                                        positive
                                            ? Icons.south_west
                                            : Icons.north_east,
                                        color: positive
                                            ? const Color(0xFF43A047)
                                            : const Color(0xFFFB8C00),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            localizeGoldTitle(
                                              item['title']?.toString(),
                                              item['source']?.toString(),
                                              L10n.of(context),
                                              Localizations.localeOf(
                                                context,
                                              ).languageCode,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF5A4038),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            localizeGoldDescription(
                                              item['description']?.toString(),
                                              item['source']?.toString(),
                                              L10n.of(context),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF8A7A72),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _formatHistoryDate(
                                              item['createdAt'],
                                            ),
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
                    const SizedBox(height: 14),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _showGoldGuideDialog,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF6E7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF0D6A6)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 18,
                              color: Color(0xFFB67C1D),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                L10n.of(context).shopHowToEarn,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8B6220),
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: Color(0xFFB89C76),
                            ),
                          ],
                        ),
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
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 28,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
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
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(child: GoldIcon(size: 24)),
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEFE7E3))),
      ),
      child: TabBar(
        labelColor: const Color(0xFF5A4038),
        unselectedLabelColor: const Color(0xFF9A8E8A),
        indicatorColor: const Color(0xFF7E57C2),
        indicatorWeight: 2.5,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
        tabs: [
          Tab(height: 42, text: L10n.of(context).shopTabShop),
          Tab(height: 42, text: L10n.of(context).shopTabInventory),
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
      length: 5,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildCategoryTabs([
            L10n.of(context).shopCategoryBanner,
            L10n.of(context).shopCategoryTitle,
            L10n.of(context).shopCategoryTheme,
            L10n.of(context).shopCategoryUtil,
            L10n.of(context).shopCategoryFeature,
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _buildShopList(
                  context,
                  game,
                  _filterShop(game.shopItems, 'banner'),
                ),
                _buildShopList(
                  context,
                  game,
                  _filterShop(game.shopItems, 'title'),
                ),
                _buildShopList(
                  context,
                  game,
                  _filterShop(game.shopItems, 'theme'),
                ),
                _buildShopList(
                  context,
                  game,
                  _filterShop(game.shopItems, 'utility'),
                ),
                _buildShopList(
                  context,
                  game,
                  _filterShop(game.shopItems, 'feature'),
                ),
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
    // Group duration tiers of one feature (same effect_type) into a single
    // card so "마이티 기루다 카운터(7일)" and "(30일)" don't read as two separate
    // near-identical items. Items without an effect_type (banners/titles/…)
    // stay as their own single-item groups. First-appearance order preserved.
    final groups = <List<Map<String, dynamic>>>[];
    final indexByEffect = <String, int>{};
    for (final item in items) {
      final et = item['effect_type']?.toString() ?? '';
      final dur = (item['duration_days'] as num?)?.toInt() ?? 0;
      // Only merge true DURATION tiers (same effect_type + a duration) into one
      // card. Consumables that share an effect_type but have no duration
      // (e.g. 탈주 카운트 -1 / -3) must stay as separate rows, else the tier
      // chips render blank.
      if (et.isEmpty || dur <= 0) {
        groups.add([item]);
        continue;
      }
      final existing = indexByEffect[et];
      if (existing != null) {
        groups[existing].add(item);
      } else {
        indexByEffect[et] = groups.length;
        groups.add([item]);
      }
    }
    for (final g in groups) {
      if (g.length > 1) {
        g.sort(
          (a, b) => ((a['duration_days'] as num?)?.toInt() ?? 0).compareTo(
            (b['duration_days'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }
    // Cluster by game/theme so utility items read as groups (티츄끼리, 마이티끼리,
    // 탈주끼리, …). Stable: ties keep first-appearance order, so single-theme
    // tabs (banner/title/theme) are left exactly as-is.
    final ordered = List<List<Map<String, dynamic>>>.from(groups);
    final origIndex = {for (var i = 0; i < groups.length; i++) groups[i]: i};
    ordered.sort((a, b) {
      final r = _themeRank(
        a.first['item_key']?.toString() ?? '',
      ).compareTo(_themeRank(b.first['item_key']?.toString() ?? ''));
      return r != 0 ? r : origIndex[a]!.compareTo(origIndex[b]!);
    });
    // Hairline separators, not gaps between cards: on the sheet these read as
    // one list, and dropping the per-item border + margin fits ~2 more rows on
    // a phone screen.
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: Color(0xFFF2ECE9),
      ),
      itemBuilder: (context, index) {
        final g = ordered[index];
        return g.length == 1
            ? _buildShopRow(context, game, g.first)
            : _buildGroupedFeatureCard(context, game, g);
      },
    );
  }

  // Theme rank for shop ordering: groups same-game/same-purpose items together.
  // Only meaningful in the utility tab (mixed themes); other categories all
  // fall through to the same bucket and keep their order via the stable tiebreak.
  int _themeRank(String key) {
    // 티츄
    if (key.startsWith('top_card_counter') || key.startsWith('tichu_')) {
      return 0;
    }
    if (key.startsWith('mighty_')) return 1; // 마이티
    if (key.startsWith('sk_')) return 2; // 스컬킹
    if (key.startsWith('leave_')) return 3; // 탈주
    return 4; // 기타(닉네임 변경, 전체 전적/시즌 초기화 등)
  }

  // Base feature name without the trailing "(7일)/(30일)" duration suffix the
  // server bakes into each tier's localized name.
  String _stripDurationSuffix(String name) =>
      name.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();

  // A single card representing one feature with multiple duration tiers. The
  // name/visual show once; the tier chips and the row itself all open the same
  // sheet, which is where both durations can be bought or extended.
  Widget _buildGroupedFeatureCard(
    BuildContext context,
    GameService game,
    List<Map<String, dynamic>> tiers,
  ) {
    final first = tiers.first;
    final baseName = _stripDurationSuffix(_getLocalizedItemName(first));
    Map<String, dynamic>? ownedInv;
    for (final t in tiers) {
      ownedInv = _ownedEntitlement(game, t);
      if (ownedInv != null) break;
    }
    final ownedActive = ownedInv != null;
    final ownedExpiry = ownedInv?['expires_at'];
    final ownedExpiryText = ownedExpiry != null
        ? _formatExpire(context, ownedExpiry)
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Anywhere on the row, not only the chips: a row you cannot tap to read
        // about is a dead end, and the chips are small targets.
        onTap: () => _showItemDetailSheet(context, first, tiers: tiers),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildShopRowVisual(first, 58),
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
                            baseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4A3A33),
                            ),
                          ),
                        ),
                        if (ownedActive)
                          _badge(
                            L10n.of(context).shopItemOwned,
                            const Color(0xFF7E57C2),
                            const Color(0xFFEDE7F6),
                          ),
                      ],
                    ),
                    if (ownedExpiryText != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 12,
                            color: Color(0xFF7E57C2),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            ownedExpiryText,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7E57C2),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: tiers
                          .map((t) => _buildTierChip(context, t, tiers))
                          .toList(),
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

  // Duration option chip: "7일 · 1000골드". Reuses the server-localized "(7일)"
  // suffix so no new duration strings are needed. Tap -> detail sheet for that
  // exact tier.
  Widget _buildTierChip(
    BuildContext context,
    Map<String, dynamic> tier,
    List<Map<String, dynamic>> tiers,
  ) {
    final name = _getLocalizedItemName(tier);
    final match = RegExp(r'\(([^)]*)\)\s*$').firstMatch(name);
    final durationLabel = match != null
        ? match.group(1)!
        : '${tier['duration_days'] ?? ''}';
    final price = tier['price'] ?? 0;
    final onSale = _isOnSale(tier);
    return Material(
      color: onSale ? const Color(0xFFFFF3F3) : const Color(0xFFF4F1FB),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        // Same sheet as the row: it carries both durations, so which chip was
        // tapped no longer decides what can be bought.
        onTap: () => _showItemDetailSheet(context, tier, tiers: tiers),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                durationLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5A4A80),
                ),
              ),
              const SizedBox(width: 6),
              GoldIcon(size: 13, amount: price is int ? price : null),
              const SizedBox(width: 2),
              Text(
                '$price',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: onSale
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFF4A4080),
                ),
              ),
            ],
          ),
        ),
      ),
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
    final price = item['price'] ?? 0;
    final isSeason = item['is_season'] == true;
    final isPermanent = item['is_permanent'] == true;
    final durationDays = item['duration_days'];
    final itemKey = item['item_key']?.toString() ?? '';
    // Titles, themes and banners are all duration items, so keying the owned
    // state off isPermanent hid it for every one of them: you could hold a
    // title and the shop would still look like you had never bought it, with
    // no expiry anywhere. Read the inventory row itself.
    final ownedMatches = game.inventoryItems.where(
      (i) => i['item_key'] == itemKey,
    );
    final ownedInv = ownedMatches.isEmpty ? null : ownedMatches.first;
    final owned = ownedInv != null;
    final ownedPermanent = owned && isPermanent;
    final ownedExpiry = ownedInv?['expires_at'];
    final ownedExpiryText = ownedExpiry != null
        ? _formatExpire(context, ownedExpiry)
        : null;
    final onSale = _isOnSale(item);
    final saleWindow = _saleWindowText(item);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showItemDetailSheet(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildShopRowVisual(item, 58),
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4A3A33),
                            ),
                          ),
                        ),
                        if (isSeason)
                          _badge(
                            l10n.shopTagSeason,
                            const Color(0xFF1565C0),
                            const Color(0xFFE3F2FD),
                          )
                        else if (owned)
                          _badge(
                            l10n.shopItemOwned,
                            const Color(0xFF7E57C2),
                            const Color(0xFFEDE7F6),
                          )
                        else if (onSale)
                          _badge(
                            'SALE',
                            const Color(0xFFD32F2F),
                            const Color(0xFFFFEBEE),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // What it is, not what it does: the list stays scannable at
                    // one line per item and the description — which can run to
                    // several sentences — belongs to the sheet the row opens.
                    Text(
                      _buildItemTag(
                        context,
                        isSeason,
                        isPermanent,
                        durationDays,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF8A7A72),
                        height: 1.3,
                      ),
                    ),
                    // Same treatment the grouped feature card gives: holding
                    // something is only useful information if you can also see
                    // until when.
                    if (ownedExpiryText != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 12,
                            color: Color(0xFF7E57C2),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            ownedExpiryText,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7E57C2),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Bottom row: gold price on the left, sale window on the
                    // right (replaces the inline buy button — purchasing now
                    // happens in the detail sheet so it's an explicit choice).
                    Row(
                      children: [
                        if (!ownedPermanent) ...[
                          GoldIcon(
                            size: 15,
                            amount: price is int ? price : null,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$price',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4A4080),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (saleWindow != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 12,
                                color: onSale
                                    ? const Color(0xFFD32F2F)
                                    : const Color(0xFF9A8E8A),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                saleWindow,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: onSale
                                      ? const Color(0xFFD32F2F)
                                      : const Color(0xFF9A8E8A),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFFB0A8A2),
              ),
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
    final gradient =
        (visual['gradient'] as List<Color>?) ??
        [Colors.white, Colors.grey.shade100];
    final iconData = (visual['icon'] as IconData?) ?? Icons.flag;
    final iconColor =
        (visual['iconColor'] as Color?) ?? const Color(0xFF888888);
    final borderColor =
        (visual['borderColor'] as Color?) ?? const Color(0xFFE0D8D4);
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
      child: Center(
        child: Icon(iconData, color: iconColor, size: size * 0.45),
      ),
    );
  }

  Widget _badge(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }

  void _showExtendConfirmDialog(
    BuildContext context,
    GameService game,
    Map<String, dynamic> item,
  ) {
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
          L10n.of(
            context,
          ).shopExtendConfirm(name, durationDays as int, price as int),
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
      // 6 with 기능: a purchased feature item (profile photo) has a category the
      // inventory had no tab for, so it was owned and invisible here.
      length: 6,
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
                L10n.of(context).shopCategoryFeature,
                L10n.of(context).shopCategorySeason,
              ]),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildInventoryList(
                      _filterInventory(game.inventoryItems, 'banner'),
                    ),
                    _buildInventoryList(
                      _filterInventory(game.inventoryItems, 'title'),
                    ),
                    _buildInventoryList(
                      _filterInventory(game.inventoryItems, 'theme'),
                    ),
                    _buildInventoryList(
                      _filterInventory(game.inventoryItems, 'utility'),
                    ),
                    _buildInventoryList(
                      _filterInventory(game.inventoryItems, 'feature'),
                    ),
                    _buildInventoryList(
                      _filterInventory(game.inventoryItems, 'season'),
                    ),
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
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: Color(0xFFF2ECE9),
      ),
      itemBuilder: (context, index) =>
          _buildInventoryItem(context, items[index]),
    );
  }

  Widget _buildInventoryItem(BuildContext context, Map<String, dynamic> item) {
    final l10n = L10n.of(context);
    final game = context.read<GameService>();
    final name = _getLocalizedItemName(item);
    final category = item['category']?.toString() ?? '';
    final isActive = item['is_active'] == true;
    final itemKey = item['item_key']?.toString() ?? '';
    final effectType = item['effect_type']?.toString() ?? '';
    // Nothing to equip or use: these are simply on while they last. Profile
    // photo belongs here too — the picture itself is set from the profile
    // screen, so an "equip" button on this row would do nothing at all.
    final noEquipAction =
        itemKey.startsWith('top_card_counter') ||
        itemKey.startsWith('mighty_trump_counter') ||
        itemKey.startsWith('mighty_prev_trick') ||
        effectType == 'profile_photo' ||
        effectType == 'profile_private';
    final isConsumable = category == 'utility' && !noEquipAction;
    final expiresAt = item['expires_at'];
    final expiresText = expiresAt != null
        ? _formatExpire(context, expiresAt)
        : null;
    final equipped = isActive && !noEquipAction;

    return Material(
      // Equipped is now a tinted row with a left accent bar instead of a blue
      // card outline — there are no cards left to outline.
      color: equipped ? const Color(0xFFF3F8FD) : Colors.transparent,
      child: InkWell(
        onTap: () => _showItemDetailSheet(context, item),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: equipped ? const Color(0xFF5C9DD6) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildShopRowVisual(item, 58),
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4A3A33),
                            ),
                          ),
                        ),
                        if (equipped)
                          _badge(
                            l10n.shopStatusInUse,
                            const Color(0xFF1565C0),
                            const Color(0xFFDDECF7),
                          )
                        else if (noEquipAction)
                          _badge(
                            l10n.shopStatusActivated,
                            const Color(0xFF1565C0),
                            const Color(0xFFDDECF7),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      expiresText ?? l10n.shopPermanentOwned,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF8A7A72),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Spacer(),
                        if (!noEquipAction)
                          SizedBox(
                            height: 30,
                            child: ElevatedButton(
                              onPressed: _busyItemKeys.contains(itemKey)
                                  ? null
                                  : () {
                                      if (effectType == 'nickname_change') {
                                        _showNicknameChangeDialog(
                                          context,
                                          game,
                                        );
                                      } else if (isConsumable) {
                                        _runItemAction(
                                          itemKey,
                                          () => game.useItem(itemKey),
                                        );
                                      } else {
                                        _runItemAction(
                                          itemKey,
                                          () => game.equipItem(itemKey),
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isConsumable
                                    ? const Color(0xFFFFE0B2)
                                    : (equipped
                                          ? const Color(0xFFE3F2FD)
                                          : const Color(0xFFB3E5FC)),
                                foregroundColor: const Color(0xFF4A3A33),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: _busyItemKeys.contains(itemKey)
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF4A3A33),
                                      ),
                                    )
                                  : Text(
                                      isConsumable
                                          ? l10n.shopButtonUse
                                          : l10n.shopButtonEquip,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
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

  // Run a use/equip action with a short busy window so a double-tap can't fire
  // it twice before the server round-trip lands (the item list rebuilds on the
  // result, which clears any stale busy state via the delayed removal below).
  void _runItemAction(String itemKey, VoidCallback action) {
    if (_busyItemKeys.contains(itemKey)) return;
    setState(() => _busyItemKeys.add(itemKey));
    action();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _busyItemKeys.remove(itemKey));
    });
  }

  // Fallback chain: server-driven visual (admin-editable) → legacy hardcoded
  // switch (kept so v2.3.0+26 items still render even if a backfill row is
  // missing) → category default.
  Map<String, Object> _resolveThumbnailStyle(
    String itemKey,
    String category,
    Map<String, dynamic>? item,
  ) {
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
      // Feature items: 'feature' has no category fallback of its own, so both
      // tiers of each are named here rather than falling through to the grey
      // "category" box.
      case 'profile_photo_7d':
      case 'profile_photo_30d':
        return {
          'icon': Icons.account_circle,
          'iconColor': const Color(0xFF5C6BC0),
          'gradient': [const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)],
          'borderColor': const Color(0xFF9FA8DA),
        };
      case 'profile_private_7d':
      case 'profile_private_30d':
        return {
          'icon': Icons.lock_rounded,
          'iconColor': const Color(0xFF7E57C2),
          'gradient': [const Color(0xFFF3E5F5), const Color(0xFFD1C4E9)],
          'borderColor': const Color(0xFFB39DDB),
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
    // Same rule as the inventory row: offering "equip now" for a profile photo
    // would hand the user a button that does nothing.
    final noEquipAction =
        itemKey.startsWith('top_card_counter') ||
        itemKey.startsWith('mighty_trump_counter') ||
        itemKey.startsWith('mighty_prev_trick') ||
        item['effect_type']?.toString() == 'profile_photo' ||
        item['effect_type']?.toString() == 'profile_private';
    final isConsumable = category == 'utility' && !noEquipAction;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          extended
              ? L10n.of(context).shopExtendComplete
              : L10n.of(context).shopPurchaseComplete,
        ),
        content: Text(
          extended
              ? L10n.of(context).shopExtendDone(name)
              : isConsumable
              ? L10n.of(context).shopPurchaseDoneConsumable
              : noEquipAction
              ? L10n.of(context).shopPurchaseDonePassive
              : L10n.of(context).shopPurchaseDoneEquip,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).commonClose),
          ),
          if (!extended && !isConsumable && !noEquipAction)
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

  /// Detail for one item, or for one feature sold in duration tiers.
  ///
  /// [tiers] is the whole group (7d + 30d). They share one entitlement on the
  /// server — buying either extends the same expiry — so the sheet shows the
  /// feature once and offers every tier as its own button. Before this, opening
  /// the 7-day row while holding the 30-day one said "구매" and the other way
  /// round said "연장": ownership was read per item_key, which is not what the
  /// server does.
  void _showItemDetailSheet(
    BuildContext context,
    Map<String, dynamic> item, {
    List<Map<String, dynamic>>? tiers,
  }) {
    final l10n = L10n.of(context);
    final game = context.read<GameService>();
    final tierList = (tiers != null && tiers.length > 1) ? tiers : null;
    final name = tierList != null
        ? _stripDurationSuffix(_getLocalizedItemName(item))
        : _getLocalizedItemName(item);
    // The only place the description is shown — the list rows deliberately
    // don't carry it.
    final description = _getLocalizedItemDescription(item);
    final price = (item['price'] ?? 0) as int;
    final isSeason = item['is_season'] == true;
    final isPermanent = item['is_permanent'] == true;
    final durationDays = item['duration_days'];
    final category = item['category']?.toString() ?? '';
    final itemKey = item['item_key']?.toString() ?? '';
    final canBuy = game.gold >= price;
    final ownedInv = _ownedEntitlement(game, item);
    final owned = ownedInv != null;
    final ownedPermanent = owned && isPermanent;
    final ownedExpiry = ownedInv?['expires_at'];
    final ownedExpiryText = ownedExpiry != null
        ? _formatExpire(context, ownedExpiry)
        : null;
    final onSale = _isOnSale(item);

    final visual = _resolveThumbnailStyle(itemKey, category, item);
    final gradient =
        (visual['gradient'] as List<Color>?) ??
        [Colors.white, Colors.grey.shade100];
    final iconData = (visual['icon'] as IconData?) ?? Icons.flag;
    final iconColor =
        (visual['iconColor'] as Color?) ?? const Color(0xFF888888);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtl) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFAF6F2),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            // Price and CTA are pinned below the scroll area. Inside it they sat
            // past the fold at the sheet's initial height, so the buy button was
            // only reachable by dragging the sheet up first — and the last of it
            // hid behind the navigation bar.
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollCtl,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
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
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gradient,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Icon(iconData, color: iconColor, size: 64),
                          ),
                        ),
                        // Cosmetics are bought on how they look, so show the
                        // thing itself applied: a banner and a title on a
                        // waiting-room seat, a theme as the screen behind it.
                        if (_hasPreview(category, effectTypeOf(item))) ...[
                          const SizedBox(height: 14),
                          Text(
                            l10n.shopPreviewLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A7A72),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Consumer, so a profile fetch that lands while the
                          // sheet is open fills in the level and photo without
                          // the user having to reopen it.
                          Consumer<GameService>(
                            builder: (_, g, _) => _buildItemPreview(
                              g,
                              category: category,
                              effectType: effectTypeOf(item),
                              itemKey: itemKey,
                              itemName: name,
                              fallbackGradient: gradient,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4A3A33),
                                ),
                              ),
                            ),
                            if (isSeason)
                              _badge(
                                l10n.shopTagSeason,
                                const Color(0xFF1565C0),
                                const Color(0xFFE3F2FD),
                              )
                            else if (owned)
                              _badge(
                                l10n.shopItemOwned,
                                const Color(0xFF7E57C2),
                                const Color(0xFFEDE7F6),
                              )
                            else if (onSale)
                              _badge(
                                'SALE',
                                const Color(0xFFD32F2F),
                                const Color(0xFFFFEBEE),
                              ),
                          ],
                        ),
                        if (ownedExpiryText != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.schedule,
                                size: 13,
                                color: Color(0xFF7E57C2),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ownedExpiryText,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF7E57C2),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            description,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF5A4038),
                              height: 1.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _chip(_categoryLabel(context, category)),
                            _chip(
                              isPermanent
                                  ? l10n.shopDetailPermanent
                                  : (durationDays != null
                                        ? l10n.shopDetailDuration(
                                            durationDays as int,
                                          )
                                        : l10n.shopTagDurationOnly),
                            ),
                            if (isSeason) _chip(l10n.shopTagSeason),
                          ],
                        ),
                        if (_saleWindowText(item) != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: onSale
                                    ? const Color(0xFFD32F2F)
                                    : const Color(0xFF9A8E8A),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '판매기간 ${_saleWindowText(item)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: onSale
                                      ? const Color(0xFFD32F2F)
                                      : const Color(0xFF9A8E8A),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    12 + MediaQuery.viewPaddingOf(ctx).bottom,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFAF6F2),
                    border: Border(top: BorderSide(color: Color(0xFFEDE4DE))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tierList == null)
                        Row(
                          children: [
                            GoldIcon(size: 19, amount: price),
                            const SizedBox(width: 4),
                            Text(
                              '$price G',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4A4080),
                              ),
                            ),
                          ],
                        ),
                      if (tierList == null) const SizedBox(height: 10),
                      if (tierList != null)
                        Row(
                          children: [
                            for (var i = 0; i < tierList.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: _buildTierActionButton(
                                  ctx,
                                  game,
                                  tierList[i],
                                  extend: owned,
                                ),
                              ),
                            ],
                          ],
                        )
                      else
                        Builder(
                          builder: (_) {
                            // Season banners are reward-only — once owned, they can
                            // not be re-purchased or extended through the shop. Treat
                            // owned-season the same as owned-permanent here.
                            final lockedAsOwned =
                                ownedPermanent || (isSeason && owned);
                            return SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton(
                                onPressed: lockedAsOwned
                                    ? null
                                    : (canBuy
                                          ? () {
                                              Navigator.pop(ctx);
                                              if (owned) {
                                                _showExtendConfirmDialog(
                                                  context,
                                                  game,
                                                  item,
                                                );
                                              } else {
                                                game.buyItem(itemKey);
                                              }
                                            }
                                          : null),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: owned
                                      ? const Color(0xFFBBDEFB)
                                      : const Color(0xFFC7E6D0),
                                  foregroundColor: owned
                                      ? const Color(0xFF1565C0)
                                      : const Color(0xFF2E5A3A),
                                  disabledBackgroundColor: const Color(
                                    0xFFE5E5E5,
                                  ),
                                  disabledForegroundColor: const Color(
                                    0xFF9A9A9A,
                                  ),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  lockedAsOwned
                                      ? l10n.shopItemOwned
                                      : (owned
                                            ? l10n.shopButtonExtend
                                            : l10n.shopButtonPurchase),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The inventory row that makes this item "owned".
  ///
  /// Matched by effect_type when the item has one, because that is how the
  /// server grants and extends these: the 7-day and 30-day rows of one feature
  /// are the same entitlement.
  Map<String, dynamic>? _ownedEntitlement(
    GameService game,
    Map<String, dynamic> item,
  ) {
    final itemKey = item['item_key']?.toString() ?? '';
    final effectType = item['effect_type']?.toString() ?? '';
    final byKey = game.inventoryItems.where((i) => i['item_key'] == itemKey);
    if (byKey.isNotEmpty) return byKey.first;
    if (effectType.isEmpty) return null;
    final byEffect = game.inventoryItems.where(
      (i) => (i['effect_type']?.toString() ?? '') == effectType,
    );
    return byEffect.isEmpty ? null : byEffect.first;
  }

  /// One duration tier as a buy/extend button: "7일 · 1000 구매".
  Widget _buildTierActionButton(
    BuildContext sheetCtx,
    GameService game,
    Map<String, dynamic> tier, {
    required bool extend,
  }) {
    final l10n = L10n.of(sheetCtx);
    final price = (tier['price'] ?? 0) as int;
    final tierKey = tier['item_key']?.toString() ?? '';
    final canBuy = game.gold >= price;
    final name = _getLocalizedItemName(tier);
    final match = RegExp(r'\(([^)]*)\)\s*$').firstMatch(name);
    final durationLabel = match != null
        ? match.group(1)!
        : '${tier['duration_days'] ?? ''}';
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: canBuy
            ? () {
                Navigator.pop(sheetCtx);
                if (extend) {
                  _showExtendConfirmDialog(context, game, tier);
                } else {
                  game.buyItem(tierKey);
                }
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: extend
              ? const Color(0xFFBBDEFB)
              : const Color(0xFFC7E6D0),
          foregroundColor: extend
              ? const Color(0xFF1565C0)
              : const Color(0xFF2E5A3A),
          disabledBackgroundColor: const Color(0xFFE5E5E5),
          disabledForegroundColor: const Color(0xFF9A9A9A),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              durationLabel,
              maxLines: 1,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GoldIcon(size: 14, amount: price),
                  const SizedBox(width: 3),
                  Text(
                    '$price',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    extend ? l10n.shopButtonExtend : l10n.shopButtonPurchase,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The player's own equipped banner/title, read off their profile — the
  /// service tracks the title key but not its display name or the banner.
  String? _myBannerKey(GameService g) =>
      _myProfile(g)?['bannerKey']?.toString();

  String? _myTitleName(GameService g) =>
      _myProfile(g)?['titleName']?.toString();

  Map? _myProfile(GameService g) {
    if (g.playerName.isEmpty) return null;
    return g.profileFor(g.playerName)?['profile'] as Map?;
  }

  String effectTypeOf(Map<String, dynamic> item) =>
      item['effect_type']?.toString() ?? '';

  static const _previewEffects = {
    'top_card_counter',
    'mighty_trump_counter',
    'mighty_prev_trick',
  };

  bool _hasPreview(String category, String effectType) =>
      category == 'banner' ||
      category == 'title' ||
      category == 'theme' ||
      _previewEffects.contains(effectType);

  /// What the in-game aid actually looks like on screen.
  ///
  /// A counter is bought sight unseen otherwise: the description says it counts
  /// something, but not that it is a small chip in the corner of the board. This
  /// mirrors the real widgets (game_screen's top-card counter, mighty's trump
  /// chip) with sample numbers.
  Widget _buildFeaturePreview(String effectType) {
    Widget frame(Widget child) => Container(
      height: 64,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF4EFEA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6DDD8)),
      ),
      alignment: Alignment.center,
      child: child,
    );

    switch (effectType) {
      case 'top_card_counter':
        return frame(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F4F0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE6DCE8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'A',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
                  ),
                ),
                Text(
                  ':2',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8A7A6A),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'K',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
                  ),
                ),
                Text(
                  ':3',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8A7A6A),
                  ),
                ),
                SizedBox(width: 8),
                Text('\u{1F409}', style: TextStyle(fontSize: 13)),
                Text(
                  '\u25CB',
                  style: TextStyle(fontSize: 12, color: Color(0xFF4A90D9)),
                ),
                SizedBox(width: 6),
                Text('\u{1F426}', style: TextStyle(fontSize: 13)),
                Text(
                  '\u2715',
                  style: TextStyle(fontSize: 12, color: Color(0xFFCCC0B8)),
                ),
              ],
            ),
          ),
        );
      case 'mighty_trump_counter':
        return frame(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCCCCCC)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\u2660',
                  style: TextStyle(fontSize: 15, color: Color(0xFF2E2E2E)),
                ),
                SizedBox(width: 4),
                Text(
                  '5',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E2E2E),
                  ),
                ),
              ],
            ),
          ),
        );
      default:
        // mighty_prev_trick — the little card row the button opens.
        return frame(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final label in const ['\u2660A', '\u2665K', '\u26603'])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width: 28,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFFD8CEC8)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: label.startsWith('\u2665')
                            ? const Color(0xFFD32F2F)
                            : const Color(0xFF2E2E2E),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
    }
  }

  /// A banner / title / theme drawn the way it will actually appear.
  ///
  /// Banner and title share the waiting-room seat, because that is where they
  /// live: 60dp tall, 38dp avatar with the level on its corner, title chip above
  /// the nickname. The old banner preview predated that layout — it drew a
  /// standalone level badge beside the name, which is not a thing any screen
  /// shows any more.
  Widget _buildItemPreview(
    GameService g, {
    required String category,
    required String effectType,
    required String itemKey,
    required String itemName,
    required List<Color> fallbackGradient,
  }) {
    final l10n = L10n.of(context);
    if (_previewEffects.contains(effectType)) {
      return _buildFeaturePreview(effectType);
    }
    if (category == 'theme') {
      final colors = g.themeGradientFor(itemKey);
      return Container(
        // 100, not 96: 12 padding + 72 content + the 1px border on each side.
        height: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDDD0CC)),
        ),
        // A bare gradient says little; the surfaces the app puts on top of it
        // are what makes a theme readable or not.
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5A4038),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in g.cardBackColorsFor(itemKey).take(1))
                  Container(
                    width: 46,
                    height: 72,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: g.cardBackColorsFor(itemKey).length > 1
                            ? g.cardBackColorsFor(itemKey)[1]
                            : const Color(0xFFDDD0CC),
                        width: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    final isBanner = category == 'banner';
    final bannerKey = isBanner ? itemKey : _myBannerKey(g);
    final previewGradient = g.bannerGradient(bannerKey);
    final textColor = g.bannerTextColor(bannerKey);
    final nickname = g.playerName.isNotEmpty
        ? g.playerName
        : l10n.shopPreviewNickname;
    final ownData = g.playerName.isNotEmpty ? g.profileFor(g.playerName) : null;
    final inner = ownData?['profile'] as Map?;
    final myLevel = (inner?['level'] as int?) ?? 1;
    final photo = g.resolvePhotoUrl(g.myPhotoUrl);
    const avatarSize = 38.0;

    return Container(
      width: double.infinity,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: previewGradient == null
            ? Colors.white.withValues(alpha: 0.72)
            : null,
        gradient: previewGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6DDD8)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ProfileAvatar(
                  photoUrl: photo,
                  size: avatarSize,
                  fallback: Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0E7E3),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.person,
                      size: 23,
                      color: Color(0xFF9C8B84),
                    ),
                  ),
                ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: LevelBadge(level: myLevel, size: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // A title preview shows THIS title; a banner preview keeps
                // whatever title is equipped, so the seat reads as your own.
                if (isBanner && _myTitleName(g) != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TitleChip(
                      titleKey: g.equippedTitle,
                      titleName: _myTitleName(g),
                    ),
                  )
                else if (!isBanner)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TitleChip(titleKey: itemKey, titleName: itemName),
                  ),
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor ?? const Color(0xFF5A4038),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE7E3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF6A5A52),
          fontWeight: FontWeight.w600,
        ),
      ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                  SnackBar(
                    content: Text(
                      L10n.of(context).shopNicknameChangeValidation,
                    ),
                  ),
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

  /// Category selector as pill chips — the same language the lobby's game
  /// filters use. A second boxed TabBar under the first one made the top of the
  /// screen read as three separate headers.
  Widget _buildCategoryTabs(List<String> labels) {
    // Builder, not this.context: the category controller is the inner
    // DefaultTabController, and the State's own context sits above it — looking
    // up from there finds the 상점/인벤토리 controller instead.
    return Builder(
      builder: (tabCtx) {
        final controller = DefaultTabController.of(tabCtx);
        return AnimatedBuilder(
          animation: controller.animation ?? controller,
          builder: (context, _) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  for (var i = 0; i < labels.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _buildCategoryChip(
                      labels[i],
                      selected: controller.index == i,
                      onTap: () => controller.animateTo(i),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryChip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFF7E57C2) : const Color(0xFFF3EFF9),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF7A6E82),
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterShop(
    List<Map<String, dynamic>> items,
    String category,
  ) {
    if (category == 'all') return items;
    return items
        .where((i) => (i['category']?.toString() ?? '') == category)
        .toList();
  }

  List<Map<String, dynamic>> _filterInventory(
    List<Map<String, dynamic>> items,
    String category,
  ) {
    if (category == 'all') return items;
    if (category == 'season') {
      return items.where((i) => i['is_season'] == true).toList();
    }
    return items
        .where((i) => (i['category']?.toString() ?? '') == category)
        .toList();
  }

  String _buildItemTag(
    BuildContext context,
    bool isSeason,
    bool isPermanent,
    dynamic durationDays,
  ) {
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
      return L10n.of(
        context,
      ).shopExpireDate('${dt.year}.${dt.month}.${dt.day}');
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

  // ---- Daily attendance banner / dialog ------------------------------------
  // Banner stays visible all day — even after claim. After claim it just
  // switches to a "completed" look so users can still tap it to see the
  // 7-day grid in the dialog (claim button there is disabled).
  bool _shouldShowAttendanceBanner(GameService game) =>
      game.attendanceState != null;

  Widget _buildAttendanceTile(GameService game) {
    final s = game.attendanceState!;
    final claimed = s['claimedToday'] == true;
    final reward = (s['todayRewardGold'] as int?) ?? 50;
    final day = (s['todayDay'] as int?) ?? 1;
    final isLastDay = day == 7;
    final l10n = L10n.of(context);
    return _buildRewardTile(
      gradient: claimed
          ? const [Color(0xFF81C784), Color(0xFF4CAF50)]
          : isLastDay
          ? const [Color(0xFFFFCA28), Color(0xFFFF8F00)]
          : const [Color(0xFFFFD180), Color(0xFFFFA726)],
      icon: claimed ? Icons.check_circle : Icons.event_available,
      title: claimed
          ? l10n.attendanceBannerCompletedTitle(day)
          : l10n.attendanceBannerTitle(day),
      subtitle: claimed
          ? l10n.attendanceBannerCompletedSubtitle
          : l10n.attendanceBannerSubtitle(reward),
      onTap: () => _showAttendanceDialog(game),
    );
  }

  String _formatResetClock(String? resetAtUtc) {
    if (resetAtUtc == null) return '';
    try {
      final dt = DateTime.parse(resetAtUtc).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  void _showAttendanceDialog(GameService game) {
    // Always refresh state on open. Stale `claimedToday=false` could let the
    // user tap "watch ad" and burn the ad on a server-rejected claim.
    game.requestAttendanceState();
    // Make sure the rewarded ad is loading so the claim button can enable
    // (no-op if already loaded or a load is in flight).
    _preloadAttendanceAd();
    showDialog(
      context: context,
      builder: (_) => Consumer<GameService>(
        builder: (dialogCtx, g, _) {
          final s = g.attendanceState;
          final l = L10n.of(context);
          if (s == null) {
            return const AlertDialog(
              content: SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          final claimedToday = s['claimedToday'] == true;
          final cycleClaimed = (s['cycleClaimedDays'] as int?) ?? 0;
          final todayDay = (s['todayDay'] as int?) ?? 1;
          final rewards =
              (s['weekRewards'] as List?)?.cast<int>() ??
              const [50, 50, 50, 50, 50, 50, 1000];
          final resetClock = _formatResetClock(s['resetAtUtc'] as String?);

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.event_available,
                        color: Color(0xFFFFA000),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.attendanceDialogTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF5A4038),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        icon: const Icon(Icons.close),
                        color: const Color(0xFF8A7A72),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.attendanceResetInfo(resetClock),
                    style: const TextStyle(
                      color: Color(0xFF8A7A72),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 7-day grid (4 + 3)
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: List.generate(7, (i) {
                      final day = i + 1;
                      final reward = rewards.length > i ? rewards[i] : 50;
                      final isClaimed = day <= cycleClaimed;
                      final isToday = !claimedToday && day == todayDay;
                      final isFinale = day == 7;
                      return _attendanceDayCell(
                        day,
                        reward,
                        isClaimed,
                        isToday,
                        isFinale,
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (claimedToday)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        l.attendanceDoneToday,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    // Reacts to the attendance ad becoming ready (ValueNotifier)
                    // so the button stays DISABLED — showing a loading state —
                    // until the rewarded ad has loaded, then enables. Avoids the
                    // old "tap → ad not ready" dead-end.
                    ValueListenableBuilder<bool>(
                      valueListenable: _attendanceAdReady,
                      builder: (context, adReady, _) {
                        // Disable on: claim in flight, state refresh in flight
                        // (avoid wasting the ad on a stale claimedToday about to
                        // flip), already claimed, or the ad not yet loaded.
                        final busy =
                            g.attendanceClaiming || g.attendanceLoading;
                        final claimed =
                            g.attendanceState?['claimedToday'] == true;
                        final enabled = adReady && !busy && !claimed;
                        return ElevatedButton.icon(
                          onPressed: enabled ? () => _attendanceClaim(g) : null,
                          icon: (!adReady && !busy && !claimed)
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_circle_outline),
                          label: Text(
                            busy
                                ? l.attendanceClaiming
                                : !adReady
                                ? l.attendanceAdLoading
                                : l.attendanceWatchAdAndClaim(
                                    (s['todayRewardGold'] as int?) ?? 50,
                                  ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB300),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFFFD180),
                            disabledForegroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _attendanceDayCell(
    int day,
    int reward,
    bool claimed,
    bool today,
    bool finale,
  ) {
    final bg = claimed
        ? const Color(0xFFE8F5E9)
        : today
        ? const Color(0xFFFFF8E1)
        : Colors.white;
    final borderColor = today
        ? const Color(0xFFFFB300)
        : claimed
        ? const Color(0xFF66BB6A)
        : const Color(0xFFE0DAD6);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: today ? 2 : 1),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      // Narrow phones can squeeze the cell below the content's natural
      // height. FittedBox scales the whole stack down instead of clipping;
      // mainAxisSize.min lets it actually measure smaller than the parent.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Day $day',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: claimed
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF8A7A72),
              ),
            ),
            const SizedBox(height: 4),
            claimed
                ? Icon(
                    Icons.check_circle,
                    color: const Color(0xFF43A047),
                    size: finale ? 22 : 18,
                  )
                : GoldIcon(size: finale ? 22 : 18, amount: reward),
            const SizedBox(height: 4),
            Text(
              '$reward',
              style: TextStyle(
                fontSize: finale ? 13 : 11,
                fontWeight: FontWeight.w900,
                color: finale
                    ? const Color(0xFFE65100)
                    : const Color(0xFF5A4038),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attendanceClaim(GameService game) async {
    // Final guards before burning the ad. Three things must hold or we abort
    // immediately (no ad shown):
    //  - local state says we're not already claimed today
    //  - no claim in flight (anti-spam)
    //  - state isn't still being refreshed (avoid acting on stale data)
    if (game.attendanceState?['claimedToday'] == true) return;
    if (game.attendanceClaiming) return;
    if (game.attendanceLoading) return;
    // Reward gate: must watch the dedicated ATTENDANCE rewarded ad first.
    // Uses a separate AdMob unit from rewardedAdId so the "ad reward gold"
    // button and attendance don't race for a single ad instance.
    if (!_attendanceAdReady.value || _attendanceAd == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).attendanceAdNotReady)),
        );
        _preloadAttendanceAd();
      }
      return;
    }
    final ad = _attendanceAd!;
    _attendanceAd = null;
    _attendanceAdReady.value = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _preloadAttendanceAd();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _preloadAttendanceAd();
      },
    );
    await ad.show(
      onUserEarnedReward: (a, reward) {
        // Server is the source of truth; double-claim safe.
        game.claimAttendance();
      },
    );
  }

  Widget _buildAdRewardTile(GameService game) {
    final l10n = L10n.of(context);
    final canWatch = _todayAdCount < AdService.maxDailyRewards;
    final enabled = canWatch && !_adLoading;
    return _buildRewardTile(
      gradient: enabled
          ? const [Color(0xFF9575CD), Color(0xFF7E57C2)]
          : const [Color(0xFFBDBDBD), Color(0xFF9E9E9E)],
      icon: Icons.play_circle_fill,
      leadingOverride: _adLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : null,
      title: canWatch ? l10n.shopAdWatchTitle : l10n.shopAdRewardDone,
      subtitle: canWatch
          ? l10n.shopAdWatchProgress(_todayAdCount, AdService.maxDailyRewards)
          : l10n.shopAdRewardDoneSubtitle,
      onTap: enabled
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
                      SnackBar(
                        content: Text(L10n.of(context).shopAdCannotShow),
                      ),
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
