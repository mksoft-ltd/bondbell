import 'dart:io';

import 'package:bondbell/core/storage/local_store.dart';
import 'package:bondbell/features/bonds/domain/bond_number.dart';
import 'package:bondbell/features/bonds/presentation/holders_controller.dart';
import 'package:bondbell/features/draws/presentation/check_session.dart';
import 'package:bondbell/features/purchases/presentation/pro_screen.dart';
import 'package:bondbell/features/purchases/presentation/purchase_controller.dart';
import 'package:bondbell/features/settings/presentation/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

/// Every free/Pro line in the spec's table, enforced in logic (providers
/// and controllers), not only by what the screens choose to show.
void main() {
  // Sample mode reads the bundled sample lists through rootBundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ScriptedSource source;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bondbell_gates');
    source = ScriptedSource(dir)
      ..defaultZip = buildZip(
        'PWREP.txt',
        winnersFile(<int, List<String>>{25: <String>['100AA000001']}),
      );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProviderContainer> make({
    bool pro = false,
    bool sample = false,
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'real.holders': '[{"id":"h","name":"Me","ranges":['
          '{"id":"r","start":"100AA000000","end":"100AA000009"}]}]',
      'settings.sampleMode': sample,
      ...prefs,
    });
    final ProviderContainer c = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(
          LocalStore(await SharedPreferences.getInstance()),
        ),
        liveDrawSourceProvider.overrideWithValue(source),
        if (pro) forceProProvider.overrideWithValue(true),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('holders: free keeps one', () {
    test('a second holder is refused by the controller itself', () async {
      final ProviderContainer c = await make();
      await expectLater(
        c.read(holdersProvider.notifier).addHolder('Gran'),
        throwsA(isA<FreeTierLimitException>()),
      );
      expect(c.read(holdersProvider), hasLength(1));
    });

    test('the first holder is free', () async {
      final ProviderContainer c = await make(
        prefs: const <String, Object>{'real.holders': '[]'},
      );
      await c.read(holdersProvider.notifier).addHolder('Me');
      expect(c.read(holdersProvider), hasLength(1));
    });

    test('Pro adds as many as it likes', () async {
      final ProviderContainer c = await make(pro: true);
      await c.read(holdersProvider.notifier).addHolder('Gran');
      await c.read(holdersProvider.notifier).addHolder('Sam');
      expect(c.read(holdersProvider), hasLength(3));
    });

    test('a purchased (not forced) Pro also lifts the limit', () async {
      final ProviderContainer c = await make(
        prefs: const <String, Object>{PurchaseController.proKey: true},
      );
      await c.read(holdersProvider.notifier).addHolder('Gran');
      expect(c.read(holdersProvider), hasLength(2));
    });

    test('free users can still add unlimited ranges to their holder', () async {
      final ProviderContainer c = await make();
      for (int i = 1; i <= 5; i++) {
        await c.read(holdersProvider.notifier).addRange(
          'h',
          BondNumber.parse('100AB00000$i'),
          BondNumber.parse('100AB00000$i'),
        );
      }
      expect(c.read(holdersProvider).single.ranges, hasLength(6));
    });

    // Item 8 (Play "full access" for reviewers, who can't buy): sample
    // mode opens every Pro feature on the sample data. Before this, sample
    // mode applied the free limits, so History, earlier draws, bulk
    // unclaimed and extra holders were locked for a reviewer.
    test('sample mode opens the holder limit on the sample data only',
        () async {
      final ProviderContainer c = await make(sample: true);
      expect(c.read(proFeaturesProvider), isTrue);
      expect(c.read(isProProvider), isFalse, reason: 'the entitlement is real');
      await c.read(holdersProvider.notifier).addHolder('Sam (sample)');
      expect(c.read(holdersProvider), hasLength(3)); // 2 sample + Sam
      await c.read(appSettingsProvider.notifier).setSampleMode(false);
      expect(c.read(proFeaturesProvider), isFalse);
      expect(c.read(holdersProvider).map((h) => h.id), <String>['h'],
          reason: 'real data untouched');
      await expectLater(
        c.read(holdersProvider.notifier).addHolder('Gran'),
        throwsA(isA<FreeTierLimitException>()),
        reason: 'real data is still gated after leaving sample mode',
      );
    });
  });

  group('item 8: sample mode opens Pro features, never the entitlement', () {
    test('every Pro check opens in sample mode: earlier draw, bulk unclaimed',
        () async {
      final ProviderContainer c = await make(sample: true);
      final CheckSessionController s = c.read(checkSessionProvider.notifier);
      await s.prepare(const CheckRequest.draw('2026-10'));
      expect(c.read(checkSessionProvider).phase, CheckPhase.ready,
          reason: c.read(checkSessionProvider).error);
      expect(c.read(checkSessionProvider).list!.label, 'October 2026 (sample)');
      await s.prepare(const CheckRequest.unclaimedAll());
      expect(c.read(checkSessionProvider).phase, CheckPhase.ready,
          reason: c.read(checkSessionProvider).error);
    });

    test('leaving sample mode restores the real gates', () async {
      final ProviderContainer c = await make(sample: true);
      await c.read(appSettingsProvider.notifier).setSampleMode(false);
      final CheckSessionController s = c.read(checkSessionProvider.notifier);
      await s.prepare(const CheckRequest.draw('2026-10'));
      expect(c.read(checkSessionProvider).error, contains('Pro'));
      await s.prepare(const CheckRequest.unclaimedAll());
      expect(c.read(checkSessionProvider).error, contains('Pro'));
      expect(source.handedOut, isEmpty);
    });

    test('the persisted Pro flag is never written by sample mode', () async {
      final ProviderContainer c = await make(sample: true);
      c.read(proFeaturesProvider);
      await c.read(holdersProvider.notifier).addHolder('Sam (sample)');
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PurchaseController.proKey), isNull);
      expect(c.read(purchaseControllerProvider).proOwned, isFalse);
      expect(c.read(sampleOpensProProvider), isTrue);
    });

    test('with real Pro, the sample note is not shown', () async {
      final ProviderContainer c = await make(sample: true, pro: true);
      expect(c.read(sampleOpensProProvider), isFalse);
    });
  });

  group('draws and unclaimed: free is the latest draw and single numbers', () {
    test('free can check the latest draw by its explicit id', () async {
      final ProviderContainer c = await make();
      await c
          .read(checkSessionProvider.notifier)
          .prepare(const CheckRequest.draw('2026-11'));
      expect(c.read(checkSessionProvider).phase, CheckPhase.ready);
    });

    test('free is refused an earlier draw before anything is downloaded',
        () async {
      final ProviderContainer c = await make();
      final CheckSessionController s = c.read(checkSessionProvider.notifier);
      await s.prepare(const CheckRequest.draw('2026-10'));
      expect(c.read(checkSessionProvider).phase, CheckPhase.failed);
      expect(c.read(checkSessionProvider).error, contains('Pro'));
      await s.start(); // must be a no-op from a failed state
      expect(source.handedOut, isEmpty);
    });

    test('free can search one number against the unclaimed list', () async {
      final ProviderContainer c = await make();
      await c.read(checkSessionProvider.notifier).prepare(
        CheckRequest.unclaimedSingle(BondNumber.parse('100AA000001')),
      );
      expect(c.read(checkSessionProvider).phase, CheckPhase.ready);
    });

    test('free is refused the all-bonds unclaimed search', () async {
      final ProviderContainer c = await make();
      await c
          .read(checkSessionProvider.notifier)
          .prepare(const CheckRequest.unclaimedAll());
      expect(c.read(checkSessionProvider).phase, CheckPhase.failed);
      expect(c.read(checkSessionProvider).error, contains('Pro'));
    });

    test('buying Pro mid-session lifts the gate on the next prepare', () async {
      final ProviderContainer c = await make();
      final CheckSessionController s = c.read(checkSessionProvider.notifier);
      await s.prepare(const CheckRequest.draw('2026-10'));
      expect(c.read(checkSessionProvider).phase, CheckPhase.failed);
      await c.read(localStoreProvider).setBool(PurchaseController.proKey, true);
      c.invalidate(purchaseControllerProvider);
      await s.prepare(const CheckRequest.draw('2026-10'));
      expect(c.read(checkSessionProvider).phase, CheckPhase.ready);
    });
  });

  test('the paywall lists exactly the four gated features', () {
    expect(ProScreen.benefits.map((b) => b.title).toList(), <String>[
      'Unlimited holders',
      'Earlier draws',
      'Unclaimed search for all your bonds',
      'History and stats',
    ]);
  });
}
