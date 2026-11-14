import 'package:bondbell/core/constants/app_constants.dart';
import 'package:bondbell/core/storage/local_store.dart';
import 'package:bondbell/features/purchases/data/store_gateway.dart';
import 'package:bondbell/features/purchases/presentation/purchase_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

/// The money paths, against a fake of the in_app_purchase platform. The
/// store products don't exist yet, so this is the only place purchases are
/// exercised before release.
void main() {
  const String pro = AppConstants.proProductId;
  late FakeStoreGateway store;
  late LocalStore local;

  Future<void> freshPrefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    local = LocalStore(await SharedPreferences.getInstance());
  }

  setUp(() async {
    store = FakeStoreGateway();
    await freshPrefs();
    // flutter_test defaults to Android; the launch restore is pinned
    // separately, so most tests run on the iOS path where it doesn't fire.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  ProviderContainer makeContainer({StoreGateway? gateway}) =>
      ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(local),
          storeGatewayProvider.overrideWithValue(gateway ?? store),
        ],
      );

  /// Runs [body] on a fake clock with a controller that has finished its
  /// launch work (product query, Android's silent restore).
  void run(void Function(FakeAsync clock, ProviderContainer c) body) {
    fakeAsync((FakeAsync clock) {
      final ProviderContainer c = makeContainer();
      c.read(purchaseControllerProvider);
      clock.flushMicrotasks();
      body(clock, c);
      c.dispose();
      clock.flushMicrotasks();
    });
  }

  PurchaseState st(ProviderContainer c) => c.read(purchaseControllerProvider);
  PurchaseController ctrl(ProviderContainer c) =>
      c.read(purchaseControllerProvider.notifier);

  group('launch', () {
    test('loads the store\'s own localised prices, never hardcoded ones', () {
      run((FakeAsync clock, ProviderContainer c) {
        expect(st(c).storeAvailable, isTrue);
        expect(st(c).prices, FakeStoreGateway.defaultPrices);
        expect(st(c).prices[pro], '£4.79', reason: 'not the £4.99 list price');
        expect(st(c).proOwned, isFalse);
        expect(c.read(isProProvider), isFalse);
      });
    });

    test('Pro bought in an earlier session is unlocked before the store answers',
        () async {
      await freshPrefs(<String, Object>{PurchaseController.proKey: true});
      store.available = false;
      run((FakeAsync clock, ProviderContainer c) {
        expect(st(c).proOwned, isTrue);
        expect(c.read(isProProvider), isTrue);
      });
    });

    test('an already-owned Pro delivered on the stream at launch is granted, '
        'persisted, then finished', () {
      run((FakeAsync clock, ProviderContainer c) {
        bool? persistedAtCompletion;
        store.onComplete = (_) =>
            persistedAtCompletion = local.getBool(PurchaseController.proKey);
        store.emit(<PurchaseDetails>[
          purchaseUpdate(pro, PurchaseStatus.purchased),
        ]);
        clock.flushMicrotasks();
        expect(st(c).proOwned, isTrue);
        expect(local.getBool(PurchaseController.proKey), isTrue);
        expect(persistedAtCompletion, isTrue,
            reason: 'Pro must be saved before the transaction is finished');
        expect(store.completed.single.productID, pro);
      });
    });

    test('Pro survives a restart: a new controller reads the saved entitlement',
        () {
      fakeAsync((FakeAsync clock) {
        final ProviderContainer first = makeContainer();
        first.read(purchaseControllerProvider);
        clock.flushMicrotasks();
        store.emit(<PurchaseDetails>[
          purchaseUpdate(pro, PurchaseStatus.purchased),
        ]);
        clock.flushMicrotasks();
        first.dispose();

        // Relaunch offline: no store, nothing on the stream.
        final ProviderContainer second = makeContainer(
          gateway: const OfflineStoreGateway(),
        );
        expect(second.read(isProProvider), isTrue);
        clock.flushMicrotasks();
        expect(second.read(isProProvider), isTrue);
        second.dispose();
        clock.flushMicrotasks();
      });
    });

    test('Android silently restores at launch (missed purchases and acks); '
        'iOS does not', () {
      for (final TargetPlatform p in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        store = FakeStoreGateway();
        run((FakeAsync clock, ProviderContainer c) {
          expect(store.restoreCalls, p == TargetPlatform.android ? 1 : 0,
              reason: '$p');
        });
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('silent restore of an owned Pro shows no notice', () async {
      await freshPrefs(<String, Object>{PurchaseController.proKey: true});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      store.onRestore = () => <PurchaseDetails>[
        purchaseUpdate(pro, PurchaseStatus.restored, pendingComplete: false),
      ];
      run((FakeAsync clock, ProviderContainer c) {
        expect(store.restoreCalls, 1);
        expect(st(c).proOwned, isTrue);
        expect(st(c).notice, isNull);
      });
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('products missing from the store', () {
    test('store reachable but products not created: no prices, honest state',
        () {
      store.prices = const <String, String>{};
      run((FakeAsync clock, ProviderContainer c) {
        expect(st(c).storeAvailable, isFalse);
        expect(st(c).prices, isEmpty);
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        expect(store.nonConsumableBuys, isEmpty);
        expect(st(c).notice, PurchaseNotice.storeUnavailable);
        expect(st(c).busy, isFalse);
      });
    });

    test('only Pro missing: tips still priced, Pro has no price', () {
      store.prices = Map<String, String>.of(FakeStoreGateway.defaultPrices)
        ..remove(pro);
      run((FakeAsync clock, ProviderContainer c) {
        expect(st(c).prices.containsKey(pro), isFalse);
        expect(st(c).prices[AppConstants.tipSmallId], '£1.89');
      });
    });

    test('store unavailable, or the query throws: no crash, nothing priced',
        () {
      store.available = false;
      run((FakeAsync clock, ProviderContainer c) {
        expect(st(c).storeAvailable, isFalse);
        expect(store.queryCalls, 0);
      });
      store = FakeStoreGateway()..queryError = Exception('billing down');
      run((FakeAsync clock, ProviderContainer c) {
        expect(st(c).storeAvailable, isFalse);
        expect(st(c).prices, isEmpty);
      });
    });

    test('a retry after the store comes back loads the prices', () {
      store.available = false;
      run((FakeAsync clock, ProviderContainer c) {
        store.available = true;
        ctrl(c).loadProducts();
        clock.flushMicrotasks();
        expect(st(c).storeAvailable, isTrue);
        expect(st(c).prices[pro], '£4.79');
      });
    });
  });

  group('buying Pro', () {
    test('success: sheet opens busy, purchase arrives, Pro unlocked once', () {
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        expect(store.nonConsumableBuys, <String>[pro]);
        expect(store.consumableBuys, isEmpty);
        expect(st(c).busy, isTrue);
        expect(st(c).proOwned, isFalse, reason: 'opening the sheet grants nothing');

        store.emit(<PurchaseDetails>[
          purchaseUpdate(pro, PurchaseStatus.purchased),
        ]);
        clock.flushMicrotasks();
        expect(st(c).proOwned, isTrue);
        expect(c.read(isProProvider), isTrue);
        expect(st(c).busy, isFalse);
        expect(st(c).notice, PurchaseNotice.proPurchased);
        expect(store.completed, hasLength(1));
      });
    });

    test('a second tap while the sheet is open starts nothing', () {
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        expect(store.nonConsumableBuys, hasLength(1));
      });
    });

    test('pending (Ask to Buy, slow card): not unlocked, not finished, then '
        'unlocks when it completes', () {
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        store.emit(<PurchaseDetails>[
          purchaseUpdate(pro, PurchaseStatus.pending),
        ]);
        clock.flushMicrotasks();
        expect(st(c).notice, PurchaseNotice.pending);
        expect(st(c).proOwned, isFalse);
        expect(st(c).busy, isFalse);
        expect(store.completed, isEmpty,
            reason: 'a pending purchase must not be finished/acknowledged');
        expect(local.getBool(PurchaseController.proKey), isNull);

        store.emit(<PurchaseDetails>[
          purchaseUpdate(pro, PurchaseStatus.purchased),
        ]);
        clock.flushMicrotasks();
        expect(st(c).proOwned, isTrue);
        expect(st(c).notice, PurchaseNotice.proPurchased);
      });
    });

    test('cancelled: not unlocked, busy cleared, no error shown', () {
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        store.emit(<PurchaseDetails>[
          purchaseUpdate(pro, PurchaseStatus.canceled),
        ]);
        clock.flushMicrotasks();
        expect(st(c).proOwned, isFalse);
        expect(st(c).busy, isFalse);
        expect(st(c).notice, PurchaseNotice.cancelled);
        expect(local.getBool(PurchaseController.proKey), isNull);
      });
    });

    test('Play reports a cancel with an empty product id: it ends the purchase '
        'in flight', () {
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        store.emit(<PurchaseDetails>[
          purchaseUpdate('', PurchaseStatus.canceled, pendingComplete: false),
        ]);
        clock.flushMicrotasks();
        expect(st(c).busy, isFalse);
        expect(st(c).notice, PurchaseNotice.cancelled);
        expect(st(c).proOwned, isFalse);
      });
    });

    test('an empty-id cancel with no purchase in flight is ignored', () {
      run((FakeAsync clock, ProviderContainer c) {
        store.emit(<PurchaseDetails>[
          purchaseUpdate('', PurchaseStatus.canceled, pendingComplete: false),
        ]);
        clock.flushMicrotasks();
        expect(st(c).notice, isNull);
      });
    });

    test('error: not unlocked, failure shown, transaction finished', () {
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        store.emit(<PurchaseDetails>[
          purchaseUpdate(pro, PurchaseStatus.error, errorMessage: 'declined'),
        ]);
        clock.flushMicrotasks();
        expect(st(c).proOwned, isFalse);
        expect(st(c).busy, isFalse);
        expect(st(c).notice, PurchaseNotice.failed);
        expect(store.completed, hasLength(1));
      });
    });

    test('"item already owned" on Play restores instead of failing', () {
      run((FakeAsync clock, ProviderContainer c) {
        store.onRestore = () => <PurchaseDetails>[
          purchaseUpdate(pro, PurchaseStatus.restored),
        ];
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        // in_app_purchase_android puts BillingResponse.toString() in message.
        store.emit(<PurchaseDetails>[
          purchaseUpdate(pro, PurchaseStatus.error,
              errorMessage: 'BillingResponse.itemAlreadyOwned'),
        ]);
        clock.flushMicrotasks();
        expect(store.restoreCalls, 1);
        expect(st(c).proOwned, isTrue);
        expect(st(c).notice, PurchaseNotice.restored);
        expect(st(c).busy, isFalse);
      });
    });

    test('the sheet fails to open, or the plugin throws: failure, not stuck',
        () {
      store.buyStarts = false;
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        expect(st(c).notice, PurchaseNotice.failed);
        expect(st(c).busy, isFalse);
      });
      store = FakeStoreGateway()..buyError = Exception('storekit');
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        expect(st(c).notice, PurchaseNotice.failed);
        expect(st(c).busy, isFalse);
      });
    });

    test('if the store never answers, busy clears at the ceiling', () {
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        clock.elapse(PurchaseController.busyCeiling - const Duration(seconds: 1));
        expect(st(c).busy, isTrue);
        clock.elapse(const Duration(seconds: 2));
        expect(st(c).busy, isFalse);
        expect(st(c).proOwned, isFalse);
      });
    });

    test('a stream error clears busy with a failure', () {
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        store.emitError(Exception('channel died'));
        clock.flushMicrotasks();
        expect(st(c).busy, isFalse);
        expect(st(c).notice, PurchaseNotice.failed);
      });
    });

    test('nothing to buy once Pro is owned', () async {
      await freshPrefs(<String, Object>{PurchaseController.proKey: true});
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).buyPro();
        clock.flushMicrotasks();
        expect(store.nonConsumableBuys, isEmpty);
      });
    });
  });

  group('restore', () {
    test('finds Pro: unlocked, restored notice, finished, no "nothing found"',
        () {
      store.onRestore = () => <PurchaseDetails>[
        purchaseUpdate(pro, PurchaseStatus.restored),
      ];
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).restore();
        clock.flushMicrotasks();
        expect(st(c).proOwned, isTrue);
        expect(st(c).notice, PurchaseNotice.restored);
        expect(store.completed.single.productID, pro);
        final int serial = st(c).noticeSerial;
        clock.elapse(PurchaseController.restoreWindow);
        expect(st(c).notice, PurchaseNotice.restored);
        expect(st(c).noticeSerial, serial, reason: 'no second notice');
      });
    });

    test('nothing to restore: says so after the window, busy cleared', () {
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).restore();
        clock.flushMicrotasks();
        expect(st(c).busy, isTrue);
        clock.elapse(PurchaseController.restoreWindow);
        expect(st(c).busy, isFalse);
        expect(st(c).notice, PurchaseNotice.nothingToRestore);
        expect(st(c).proOwned, isFalse);
      });
    });

    test('restoring when the store is unreachable says so', () {
      store.available = false;
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).restore();
        clock.flushMicrotasks();
        expect(st(c).notice, PurchaseNotice.storeUnavailable);
        expect(st(c).busy, isFalse);
        expect(store.restoreCalls, 0);
      });
    });

    test('a restore that finds nothing never takes away an owned Pro',
        () async {
      await freshPrefs(<String, Object>{PurchaseController.proKey: true});
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).restore();
        clock.elapse(PurchaseController.restoreWindow);
        expect(st(c).proOwned, isTrue);
        expect(local.getBool(PurchaseController.proKey), isTrue);
      });
    });

    test('restore re-delivering an owned Pro reports it restored', () async {
      await freshPrefs(<String, Object>{PurchaseController.proKey: true});
      store.onRestore = () => <PurchaseDetails>[
        purchaseUpdate(pro, PurchaseStatus.restored, pendingComplete: false),
      ];
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).restore();
        clock.flushMicrotasks();
        expect(st(c).notice, PurchaseNotice.restored);
        expect(st(c).busy, isFalse);
      });
    });
  });

  group('tips (consumables)', () {
    for (final String tip in AppConstants.tipIds) {
      test('$tip is bought as a consumable, finished, thanked, and grants '
          'nothing', () {
        run((FakeAsync clock, ProviderContainer c) {
          ctrl(c).tip(tip);
          clock.flushMicrotasks();
          expect(store.consumableBuys, <String>[tip]);
          expect(store.nonConsumableBuys, isEmpty);
          store.emit(<PurchaseDetails>[
            purchaseUpdate(tip, PurchaseStatus.purchased),
          ]);
          clock.flushMicrotasks();
          expect(store.completed.single.productID, tip);
          expect(st(c).notice, PurchaseNotice.tipThanks);
          expect(st(c).busy, isFalse);
          expect(st(c).proOwned, isFalse);
          expect(c.read(isProProvider), isFalse);
          expect(local.getBool(PurchaseController.proKey), isNull);
        });
      });
    }

    test('a tip can be given again after the first one is finished', () {
      run((FakeAsync clock, ProviderContainer c) {
        for (int i = 0; i < 2; i++) {
          ctrl(c).tip(AppConstants.tipSmallId);
          clock.flushMicrotasks();
          store.emit(<PurchaseDetails>[
            purchaseUpdate(AppConstants.tipSmallId, PurchaseStatus.purchased),
          ]);
          clock.flushMicrotasks();
        }
        expect(store.consumableBuys, hasLength(2));
        expect(store.completed, hasLength(2));
      });
    });

    test('a restored tip is finished silently and grants nothing', () {
      store.onRestore = () => <PurchaseDetails>[
        purchaseUpdate(AppConstants.tipLargeId, PurchaseStatus.restored),
      ];
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).restore();
        clock.flushMicrotasks();
        expect(store.completed.single.productID, AppConstants.tipLargeId);
        expect(st(c).proOwned, isFalse);
        clock.elapse(PurchaseController.restoreWindow);
        expect(st(c).notice, PurchaseNotice.nothingToRestore,
            reason: 'a tip is not a Pro purchase to restore');
      });
    });

    test('a purchase for someone else\'s product id is finished, never granted',
        () {
      run((FakeAsync clock, ProviderContainer c) {
        store.emit(<PurchaseDetails>[
          purchaseUpdate('com.example.other.pro', PurchaseStatus.purchased),
        ]);
        clock.flushMicrotasks();
        expect(store.completed, hasLength(1));
        expect(st(c).proOwned, isFalse);
        expect(st(c).notice, isNull);
      });
    });

    test('a tip missing from the store reports unavailable and buys nothing',
        () {
      store.prices = <String, String>{pro: '£4.79'};
      run((FakeAsync clock, ProviderContainer c) {
        ctrl(c).tip(AppConstants.tipMediumId);
        clock.flushMicrotasks();
        expect(store.consumableBuys, isEmpty);
        expect(st(c).notice, PurchaseNotice.storeUnavailable);
      });
    });
  });

  test('product ids are the ones created in both stores', () {
    // Pinned literally: drift here silently breaks every purchase.
    expect(AppConstants.proProductId, 'com.froggyeye.bondbell.pro');
    expect(AppConstants.tipIds, <String>[
      'com.froggyeye.bondbell.tip.small',
      'com.froggyeye.bondbell.tip.medium',
      'com.froggyeye.bondbell.tip.large',
    ]);
    expect(FreeTier.maxHolders, 1);
  });
}
