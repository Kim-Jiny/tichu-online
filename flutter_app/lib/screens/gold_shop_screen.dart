import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/game_service.dart';
import '../services/iap_service.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('골드 충전'),
        actions: [
          Consumer<GameService>(
            builder: (_, game, _) => Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    const Icon(Icons.monetization_on,
                        color: Color(0xFFFFC107), size: 20),
                    const SizedBox(width: 4),
                    Text('${game.gold}',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Consumer<GameService>(
        builder: (context, game, _) {
          if (_storeUnavailable) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '이 기기에서는 인앱결제를 사용할 수 없습니다.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (game.goldProductsLoading && game.goldProducts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = game.goldProducts;
          if (products.isEmpty) {
            return const Center(child: Text('판매 중인 골드 상품이 없습니다.'));
          }
          // Trigger store lookup after the server list is in.
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _loadStoreDetails(products));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            // +1 for the legally-required pre-purchase disclosure footer.
            itemCount: products.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == products.length) return _purchaseNotice();
              final p = products[i];
              final id = p['product_id']?.toString() ?? '';
              final base = (p['gold_amount'] ?? 0) as int;
              final bonus = (p['bonus_gold'] ?? 0) as int;
              final total = base + bonus;
              // Computed from base/bonus so the % is always correct and
              // shown even if the admin label omits it.
              final bonusPct =
                  base > 0 ? ((bonus / base) * 100).round() : 0;
              final pd = _details[id];
              final priceText = pd?.price ?? '...';
              final busy = _busyProductId == id;

              return Card(
                child: ListTile(
                  leading: const Icon(Icons.monetization_on,
                      color: Color(0xFFFFC107), size: 36),
                  title: Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) {
                            const numStyle = TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17);
                            final numStr = _fmt(total);
                            final fullStr = '$numStr Gold';
                            double textW(String s) {
                              final tp = TextPainter(
                                text: TextSpan(
                                    text: s, style: numStyle),
                                maxLines: 1,
                                textDirection: TextDirection.ltr,
                              )..layout();
                              return tp.width;
                            }

                            // 1) Full "N Gold" fits → show it.
                            if (textW(fullStr) <= c.maxWidth) {
                              return Text(fullStr,
                                  maxLines: 1, style: numStyle);
                            }
                            // 2) Drop " Gold", keep the number if it fits.
                            if (textW(numStr) <= c.maxWidth) {
                              return Text(numStr,
                                  maxLines: 1, style: numStyle);
                            }
                            // 3) Number alone still too wide → shrink it.
                            return FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(numStr,
                                  maxLines: 1, style: numStyle),
                            );
                          },
                        ),
                      ),
                      if (bonus > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
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
                  subtitle: bonus > 0
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '기본 ${_fmt(base)} + 보너스 ${_fmt(bonus)}',
                            maxLines: 1,
                            style: const TextStyle(
                                color: Color(0xFF2E7D32), fontSize: 12),
                          ),
                        )
                      : null,
                  trailing: ElevatedButton(
                    onPressed:
                        (busy || pd == null) ? null : () => _buy(p),
                    // Spinner both while the purchase is in-flight AND while the
                    // store price is still resolving (pd == null) — clearer than
                    // a disabled "..." that looks broken.
                    child: (busy || pd == null)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : Text(priceText),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Pre-purchase disclosure required by 전자상거래법 / 콘텐츠이용자보호지침.
  // Wording is a baseline; the seller is responsible for final/legal review
  // and for filling real 사업자정보 into the EULA/privacy policy.
  Widget _purchaseNotice() {
    const muted = TextStyle(fontSize: 11.5, color: Color(0xFF8A8A8A), height: 1.5);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6DECF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('구매 전 안내',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038))),
          SizedBox(height: 8),
          Text(
            '• 골드는 게임 내에서만 사용하는 유료 디지털 콘텐츠이며 현금 환전·환급·양도가 불가합니다.\n'
            '• 결제 즉시 사용 가능한 콘텐츠로, 이미 사용한 골드는 청약철회(환불) 대상에서 제외됩니다.\n'
            '• 환불·결제취소는 Apple App Store / Google Play의 정책 및 절차에 따릅니다.\n'
            '• 미성년자는 법정대리인의 동의 후 결제해야 하며, 동의 없는 결제는 취소될 수 있습니다.\n'
            '• 결제 관련 문의: 설정 > 문의하기 > \'결제·환불\'\n'
            '• 판매자 정보 및 환불 정책 상세는 설정의 이용약관·개인정보처리방침에 표기됩니다.',
            style: muted,
          ),
        ],
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
