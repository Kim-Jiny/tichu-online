import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../models/shop_visual.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import '../services/ad_service.dart';
import '../services/inventory_new_tracker.dart';
import '../utils/gold_format.dart';
import '../widgets/level_badge.dart';
import '../widgets/playing_card.dart';
import '../widgets/coupon_redeem.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/player_profile_header.dart' show changeProfilePhoto;
import '../widgets/title_chip.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/gold_icon.dart';
import '../widgets/gold_history_dialog.dart';
import 'gold_shop_screen.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import '../widgets/store_link.dart';

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
  // 상점/인벤토리 최상위 탭. 인벤토리를 보고 있을 때만 "본 것" 처리를 한다.
  TabController? _shopTabs;
  // 인벤토리에서 아직 안 본 새 아이템 표시.
  InventoryNewTracker? _newTracker;

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

  bool _isNew(Map<String, dynamic> item) {
    final until = item['new_until'];
    if (until == null) return false;
    final dt = DateTime.tryParse(until.toString());
    return dt != null && DateTime.now().isBefore(dt);
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
      _loadNewTracker(game.playerName);
      // Pull own profile so the banner preview can show the real level badge
      // (falls back to Lv.1 when not yet cached).
      if (game.playerName.isNotEmpty) {
        game.requestProfile(game.playerName);
      }
    });
  }

  Future<void> _loadNewTracker(String nickname) async {
    if (nickname.isEmpty) return;
    final tracker = await InventoryNewTracker.load(nickname);
    if (!mounted) return;
    setState(() => _newTracker = tracker);
  }

  /// 인벤토리 6칸에 들어갈 아이템. 탭 화면과 새것 표시가 같은 분류를 쓴다.
  List<List<Map<String, dynamic>>> _inventoryTabLists(
    List<Map<String, dynamic>> items,
  ) => [
    _filterInventory(items, 'banner'),
    _titleInventoryItems(items),
    _filterInventory(items, 'theme'),
    _filterInventory(items, 'utility'),
    _profileTabItems(_filterInventory(items, 'feature')),
    _filterInventory(items, 'season'),
  ];

  /// 새 아이템 표시를 맞춘다: 목록을 정리하고, 지금 보고 있는 칸은 본 것으로 친다.
  void _syncInventoryNew(GameService game) {
    final t = _newTracker;
    if (t == null ||
        !game.inventoryLoadedOnce ||
        game.inventoryLoading ||
        game.inventoryError != null) {
      return;
    }
    var changed = t.sync(game.inventoryItems);
    final onInventory = _shopTabs?.index == 1;
    if (onInventory) {
      final lists = _inventoryTabLists(game.inventoryItems);
      final idx = _inventoryTabController.value;
      if (idx < lists.length && t.markSeen(lists[idx])) changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _loadAdCount() async {
    final count = await AdService.getTodayRewardCount();
    if (mounted) setState(() => _todayAdCount = count);
  }

  void _preloadRewardedAd() {
    // No AdMob on web; the tiles that need a loaded ad stay hidden because
    // _rewardedAdReady never flips.
    if (kIsWeb) return;
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
    // No AdMob on web; the tiles that need a loaded ad stay hidden because
    // _rewardedAdReady never flips.
    if (kIsWeb) return;
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
    _shopTabs?.removeListener(_handleShopTabChanged);
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
    return Theme(
      data: cartoonTheme(Theme.of(context)),
      child: DefaultTabController(
        length: 2,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(adjustedScale)),
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
              // 아래 안전영역은 비워 두지 않는다: 시트가 화면 끝까지 내려가고, 목록
              // 아래 여백(viewPadding)이 그만큼 띄워서 마지막 줄이 가려지지 않는다.
              child: SafeArea(
                bottom: false,
                child: Consumer<GameService>(
                  builder: (context, game, _) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _maybeShowShopActionResult(context, game);
                      _maybeShowPurchaseDialog(context, game);
                      _maybeShowNicknameChangeResult(context, game);
                      _maybeShowCustomTitleResult(context, game);
                      _maybeShowAdRewardResult(context, game);
                      _syncInventoryNew(game);
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
      ),
    );
  }

  void _handleInventoryTabChanged() {
    final tabController = _inventoryTabs;
    if (tabController == null || tabController.indexIsChanging) return;
    _inventoryTabController.value = tabController.index;
    _syncInventoryNew(context.read<GameService>());
  }

  void _handleShopTabChanged() {
    final c = _shopTabs;
    if (c == null || c.indexIsChanging) return;
    _syncInventoryNew(context.read<GameService>());
  }

  /// 카툰 헤더: 뒤로가기 · 제목 · 쿠폰 · 내 프로필, 그 아래 지갑(골드 내역)과 충전.
  Widget _buildTopBar(BuildContext context, GameService game) {
    final l10n = L10n.of(context);
    Widget chip({required Widget child, required VoidCallback onTap}) {
      return CartoonPressable(
        onTap: onTap,
        scale: 0.88,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Cartoon.paper,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Cartoon.ink, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Cartoon.ink, offset: Offset(0, 3)),
            ],
          ),
          child: child,
        ),
      );
    }

    return CartoonEntrance(
      from: const Offset(0, -30),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                chip(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Cartoon.ink,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Cartoon.outlinedText(l10n.shopTitle, size: 28),
                const Spacer(),
                // 코드를 들고 온 사람은 쓰려고 상점을 연다 — 쿠폰 입구는 여기.
                // iOS 앱에는 없다 (couponRedeemAllowed).
                if (couponRedeemAllowed) ...[
                  chip(
                    onTap: () => showCouponRedeemDialog(context),
                    child: couponIcon(size: 26),
                  ),
                  const SizedBox(width: 10),
                ],
                _buildMyProfileButton(game),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: CartoonPressable(
                    scale: 0.97,
                    onTap: () => showGoldHistoryDialog(context, game),
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Cartoon.cream,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Cartoon.ink, width: 2.5),
                        boxShadow: const [
                          BoxShadow(color: Cartoon.ink, offset: Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        children: [
                          GoldIcon(size: 28, amount: game.gold),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n.shopGoldAmount(game.gold),
                                maxLines: 1,
                                style: Cartoon.text(size: 22),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.history_rounded,
                            size: 20,
                            color: Cartoon.ink,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                CartoonPulse(
                  child: CartoonButton(
                    expand: false,
                    height: 46,
                    color: Cartoon.green,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GoldShopScreen(),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10, right: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          CartoonButton.label(l10n.shopChargeGold, size: 17),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The two daily rewards as one short strip.
  ///
  /// They used to be two full-width blocks stacked on top of each other — a
  /// gradient attendance banner and a purple ad button — about 110px before the
  /// tabs even started. Side by side they cost one 46px row.
  /// Own avatar in the header — opens the profile popup.
  ///
  /// Sized and placed like the other header icons rather than as a nameplate:
  /// the shop title row also carries the desertion count and refresh, and a
  /// nickname beside them left nothing for either.
  Widget _buildMyProfileButton(GameService game) {
    final nickname = game.playerName;
    if (nickname.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: L10n.of(context).lobbyPlayerProfile,
      child: InkWell(
        borderRadius: BorderRadius.circular(avatarCornerRadius(44)),
        onTap: () => showPlayerProfileDialog(context, nickname, game),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(avatarCornerRadius(40)),
              border: Border.all(color: Cartoon.ink, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Cartoon.ink, offset: Offset(0, 3)),
              ],
            ),
            child: ProfileAvatar(
              photoUrl: game.resolvePhotoUrl(game.myPhotoUrl),
              size: 40,
              fallback: const DefaultAvatar(size: 40),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRewardStrip(GameService game) {
    final hasAttendance = _shouldShowAttendanceBanner(game);
    if (!hasAttendance && !_rewardedAdReady) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
    return CartoonPressable(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        height: 54,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Cartoon.ink, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Cartoon.ink, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            leadingOverride ?? Icon(icon, color: Colors.white, size: 22),
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
                    style: Cartoon.userText(
                      size: 13.5,
                      color: Colors.white,
                      weight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Cartoon.userText(
                      size: 11.5,
                      color: Colors.white,
                      weight: FontWeight.w600,
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
        color: Cartoon.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(color: Cartoon.ink, width: 3),
          left: BorderSide(color: Cartoon.ink, width: 3),
          right: BorderSide(color: Cartoon.ink, width: 3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Builder(
        builder: (sheetCtx) {
          final outer = DefaultTabController.of(sheetCtx);
          if (!identical(_shopTabs, outer)) {
            _shopTabs?.removeListener(_handleShopTabChanged);
            _shopTabs = outer;
            _shopTabs?.addListener(_handleShopTabChanged);
          }
          return Column(
            children: [
              _buildTabs(game),
              Expanded(
                child: TabBarView(
                  children: [_buildShopTab(game), _buildInventoryTab(game)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 안 본 새 아이템이 있다는 빨간 점.
  Widget _newDot() => Container(
    width: 8,
    height: 8,
    decoration: const BoxDecoration(
      color: Color(0xFFE53935),
      shape: BoxShape.circle,
    ),
  );

  /// 상점 ↔ 인벤토리: 알약 두 칸짜리 토글. 선택된 칸이 색으로 채워진다.
  Widget _buildTabs(GameService game) {
    final t = _newTracker;
    final inventoryHasNew =
        t != null && game.inventoryLoadedOnce && t.anyNew(game.inventoryItems);
    final l10n = L10n.of(context);
    return Builder(
      builder: (tabCtx) {
        final controller = DefaultTabController.of(tabCtx);
        return AnimatedBuilder(
          animation: controller.animation ?? controller,
          builder: (context, _) {
            Widget segment(
              int i,
              String label,
              IconData icon, {
              bool dot = false,
            }) {
              final selected = controller.index == i;
              return Expanded(
                child: CartoonPressable(
                  scale: 0.95,
                  onTap: () => controller.animateTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected ? Cartoon.orange : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? Cartoon.ink : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: selected ? Colors.white : Cartoon.ink,
                        ),
                        const SizedBox(width: 6),
                        selected
                            ? Cartoon.outlinedText(label, size: 18)
                            : Text(label, style: Cartoon.text(size: 18)),
                        if (dot) ...[const SizedBox(width: 6), _newDot()],
                      ],
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Cartoon.cream,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Cartoon.ink, width: 2.5),
                ),
                child: Row(
                  children: [
                    segment(0, l10n.shopTabShop, Icons.storefront_rounded),
                    const SizedBox(width: 4),
                    segment(
                      1,
                      l10n.shopTabInventory,
                      Icons.backpack_rounded,
                      dot: inventoryHasNew,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
            L10n.of(context).shopCategoryProfile,
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _buildShopList(
                  context,
                  game,
                  _filterShop(game.shopItems, 'banner'),
                ),
                _buildShopList(context, game, _titleTabItems(game.shopItems)),
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
                _buildShopList(context, game, _profileTabItems(game.shopItems)),
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
    return _buildShopGrid(context, game, ordered);
  }

  /// 단일 아이템은 카드 2열(넓으면 3~4열), 기간별 묶음 카드는 가로 한 줄 전체.
  /// 한 줄에 몇 개가 들어가는지는 폭으로만 정한다.
  Widget _buildShopGrid(
    BuildContext context,
    GameService game,
    List<List<Map<String, dynamic>>> ordered,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w < 520 ? 2 : (w < 860 ? 3 : 4);
        final rows = <Widget>[];
        final groupOf = <Map<String, dynamic>, List<Map<String, dynamic>>>{};
        var pending = <Map<String, dynamic>>[];
        var rowIndex = 0;
        void flush() {
          if (pending.isEmpty) return;
          final chunk = pending;
          pending = [];
          rows.add(
            CartoonEntrance(
              key: ValueKey('shop-row-${chunk.first['item_key']}'),
              delay: Duration(milliseconds: 40 * rowIndex.clamp(0, 6)),
              from: const Offset(0, 18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cols; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: i < chunk.length
                              ? ((groupOf[chunk[i]]?.length ?? 1) > 1
                                    ? _buildGroupedFeatureCard(
                                        context,
                                        game,
                                        groupOf[chunk[i]]!,
                                      )
                                    : _buildShopCard(context, game, chunk[i]))
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
          rowIndex++;
        }

        for (final g in ordered) {
          pending.add(g.first);
          groupOf[g.first] = g;
          if (pending.length == cols) flush();
        }
        flush();
        return ListView(
          padding: EdgeInsets.only(
            top: 6,
            bottom: 28 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: rows,
        );
      },
    );
  }

  /// 카툰 아이템 카드: 큰 썸네일 → 이름 → 종류 → 가격 알약. 누르면 상세 시트.
  Widget _buildShopCard(
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
    final category = item['category']?.toString() ?? '';
    final ownedMatches = game.inventoryItems.where(
      (i) => i['item_key'] == itemKey,
    );
    final ownedInv = ownedMatches.isEmpty ? null : ownedMatches.first;
    final owned = ownedInv != null;
    // 소모품(utility)은 여러 개 살 수 있으니 가졌어도 가격을 숨기지 않는다.
    final ownedPermanent = owned && isPermanent && category != 'utility';
    final ownedExpiry = ownedInv?['expires_at'];
    final ownedExpiryText = ownedExpiry != null
        ? _formatExpire(context, ownedExpiry)
        : null;
    final onSale = _isOnSale(item);
    final saleWindow = _saleWindowText(item);
    // 이미 가진 꾸미기 아이템은 인벤토리까지 가지 않고 카드에서 바로 장착/해제.
    final effectType = item['effect_type']?.toString() ?? '';
    final canQuickEquip =
        owned &&
        const {'banner', 'title', 'theme'}.contains(category) &&
        effectType != 'custom_title';
    final isWorn = canQuickEquip && ownedInv['is_active'] == true;

    Widget? ribbon;
    if (isSeason) {
      ribbon = _cartoonTag(l10n.shopTagSeason, Cartoon.blue);
    } else if (owned) {
      final worn = ownedInv['is_active'] == true;
      ribbon = _cartoonTag(
        worn ? l10n.shopStatusInUse : l10n.shopItemOwned,
        worn ? Cartoon.blue : Cartoon.green,
      );
    } else if (onSale) {
      ribbon = _cartoonTag(l10n.shopTagLimited, Cartoon.red);
    }

    return CartoonPressable(
      scale: 0.96,
      onTap: () => _showItemDetailSheet(context, item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: Cartoon.panelDecoration(radius: 20, shadowOffset: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildShopRowVisual(item, 84, isNew: _isNew(item)),
                ),
                if (ribbon != null)
                  Positioned(right: 0, top: -2, child: ribbon),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Cartoon.userText(size: 14.5, height: 1.2),
            ),
            const SizedBox(height: 2),
            Text(
              _buildItemTag(
                context,
                isSeason,
                isPermanent,
                durationDays,
                category,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Cartoon.userText(
                size: 11.5,
                weight: FontWeight.w500,
                color: Cartoon.ink.withValues(alpha: 0.6),
              ),
            ),
            if (ownedExpiryText != null) ...[
              const SizedBox(height: 3),
              Text(
                ownedExpiryText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cartoon.userText(
                  size: 11,
                  color: const Color(0xFF2E8B57),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (canQuickEquip)
              CartoonPressable(
                scale: 0.92,
                onTap: _busyItemKeys.contains(itemKey)
                    ? null
                    : () => _runItemAction(
                        itemKey,
                        () => isWorn
                            ? game.unequipCategory(category)
                            : game.equipItem(itemKey),
                      ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: isWorn ? Cartoon.paper : Cartoon.blue,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Cartoon.ink, width: 2.2),
                    boxShadow: const [
                      BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Text(
                    isWorn ? l10n.shopButtonUnequip : l10n.shopButtonEquip,
                    textAlign: TextAlign.center,
                    style: Cartoon.text(
                      size: 15,
                      color: isWorn ? Cartoon.ink : Colors.white,
                    ),
                  ),
                ),
              )
            else if (!ownedPermanent)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: onSale ? const Color(0xFFFFE3E3) : Cartoon.cream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Cartoon.ink, width: 2.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GoldIcon(size: 18, amount: price is int ? price : null),
                    const SizedBox(width: 5),
                    Text(
                      formatGold(price),
                      style: Cartoon.text(
                        size: 16,
                        color: onSale ? const Color(0xFFD32F2F) : Cartoon.ink,
                      ),
                    ),
                  ],
                ),
              ),
            if (saleWindow != null) ...[
              const SizedBox(height: 4),
              Text(
                saleWindow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cartoon.userText(
                  size: 10.5,
                  color: onSale
                      ? const Color(0xFFD32F2F)
                      : Cartoon.ink.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "골드가 N 부족해요" + 충전 버튼.
  Widget _shortageBanner(BuildContext sheetCtx, int lack) {
    final l10n = L10n.of(sheetCtx);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE3E3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Cartoon.ink, width: 2.5),
      ),
      child: Row(
        children: [
          GoldIcon(size: 24, amount: lack),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.shopNeedMoreGold(formatGold(lack)),
              style: Cartoon.text(size: 16),
            ),
          ),
          CartoonButton(
            expand: false,
            height: 40,
            radius: 14,
            color: Cartoon.green,
            onPressed: () {
              Navigator.pop(sheetCtx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GoldShopScreen()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CartoonButton.label(l10n.shopChargeGold, size: 15),
            ),
          ),
        ],
      ),
    );
  }

  /// 구매 완료 축하: 색종이가 터지고 아이템이 통통 튀어나온다. 바로 장착도 여기서.
  void _showPurchaseCelebration(
    BuildContext context,
    GameService game, {
    required Map<String, dynamic> item,
    required bool extended,
    required bool canEquip,
    required String message,
  }) {
    final l10n = L10n.of(context);
    final itemKey = item['item_key']?.toString() ?? '';
    final name = _getLocalizedItemName(item);
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Positioned.fill(child: CartoonConfetti()),
            CartoonEntrance(
              from: const Offset(0, 40),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: Cartoon.panelDecoration(radius: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CartoonFloat(
                      amplitude: 5,
                      child: _buildShopRowVisual(item, 104),
                    ),
                    const SizedBox(height: 14),
                    Cartoon.outlinedText(
                      extended
                          ? l10n.shopExtendComplete
                          : l10n.shopPurchaseComplete,
                      size: 30,
                      fill: Cartoon.yellow,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: Cartoon.userText(size: 17),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Cartoon.userText(
                        size: 13.5,
                        weight: FontWeight.w500,
                        color: Cartoon.ink.withValues(alpha: 0.7),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: CartoonButton(
                            height: 50,
                            color: const Color(0xFFB9B0A8),
                            onPressed: () => Navigator.pop(ctx),
                            child: CartoonButton.label(
                              l10n.commonClose,
                              size: 17,
                            ),
                          ),
                        ),
                        if (canEquip) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: CartoonPulse(
                              child: CartoonButton(
                                height: 50,
                                color: Cartoon.green,
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  game.equipItem(itemKey);
                                },
                                child: CartoonButton.label(
                                  l10n.shopEquipNow,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 카드 모서리에 붙는 작은 라벨(시즌 / 보유중 / 한정).
  Widget _cartoonTag(String text, Color color) {
    return Transform.rotate(
      angle: 0.08,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Cartoon.ink, width: 2),
        ),
        child: Text(
          text,
          style: Cartoon.userText(
            size: 10.5,
            color: Colors.white,
            weight: FontWeight.w900,
          ),
        ),
      ),
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
    final l10n = L10n.of(context);
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

    // 단일 카드와 같은 칸 크기 — 가격 알약 자리에 기간별 칩이 세로로 들어간다.
    return CartoonPressable(
      scale: 0.96,
      // 카드 어디를 눌러도 같은 시트가 열린다: 두 기간을 한 시트에서 고른다.
      onTap: () => _showItemDetailSheet(context, first, tiers: tiers),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: Cartoon.panelDecoration(radius: 20, shadowOffset: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildShopRowVisual(first, 84, isNew: _isNew(first)),
                ),
                if (ownedActive)
                  Positioned(
                    right: 0,
                    top: -2,
                    child: _cartoonTag(l10n.shopItemOwned, Cartoon.green),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              baseName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Cartoon.userText(size: 14.5, height: 1.2),
            ),
            if (ownedExpiryText != null) ...[
              const SizedBox(height: 3),
              Text(
                ownedExpiryText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cartoon.userText(
                  size: 11,
                  color: const Color(0xFF2E8B57),
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (var i = 0; i < tiers.length; i++) ...[
              if (i > 0) const SizedBox(height: 5),
              _buildTierChip(context, tiers[i], tiers),
            ],
          ],
        ),
      ),
    );
  }

  // 기간 칩: 왼쪽에 "7일", 오른쪽에 가격. 칸 폭을 꽉 채운다. 누르면 그 기간이
  // 아니라 같은 시트가 열린다(두 기간 모두 거기서 살 수 있다).
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onSale ? const Color(0xFFFFE3E3) : Cartoon.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Cartoon.ink, width: 2.2),
      ),
      child: Row(
        children: [
          Text(
            durationLabel,
            style: Cartoon.userText(size: 13, weight: FontWeight.w900),
          ),
          const Spacer(),
          GoldIcon(size: 16, amount: price is int ? price : null),
          const SizedBox(width: 4),
          Text(
            formatGold(price),
            style: Cartoon.text(
              size: 15,
              color: onSale ? const Color(0xFFD32F2F) : Cartoon.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopRowVisual(
    Map<String, dynamic> item,
    double size, {
    bool isNew = false,
  }) {
    final category = item['category']?.toString() ?? '';
    final itemKey = item['item_key']?.toString() ?? '';
    final visual = _resolveThumbnailStyle(itemKey, category, item);
    final gradient =
        (visual['gradient'] as List<Color>?) ??
        [Colors.white, Colors.grey.shade100];
    final iconData = (visual['icon'] as IconData?) ?? Icons.flag;
    final iconColor =
        (visual['iconColor'] as Color?) ?? const Color(0xFF888888);
    final thumbnail = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(size >= 70 ? 18 : 12),
        border: Border.all(color: Cartoon.ink, width: size >= 70 ? 2.5 : 1.5),
      ),
      child: Center(
        child: Icon(iconData, color: iconColor, size: size * 0.45),
      ),
    );
    if (!isNew) return thumbnail;
    // A sticker, not a chip — this is the one badge meant to grab the eye
    // before anything else on the row does, so it deliberately breaks from
    // the flat muted colors every other badge here uses.
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 6, top: 6, child: thumbnail),
          Positioned(
            left: -4,
            top: -4,
            child: Transform.rotate(
              angle: -0.35,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5F6D), Color(0xFFFFC371)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF5F6D).withValues(alpha: 0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
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

  // Consumable items are deleted from inventory the instant they're used
  // (e.g. 탈주 카운트 초기화) — a single misplaced tap otherwise burns one with
  // no way back, so this gates every use behind an explicit confirm.
  void _showUseConfirmDialog(
    BuildContext context,
    String itemKey,
    String name,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(context).shopUseConfirmTitle),
        content: Text(L10n.of(context).shopUseConfirmBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(L10n.of(context).shopButtonUse),
          ),
        ],
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
                L10n.of(context).shopCategoryProfile,
                L10n.of(context).shopCategorySeason,
              ], badges: _inventoryBadges(game)),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final tabItems in _inventoryTabLists(
                      game.inventoryItems,
                    ))
                      _buildInventoryList(tabItems),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 칸마다 안 본 새 아이템이 있는지. 지금 보고 있는 칸은 곧 지워지니 그대로 둔다.
  List<bool> _inventoryBadges(GameService game) {
    final t = _newTracker;
    final lists = _inventoryTabLists(game.inventoryItems);
    if (t == null || !game.inventoryLoadedOnce) {
      return List.filled(lists.length, false);
    }
    return [for (final l in lists) t.anyNew(l)];
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.builder(
          padding: EdgeInsets.only(
            top: 6,
            bottom: 28 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => CartoonEntrance(
            key: ValueKey('inv-${items[i]['item_key']}'),
            delay: Duration(milliseconds: 40 * i.clamp(0, 6)),
            from: const Offset(0, 18),
            child: _buildInventoryItem(context, items[i]),
          ),
        ),
      ),
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
    // Custom title is the one feature item with something to set: the row's
    // button opens the editor instead of doing nothing.
    final isCustomTitle = effectType == 'custom_title';
    // Passes that simply apply while they last. They cannot be equipped, but
    // they can be switched off — the days run either way, and someone who wants
    // the counter off for a few games should not have to lose the pass.
    const toggleable = {
      'top_card_counter',
      'mighty_trump_counter',
      'mighty_prev_trick',
      'profile_private',
    };
    final isToggleable = toggleable.contains(effectType);
    final featureOn = item['feature_disabled'] != true;
    final isConsumable = category == 'utility' && !noEquipAction;
    final expiresAt = item['expires_at'];
    final expiresText = expiresAt != null
        ? _formatExpire(context, expiresAt)
        : null;
    final equipped = isActive && !noEquipAction;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: Cartoon.panelDecoration(
        color: equipped ? const Color(0xFFE6F2FF) : Cartoon.paper,
        radius: 20,
        shadowOffset: 4,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showItemDetailSheet(context, item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildShopRowVisual(item, 64),
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
                          // A pass that is switched off is not "활성화됨": the
                          // button beside it already says 사용 안 함, and two
                          // labels disagreeing is worse than one missing.
                          else if (noEquipAction &&
                              (!isToggleable || featureOn))
                            _badge(
                              l10n.shopStatusActivated,
                              const Color(0xFF1565C0),
                              const Color(0xFFDDECF7),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (isCustomTitle && game.myCustomTitleText != null) ...[
                        // What the pass is currently set to. Without it the row
                        // says only that you hold a custom title, not which one.
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: TitleChip(
                            titleKey:
                                'custom:${game.myCustomTitleColor ?? 'rose'}',
                            titleName: game.myCustomTitleText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      Text(
                        expiresText ??
                            (isConsumable
                                ? l10n.shopStatusReadyToUse
                                : l10n.shopPermanentOwned),
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
                          if (isToggleable)
                            // A button that says the current state, not a switch:
                            // switching it off costs days that keep running, so it
                            // asks first — and a switch that opens a dialog is a
                            // button wearing the wrong clothes.
                            SizedBox(
                              height: 34,
                              child: ElevatedButton(
                                onPressed: () => _showFeatureToggleDialog(
                                  context,
                                  game,
                                  effectType,
                                  featureOn,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: featureOn
                                      ? const Color(0xFFDDF0E4)
                                      : const Color(0xFFEFEBE9),
                                  foregroundColor: featureOn
                                      ? const Color(0xFF33734B)
                                      : const Color(0xFF8A7A72),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  minimumSize: const Size(0, 34),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(
                                      color: Cartoon.ink,
                                      width: 2.2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  featureOn
                                      ? l10n.shopFeatureInUse
                                      : l10n.shopFeatureOff,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          else if (isCustomTitle) ...[
                            // Two things to do with a written title: change the
                            // text, and take it off without losing it. Unequip is
                            // the same slot clear as any other title; putting it
                            // back on re-saves the stored text.
                            if (game.myCustomTitleText != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: SizedBox(
                                  height: 34,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      final worn =
                                          game.equippedTitle?.startsWith(
                                            'custom:',
                                          ) ==
                                          true;
                                      if (worn) {
                                        _runItemAction(
                                          itemKey,
                                          () => game.unequipCategory('title'),
                                        );
                                      } else {
                                        _runItemAction(
                                          itemKey,
                                          () => game.setCustomTitle(
                                            game.myCustomTitleText!,
                                            game.myCustomTitleColor ?? 'rose',
                                          ),
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          game.equippedTitle?.startsWith(
                                                'custom:',
                                              ) ==
                                              true
                                          ? const Color(0xFFE3F2FD)
                                          : const Color(0xFFB3E5FC),
                                      foregroundColor: const Color(0xFF4A3A33),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      minimumSize: const Size(0, 34),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: const BorderSide(
                                          color: Cartoon.ink,
                                          width: 2.2,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      game.equippedTitle?.startsWith(
                                                'custom:',
                                              ) ==
                                              true
                                          ? l10n.shopButtonUnequip
                                          : l10n.shopButtonEquip,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            SizedBox(
                              height: 34,
                              child: ElevatedButton(
                                onPressed: _busyItemKeys.contains(itemKey)
                                    ? null
                                    : () =>
                                          _showCustomTitleDialog(context, game),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFB3E5FC),
                                  foregroundColor: const Color(0xFF4A3A33),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  minimumSize: const Size(0, 34),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(
                                      color: Cartoon.ink,
                                      width: 2.2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  l10n.customTitleButton,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ] else if (!noEquipAction)
                            SizedBox(
                              height: 34,
                              child: ElevatedButton(
                                onPressed: _busyItemKeys.contains(itemKey)
                                    ? null
                                    : () {
                                        if (effectType == 'nickname_change') {
                                          _showNicknameChangeDialog(
                                            context,
                                            game,
                                          );
                                        } else if (effectType ==
                                            'custom_title') {
                                          _showCustomTitleDialog(context, game);
                                        } else if (isConsumable) {
                                          _showUseConfirmDialog(
                                            context,
                                            itemKey,
                                            name,
                                            () => _runItemAction(
                                              itemKey,
                                              () => game.useItem(itemKey),
                                            ),
                                          );
                                        } else if (equipped) {
                                          // Same button, other direction: what is
                                          // on can be taken off. There was no way
                                          // back to "no banner" once one was worn.
                                          _runItemAction(
                                            itemKey,
                                            () =>
                                                game.unequipCategory(category),
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
                                    side: const BorderSide(
                                      color: Cartoon.ink,
                                      width: 2.2,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  minimumSize: const Size(0, 34),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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
                                        isCustomTitle
                                            ? l10n.customTitleButton
                                            : isConsumable
                                            ? l10n.shopButtonUse
                                            : (equipped
                                                  ? l10n.shopButtonUnequip
                                                  : l10n.shopButtonEquip),
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
      case 'custom_title_7d':
        return {
          'icon': Icons.drive_file_rename_outline,
          'iconColor': const Color(0xFFC2185B),
          'gradient': [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)],
          'borderColor': const Color(0xFFF48FB1),
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
    _showPurchaseCelebration(
      context,
      game,
      item: item,
      extended: extended,
      canEquip: !extended && !isConsumable && !noEquipAction,
      message: extended
          ? L10n.of(context).shopExtendDone(name)
          : isConsumable
          ? L10n.of(context).shopPurchaseDoneConsumable
          : noEquipAction
          ? L10n.of(context).shopPurchaseDonePassive2
          : L10n.of(context).shopPurchaseDoneEquip,
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

  /// Why a title was refused (four characters, a banned word, a colour that is
  /// not in the palette) has to be said out loud — the editor closes on submit,
  /// so a silent rejection would look like it worked.
  void _maybeShowCustomTitleResult(BuildContext context, GameService game) {
    if (game.customTitleSuccess == null) return;
    final ok = game.customTitleSuccess == true;
    final msg = game.customTitleMessage;
    game.customTitleSuccess = null;
    game.customTitleMessage = null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? L10n.of(context).customTitleSaved : (msg ?? '')),
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
    // A permanent *utility* item is a one-shot consumable (탈주 카운트 -1/-3,
    // 전적 초기화권, …) — same split as the server's buyItem/grantItemToUser.
    // Owning an unused one must not block buying another.
    final ownedPermanent = owned && isPermanent && category != 'utility';
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
              color: Cartoon.paper,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(color: Cartoon.ink, width: 3),
                left: BorderSide(color: Cartoon.ink, width: 3),
                right: BorderSide(color: Cartoon.ink, width: 3),
              ),
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
                            height: 6,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Cartoon.ink.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              height: 150,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: gradient,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: Cartoon.ink,
                                  width: 3,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Cartoon.ink,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  iconData,
                                  color: iconColor,
                                  size: 64,
                                ),
                              ),
                            ),
                            if (_isNew(item))
                              Positioned(
                                left: 10,
                                top: -8,
                                child: Transform.rotate(
                                  angle: -0.2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Cartoon.red,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Cartoon.ink,
                                        width: 2.5,
                                      ),
                                    ),
                                    child: const Text(
                                      'NEW',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
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
                              titleOverride:
                                  effectTypeOf(item) == 'custom_title'
                                  ? l10n.shopCustomTitleSample
                                  : null,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Cartoon.userText(
                                  size: 22,
                                  weight: FontWeight.w900,
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
                                l10n.shopTagLimited,
                                const Color(0xFFD32F2F),
                                const Color(0xFFFFEBEE),
                              ),
                          ],
                        ),
                        // 가격은 이름 바로 아래에 크게 — 아래 바까지 눈을 내리지 않아도
                        // 알 수 있게. (기간별 상품은 아래 버튼 하나하나에 가격이 있다.)
                        if (tierList == null && !ownedPermanent) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: onSale
                                    ? const Color(0xFFFFE3E3)
                                    : Cartoon.cream,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Cartoon.ink,
                                  width: 2.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Cartoon.ink,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GoldIcon(size: 26, amount: price),
                                  const SizedBox(width: 6),
                                  Text(
                                    formatGold(price),
                                    style: Cartoon.text(
                                      size: 26,
                                      color: onSale
                                          ? const Color(0xFFD32F2F)
                                          : Cartoon.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
                                  ? (category == 'utility'
                                        ? l10n.shopDetailConsumable
                                        : l10n.shopDetailPermanent)
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
                                l10n.shopSaleWindow(
                                  _saleWindowText(item) ?? '',
                                ),
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
                  decoration: BoxDecoration(
                    color: Cartoon.cream,
                    border: const Border(
                      top: BorderSide(color: Cartoon.ink, width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 골드가 모자라면 이유와 해결책을 같이: 회색 버튼만 두면 왜
                      // 못 사는지 알 수 없다.
                      if (!owned || !ownedPermanent)
                        Builder(
                          builder: (_) {
                            final cheapest = tierList == null
                                ? price
                                : tierList
                                      .map((t) => (t['price'] ?? 0) as int)
                                      .reduce((x, y) => x < y ? x : y);
                            final lack = cheapest - game.gold;
                            if (lack <= 0 || (isSeason && owned)) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _shortageBanner(ctx, lack),
                            );
                          },
                        ),
                      if (tierList != null)
                        Builder(
                          builder: (_) {
                            final action = owned
                                ? _ownedActions(ctx, game, item, compact: true)
                                : null;
                            return Row(
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
                                // A pass is bought to DO something. With two
                                // tiers already on the row this is a third
                                // column, which is why the label is short.
                                if (action != null) ...[
                                  const SizedBox(width: 8),
                                  Expanded(child: action),
                                ],
                              ],
                            );
                          },
                        )
                      else
                        Builder(
                          builder: (_) {
                            // Season banners are reward-only — once owned, they can
                            // not be re-purchased or extended through the shop. Treat
                            // owned-season the same as owned-permanent here.
                            final lockedAsOwned =
                                ownedPermanent || (isSeason && owned);
                            // A permanent utility item is a one-shot consumable
                            // (탈주 카운트 -1/-3, 전적 초기화권, …) — each purchase
                            // is a separate, independent copy, not an extension
                            // of the one already held. "연장" ("extend by N
                            // days") makes no sense for something with no
                            // duration_days, and buying a second one must read
                            // exactly like buying the first.
                            final isStackableConsumable =
                                isPermanent && category == 'utility';
                            final treatAsExtend =
                                owned && !isStackableConsumable;
                            final action = owned
                                ? _ownedActions(ctx, game, item)
                                : null;
                            final buyButton = CartoonButton(
                              height: 52,
                              color: treatAsExtend
                                  ? Cartoon.blue
                                  : Cartoon.green,
                              onPressed: (lockedAsOwned || !canBuy)
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      if (treatAsExtend) {
                                        _showExtendConfirmDialog(
                                          context,
                                          game,
                                          item,
                                        );
                                      } else {
                                        game.buyItem(itemKey);
                                      }
                                    },
                              child: CartoonButton.label(
                                lockedAsOwned
                                    ? l10n.shopItemOwned
                                    : (treatAsExtend
                                          ? l10n.shopButtonExtend
                                          : l10n.shopButtonPurchase),
                                size: 19,
                              ),
                            );
                            // Side by side, not stacked: a second full-width
                            // button pushes the sheet past its height and turns
                            // reading an item into scrolling.
                            if (action == null) {
                              return SizedBox(
                                width: double.infinity,
                                child: buyButton,
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: buyButton),
                                const SizedBox(width: 8),
                                Expanded(child: action),
                              ],
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

  /// The row of actions an item offers once you already own it.
  ///
  /// Before this, owning something ended the sheet: an owned permanent item
  /// showed a dead "보유 중" button and an owned pass showed only 연장. Both
  /// left the actual use of the thing somewhere else — equip in the inventory
  /// tab, write a title in a dialog reached from a different screen, upload a
  /// photo from the profile popup. The sheet you opened to look at the item is
  /// the obvious place to use it.
  ///
  /// Returns null when there is nothing to offer, so the caller can skip the
  /// spacing too.
  /// [compact] drops the icon and tightens the text. A pass with two duration
  /// tiers already fills the row, so its action is a third column and has no
  /// width to spare.
  Widget? _ownedActions(
    BuildContext sheetCtx,
    GameService game,
    Map<String, dynamic> item, {
    bool compact = false,
  }) {
    final l10n = L10n.of(sheetCtx);
    final itemKey = item['item_key'] as String? ?? '';
    final category = item['category'] as String? ?? '';
    final effect = item['effect_type'] as String?;

    // The pass items do not get equipped; they unlock a thing to do. Send the
    // player at that thing instead.
    if (effect == 'custom_title') {
      return _sheetAction(
        sheetCtx,
        Icons.edit_outlined,
        l10n.shopSheetCreateTitle,
        () {
          Navigator.pop(sheetCtx);
          _showCustomTitleDialog(context, game);
        },
      );
    }
    if (effect == 'profile_photo') {
      return _sheetAction(
        sheetCtx,
        Icons.photo_camera_rounded,
        l10n.shopSheetRegisterPhoto,
        () {
          Navigator.pop(sheetCtx);
          changeProfilePhoto(
            context,
            game,
            photoUrl: game.resolvePhotoUrl(game.myPhotoUrl),
            nickname: game.playerName,
          );
        },
        compact: compact,
      );
    }

    // Only the three whose equipped state we can actually read. card_skin is a
    // category the schema allows and nothing currently uses; offering 장착하기
    // for it would leave the button showing on a skin that is already on,
    // because there is no equippedCardSkin to compare against.
    const equippable = {'banner', 'title', 'theme'};
    if (!equippable.contains(category)) return null;
    final equipped = switch (category) {
      'banner' => game.equippedBanner,
      'title' => game.equippedTitle,
      _ => game.equippedTheme,
    };
    if (equipped == itemKey) {
      // Not a button: there is nothing to do, and a live-looking control that
      // re-equips what is already on reads as if it failed the first time.
      return Container(
        width: double.infinity,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFEDE7F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_rounded, size: 18, color: Color(0xFF7E57C2)),
            const SizedBox(width: 6),
            Text(
              l10n.shopSheetEquipped,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7E57C2),
              ),
            ),
          ],
        ),
      );
    }
    return _sheetAction(
      sheetCtx,
      Icons.check_circle_outline,
      l10n.shopEquipNow,
      () {
        Navigator.pop(sheetCtx);
        game.equipItem(itemKey);
      },
    );
  }

  Widget _sheetAction(
    BuildContext ctx,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool compact = false,
  }) {
    return CartoonButton(
      height: 52,
      color: const Color(0xFFB08CFF),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Flexible(child: CartoonButton.label(label, size: compact ? 15 : 17)),
        ],
      ),
    );
  }

  /// effect_types the server shares one entitlement across duration tiers for
  /// (`buyItem`'s FEATURE_EFFECTS in db/database.js, plus profile_photo which
  /// gets the same treatment via its own branch) — a 7-day and 30-day row of
  /// these are the same thing, so owning either counts as owning the feature.
  /// Every other utility item (탈주 카운트 -1/-3, 전적 초기화권, …) is a
  /// separate one-shot consumable per item_key with no shared entitlement —
  /// matching those by effect_type would make owning one variant block buying
  /// a different one.
  static const _sharedFeatureEffects = {
    'top_card_counter',
    'mighty_trump_counter',
    'mighty_prev_trick',
    'profile_private',
    'custom_title',
    'profile_photo',
  };

  /// The inventory row that makes this item "owned".
  Map<String, dynamic>? _ownedEntitlement(
    GameService game,
    Map<String, dynamic> item,
  ) {
    final itemKey = item['item_key']?.toString() ?? '';
    final effectType = item['effect_type']?.toString() ?? '';
    final byKey = game.inventoryItems.where((i) => i['item_key'] == itemKey);
    if (byKey.isNotEmpty) return byKey.first;
    if (!_sharedFeatureEffects.contains(effectType)) return null;
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
    return CartoonButton(
      height: 60,
      color: extend ? Cartoon.blue : Cartoon.green,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            durationLabel,
            maxLines: 1,
            style: Cartoon.userText(
              size: 12,
              color: Colors.white,
              weight: FontWeight.w900,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GoldIcon(size: 15, amount: price),
                const SizedBox(width: 3),
                Cartoon.outlinedText(formatGold(price), size: 15),
                const SizedBox(width: 4),
                Cartoon.outlinedText(
                  extend ? l10n.shopButtonExtend : l10n.shopButtonPurchase,
                  size: 13,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The player's own equipped banner/title, read off their profile — the
  /// service tracks the title key but not its display name or the banner.
  // Live values first, cached profile second: equipping updates the service
  // immediately, while the profile is only as fresh as the last fetch — which
  // is why a preview kept showing the banner you had just replaced.
  String? _myBannerKey(GameService g) =>
      g.equippedBanner ?? _myProfile(g)?['bannerKey']?.toString();

  String? _myTitleName(GameService g) =>
      g.equippedTitleName ?? _myProfile(g)?['titleName']?.toString();

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
    'custom_title',
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
        // SuitIcon, not a '♠' glyph: the app paints its suits so they look the
        // same on every platform, and a system spade next to them is visibly a
        // different shape.
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
                SuitIcon(suit: 'spade', size: 14),
                SizedBox(width: 3),
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
      case 'custom_title':
        // Handled by the seat preview with a sample title — see the
        // titleOverride path in _buildItemPreview.
        return const SizedBox.shrink();
      default:
        // mighty_prev_trick — the little card row the button opens.
        return frame(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final card in const [
                ('spade', 'A'),
                ('heart', 'K'),
                ('spade', '3'),
              ])
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          card.$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color:
                                PlayingCard.suitColors[card.$1] ??
                                const Color(0xFF2E2E2E),
                          ),
                        ),
                        const SizedBox(height: 1),
                        SuitIcon(suit: card.$1, size: 11),
                      ],
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
    String? titleOverride,
  }) {
    final l10n = L10n.of(context);
    if (titleOverride == null && _previewEffects.contains(effectType)) {
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
                  fallback: DefaultAvatar(size: avatarSize),
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
                if (titleOverride != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TitleChip(
                      titleKey: 'custom:rose',
                      titleName: titleOverride,
                      onInk: textColor,
                    ),
                  )
                else if (isBanner && _myTitleName(g) != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TitleChip(
                      titleKey: g.equippedTitle,
                      titleName: _myTitleName(g),
                      // The whole point of this strip is showing the banner
                      // under your own name and title. On a dark one the title
                      // has to come up with the nickname.
                      onInk: textColor,
                    ),
                  )
                else if (!isBanner)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TitleChip(
                      titleKey: itemKey,
                      titleName: itemName,
                      onInk: textColor,
                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Cartoon.cream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Cartoon.ink, width: 2),
      ),
      child: Text(
        label,
        style: Cartoon.userText(size: 12, weight: FontWeight.w700),
      ),
    );
  }

  /// Editor for the user-written title.
  ///
  /// The live preview is the point: it is drawn with the same TitleChip the
  /// waiting room uses, so what is on screen here is exactly what other players
  /// will see — including that a custom title carries no icon.
  ///
  /// The 4-character limit and the character set are enforced here for feedback
  /// only; the server validates again and is the one that decides.
  void _showCustomTitleDialog(BuildContext context, GameService game) {
    final l10n = L10n.of(context);
    final profile = _myProfile(game);
    // Prefer what was last saved over the fetched profile: the save reply lands
    // immediately, the profile refetch does not, and reopening the editor in
    // between showed the previous title.
    final controller = TextEditingController(
      text:
          game.myCustomTitleText ??
          profile?['customTitleText']?.toString() ??
          '',
    );
    var colorId =
        game.myCustomTitleColor ??
        profile?['customTitleColor']?.toString() ??
        'rose';
    if (!customTitleColors.containsKey(colorId)) colorId = 'rose';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final text = controller.text.trim();
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: const Color(0xFFFDFBFA),
            title: Text(
              l10n.customTitleEditTitle,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4A3A33),
              ),
            ),
            // Scrollable: the keyboard is up the whole time this dialog is
            // open, and the preview plus the rule line do not fit in what is
            // left on a phone.
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.customTitleHint,
                        counterText: '',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.customTitlePreviewLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A7A72),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE6DDD8)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Nothing typed, nothing shown: the hint in the
                                // chip previewed a title that will never exist,
                                // and read as one already set.
                                if (text.isNotEmpty) ...[
                                  TitleChip(
                                    titleKey: 'custom:$colorId',
                                    titleName: text,
                                    fontSize: 12,
                                  ),
                                  const SizedBox(height: 2),
                                ],
                                Text(
                                  game.playerName.isEmpty
                                      ? l10n.shopPreviewNickname
                                      : game.playerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5A4038),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.customTitleColorLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A7A72),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in customTitleColors.entries)
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () =>
                                setSheetState(() => colorId = entry.key),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: entry.value,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorId == entry.key
                                      ? const Color(0xFF4A3A33)
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.customTitleRule,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Color(0xFF9A8E8A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.commonCancel),
              ),
              ElevatedButton(
                onPressed: text.isEmpty
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        game.setCustomTitle(text, colorId);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC7E6D0),
                  foregroundColor: const Color(0xFF2E5A3A),
                  elevation: 0,
                ),
                child: Text(l10n.customTitleSave),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Confirms switching a feature pass off (or back on).
  ///
  /// Off is the one that needs saying out loud: the days keep running, so
  /// turning it off is not a pause and the expiry date does not move.
  void _showFeatureToggleDialog(
    BuildContext context,
    GameService game,
    String effectType,
    bool currentlyOn,
  ) {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFFDFBFA),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
        contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
        title: Text(
          currentlyOn
              ? l10n.shopFeatureDisableTitle
              : l10n.shopFeatureEnableTitle,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF4A3A33),
          ),
        ),
        content: Text(
          currentlyOn
              ? l10n.shopFeatureDisableBody
              : l10n.shopFeatureEnableBody,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: Color(0xFF6A5A52),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.setFeatureEnabled(effectType, !currentlyOn);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyOn
                  ? const Color(0xFFF0DEDE)
                  : const Color(0xFFC7E6D0),
              foregroundColor: currentlyOn
                  ? const Color(0xFFA33F3F)
                  : const Color(0xFF2E5A3A),
              elevation: 0,
            ),
            child: Text(
              currentlyOn
                  ? l10n.shopFeatureDisableConfirm
                  : l10n.shopFeatureEnableConfirm,
            ),
          ),
        ],
      ),
    );
  }

  void _showNicknameChangeDialog(BuildContext context, GameService game) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
  Widget _buildCategoryTabs(List<String> labels, {List<bool>? badges}) {
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
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  for (var i = 0; i < labels.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _buildCategoryChip(
                      labels[i],
                      selected: controller.index == i,
                      badge: badges != null && badges[i],
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
    bool badge = false,
  }) {
    return CartoonPressable(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.elasticOut,
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Cartoon.blue : Cartoon.paper,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Cartoon.ink, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Cartoon.ink,
                offset: Offset(0, selected ? 3 : 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Cartoon.text(
                  size: 15,
                  color: selected ? Colors.white : Cartoon.ink,
                ),
              ),
              if (badge) ...[const SizedBox(width: 5), _newDot()],
            ],
          ),
        ),
      ),
    );
  }

  /// The 칭호 tab: the custom-title pass first, then the catalog titles.
  ///
  /// The pass is a 'feature' item on the server (an entitlement, not something
  /// to equip), so it only showed under 기능 — where nobody shopping for a title
  /// would look. It stays in 기능 too; this is the same item listed where it is
  /// relevant.
  List<Map<String, dynamic>> _titleTabItems(List<Map<String, dynamic>> items) {
    final custom = items
        .where((i) => (i['effect_type']?.toString() ?? '') == 'custom_title')
        .toList();
    return [...custom, ..._filterShop(items, 'title')];
  }

  /// The 프로필 tab: feature passes minus the custom title, which now lives in
  /// 칭호 where someone shopping for a title will look for it.
  List<Map<String, dynamic>> _profileTabItems(
    List<Map<String, dynamic>> items,
  ) {
    return items
        .where(
          (i) =>
              (i['category']?.toString() ?? '') == 'feature' &&
              (i['effect_type']?.toString() ?? '') != 'custom_title',
        )
        .toList();
  }

  /// Owned titles: the custom-title pass first, then owned catalog titles.
  /// Mirrors the shop tab, so the item is where it is looked for in both.
  List<Map<String, dynamic>> _titleInventoryItems(
    List<Map<String, dynamic>> items,
  ) {
    final custom = items
        .where((i) => (i['effect_type']?.toString() ?? '') == 'custom_title')
        .toList();
    return [...custom, ..._filterInventory(items, 'title')];
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
    String category,
  ) {
    final l10n = L10n.of(context);
    if (isSeason) {
      return l10n.shopTagSeason;
    }
    if (isPermanent) {
      // "영구" ("permanent") reads as "own it forever, like a cosmetic" — true
      // for a pioneer banner/theme, false for a one-shot consumable that
      // disappears from inventory the moment it's used.
      return category == 'utility'
          ? l10n.shopTagConsumable
          : l10n.shopTagPermanent;
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

  // ---- Daily attendance banner / dialog ------------------------------------
  // Banner stays visible all day — even after claim. After claim it just
  // switches to a "completed" look so users can still tap it to see the
  // 7-day grid in the dialog (claim button there is disabled).
  // Shown on the web too, but as an invitation rather than a control: the
  // reward is claimed by watching a rewarded ad and AdMob has no web
  // implementation, so the claim button there can never work. Hiding it left
  // web users unaware the daily gold exists at all; tapping it now explains
  // that and offers the store.
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

          return _AttendanceFx(
            claimedToday: claimedToday,
            reward: (s['todayRewardGold'] as int?) ?? 50,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
                side: const BorderSide(color: Cartoon.ink, width: 3),
              ),
              // Capped, not free-sizing. Dialog lets its child take whatever
              // width is on offer, and the rows inside are Expanded — so on a
              // desktop browser the seven-day strip stretched across the whole
              // window. A phone is narrower than this cap, so nothing about the
              // app layout changes.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Cartoon.yellow,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Cartoon.ink,
                                width: 2.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Cartoon.ink,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.event_available_rounded,
                              color: Cartoon.ink,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l.attendanceDialogTitle,
                              style: Cartoon.text(size: 22),
                            ),
                          ),
                          CartoonPressable(
                            scale: 0.88,
                            onTap: () => Navigator.pop(dialogCtx),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Cartoon.paper,
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: Cartoon.ink,
                                  width: 2.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Cartoon.ink,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Cartoon.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.attendanceResetInfo(resetClock),
                        style: Cartoon.userText(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: Cartoon.ink.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 이번 주 진행: 칸이 차오르는 막대
                      TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: (cycleClaimed / 7).clamp(0.0, 1.0),
                        ),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: Cartoon.ink,
                                    width: 2.2,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: v,
                                  child: Container(color: Cartoon.green),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              l.attendanceProgress(cycleClaimed),
                              style: Cartoon.text(size: 15),
                            ),
                          ],
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
                          return CartoonEntrance(
                            key: ValueKey('att-$day'),
                            delay: Duration(milliseconds: 60 * i),
                            from: const Offset(0, 16),
                            child: _attendanceDayCell(
                              day,
                              reward,
                              isClaimed,
                              isToday,
                              isFinale,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                      if (claimedToday)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD8F5DF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Cartoon.ink, width: 2.5),
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
                      else if (kIsWeb)
                        // Everything above is the same as in the app — which day,
                        // what today pays, the week's rewards. Only the action
                        // changes, because claiming happens in the app.
                        CartoonButton(
                          height: 52,
                          color: Cartoon.orange,
                          onPressed: () => openStoreUrl(
                            storeChoicesFor(defaultTargetPlatform).first.url,
                          ),
                          child: CartoonButton.label(
                            l.attendanceAppOnlyCta,
                            size: 17,
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
                            return CartoonButton(
                              height: 54,
                              color: Cartoon.orange,
                              onPressed: enabled
                                  ? () => _attendanceClaim(g)
                                  : null,
                              child: busy || !adReady
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!adReady && !busy && !claimed) ...[
                                          const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Flexible(
                                          child: CartoonButton.label(
                                            busy
                                                ? l.attendanceClaiming
                                                : l.attendanceAdLoading,
                                            size: 16,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.play_circle_fill_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: CartoonButton.label(
                                            l.attendanceWatchAdAndClaim(
                                              (s['todayRewardGold'] as int?) ??
                                                  50,
                                            ),
                                            size: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
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
        ? const Color(0xFFD8F5DF)
        : today
        ? Cartoon.yellow
        : finale
        ? const Color(0xFFFFE6B8)
        : Colors.white;
    final cell = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Cartoon.ink, width: today ? 3 : 2.2),
        boxShadow: [
          BoxShadow(color: Cartoon.ink, offset: Offset(0, today ? 4 : 2)),
        ],
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
            Text('Day $day', style: Cartoon.text(size: 13)),
            const SizedBox(height: 4),
            claimed
                ? _StampCheck(size: finale ? 26 : 22, delay: 120 * day)
                : (finale
                      ? CartoonFloat(
                          amplitude: 2.5,
                          child: GoldIcon(size: 26, amount: reward),
                        )
                      : GoldIcon(size: 22, amount: reward)),
            const SizedBox(height: 4),
            Text(
              '$reward',
              style: Cartoon.text(
                size: finale ? 17 : 14,
                color: finale ? const Color(0xFFE65100) : Cartoon.ink,
              ),
            ),
          ],
        ),
      ),
    );
    // 오늘 받을 칸은 숨 쉬듯 움직여서 눈에 띈다.
    return today ? CartoonPulse(amount: 0.05, child: cell) : cell;
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

/// 출석 도장: 크게 떨어져 "쾅" 찍힌다. 칸이 처음 그려질 때(이미 받은 날) 차례로,
/// 방금 받은 오늘 칸은 바뀌는 순간 한 번 찍힌다.
class _StampCheck extends StatefulWidget {
  const _StampCheck({required this.size, this.delay = 0});

  final double size;
  final int delay;

  @override
  State<_StampCheck> createState() => _StampCheckState();
}

class _StampCheckState extends State<_StampCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(milliseconds: 250 + widget.delay), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // 2.4배에서 1배로 내리꽂힌 뒤 살짝 튕긴다.
        final drop = Curves.easeIn.transform((t / 0.55).clamp(0.0, 1.0));
        final settle = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
        final scale =
            2.4 - 1.4 * drop + 0.12 * math.sin(settle * math.pi) * (1 - settle);
        return Opacity(
          opacity: (t / 0.2).clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: -0.35 * (1 - drop) - 0.1 * drop,
            child: Transform.scale(
              scale: scale,
              child: Icon(
                Icons.check_circle_rounded,
                color: Cartoon.green,
                size: widget.size,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 출석을 받는 순간(claimedToday 가 false → true) 색종이와 "+골드" 가 터진다.
/// 팝업이 열리자마자 이미 받은 상태면 아무것도 하지 않는다.
class _AttendanceFx extends StatefulWidget {
  const _AttendanceFx({
    required this.claimedToday,
    required this.reward,
    required this.child,
  });

  final bool claimedToday;
  final int reward;
  final Widget child;

  @override
  State<_AttendanceFx> createState() => _AttendanceFxState();
}

class _AttendanceFxState extends State<_AttendanceFx>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  int _burst = 0;

  @override
  void didUpdateWidget(_AttendanceFx old) {
    super.didUpdateWidget(old);
    if (!old.claimedToday && widget.claimedToday) {
      _burst++;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        if (_burst > 0) ...[
          Positioned.fill(
            child: CartoonConfetti(key: ValueKey('att-$_burst'), seed: _burst),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                final pop = Curves.elasticOut.transform(
                  (t / 0.35).clamp(0.0, 1.0),
                );
                final fade = 1 - ((t - 0.7) / 0.3).clamp(0.0, 1.0);
                return Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(0, -70 * t),
                    child: Transform.scale(
                      scale: 0.4 + 0.6 * pop,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GoldIcon(size: 44, amount: widget.reward),
                          const SizedBox(width: 8),
                          Cartoon.outlinedText(
                            '+${widget.reward}',
                            size: 52,
                            fill: Cartoon.yellow,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
