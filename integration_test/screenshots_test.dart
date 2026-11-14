// Store-screenshot journey. Visits the six screens in
// store_assets/SCREENSHOTS.md (marketing order) plus two supplementary
// shots, on the real app with its own SCREENSHOT_MODE seed, and runs the
// real sample check (bundled synthetic ZIP → download → background-isolate
// scan) on the device on the way.
//
// Run (see docs/TEST_PLAN.md for the full per-device recipe):
//   Android:  flutter drive -d <emulator> --driver=test_driver/integration_test.dart \
//               --target=integration_test/screenshots_test.dart \
//               --dart-define=SCREENSHOT_MODE=true
//             → build/screenshots/<name>.png (in-test capture works on Android)
//   iOS sim:  integration_test/capture_ios.sh <udid>
//             (in-test capture returns the launch screen on the simulator, so
//             the test prints a marker per shot and holds the frame while the
//             host runs `xcrun simctl io <udid> screenshot`;
//             --dart-define=HOST_CAPTURE=true)
//
// This file also works as a plain journey test without SCREENSHOT_MODE: it
// then fails fast with an explanation rather than photographing a locked app.

import 'dart:async';
import 'dart:io';

import 'package:bondbell/app/app.dart';
import 'package:bondbell/app/debug_flags.dart';
import 'package:bondbell/app/router.dart';
import 'package:bondbell/app/screenshot_seed.dart';
import 'package:bondbell/core/storage/local_store.dart';
import 'package:bondbell/features/draws/data/draw_source.dart';
import 'package:bondbell/features/purchases/data/store_gateway.dart';
import 'package:bondbell/features/purchases/presentation/purchase_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Host-side capture (iOS simulator): print a marker and hold the frame.
const bool hostCapture = bool.fromEnvironment('HOST_CAPTURE');

/// Seconds each shot is held for the host to capture it.
const int holdSeconds = int.fromEnvironment('HOLD_SECONDS', defaultValue: 4);

/// Marketing order from store_assets/SCREENSHOTS.md, then supplementary.
const List<String> shotNames = <String>[
  '01_result',
  '02_onboarding_privacy',
  '03_home',
  '04_holder',
  '05_unclaimed',
  '06_history',
  '07_check_ready',
  '08_pro',
];

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshot journey', (WidgetTester tester) async {
    expect(
      screenshotMode,
      isTrue,
      reason: 'Run with --dart-define=SCREENSHOT_MODE=true (debug or profile).',
    );
    final Set<String> taken = <String>{};
    bool surfaceConverted = false;

    Future<void> shot(String name) async {
      expect(shotNames, contains(name));
      await tester.pumpAndSettle();
      if (hostCapture) {
        // ignore: avoid_print
        print('BONDBELL_SHOT $name');
        // Real time: the binding is live on a device.
        await Future<void>.delayed(const Duration(seconds: holdSeconds));
      } else {
        if (Platform.isAndroid && !surfaceConverted) {
          // Once per run only (a second call breaks later captures).
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
          await tester.pumpAndSettle();
        }
        await binding.takeScreenshot(name);
      }
      taken.add(name);
    }

    Future<void> waitFor(Finder f, {int seconds = 30}) async {
      final DateTime end = DateTime.now().add(Duration(seconds: seconds));
      while (f.evaluate().isEmpty) {
        if (DateTime.now().isAfter(end)) {
          fail('Timed out waiting for $f');
        }
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pumpAndSettle();
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final LocalStore store = LocalStore(prefs);
    await clearScratch();

    // ── Shot 2 first: onboarding needs a first-run (unseeded) state. ──
    ProviderContainer container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        storeGatewayProvider.overrideWithValue(const OfflineStoreGateway()),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const BondbellApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Check your bonds without logging in'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your numbers stay on this phone'), findsOneWidget);
    await shot('02_onboarding_privacy');

    // ── Seed exactly as main() does under SCREENSHOT_MODE. ──
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await seedScreenshotData(store);
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        storeGatewayProvider.overrideWithValue(const OfflineStoreGateway()),
        forceProProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const BondbellApp()),
    );
    await tester.pumpAndSettle();
    void go(String r) => container.read(routerProvider).go(r);

    // ── 03 Home: hero card, latest draw, reminder card. ──
    expect(find.text('Sample mode: made-up numbers, not real results'), findsOneWidget);
    expect(find.textContaining('Next results expected'), findsOneWidget);
    expect(find.text('Remind me on results day'), findsOneWidget);
    await shot('03_home');

    // ── 01 Result: run the real sample check end to end. ──
    unawaited(container.read(routerProvider).push('/check/draw/latest'));
    await waitFor(find.text('Check the sample'));
    await tester.tap(find.text('Check the sample'));
    await waitFor(find.text('Congratulations!'));
    expect(find.text('312KM104217'), findsOneWidget);
    expect(find.text('312KM104388'), findsOneWidget);
    expect(find.textContaining('2 prizes worth £125'), findsOneWidget);
    await shot('01_result');
    final Directory scratch = await scratchDir();
    expect(scratch.listSync(), isEmpty, reason: 'the sample ZIP was deleted');

    // ── 07 Check, ready to download (supplementary). ──
    go('/home');
    await tester.pumpAndSettle();
    unawaited(container.read(routerProvider).push('/check/draw/latest'));
    await waitFor(find.text('Check the sample'));
    await shot('07_check_ready');

    // ── 04 Holder: statement range and old certificate. ──
    go('/bonds');
    await tester.pumpAndSettle();
    unawaited(container.read(routerProvider).push('/holder/sample-holder'));
    await waitFor(find.text('Sample holder'));
    expect(find.textContaining('20,050 bonds'), findsOneWidget);
    await shot('04_holder');

    // ── 05 Unclaimed. ──
    go('/unclaimed');
    await waitFor(find.text('Search one bond number'));
    expect(find.text('Search all my bonds'), findsOneWidget);
    await shot('05_unclaimed');

    // ── 06 History: tiles + yearly-rate card with its note visible. ──
    go('/history');
    await waitFor(find.text('Total won'));
    final Finder note = find.textContaining('not financial advice');
    await waitFor(note);
    // Phones have a bottom bar; iPad uses a side rail.
    final Finder bar = find.byType(NavigationBar);
    final double viewBottom = bar.evaluate().isNotEmpty
        ? tester.getTopLeft(bar).dy
        : tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final double noteBottom = tester.getBottomLeft(note).dy;
    if (noteBottom > viewBottom) {
      await tester.drag(
        find.byType(Scrollable).hitTestable().first,
        Offset(0, -(noteBottom - viewBottom + 24)),
      );
      await tester.pumpAndSettle();
    }
    expect(tester.getBottomLeft(note).dy, lessThanOrEqualTo(viewBottom + 0.5));
    await shot('06_history');

    // ── 08 Pro (supplementary; forced-Pro shows the owned state). ──
    unawaited(container.read(routerProvider).push('/pro'));
    await waitFor(find.text('You have Bondbell Pro'));
    await shot('08_pro');

    expect(taken, shotNames.toSet());
  });
}
