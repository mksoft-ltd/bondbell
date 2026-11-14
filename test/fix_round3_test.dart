import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bondbell/core/constants/app_constants.dart';
import 'package:bondbell/core/storage/local_store.dart';
import 'package:bondbell/features/draws/data/draw_source.dart';
import 'package:bondbell/features/draws/engine/scan_worker.dart';
import 'package:bondbell/features/draws/presentation/check_session.dart';
import 'package:bondbell/features/draws/presentation/records_controller.dart';
import 'package:bondbell/features/purchases/presentation/purchase_controller.dart';
import 'package:bondbell/features/settings/presentation/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';
import 'helpers/fakes.dart';

/// Fix round 3 (code review N1/N3–N5, security N-1/N-2, compliance S-2).
void main() {
  group('N1: a check whose result cannot be saved says so', () {
    test('failed phase, nothing recorded, the file still deleted', () async {
      final Directory dir = Directory.systemTemp.createTempSync('bb_r3');
      addTearDown(() => dir.deleteSync(recursive: true));
      final ScriptedSource source = ScriptedSource(dir)
        ..defaultZip = buildZip('PWREP.txt',
            winnersFile(<int, List<String>>{25: <String>['312KM104000']}));
      SharedPreferences.setMockInitialValues(<String, Object>{
        'real.holders': '[{"id":"me","name":"Me","ranges":['
            '{"id":"r1","start":"312KM104000","end":"312KM104499"}]}]',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final FailingStore store = FailingStore(prefs);
      final ProviderContainer c = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        liveDrawSourceProvider.overrideWithValue(source),
        forceProProvider.overrideWithValue(true),
      ]);
      addTearDown(c.dispose);
      final CheckSessionController s = c.read(checkSessionProvider.notifier);
      await s.prepare(const CheckRequest.draw('latest'));
      await s.start();
      final CheckSessionState st = c.read(checkSessionProvider);
      expect(st.phase, CheckPhase.failed);
      expect(st.error, contains("couldn't save the result"));
      expect(c.read(recordsProvider), isEmpty);
      expect(dir.listSync(), isEmpty);
    });
  });

  group('N-1: the delete dialog says exactly what goes and what stays', () {
    test('names holders, bond numbers, results; keeps settings and Pro', () {
      final String t = deleteAllDialogText('phone');
      expect(t, contains('every holder, bond number and saved result'));
      expect(t, contains('sample-mode data'));
      expect(t, contains('settings'));
      expect(t, contains('Bondbell Pro purchase are kept'));
      expect(t, isNot(contains('can be restored')));
    });
  });

  group('N-2 / N4: download time bounds', () {
    test('30 minutes for the ZIP, a real overall bound for the page', () {
      expect(NsiDrawSource.totalDeadline, const Duration(minutes: 30));
      expect(NsiDrawSource.pageDeadline, lessThanOrEqualTo(const Duration(minutes: 2)));
    });

    test('a downloads page trickled inside the stall timeout is stopped',
        () async {
      final MockClient c = MockClient.streaming((http.BaseRequest r, _) async {
        Stream<List<int>> body() async* {
          for (int i = 0; i < 100; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            yield <int>[0x20];
          }
        }

        return http.StreamedResponse(body(), 200,
            headers: const <String, String>{'content-type': 'text/html'});
      });
      final Stopwatch sw = Stopwatch()..start();
      await expectLater(
        NsiDrawSource(
          clientFactory: () => c,
          platform: 'iOS',
          pageReadDeadline: const Duration(milliseconds: 150),
        ).fetchIndex(),
        throwsA(isA<SourceException>().having(
            (SourceException e) => e.message, 'message', contains('too long'))),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('N3: the faster line splitter keeps the M-1 bound', () {
    Future<List<String>> split(List<String> chunks, int max) =>
        Stream<String>.fromIterable(chunks)
            .transform(BoundedLineSplitter(max))
            .toList();

    test('a line exactly at the limit passes; one over fails', () async {
      expect(await split(<String>['a' * 10, '\nb'], 10), <String>['a' * 10, 'b']);
      await expectLater(split(<String>['a' * 11, '\n'], 10),
          throwsA(isA<ScanLimitException>()));
    });

    test('a long stretch split across many chunks is caught', () async {
      await expectLater(
        split(<String>['x\n', 'aaaa', 'aaaa', 'aaa', 'b\n'], 10),
        throwsA(isA<ScanLimitException>()),
      );
    });

    test('a stretch carried into a chunk that has a break is counted',
        () async {
      await expectLater(
        split(<String>['aaaaaaaa', 'aaaa\nshort'], 10),
        throwsA(isA<ScanLimitException>()),
      );
      expect(await split(<String>['aaaaa', 'aaaa\nshort'], 10),
          <String>['aaaaaaaaa', 'short']);
    });

    test('output equals LineSplitter on mixed endings and odd chunking',
        () async {
      const String text = 'a\r\nbb\rccc\n\nd\r\r\ne';
      for (int cut = 1; cut < text.length; cut++) {
        final List<String> chunks = <String>[
          for (int i = 0; i < text.length; i += cut)
            text.substring(i, (i + cut).clamp(0, text.length)),
        ];
        expect(await split(chunks, 100), const LineSplitterLines(text).lines,
            reason: 'chunk size $cut');
      }
    });
  });

  group('S-2: the in-app notice matches the store disclaimer', () {
    test('word for word with both long descriptions', () {
      for (final String f in <String>[
        'ios/fastlane/metadata/en-GB/description.txt',
        'android/fastlane/metadata/android/en-GB/full_description.txt',
      ]) {
        expect(File(f).readAsStringSync(), contains(AppConstants.independenceNotice),
            reason: f);
      }
      expect(AppConstants.independenceNotice, contains('Director of Savings'));
      expect(AppConstants.independenceNotice, isNot(contains('are trade marks of National')));
    });

    test('no other trade-mark ownership statement anywhere in lib/', () {
      final List<String> hits = <String>[];
      for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String src = f.readAsStringSync();
        if (RegExp('trade ?mark', caseSensitive: false).hasMatch(src) &&
            !f.path.endsWith('app_constants.dart')) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty);
    });
  });
}

/// LineSplitter's own output for [text], the reference for the splitter.
class LineSplitterLines {
  const LineSplitterLines(this.text);
  final String text;
  List<String> get lines => const LineSplitter().convert(text);
}
