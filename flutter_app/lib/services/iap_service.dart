import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:crypto/crypto.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Thin wrapper around the in_app_purchase plugin.
///
/// This service is APP-LIVED (owned by GameService), not screen-scoped: the
/// purchaseStream listener must stay alive for the whole session so that a
/// purchase left unfinished after a transient verify failure is re-delivered
/// and reconciled on the next app launch — even if the user never reopens the
/// gold shop. The shop screen only attaches UI callbacks while it is visible;
/// reconciliation (verify + completePurchase + balance update via the WS
/// iap_purchase_result handler) works with no callbacks attached.
///
/// The client never hardcodes product ids: the caller fetches the active list
/// from the server and passes the ids into [loadProducts]. The store is the
/// source of truth for price/currency; the server is the source of truth for
/// how much gold each product grants and whether the grant succeeded.
typedef IapVerify = Future<Map<String, dynamic>> Function({
  required String productId,
  required String verificationData,
  String? transactionId,
});

class IapService {
  IapService({required this.verify, this.accountNameProvider});

  /// Sends the store receipt to the server and returns the server verdict.
  final IapVerify verify;

  /// Returns the authenticated user's current nickname (read lazily so a
  /// rename is always reflected). Hashed into the store account-binding token.
  final String? Function()? accountNameProvider;

  /// Deterministic account-binding UUID. StoreKit 2's appAccountToken MUST be
  /// a UUID, so we derive an RFC-4122-shaped UUID from sha256(nickname). Must
  /// be byte-for-byte identical to the server's accountBinding.bindingUuid().
  String? get _boundAccountId {
    final n = accountNameProvider?.call();
    if (n == null || n.isEmpty) return null;
    final b = List<int>.from(sha256.convert(utf8.encode(n)).bytes.sublist(0, 16));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4 shape
    b[8] = (b[8] & 0x3f) | 0x80; // RFC-4122 variant
    final x = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${x.substring(0, 8)}-${x.substring(8, 12)}-${x.substring(12, 16)}'
        '-${x.substring(16, 20)}-${x.substring(20, 32)}';
  }

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Future<void>? _initFuture;
  // Global serialization gate for verification (see _onPurchaseUpdates).
  Future<void> _verifyChain = Future<void>.value();

  bool _available = false;
  bool get isAvailable => _available;

  /// Fired with (goldGranted, newGold) after the server confirms a grant.
  void Function(int goldGranted, int newGold)? onSuccess;

  /// Fired with a user-facing message when a purchase fails or is rejected.
  void Function(String message)? onError;

  /// Fired when a purchase enters the pending state (e.g. ask-to-buy).
  void Function()? onPending;

  /// Fired when the buy flow settles (success or failure) so the UI can clear
  /// any per-product spinner.
  void Function(String productId)? onSettled;

  /// Idempotent and concurrency-safe: callers share one in-flight future, so
  /// the purchaseStream listener is attached exactly once even if app
  /// bootstrap and the shop screen both call init() at the same time.
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    // macOS is not an IAP sales target. The client would otherwise send the
    // wrong platform string and every purchase would fail after payment —
    // block it outright so the store flow can't even be entered.
    if (Platform.isMacOS) {
      _available = false;
      return;
    }
    _available = await _iap.isAvailable();
    if (!_available) {
      // Clear the memo so a later attempt (e.g. after connectivity) can retry
      // and still attach the listener.
      _initFuture = null;
      return;
    }
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (e) => onError?.call('$e'),
    );
  }

  Future<List<ProductDetails>> loadProducts(List<String> ids) async {
    if (!_available || ids.isEmpty) return const [];
    final resp = await _iap.queryProductDetails(ids.toSet());
    return resp.productDetails;
  }

  Future<void> buy(ProductDetails product) async {
    // applicationUserName → SKPayment.applicationUsername (iOS) /
    // obfuscatedAccountId (Android). Binds the purchase to this account so a
    // stolen receipt can't be redeemed elsewhere (server-enforced on Android).
    final param = PurchaseParam(
      productDetails: product,
      applicationUserName: _boundAccountId,
    );
    // Consumable: autoConsume so Android marks it consumable again. Server-side
    // idempotency (transaction_id) is what actually prevents double-granting,
    // not consumption timing.
    await _iap.buyConsumable(purchaseParam: param, autoConsume: true);
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          onPending?.call();
          break;
        case PurchaseStatus.canceled:
          onSettled?.call(p.productID);
          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          break;
        case PurchaseStatus.error:
          onError?.call(p.error?.message ?? 'purchase_error');
          onSettled?.call(p.productID);
          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Serialize ALL verifications globally. The plugin can emit a new
          // stream event (a fresh user purchase) while a background
          // reconciliation of a prior pending purchase is still awaiting the
          // server; running them concurrently would race the single
          // server-side result completer and cross-wire results. Chaining
          // guarantees strictly one verify in flight at a time.
          _verifyChain = _verifyChain
              .then((_) => _verifyAndComplete(p))
              .catchError((_) {});
          await _verifyChain;
          break;
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails p) async {
    // Only finish the store transaction when the purchase is resolved for
    // good: server granted it, OR server says the receipt is permanently
    // invalid (result['finish'] == true). On a transient failure/timeout we
    // must NOT finish — consumables are never re-delivered via restore, so
    // finishing now would permanently lose a paid purchase. Leaving it
    // unfinished makes the plugin re-deliver it on the next launch and we
    // retry verification then (server grant is idempotent).
    bool mayFinish = false;
    try {
      final result = await verify(
        productId: p.productID,
        verificationData: p.verificationData.serverVerificationData,
        // The exact transaction being settled. Lets the server grant only
        // this one instead of every accumulated receipt entry.
        transactionId: p.purchaseID,
      ).timeout(const Duration(seconds: 20));
      if (result['success'] == true) {
        mayFinish = true;
        final granted = (result['goldGranted'] ?? 0) as int;
        final newGold = (result['newGold'] ?? 0) as int;
        onSuccess?.call(granted, newGold);
      } else {
        mayFinish = result['finish'] == true;
        onError?.call((result['message'] as String?) ?? 'verify_failed');
      }
    } catch (e) {
      // Network/timeout/unknown → transient. Keep the transaction pending.
      mayFinish = false;
      onError?.call('$e');
    } finally {
      onSettled?.call(p.productID);
      if (mayFinish && p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initFuture = null;
  }
}
