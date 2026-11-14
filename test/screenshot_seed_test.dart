import 'dart:io';

import 'package:bondbell/app/debug_flags.dart';
import 'package:bondbell/app/screenshot_seed.dart';
import 'package:bondbell/core/storage/local_store.dart';
import 'package:bondbell/features/draws/domain/check_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SCREENSHOT_MODE unlocks Pro and seeds made-up data. It must be impossible
/// in a release build, and the seed must never touch the user's real data.
void main() {
  test('both screenshot flags are compiled out of release builds', () {
    // Read the source: a const evaluated in a debug test run can't show
    // what a release build would compute.
    final String src = File('lib/app/debug_flags.dart').readAsStringSync();
    expect(
      RegExp(r"screenshotMode\s*=\s*\n?\s*bool\.fromEnvironment\('SCREENSHOT_MODE'\)\s*&&\s*!kReleaseMode")
          .hasMatch(src),
      isTrue,
      reason: 'screenshotMode must be ANDed with !kReleaseMode',
    );
    expect(
      RegExp(r'screenshotTour\s*=\s*\n?\s*screenshotMode\s*&&').hasMatch(src),
      isTrue,
      reason: 'the tour must depend on screenshotMode',
    );
    // And main() only forces Pro behind that flag.
    final String main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('if (screenshotMode) forceProProvider.overrideWithValue(true)'));
    expect(main, contains('if (screenshotMode) await seedScreenshotData(store)'));
  });

  test('a plain test run has both flags off', () {
    expect(screenshotMode, isFalse);
    expect(screenshotTour, isFalse);
  });

  test('the seed writes sample-scope data only, labelled as sample', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'real.holders': '[{"id":"me","name":"Me","ranges":[]}]',
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await seedScreenshotData(LocalStore(prefs));
    expect(prefs.getString('real.holders'), '[{"id":"me","name":"Me","ranges":[]}]');
    expect(prefs.getKeys().where((String k) => k.startsWith('real.')), <String>['real.holders']);
    expect(prefs.getBool('settings.sampleMode'), isTrue);
    expect(prefs.getBool('settings.onboarded'), isTrue);
    expect(prefs.getBool('purchases.proOwned'), isNull,
        reason: 'Pro comes from forceProProvider, never a saved purchase');
    final Object? raw = LocalStore(prefs).readJson('sample.records');
    final List<CheckRecord> recs = (raw! as Map<String, Object?>)
        .values
        .map((Object? v) => CheckRecord.fromJson(v! as Map<String, Object?>))
        .toList();
    expect(recs, hasLength(6));
    // The headline sample result: £100 + £25, as the sample ZIP produces.
    expect(recs.firstWhere((CheckRecord r) => r.listId == '2026-11').totalWon, 125);
  });
}
