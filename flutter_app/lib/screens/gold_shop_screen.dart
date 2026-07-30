import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/game_service.dart';
import '../services/iap_service.dart';
import '../widgets/gold_icon.dart';

class GoldShopScreen extends StatefulWidget {
  const GoldShopScreen({super.key});

  @override
  State<GoldShopScreen> createState() => _GoldShopScreenState();
}

class _GoldShopScreenState extends State<GoldShopScreen> {
  late final IapService _iap;
  bool _storeReady = false;
  bool _storeUnavailable = false;
  bool _detailsRequested = false;
  String? _busyProductId;
  Map<String, ProductDetails> _details = {};

  @override
  void initState() {
    super.initState();
    final game = context.read<GameService>();
    // Use the APP-LIVED instance (not a screen-scoped one) so pending-purchase
    // reconciliation keeps working after this screen is closed.
    game.ensureIapStarted();
    _iap = game.iap!;
    _iap
      ..onSuccess = _handleSuccess
      ..onError = _handleError
      ..onPending = () {
        _toast('결제 처리 중입니다...');
      }
      ..onSettled = (_) {
        if (mounted) setState(() => _busyProductId = null);
      };
    _initStore();
    // requestGoldProducts() calls notifyListeners() synchronously. initState
    // can run mid-build (e.g. this screen re-inflated during a GameService-
    // triggered ShopScreen rebuild after a prior purchase), so defer it to
    // after the current frame to avoid "notifyListeners during build".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      game.requestGoldProducts();
    });
  }

  Future<void> _initStore() async {
    await _iap.init();
    if (!mounted) return;
    setState(() {
      _storeReady = _iap.isAvailable;
      _storeUnavailable = !_iap.isAvailable;
    });
  }

  // Server list arrives via WS after requestGoldProducts(); once we have the
  // product ids, resolve their store price/currency exactly once.
  Future<void> _loadStoreDetails(List<Map<String, dynamic>> products) async {
    if (_detailsRequested || !_storeReady || products.isEmpty) return;
    _detailsRequested = true;
    final ids = products
        .map((p) => p['product_id']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    final details = await _iap.loadProducts(ids);
    if (!mounted) return;
    setState(() {
      _details = {for (final d in details) d.id: d};
    });
  }

  void _handleSuccess(int granted, int newGold) {
    if (!mounted) return;
    if (granted <= 0) {
      _toast('이미 처리된 결제입니다.');
      return;
    }
    // Real-money purchase deserves a clear confirmation (not just a 3s toast),
    // and should surface the new balance.
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF66BB6A), size: 52),
            const SizedBox(height: 14),
            const Text('결제 완료',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
            const SizedBox(height: 8),
            Text('+$granted 골드가 지급되었습니다',
                style: const TextStyle(fontSize: 15, color: Color(0xFF5A4038))),
            const SizedBox(height: 4),
            Text('보유 골드 $newGold',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFB35B19))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _handleError(String message) {
    if (!mounted) return;
    _toast('결제 실패: $message');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _buy(Map<String, dynamic> product) async {
    final id = product['product_id']?.toString() ?? '';
    final pd = _details[id];
    if (pd == null) {
      _toast('스토어에서 상품 정보를 불러오지 못했습니다.');
      return;
    }
    setState(() => _busyProductId = id);
    try {
      await _iap.buy(pd);
    } catch (e) {
      if (mounted) setState(() => _busyProductId = null);
      _toast('결제를 시작할 수 없습니다: $e');
    }
  }

  @override
  void dispose() {
    // The IAP service is app-lived (owned by GameService) — do NOT dispose it
    // here or pending-purchase reconciliation would stop. Just detach our UI
    // callbacks so this screen's State can be GC'd; background reconciliation
    // (verify + completePurchase + balance update) continues without them.
    if (identical(_iap.onSuccess, _handleSuccess)) _iap.onSuccess = null;
    if (identical(_iap.onError, _handleError)) _iap.onError = null;
    _iap.onPending = null;
    _iap.onSettled = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    // Same shape as the shop it opens from: theme gradient, transparent header,
    // and one white sheet holding the list. It used to be a stock AppBar with a
    // Material Card per tier, which looked like a different app.
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
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFDFC),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Consumer<GameService>(
                    builder: (context, game, _) => _buildBody(game),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 16, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            color: const Color(0xFF8A7A72),
            visualDensity: VisualDensity.compact,
          ),
          const Text(
            '골드 충전',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const Spacer(),
          const GoldIcon(size: 20),
          const SizedBox(width: 5),
          Consumer<GameService>(
            builder: (_, game, _) => Text(
              _fmt(game.gold),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(GameService game) {
    if (_storeUnavailable) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '이 기기에서는 인앱결제를 사용할 수 없습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8A7A72)),
          ),
        ),
      );
    }
    if (game.goldProductsLoading && game.goldProducts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final products = game.goldProducts;
    if (products.isEmpty) {
      return const Center(
        child: Text(
          '판매 중인 골드 상품이 없습니다.',
          style: TextStyle(color: Color(0xFF8A7A72)),
        ),
      );
    }
    // Trigger store lookup after the server list is in.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadStoreDetails(products));

    // Best bonus rate gets a marker, so the tiers are comparable at a glance
    // instead of five near-identical rows.
    var bestPct = 0;
    for (final p in products) {
      final base = (p['gold_amount'] ?? 0) as int;
      final bonus = (p['bonus_gold'] ?? 0) as int;
      if (base > 0) {
        final pct = ((bonus / base) * 100).round();
        if (pct > bestPct) bestPct = pct;
      }
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      itemCount: products.length + 1,
      separatorBuilder: (_, index) => index == products.length - 1
          ? const SizedBox(height: 12)
          : const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: Color(0xFFF2ECE9),
            ),
      itemBuilder: (context, i) {
        if (i == products.length) return _purchaseNotice();
        return _buildTierRow(products[i], bestPct, i, products.length);
      },
    );
  }

  Widget _buildTierRow(
    Map<String, dynamic> product,
    int bestPct,
    int index,
    int count,
  ) {
    final id = product['product_id']?.toString() ?? '';
    final base = (product['gold_amount'] ?? 0) as int;
    final bonus = (product['bonus_gold'] ?? 0) as int;
    final total = base + bonus;
    // Computed from base/bonus so the % is always correct and shown even if the
    // admin label omits it.
    final bonusPct = base > 0 ? ((bonus / base) * 100).round() : 0;
    final isBest = bonusPct > 0 && bonusPct == bestPct;
    final pd = _details[id];
    final busy = _busyProductId == id;
    final pending = busy || pd == null;

    // Five identical coin icons said nothing about which tier was which. The
    // badge grows and deepens with the amount, so the ladder is readable before
    // any number is.
    final t = count > 1 ? index / (count - 1) : 0.0;
    final badgeSize = 38 + 10 * t;
    final iconCount = index >= count - 1
        ? 3
        : index >= (count - 1) / 2
            ? 2
            : 1;
    final badgeGradient = [
      Color.lerp(const Color(0xFFFFF1CC), const Color(0xFFFFD166), t)!,
      Color.lerp(const Color(0xFFFFD98A), const Color(0xFFF5A623), t)!,
    ];

    return Container(
      color: isBest ? const Color(0xFFFFFBF2) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: badgeGradient,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  iconCount,
                  (i) => Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 1),
                    child: GoldIcon(
                      size: iconCount == 1 ? 24 : (iconCount == 2 ? 19 : 15),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _fmt(total),
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4A3A33),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '골드',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9A8E8A),
                      ),
                    ),
                    if (bonus > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '+$bonusPct%',
                          style: const TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (bonus > 0) ...[
                  const SizedBox(height: 2),
                  // "최대 혜택" sits here, not up with the amount: on the top
                  // line a third chip squeezed the biggest tier's number until
                  // it rendered smaller than the cheaper ones.
                  Row(
                    children: [
                      if (isBest) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '최대 혜택',
                            style: TextStyle(
                              color: Color(0xFFE07A1F),
                              fontWeight: FontWeight.bold,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          // Shorter than "기본 X + 보너스 Y": with the 최대 혜택
                          // badge beside it, that form got ellipsised exactly on
                          // the tier it mattered for.
                          '보너스 +${_fmt(bonus)} 포함',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF2E7D32),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // The price IS the button — there is nothing else to press on a row.
          SizedBox(
            width: 96,
            height: 38,
            child: ElevatedButton(
              onPressed: pending ? null : () => _buy(product),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFE9B0),
                foregroundColor: const Color(0xFFB07A12),
                disabledBackgroundColor: const Color(0xFFF0EBE7),
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              // Spinner both while the purchase is in-flight AND while the store
              // price is still resolving (pd == null) — clearer than a disabled
              // "..." that looks broken.
              child: pending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        pd.price,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Pre-purchase disclosure required by 전자상거래법 / 콘텐츠이용자보호지침.
  // Wording is a baseline; the seller is responsible for final/legal review
  // and for filling real 사업자정보 into the EULA/privacy policy.
  //
  // The two lines that actually change a purchase decision (no cash-out, spent
  // gold is not refundable) stay visible; the procedural rest is one tap away.
  // A six-bullet wall used to take a third of the screen above the fold.
  Widget _purchaseNotice() {
    const muted = TextStyle(
      fontSize: 11.5,
      color: Color(0xFF8A8A8A),
      height: 1.5,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDE4DE)),
      ),
      child: Theme(
        // Strips the ExpansionTile's own divider lines, which fight the border.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '구매 전 안내',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '• 골드는 게임 내에서만 사용하는 유료 디지털 콘텐츠이며 현금 환전·환급·양도가 불가합니다.\n'
              '• 결제 즉시 사용 가능한 콘텐츠로, 이미 사용한 골드는 청약철회(환불) 대상에서 제외됩니다.',
              style: muted,
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              minTileHeight: 40,
              title: const Text(
                '환불·결제 문의 등 자세한 안내',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A7A72),
                ),
              ),
              children: const [
                Text(
                  '• 환불·결제취소는 Apple App Store / Google Play의 정책 및 절차에 따릅니다.\n'
                  '• 미성년자는 법정대리인의 동의 후 결제해야 하며, 동의 없는 결제는 취소될 수 있습니다.\n'
                  '• 결제 관련 문의: 설정 > 문의하기 > \'결제·환불\'\n'
                  '• 판매자 정보 및 환불 정책 상세는 설정의 이용약관·개인정보처리방침에 표기됩니다.',
                  style: muted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
