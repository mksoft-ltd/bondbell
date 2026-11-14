import 'dart:io';

import 'package:bondbell/app/app_hooks.dart';
import 'package:bondbell/core/storage/local_store.dart';
import 'package:bondbell/features/bonds/domain/bond_number.dart';
import 'package:bondbell/features/bonds/domain/holder.dart';
import 'package:bondbell/features/bonds/presentation/holders_controller.dart';
import 'package:bondbell/features/draws/data/nsi_index.dart';
import 'package:bondbell/features/draws/domain/check_models.dart';
import 'package:bondbell/features/purchases/presentation/purchase_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fix round 2 (code review m5, m6, m8; security L-4).
void main() {
  group('m5: one unreadable range never costs the other holders', () {
    // Gran's second range uses the letter O, which validation refuses.
    const String stored = '[{"id":"me","name":"Me","ranges":['
        '{"id":"r1","start":"312KM104000","end":"312KM104499"}]},'
        '{"id":"gran","name":"Gran","ranges":['
        '{"id":"r2","start":"47DW185520","end":"47DW185569"},'
        '{"id":"r3","start":"12AO000001","end":"12AO000009"}]}]';

    Future<(ProviderContainer, SharedPreferences)> make() async {
      SharedPreferences.setMockInitialValues(<String, Object>{'real.holders': stored});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer c = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(LocalStore(prefs)),
        forceProProvider.overrideWithValue(true),
      ]);
      addTearDown(c.dispose);
      return (c, prefs);
    }

    test('only the bad range is skipped; everyone else loads', () async {
      final (ProviderContainer c, SharedPreferences prefs) = await make();
      final List<Holder> hs = c.read(holdersProvider);
      expect(hs.map((Holder h) => h.name), <String>['Me', 'Gran']);
      expect(hs[0].ranges, hasLength(1));
      expect(hs[1].ranges.single.id, 'r2');
      expect(prefs.getString('real.holders.bak'), stored,
          reason: 'the original text is kept before anything is rewritten');
    });

    test('the next save keeps every readable holder and range', () async {
      final (ProviderContainer c, _) = await make();
      c.read(holdersProvider);
      await c.read(holdersProvider.notifier).addRange(
          'me', BondNumber.parse('9XY000001'), BondNumber.parse('9XY000001'));
      final List<Holder> hs = c.read(holdersProvider);
      expect(hs, hasLength(2));
      expect(hs[1].name, 'Gran');
      expect(hs[1].ranges.single.start.toString(), '47DW185520');
    });

    test('unreadable JSON is backed up, not silently lost', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'real.holders': '[{"id":'});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer c = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(LocalStore(prefs)),
      ]);
      addTearDown(c.dispose);
      expect(c.read(holdersProvider), isEmpty);
      expect(prefs.getString('real.holders.bak'), '[{"id":');
    });
  });

  group('m6: household totals count each bond once', () {
    BondRange r(String id, String a, String b) =>
        BondRange(id: id, start: BondNumber.parse(a), end: BondNumber.parse(b));

    test('the same range under two holders counts once', () {
      final List<Holder> hs = <Holder>[
        Holder(id: 'a', name: 'Me', ranges: <BondRange>[r('1', '312KM104000', '312KM104499')]),
        Holder(id: 'b', name: 'Gran', ranges: <BondRange>[r('2', '312KM104000', '312KM104499')]),
      ];
      expect(uniqueBondCount(hs), 500);
      expect(hs.fold(0, (int a, Holder h) => a + h.bondCount), 1000,
          reason: 'per-holder totals are unchanged');
    });

    test('overlapping and adjacent ranges merge; other series add', () {
      final Holder h = Holder(id: 'a', name: 'Me', ranges: <BondRange>[
        r('1', '312KM104000', '312KM104499'),
        r('2', '312KM104400', '312KM104599'), // overlaps 100
        r('3', '312KM104600', '312KM104600'), // adjacent
        r('4', '312KM104000', '312KM104000'), // already inside
        r('5', 'DW000001', 'DW000010'), // another series
        r('6', '1DW000001', '1DW000010'), // prefix matters
      ]);
      expect(uniqueBondCount(<Holder>[h]), 601 + 10 + 10);
    });
  });

  group('m8: an unclaimed result goes stale when NS&I republishes the list', () {
    CheckRecord rec(String listId, String? url) => CheckRecord(
      listId: listId,
      label: 'Unclaimed',
      checkedAt: DateTime.utc(2026, 11, 14),
      fingerprint: '',
      wins: const <Win>[],
      numbersScanned: 1,
      integrityOk: true,
      bondsChecked: 1,
      singleNumber: listId == 'unclaimed-single' ? '47DW185533' : null,
      sourceUrl: url,
    );
    NsiIndex index(String url) => NsiIndex(
      draws: const <RemoteList>[],
      unclaimed: RemoteList(id: 'unclaimed', label: 'U', url: Uri.parse(url)),
    );
    const String old = 'https://www.nsandi.com/files/unclaimed-prizes-june-1957-to-march-2025.zip';
    const String newer = 'https://www.nsandi.com/files/unclaimed-prizes-june-1957-to-march-2026.zip';

    test('a different file in a later index supersedes the result', () {
      for (final String id in <String>['unclaimed', 'unclaimed-single']) {
        final CheckRecord r = CheckRecord.fromJson(rec(id, old).toJson());
        expect(r.supersededBy(index(old)), isFalse);
        expect(r.supersededBy(index(newer)), isTrue);
        expect(r.supersededBy(null), isFalse, reason: 'unknown is not stale');
      }
    });

    test('draw results and pre-upgrade records are never flagged', () {
      expect(rec('2026-11', old).supersededBy(index(newer)), isFalse);
      expect(rec('unclaimed', null).supersededBy(index(newer)), isFalse);
    });
  });

  group('L-4: nothing user-entered reaches the release log', () {
    test('debugPrint is only used by the release-silent logger and the '
        'timing line', () {
      final List<String> offenders = <String>[];
      for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String src = f.readAsStringSync();
        final int n = 'debugPrint('.allMatches(src).length;
        if (n == 0) continue;
        if (f.path.endsWith('core/utils/app_log.dart')) continue;
        if (f.path.endsWith('check_session.dart') && n == 1 &&
            src.contains('// Timings and sizes only; no bond numbers')) {
          continue;
        }
        offenders.add('${f.path} ($n)');
      }
      expect(offenders, isEmpty);
      expect(File('lib/core/utils/app_log.dart').readAsStringSync(),
          contains('if (!kReleaseMode) debugPrint(message);'));
    });

    test('the corrupt-value log never includes the exception text', () {
      final String src = File('lib/core/storage/local_store.dart').readAsStringSync();
      expect(src, isNot(contains(r"Corrupt value at $key: $e")));
      expect(src, contains(r'${e.runtimeType}'));
    });
  });

  group('m4: orientation is decided from the real window, not in main()', () {
    test('iOS is left to Info.plist (iPhone portrait, iPad all four)', () {
      expect(orientationsFor(TargetPlatform.iOS, 390), isNull);
      expect(orientationsFor(TargetPlatform.iOS, 1024), isNull);
    });

    test('Android phones are portrait; tablets rotate', () {
      expect(orientationsFor(TargetPlatform.android, 411),
          <DeviceOrientation>[DeviceOrientation.portraitUp]);
      expect(orientationsFor(TargetPlatform.android, 800), isEmpty);
    });

    test('main() no longer locks orientation from a possibly-zero view size',
        () {
      final String src = File('lib/main.dart').readAsStringSync();
      expect(src, isNot(contains('setPreferredOrientations')));
      expect(src, isNot(contains('physicalSize')));
    });

    test('Info.plist lets iPad rotate and keeps iPhone portrait', () {
      final String plist = File('ios/Runner/Info.plist').readAsStringSync();
      final String iphone = plist.substring(
        plist.indexOf('<key>UISupportedInterfaceOrientations</key>'),
        plist.indexOf('<key>UISupportedInterfaceOrientations~ipad</key>'),
      );
      expect(iphone, isNot(contains('Landscape')));
      final String ipad = plist.substring(
          plist.indexOf('<key>UISupportedInterfaceOrientations~ipad</key>'));
      expect(ipad, contains('UIInterfaceOrientationLandscapeLeft'));
      expect(ipad, contains('UIInterfaceOrientationLandscapeRight'));
    });
  });
}
