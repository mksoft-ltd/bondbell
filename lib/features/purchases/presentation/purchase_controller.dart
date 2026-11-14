import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show PurchaseStateWrapper;
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    show GooglePlayPurchaseDetails;

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/local_store.dart';
import '../data/store_gateway.dart';
import '../../../core/utils/app_log.dart';

/// Overridden in `main()` with [NativeStoreGateway], in tests with a fake.
final Provider<StoreGateway> storeGatewayProvider = Provider<StoreGateway>(
  (Ref ref) => const OfflineStoreGateway(),
);

/// Debug-only override for screenshots (SCREENSHOT_MODE); always false in
/// release builds.
final Provider<bool> forceProProvider = Provider<bool>((Ref ref) => false);

enum PurchaseNotice {
  proPurchased,
  restored,
  nothingToRestore,
  tipThanks,

  /// A tip left unfinished by an earlier session blocked this one; it has
  /// now been cleared, so the user can simply try again.
  tipCleared,
  cancelled,
  failed,
  pending,
  storeUnavailable,
}

@immutable
class PurchaseState {
  const PurchaseState({
    this.proOwned = false,
    this.busy = false,
    this.storeAvailable = false,
    this.prices = const <String, String>{},
    this.notice,
    this.noticeSerial = 0,
  });

  final bool proOwned;
  final bool busy;
  final bool storeAvailable;

  /// productId → the store's own localised price string (never hardcoded).
  final Map<String, String> prices;
  final PurchaseNotice? notice;
  final int noticeSerial;

  PurchaseState copyWith({
    bool? proOwned,
    bool? busy,
    bool? storeAvailable,
    Map<String, String>? prices,
    PurchaseNotice? notice,
  }) => PurchaseState(
    proOwned: proOwned ?? this.proOwned,
    busy: busy ?? this.busy,
    storeAvailable: storeAvailable ?? this.storeAvailable,
    prices: prices ?? this.prices,
    notice: notice ?? this.notice,
    noticeSerial: notice == null ? noticeSerial : noticeSerial + 1,
  );
}

/// Bondbell Pro (one-time, non-consumable) and the tip jar (consumables
/// that unlock nothing), on the native `in_app_purchase` plugin.
///
/// `buy*` only reports that the sheet opened; every outcome arrives on the
/// purchase stream, so cancel/error/pending clear [PurchaseState.busy]
/// there, with a ceiling in case nothing ever arrives.
class PurchaseController extends Notifier<PurchaseState> {
  static const String proKey = 'purchases.proOwned';
  static const Duration busyCeiling = Duration(seconds: 75);
  static const Duration restoreWindow = Duration(seconds: 4);

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Map<String, ProductDetails> _products = <String, ProductDetails>{};
  Timer? _busyTimer;
  bool _restoring = false;
  bool _restoreFound = false;

  /// Play reports a cancelled or failed purchase with an EMPTY product id;
  /// such an event belongs to the purchase in flight, and only to it.
  bool _purchasing = false;

  /// The product id of the purchase in flight. Play reports errors (cancel,
  /// "item already owned") with an EMPTY product id, so this is the only
  /// way to tell what such an event is about (code review m1).
  String? _purchasingId;

  StoreGateway get _store => ref.read(storeGatewayProvider);
  LocalStore get _local => ref.read(localStoreProvider);

  static const Set<String> _allIds = <String>{
    AppConstants.proProductId,
    ...<String>{
      AppConstants.tipSmallId,
      AppConstants.tipMediumId,
      AppConstants.tipLargeId,
    },
  };

  @override
  PurchaseState build() {
    // Subscribe now: a purchase completed while the app was closed is
    // delivered in the first frames after launch.
    _sub = _store.purchaseStream.listen(
      _onPurchases,
      onError: (Object _) => _finish(PurchaseNotice.failed),
    );
    ref.onDispose(() {
      _sub?.cancel();
      _busyTimer?.cancel();
    });
    Future<void>.microtask(_init);
    return PurchaseState(proOwned: _local.getBool(proKey) ?? false);
  }

  Future<void> _init() async {
    if (!ref.mounted) return;
    await loadProducts();
    if (!ref.mounted) return;
    // Android: picks up purchases completed while closed and retries any
    // acknowledgement Play hasn't received (Play refunds unacknowledged
    // purchases after 3 days). Grant-only: never revokes Pro.
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        if (await _store.isAvailable()) await _store.restorePurchases();
      } on Object catch (e) {
        appLog('Silent restore failed: $e');
      }
    }
  }

  Future<void> loadProducts() async {
    try {
      final bool available = await _store.isAvailable();
      if (!ref.mounted) return;
      if (!available) {
        state = state.copyWith(storeAvailable: false);
        return;
      }
      final ProductDetailsResponse r = await _store.queryProductDetails(
        _allIds,
      );
      if (!ref.mounted) return;
      _products
        ..clear()
        ..addEntries(
          r.productDetails.map(
            (ProductDetails d) => MapEntry<String, ProductDetails>(d.id, d),
          ),
        );
      state = state.copyWith(
        storeAvailable: _products.isNotEmpty,
        prices: <String, String>{
          for (final ProductDetails d in _products.values) d.id: d.price,
        },
      );
    } on Object catch (e) {
      appLog('Store query failed: $e');
      if (ref.mounted) state = state.copyWith(storeAvailable: false);
    }
  }

  Future<void> buyPro() => _buy(AppConstants.proProductId, consumable: false);

  Future<void> tip(String productId) => _buy(productId, consumable: true);

  Future<void> _buy(String id, {required bool consumable}) async {
    if (state.busy) return;
    if (!consumable && state.proOwned) return;
    if (_products[id] == null) await loadProducts();
    final ProductDetails? product = _products[id];
    if (product == null) {
      _finish(PurchaseNotice.storeUnavailable);
      return;
    }
    _setBusy();
    _purchasing = true;
    _purchasingId = id;
    try {
      final bool started = consumable
          ? await _store.buyConsumable(product)
          : await _store.buyNonConsumable(product);
      if (!started) {
        _finish(PurchaseNotice.failed);
        // Play's launchBillingFlow can refuse with ITEM_ALREADY_OWNED and
        // nothing on the stream; a quiet restore delivers what is owned
        // (Pro is then granted; a stuck tip is consumed).
        unawaited(_quietRestore());
      }
    } on Object catch (e) {
      appLog('Purchase failed to start: $e');
      _finish(PurchaseNotice.failed);
    }
  }

  Future<void> restore() async {
    if (state.busy) return;
    _setBusy();
    _restoring = true;
    _restoreFound = false;
    try {
      if (!await _store.isAvailable()) {
        _restoring = false;
        _finish(PurchaseNotice.storeUnavailable);
        return;
      }
      await _store.restorePurchases();
      // Neither store signals "that was everything": wait briefly.
      await Future<void>.delayed(restoreWindow);
    } on Object catch (e) {
      appLog('Restore failed: $e');
    }
    if (!ref.mounted) return;
    final bool found = _restoreFound;
    _restoring = false;
    if (!found) _finish(PurchaseNotice.nothingToRestore);
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final PurchaseDetails p in list) {
      if (!_isOurs(p)) {
        if (p.pendingCompletePurchase) await _complete(p);
        continue;
      }
      final bool isPro = p.productID == AppConstants.proProductId;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (_isPlayPending(p)) {
            // Only tell the user when they asked (a buy or Restore). The
            // silent launch restore re-reports a pending Play order on
            // every launch, which would nag (review n4).
            if (state.busy) _finish(PurchaseNotice.pending);
            break;
          }
          if (isPro) {
            final bool hadIt = state.proOwned;
            // Persist before finishing the transaction.
            await _local.setBool(proKey, true);
            if (p.pendingCompletePurchase) await _complete(p);
            if (!ref.mounted) return;
            if (_restoring) _restoreFound = true;
            state = state.copyWith(proOwned: true);
            if (!hadIt || state.busy) {
              _finish(
                p.status == PurchaseStatus.purchased
                    ? PurchaseNotice.proPurchased
                    : PurchaseNotice.restored,
              );
            }
          } else {
            // A tip grants nothing. Consume it whatever its history (fresh,
            // left over from a killed session, or restored, even if
            // already acknowledged) so that tip size can be given again.
            await _finishTip(p);
            if (p.status == PurchaseStatus.purchased) {
              _finish(PurchaseNotice.tipThanks);
            }
          }
        case PurchaseStatus.pending:
          _finish(PurchaseNotice.pending);
        case PurchaseStatus.canceled:
          if (p.pendingCompletePurchase) await _complete(p);
          _finish(PurchaseNotice.cancelled);
        case PurchaseStatus.error:
          if (p.pendingCompletePurchase) await _complete(p);
          if ((p.error?.message ?? '').toLowerCase().contains('alreadyowned')) {
            final String id = p.productID.isNotEmpty
                ? p.productID
                : (_purchasingId ?? '');
            if (id == AppConstants.proProductId) {
              // Restore delivers the owned Pro; it finishes with "restored".
              unawaited(_recoverOwned(pro: true));
              break;
            }
            if (AppConstants.tipIds.contains(id)) {
              unawaited(_recoverOwned(pro: false));
              break;
            }
          }
          _finish(PurchaseNotice.failed);
      }
    }
  }

  /// "Already owned" during a buy: ask the store what is owned. A restored
  /// Pro is granted by the normal stream path; a restored tip is consumed
  /// there, and the user is told to try again.
  Future<void> _recoverOwned({required bool pro}) async {
    final bool wasRestoring = _restoring;
    _restoring = true;
    _restoreFound = false;
    try {
      await _store.restorePurchases();
      await Future<void>.delayed(restoreWindow);
    } on Object catch (e) {
      appLog('Recover owned failed: ${e.runtimeType}');
    }
    if (!ref.mounted) return;
    final bool found = _restoreFound;
    _restoring = wasRestoring;
    if (pro && found) return; // "restored" was already shown.
    _finish(pro ? PurchaseNotice.failed : PurchaseNotice.tipCleared);
  }

  Future<void> _quietRestore() async {
    try {
      if (await _store.isAvailable()) await _store.restorePurchases();
    } on Object catch (e) {
      appLog('Quiet restore failed: ${e.runtimeType}');
    }
  }

  bool _isOurs(PurchaseDetails p) {
    if (_allIds.contains(p.productID)) return true;
    return p.productID.isEmpty &&
        _purchasing &&
        (p.status == PurchaseStatus.canceled ||
            p.status == PurchaseStatus.error);
  }

  bool _isPlayPending(PurchaseDetails p) =>
      p is GooglePlayPurchaseDetails &&
      p.billingClientPurchase.purchaseState == PurchaseStateWrapper.pending;

  Future<void> _finishTip(PurchaseDetails p) async {
    try {
      await _store.finishConsumable(p);
    } on Object catch (e) {
      // Retried on the next launch/restore, which re-delivers it.
      appLog('finishConsumable failed: $e');
    }
  }

  Future<void> _complete(PurchaseDetails p) async {
    try {
      await _store.completePurchase(p);
    } on Object catch (e) {
      appLog('completePurchase failed: $e');
    }
  }

  void _setBusy() {
    _busyTimer?.cancel();
    _busyTimer = Timer(busyCeiling, () {
      _purchasing = false;
      if (ref.mounted && state.busy) state = state.copyWith(busy: false);
    });
    state = state.copyWith(busy: true);
  }

  void _finish(PurchaseNotice notice) {
    _busyTimer?.cancel();
    _purchasing = false;
    _purchasingId = null;
    if (!ref.mounted) return;
    state = state.copyWith(busy: false, notice: notice);
  }
}

final NotifierProvider<PurchaseController, PurchaseState>
purchaseControllerProvider =
    NotifierProvider<PurchaseController, PurchaseState>(PurchaseController.new);

/// The one gate every Pro feature reads.
final Provider<bool> isProProvider = Provider<bool>(
  (Ref ref) =>
      ref.watch(forceProProvider) ||
      ref.watch(
        purchaseControllerProvider.select((PurchaseState s) => s.proOwned),
      ),
);

/// What Pro restricts, in one place so screens, paywall copy and tests agree.
abstract final class FreeTier {
  static const int maxHolders = 1;
}
