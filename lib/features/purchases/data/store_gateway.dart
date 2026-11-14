import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show BillingResponse, BillingResultWrapper;
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    show GooglePlayPurchaseDetails, InAppPurchaseAndroidPlatformAddition;

/// The slice of the native `in_app_purchase` plugin Bondbell uses.
///
/// A seam because `InAppPurchase` is concrete and touching its instance
/// registers the platform channel. The real gateway is created in `main()`;
/// tests use a fake that emits [PurchaseDetails] on [purchaseStream], the
/// only place the plugin reports how a purchase ended.
abstract class StoreGateway {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids);

  /// Only reports that the payment sheet was presented.
  Future<bool> buyNonConsumable(ProductDetails product);

  /// Tips. Bought WITHOUT the plugin's auto-consume: every tip, whether
  /// it arrives fresh, after the app was killed mid-purchase, or from a
  /// restore, is consumed through [finishConsumable], so there is exactly
  /// one path that frees the product to be bought again.
  Future<bool> buyConsumable(ProductDetails product);
  Future<void> restorePurchases();
  Future<void> completePurchase(PurchaseDetails details);

  /// Ends a consumable for good. Play: consumes it (which also acknowledges
  /// it), even when an earlier session already acknowledged it, because an
  /// acknowledged-but-unconsumed tip stays "owned" and cannot be bought
  /// again. App Store: finishing the transaction is all a consumable needs.
  Future<void> finishConsumable(PurchaseDetails details);
}

class NativeStoreGateway implements StoreGateway {
  NativeStoreGateway() : _iap = InAppPurchase.instance;
  final InAppPurchase _iap;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;
  @override
  Future<bool> isAvailable() => _iap.isAvailable();
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) =>
      _iap.queryProductDetails(ids);
  @override
  Future<bool> buyNonConsumable(ProductDetails product) => _iap
      .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  @override
  Future<bool> buyConsumable(ProductDetails product) => _iap.buyConsumable(
    purchaseParam: PurchaseParam(productDetails: product),
    autoConsume: false,
  );
  @override
  Future<void> restorePurchases() => _iap.restorePurchases();
  @override
  Future<void> completePurchase(PurchaseDetails details) =>
      _iap.completePurchase(details);
  @override
  Future<void> finishConsumable(PurchaseDetails details) async {
    if (details is GooglePlayPurchaseDetails) {
      final BillingResultWrapper r = await _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
          .consumePurchase(details);
      if (r.responseCode != BillingResponse.ok) {
        throw StateError('consume failed: ${r.responseCode}');
      }
      return;
    }
    if (details.pendingCompletePurchase) await _iap.completePurchase(details);
  }
}

/// Used when the store can't be reached at all (and in widget tests that
/// don't care about purchases): never available, never emits.
class OfflineStoreGateway implements StoreGateway {
  const OfflineStoreGateway();
  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      const Stream<List<PurchaseDetails>>.empty();
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: const <ProductDetails>[],
        notFoundIDs: ids.toList(),
      );
  @override
  Future<bool> buyNonConsumable(ProductDetails product) async => false;
  @override
  Future<bool> buyConsumable(ProductDetails product) async => false;
  @override
  Future<void> restorePurchases() async {}
  @override
  Future<void> completePurchase(PurchaseDetails details) async {}
  @override
  Future<void> finishConsumable(PurchaseDetails details) async {}
}
