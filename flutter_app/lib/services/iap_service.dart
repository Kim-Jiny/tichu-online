import 'dart:async';
import 'dart:io' show Platform;
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
  IapService({required this.verify, this.bindingTokenProvider});

  /// Sends the store receipt to the server and returns the server verdict.
  final IapVerify verify;

  /// Returns the server-issued immutable account-binding token (a UUID derived
  /// from tc_users.id, delivered in login_success). Used AS-IS — never rehash;
  /// the server compares the exact value it issued.
  final String? Function()? bindingTokenProvider;

  /// StoreKit 2's appAccountToken / Android's obfuscatedAccountId. Already a
  /// valid UUID from the server; null when unauthenticated.
  String? get _boundAccountId {
    final t = bindingTokenProvider?.call();
    return (t == null || t.isEmpty) ? null : t;
  }

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Future<void>? _initFuture;
  // Global serialization gate for verification (see _onPurchaseUpdates).
  Future<void> _verifyChain = Future<void>.value();

  // Transaction ids already verified+granted this session. iOS in_app_purchase
  // re-emits the same purchase on purchaseStream (notably the first purchase),
  // which would otherwise trigger a second server verify — harmless for gold
  // (server is idempotent on transaction_id) but it litters the IAP attempt
  // log with a duplicate "already_granted" row. Skip the redundant round-trip
  // and just finish the store transaction.
  final Set<String> _settledTxns = {};

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
    // Already verified+granted this transaction this session (duplicate
    // purchaseStream emission): don't re-hit the server. Still finish the
    // store transaction so the plugin stops re-delivering it.
    final txnId = p.purchaseID;
    if (txnId != null && txnId.isNotEmpty && _settledTxns.contains(txnId)) {
      onSettled?.call(p.productID);
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
      return;
    }

    // Only finish the store transaction when the purchase is resolved for
    // good: server granted it, OR server says the receipt is permanently
    // invalid (result['finish'] == true). On a transient failure/timeout we
    // must NOT finish — consumables are never re-delivered via restore, so
    // finishing now would permanently lose a paid purchase. Leaving it
    // unfinished makes the plugin re-deliver it on the next launch and we
    // retry verification then (server grant is idempotent).
    bool mayFinish = false;
    try {
      // verify() self-times-out (25s) and resolves with a failure map plus
      // correlation cleanup — no local .timeout() here, which would otherwise
      // abandon the request while a late response could still mis-resolve it.
      final result = await verify(
        productId: p.productID,
        verificationData: p.verificationData.serverVerificationData,
        // The exact transaction being settled. Lets the server grant only
        // this one instead of every accumulated receipt entry.
        transactionId: p.purchaseID,
      );
      if (result['success'] == true) {
        mayFinish = true;
        if (txnId != null && txnId.isNotEmpty) _settledTxns.add(txnId);
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
