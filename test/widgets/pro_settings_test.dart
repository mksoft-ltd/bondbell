import 'package:bondbell/app/app.dart';
import 'package:bondbell/app/router.dart';
import 'package:bondbell/core/constants/app_constants.dart';
import 'package:bondbell/features/bonds/domain/holder.dart';
import 'package:bondbell/features/bonds/presentation/holders_controller.dart';
import 'package:bondbell/features/draws/domain/check_models.dart';
import 'package:bondbell/features/draws/presentation/check_session.dart';
import 'package:bondbell/features/draws/presentation/records_controller.dart';
import 'package:bondbell/features/purchases/presentation/purchase_controller.dart';
import 'package:bondbell/features/settings/presentation/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../helpers/app_harness.dart';
import '../helpers/fakes.dart';

void main() {
  final Map<String, Object> withBonds = <String, Object>{
    'real.holders': holdersJson(<Holder>[meHolder]),
  };

  group('Pro screen', () {
    testWidgets('lists the four benefits and the store\'s own price',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, route: '/pro');
      for (final b in <String>[
        'Unlimited holders',
        'Earlier draws',
        'Unclaimed search for all your bonds',
        'History and stats',
      ]) {
        expect(find.text(b), findsOneWidget);
      }
      await scrollTo(tester, find.text('Restore purchases'));
      expect(find.text('Unlock Pro · £4.79'), findsOneWidget);
      expect(find.textContaining('£4.99'), findsNothing,
          reason: 'no hardcoded price anywhere on the paywall');
      await tester.tap(find.text('Unlock Pro · £4.79'));
      await tester.pump();
      expect(h.store.nonConsumableBuys, <String>[AppConstants.proProductId]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      h.store.emit(<PurchaseDetails>[
        purchaseUpdate(AppConstants.proProductId, PurchaseStatus.purchased),
      ]);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.text('You have Bondbell Pro'), findsOneWidget);
      expect(find.text('Bondbell Pro is unlocked. Thank you!'), findsOneWidget);
      expect(find.textContaining('Unlock Pro'), findsNothing);
      await disposeApp(tester, h);
    });

    testWidgets('products not in the store: no price, disabled button, honest '
        'message and a retry', (WidgetTester tester) async {
      final FakeStoreGateway store = FakeStoreGateway(prices: const <String, String>{});
      await pumpBondbell(tester, store: store, route: '/pro');
      await scrollTo(tester, find.text('Try again'));
      final FilledButton b = tester.widget(find.widgetWithText(FilledButton, 'Unavailable right now'));
      expect(b.onPressed, isNull);
      expect(find.textContaining('Can\'t reach the app store'), findsOneWidget);
      store.prices = FakeStoreGateway.defaultPrices;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Unlock Pro · £4.79'), findsOneWidget);
    });

    testWidgets('a cancelled purchase shows no error and re-enables the button',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, route: '/pro');
      await scrollTo(tester, find.text('Restore purchases'));
      await tester.tap(find.text('Unlock Pro · £4.79'));
      await tester.pump();
      h.store.emit(<PurchaseDetails>[
        purchaseUpdate(AppConstants.proProductId, PurchaseStatus.canceled),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      final FilledButton b = tester.widget(find.widgetWithText(FilledButton, 'Unlock Pro · £4.79'));
      expect(b.onPressed, isNotNull);
      await disposeApp(tester, h);
    });

    testWidgets('pending shows the waiting message and does not unlock',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, route: '/pro');
      await scrollTo(tester, find.text('Restore purchases'));
      await tester.tap(find.text('Unlock Pro · £4.79'));
      await tester.pump();
      h.store.emit(<PurchaseDetails>[
        purchaseUpdate(AppConstants.proProductId, PurchaseStatus.pending),
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('waiting for approval'), findsOneWidget);
      expect(find.text('Unlock Pro · £4.79'), findsOneWidget);
      expect(h.container.read(isProProvider), isFalse);
      await disposeApp(tester, h);
    });

    testWidgets('restore with nothing to restore says so',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, route: '/pro');
      await scrollTo(tester, find.text('Restore purchases'));
      await tester.tap(find.text('Restore purchases'));
      await tester.pump();
      await tester.pump(PurchaseController.restoreWindow);
      await tester.pumpAndSettle();
      expect(find.text(BondbellApp.noticeText(PurchaseNotice.nothingToRestore)!),
          findsOneWidget);
      await disposeApp(tester, h);
    });

    testWidgets('every notice the controller can raise has a sensible text',
        (WidgetTester tester) async {
      for (final PurchaseNotice n in PurchaseNotice.values) {
        final String? t = BondbellApp.noticeText(n);
        if (n == PurchaseNotice.cancelled) {
          expect(t, isNull, reason: 'a user cancel is not an error');
        } else {
          expect(t, isNotEmpty, reason: '$n');
        }
      }
    });
  });

  group('settings', () {
    testWidgets('free: Pro card with the store price, restore, tips priced by '
        'the store', (WidgetTester tester) async {
      await pumpBondbell(tester, route: '/settings');
      expect(find.textContaining('One purchase, £4.79, no subscription'), findsOneWidget);
      expect(find.text('See what Pro adds'), findsOneWidget);
      expect(find.text('Restore purchases'), findsOneWidget);
      await scrollTo(tester, find.text('Tip jar'));
      expect(find.text('Small tip · £1.89'), findsOneWidget);
      expect(find.text('Medium tip · £4.89'), findsOneWidget);
      expect(find.text('Large tip · £9.89'), findsOneWidget);
      expect(find.textContaining('Tips don\'t unlock anything'), findsOneWidget);
    });

    testWidgets('a tip thanks the user and Pro stays locked',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, route: '/settings');
      await scrollTo(tester, find.text('Small tip · £1.89'));
      await tester.tap(find.text('Small tip · £1.89'));
      await tester.pump();
      expect(h.store.consumableBuys, <String>[AppConstants.tipSmallId]);
      h.store.emit(<PurchaseDetails>[
        purchaseUpdate(AppConstants.tipSmallId, PurchaseStatus.purchased),
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Thank you so much for the tip'), findsOneWidget);
      expect(h.container.read(isProProvider), isFalse);
      await disposeApp(tester, h);
    });

    testWidgets('store unavailable: no tip buttons, no price, says why',
        (WidgetTester tester) async {
      await pumpBondbell(tester, store: FakeStoreGateway(available: false), route: '/settings');
      expect(find.textContaining('One purchase, no subscription'), findsOneWidget);
      await scrollTo(tester, find.text('Tip jar'));
      expect(find.textContaining('tip ·'), findsNothing);
      expect(find.text('The app store isn\'t available right now.'), findsOneWidget);
    });

    testWidgets('Pro owned: unlocked card, no upsell', (WidgetTester tester) async {
      await pumpBondbell(
        tester,
        prefs: const <String, Object>{PurchaseController.proKey: true},
        route: '/settings',
      );
      expect(find.text('Bondbell Pro: unlocked'), findsOneWidget);
      expect(find.text('See what Pro adds'), findsNothing);
    });

    testWidgets('reminders switch: permission asked on the tap, denial leaves '
        'it off with an explanation', (WidgetTester tester) async {
      final FakeReminderService r = FakeReminderService(grant: false);
      final Harness h = await pumpBondbell(tester, reminders: r, route: '/settings');
      expect(r.permissionRequests, 0);
      await tester.tap(find.text('Results-day reminder'));
      await tester.pumpAndSettle();
      expect(r.permissionRequests, 1);
      expect(r.schedules, 0);
      expect(h.container.read(appSettingsProvider).remindersEnabled, isFalse);
      expect(find.textContaining('Notifications are turned off'), findsOneWidget);
    });

    testWidgets('reminders switch on then off cancels the queue',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, route: '/settings');
      await tester.tap(find.text('Results-day reminder'));
      await tester.pumpAndSettle();
      expect(h.container.read(appSettingsProvider).remindersEnabled, isTrue);
      expect(h.reminders.schedules, 1);
      await tester.tap(find.text('Results-day reminder'));
      await tester.pumpAndSettle();
      expect(h.reminders.cancels, 1);
      expect(h.container.read(appSettingsProvider).remindersEnabled, isFalse);
    });

    testWidgets('sample mode switch shows the banner on every tab',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, prefs: withBonds, route: '/settings');
      await tester.tap(find.text('Sample mode'));
      await tester.pumpAndSettle();
      expect(find.text('Sample mode: made-up numbers, not real results'), findsOneWidget);
      h.go('/bonds');
      await tester.pumpAndSettle();
      expect(find.text('Sample mode: made-up numbers, not real results'), findsOneWidget);
      expect(find.text('Sample holder'), findsOneWidget);
      expect(find.text('Me'), findsNothing, reason: 'real bonds are kept apart');
    });

    testWidgets('delete all my data asks, then clears holders and results in '
        'both scopes but keeps Pro', (WidgetTester tester) async {
      final Harness h = await pumpBondbell(
        tester,
        prefs: <String, Object>{
          ...withBonds,
          PurchaseController.proKey: true,
          'real.records': recordsJson(<CheckRecord>[
            CheckRecord(
              listId: '2026-11',
              label: 'November 2026',
              checkedAt: DateTime.utc(2026, 11, 3),
              fingerprint: 'x',
              wins: const <Win>[],
              numbersScanned: 1,
              integrityOk: true,
              bondsChecked: 1,
            ),
          ]),
          'sample.records': '{}',
        },
        route: '/settings',
      );
      await scrollTo(tester, find.text('Delete all my data'));
      await tester.tap(find.text('Delete all my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.container.read(holdersProvider), hasLength(1));
      await tester.tap(find.text('Delete all my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();
      expect(h.container.read(holdersProvider), isEmpty);
      expect(h.container.read(recordsProvider), isEmpty);
      expect(find.text('All your data has been deleted.'), findsOneWidget);
      expect(h.container.read(isProProvider), isTrue);
    });
  });

  group('unclaimed', () {
    testWidgets('a bad number is explained in place; nothing is searched',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, route: '/unclaimed');
      await tester.enterText(find.widgetWithText(TextField, 'Bond number'), '12IA345678');
      await tester.tap(find.text('Search the unclaimed list'));
      await tester.pump();
      expect(find.textContaining('Did you mean the number 1?'), findsOneWidget);
      expect(routerLocation(h), '/unclaimed');
    });

    testWidgets('a good number opens the single-number check, normalised',
        (WidgetTester tester) async {
      final ScriptedCheckSession session = ScriptedCheckSession(
        (CheckRequest r) => CheckSessionState(phase: CheckPhase.preparing, request: r),
      );
      await pumpBondbell(
        tester,
        route: '/unclaimed',
        extra: [checkSessionProvider.overrideWith(() => session)],
      );
      await tester.enterText(find.widgetWithText(TextField, 'Bond number'), '47 dw 185533');
      await tester.tap(find.text('Search the unclaimed list'));
      await pumpFrames(tester);
      expect(session.lastRequest!.kind, CheckKind.unclaimedSingle);
      expect(session.lastRequest!.single.toString(), '47DW185533');
      expect(find.text('Looking up NS&I\'s downloads page…'), findsOneWidget);
    });

    testWidgets('free: all-bonds search points to Pro', (WidgetTester tester) async {
      await pumpBondbell(tester, prefs: withBonds, route: '/unclaimed');
      expect(find.textContaining('part of Bondbell Pro'), findsOneWidget);
      expect(find.text('About Bondbell Pro'), findsOneWidget);
      expect(find.textContaining('Search 1,001 bonds'), findsNothing);
    });

    testWidgets('Pro: all-bonds search names the bond count; disabled with none',
        (WidgetTester tester) async {
      await pumpBondbell(tester, forcePro: true, prefs: withBonds, route: '/unclaimed');
      expect(find.text('Search 1,001 bonds'), findsOneWidget);
    });

    testWidgets('Pro with no bonds: the all-bonds button is disabled',
        (WidgetTester tester) async {
      await pumpBondbell(tester, forcePro: true, route: '/unclaimed');
      final FilledButton b = tester.widget(find.widgetWithText(FilledButton, 'Add bond numbers first'));
      expect(b.onPressed, isNull);
    });
  });

  group('history', () {
    CheckRecord rec(String id, List<int> prizes, {String? label}) => CheckRecord(
      listId: id,
      label: label ?? id,
      checkedAt: DateTime.utc(2026, 11, 3),
      fingerprint: holdingsFingerprint(<Holder>[meHolder]),
      wins: <Win>[
        for (final int p in prizes)
          Win(bond: '312KM104217', prize: p, holderId: 'me', holderName: 'Me'),
      ],
      numbersScanned: 1,
      integrityOk: true,
      bondsChecked: 1001,
    );

    testWidgets('free: locked with an explanation', (WidgetTester tester) async {
      await pumpBondbell(tester, prefs: withBonds, route: '/history');
      expect(find.text('History and stats are part of Pro'), findsOneWidget);
    });

    testWidgets('Pro: hand-added totals and the yearly-rate figure with its '
        'caveat', (WidgetTester tester) async {
      await pumpBondbell(
        tester,
        forcePro: true,
        prefs: <String, Object>{
          ...withBonds,
          'real.records': recordsJson(<CheckRecord>[
            rec('2026-11', <int>[100, 25], label: 'November 2026'),
            rec('2026-10', <int>[], label: 'October 2026'),
            rec('2026-09', <int>[50], label: 'September 2026'),
            rec('unclaimed', <int>[1000]),
          ]),
        },
        route: '/history',
      );
      // 3 draws (unclaimed excluded), 3 prizes, £175, held £1,001.
      // Rate = 175 / 1001 × (12 / 3) × 100 = 69.93% to 2 dp.
      expect(find.text('£175'), findsWidgets);
      expect(find.text('3'), findsNWidgets(2));
      expect(find.text('£1,001'), findsWidgets);
      expect(find.text('69.93% a year'), findsOneWidget);
      await scrollTo(tester, find.textContaining('not financial advice'));
      await scrollTo(tester, find.text('September 2026'));
      // Newest first.
      final double nov = tester.getTopLeft(find.text('November 2026')).dy;
      final double sep = tester.getTopLeft(find.text('September 2026')).dy;
      expect(nov, lessThan(sep));
    });

    testWidgets('Pro with nothing checked yet', (WidgetTester tester) async {
      await pumpBondbell(tester, forcePro: true, route: '/history');
      expect(find.text('Nothing checked yet'), findsOneWidget);
    });
  });
}

String routerLocation(Harness h) =>
    h.container.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();
