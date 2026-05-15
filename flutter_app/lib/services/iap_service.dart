import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:crypto/crypto.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Thin wrapper around the in_app_purchase plugin.
///
/// The client never hardcodes product ids: the caller fetches the active list
/// from the server and passes the ids into [loadProducts]. The store is the
/// source of truth for price/currency; the server is the source of truth for
/// how much gold each product grants and whether the grant succeeded.
typedef IapVerify = Future<Map<String, dynamic>> Function({
  required String productId,
  required String verificationData,
});

class IapService {
  IapService({required this.verify, this.accountName});

  /// Sends the store receipt to the server and returns the server verdict.
  final IapVerify verify;

  /// Authenticated user's nickname. Stamped onto the purchase (hashed) so the
  /// server can reject a receipt redeemed on a different account.
  final String? accountName;

  /// sha256(nickname) hex — the store account-binding token. Must match the
  /// server's crypto.createHash('sha256').update(nickname).digest('hex').
  String? get _boundAccountId {
    final n = accountName;
    if (n == null || n.isEmpty) return null;
    return sha256.convert(utf8.encode(n)).toString();
  }

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

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

  Future<void> init() async {
    // macOS is not an IAP sales target. The client would otherwise send the
    // wrong platform string and every purchase would fail after payment —
    // block it outright so the store flow can't even be entered.
    if (Platform.isMacOS) {
      _available = false;
      return;
    }
    _available = await _iap.isAvailable();
    if (!_available) return;
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
          await _verifyAndComplete(p);
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
  }
}
