import 'dart:async';
import 'dart:io';

import 'package:bondbell/core/storage/local_store.dart';
import 'package:bondbell/features/bonds/domain/bond_number.dart';
import 'package:bondbell/features/bonds/presentation/holders_controller.dart';
import 'package:bondbell/features/draws/data/draw_source.dart';
import 'package:bondbell/features/draws/data/nsi_index.dart';
import 'package:bondbell/features/draws/domain/check_models.dart';
import 'package:bondbell/features/draws/presentation/check_session.dart';
import 'package:bondbell/features/draws/presentation/records_controller.dart';
import 'package:bondbell/features/purchases/presentation/purchase_controller.dart';
import 'package:bondbell/features/settings/presentation/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

/// Every way a check can end, and proof that the downloaded NS&I file is
/// gone afterwards in each of them (the spec promises it is deleted in a
/// `finally`). All lists here are synthetic.
void main() {
  late Directory dir;
  late ScriptedSource source;

  // Me: 312KM104000–312KM104499 (500) + 47DW185533. Gran: 9XY000001.
  const String holders =
      '[{"id":"me","name":"Me","ranges":['
      '{"id":"r1","start":"312KM104000","end":"312KM104499"},'
      '{"id":"r2","start":"47DW185533","end":"47DW185533"}]},'
      '{"id":"gran","name":"Gran","ranges":['
      '{"id":"r3","start":"9XY000001","end":"9XY000001"}]}]';

  final String goodWinners = winnersFile(<int, List<String>>{
    1000: <String>['9XY000001'],
    100: <String>['312KM104217', '600AA000001'],
    25: <String>['312KM104000', '312KM104499', '312KM104500', '47DW185533', 'DW369715'],
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bondbell_paths');
    source = ScriptedSource(dir)..defaultZip = buildZip('PWREP.txt', goodWinners);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  DateTime now = DateTime(2026, 11, 20, 10);

  Future<ProviderContainer> make({bool pro = true, String h = holders}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'real.holders': h});
    final ProviderContainer c = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(
          LocalStore(await SharedPreferences.getInstance()),
        ),
        liveDrawSourceProvider.overrideWithValue(source),
        forceProProvider.overrideWithValue(pro),
        indexClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  CheckSessionState st(ProviderContainer c) => c.read(checkSessionProvider);

  void expectNoFilesLeft() {
    for (final File f in <File>[...source.handedOut, ...source.partials]) {
      expect(f.existsSync(), isFalse, reason: '${f.path} was left on disk');
    }
    expect(dir.listSync(), isEmpty);
  }

  Future<void> waitFor(ProviderContainer c, CheckPhase p) async {
    for (int i = 0; i < 400 && st(c).phase != p; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(st(c).phase, p);
  }

  test('a full check: hand-counted wins per holder, totals, and no file left',
      () async {
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    expect(st(c).phase, CheckPhase.ready);
    expect(st(c).sizeBytes, source.defaultZip!.length);
    await s.start();
    expect(st(c).phase, CheckPhase.done, reason: st(c).error);
    final CheckRecord r = st(c).record!;
    // Me: 312KM104217 £100, 312KM104000 £25, 312KM104499 £25, 47DW185533 £25.
    // Gran: 9XY000001 £1,000. 312KM104500 and the rest are not ours.
    final Map<String, int> won = <String, int>{
      for (final Win w in r.wins) w.bond: w.prize,
    };
    expect(won, <String, int>{
      '9XY000001': 1000,
      '312KM104217': 100,
      '312KM104000': 25,
      '312KM104499': 25,
      '47DW185533': 25,
    });
    expect(r.totalWon, 1175);
    expect(r.wins.where((Win w) => w.holderName == 'Gran').single.bond,
        '9XY000001');
    expect(r.wins.first.prize, 1000, reason: 'biggest prize first');
    expect(r.bondsChecked, 502);
    expect(r.numbersScanned, 8);
    expect(r.integrityOk, isTrue);
    expect(r.label, 'November 2026');
    expect(c.read(recordsProvider)['2026-11']!.totalWon, 1175);
    expectNoFilesLeft();
  });

  test('no win is a clean "done" with zero prizes, not a failure', () async {
    source.defaultZip = buildZip(
      'PWREP.txt',
      winnersFile(<int, List<String>>{25: <String>['1AA000001', '2AB000002']}),
    );
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    await s.start();
    expect(st(c).phase, CheckPhase.done);
    expect(st(c).record!.hasWins, isFalse);
    expect(st(c).record!.integrityOk, isTrue);
    expectNoFilesLeft();
  });

  test('an integrity failure still reports, flagged, and the file is deleted',
      () async {
    source.defaultZip = buildZip(
      'PWREP.txt',
      winnersFile(
        <int, List<String>>{25: <String>['312KM104001']},
        claimedTierCounts: <int, int>{25: 2},
        claimedTotal: 2,
      ),
    );
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    await s.start();
    expect(st(c).phase, CheckPhase.done);
    expect(st(c).record!.integrityOk, isFalse);
    expect(c.read(recordsProvider)['2026-11']!.integrityOk, isFalse);
    expectNoFilesLeft();
  });

  test('a truncated ZIP fails with "check on NS&I", nothing stored, file gone',
      () async {
    final List<int> z = source.defaultZip!;
    source.defaultZip = z.sublist(0, z.length - 30);
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    await s.start();
    expect(st(c).phase, CheckPhase.failed);
    expect(st(c).layoutChanged, isTrue);
    expect(st(c).error, contains('NS&I'));
    expect(c.read(recordsProvider), isEmpty);
    expectNoFilesLeft();
  });

  test('a ZIP with no bond numbers in it (format changed) fails, file gone',
      () async {
    source.defaultZip = buildZip('PWREP.txt', 'PREMIUM BOND PRIZE DRAW  December 2026\r\nNew layout\r\n');
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    await s.start();
    expect(st(c).phase, CheckPhase.failed);
    expect(st(c).layoutChanged, isTrue);
    expect(c.read(recordsProvider), isEmpty);
    expectNoFilesLeft();
  });

  test('a download error (e.g. HTML instead of a ZIP) surfaces its message',
      () async {
    source.downloadError = const SourceException(
      NsiDrawSource.webPageInsteadOfFile,
      layoutChanged: true,
    );
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    await s.start();
    expect(st(c).phase, CheckPhase.failed);
    expect(st(c).error, contains('web page'));
    expect(st(c).layoutChanged, isTrue);
    expectNoFilesLeft();
  });

  test('a changed downloads page fails at prepare with "Open NS&I\'s page"',
      () async {
    source.indexError = const SourceException('page changed', layoutChanged: true);
    final ProviderContainer c = await make();
    await c.read(checkSessionProvider.notifier).prepare(const CheckRequest.draw('latest'));
    expect(st(c).phase, CheckPhase.failed);
    expect(st(c).layoutChanged, isTrue);
  });

  test('an index with no draws listed cannot resolve "latest"', () async {
    source.index = const NsiIndex(draws: <RemoteList>[], unclaimed: null);
    final ProviderContainer c = await make();
    await c.read(checkSessionProvider.notifier).prepare(const CheckRequest.draw('latest'));
    expect(st(c).phase, CheckPhase.failed);
    expect(source.handedOut, isEmpty);
  });

  test('a missing unclaimed link fails with "page may have changed"', () async {
    source.index = NsiIndex(draws: testIndex().draws, unclaimed: null);
    final ProviderContainer c = await make();
    await c.read(checkSessionProvider.notifier).prepare(const CheckRequest.unclaimedAll());
    expect(st(c).phase, CheckPhase.failed);
    expect(st(c).layoutChanged, isTrue);
  });

  test('a draw NS&I no longer lists says so', () async {
    final ProviderContainer c = await make();
    await c.read(checkSessionProvider.notifier).prepare(const CheckRequest.draw('2025-01'));
    expect(st(c).phase, CheckPhase.failed);
    expect(st(c).error, contains('no longer lists'));
  });

  test('no bonds saved: refuses to download', () async {
    final ProviderContainer c = await make(h: '[]');
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    await s.start();
    expect(st(c).phase, CheckPhase.failed);
    expect(source.handedOut, isEmpty);
  });

  test('cancel mid-download: cancelled, partial file deleted, nothing stored',
      () async {
    source.hold = Completer<void>();
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    final Future<void> run = s.start();
    await waitFor(c, CheckPhase.downloading);
    await Future<void>.delayed(Duration.zero);
    expect(source.partials.single.existsSync(), isTrue);
    s.cancel();
    await run;
    expect(st(c).phase, CheckPhase.cancelled);
    expect(c.read(recordsProvider), isEmpty);
    expectNoFilesLeft();
  });

  test('cancel mid-scan: the isolate is stopped, file deleted, nothing stored, '
      'and the result never lands later', () async {
    source.defaultZip = buildZip(
      'PWREP.txt',
      winnersFile(<int, List<String>>{
        25: <String>[
          '312KM104001',
          for (int i = 0; i < 400000; i++) '5AB${i.toString().padLeft(6, '0')}',
        ],
      }),
    );
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    final Future<void> run = s.start();
    await waitFor(c, CheckPhase.scanning);
    s.cancel();
    await run;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(st(c).phase, CheckPhase.cancelled);
    expect(c.read(recordsProvider), isEmpty);
    expectNoFilesLeft();
  });

  test('leaving the app\'s state (provider disposed) mid-scan deletes the file',
      () async {
    source.defaultZip = buildZip(
      'PWREP.txt',
      winnersFile(<int, List<String>>{
        25: <String>[for (int i = 0; i < 400000; i++) '5AB${i.toString().padLeft(6, '0')}'],
      }),
    );
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    unawaited(s.start());
    await waitFor(c, CheckPhase.scanning);
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expectNoFilesLeft();
  });

  test('a new check started over a running one leaves only one result', () async {
    source.hold = Completer<void>();
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('2026-10'));
    final Future<void> first = s.start();
    await waitFor(c, CheckPhase.downloading);
    source.hold = null;
    await s.prepare(const CheckRequest.draw('latest'));
    await s.start();
    await first;
    expect(st(c).phase, CheckPhase.done);
    expect(st(c).record!.listId, '2026-11');
    expect(c.read(recordsProvider).keys, <String>['2026-11']);
    expectNoFilesLeft();
  });

  test('single-number unclaimed search reports the number itself, not a holder',
      () async {
    source.zips['unclaimed'] = buildZip('UAREP.txt', <String>[
      'LGS UNCLAIMED £50',
      '  8AA814111 47DW185533',
      'END OF £50, TOTAL BSN = 2',
      'LGS ANONYMOUS £25',
      '  8AA814111',
      'END OF £25, TOTAL BSN = 1',
    ].join('\r\n'));
    final ProviderContainer c = await make(pro: false);
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(CheckRequest.unclaimedSingle(
      // A number nobody has saved: the search must not need saved bonds.
      BondNumber.parse('8AA814111'),
    ));
    await s.start();
    final CheckRecord r = st(c).record!;
    expect(r.listId, 'unclaimed-single');
    expect(r.singleNumber, '8AA814111');
    expect(r.wins.map((Win w) => (w.prize, w.anonymous)).toList(),
        <(int, bool)>[(50, false), (25, true)]);
    expect(r.wins.first.holderName, 'The number you entered');
    expect(r.bondsChecked, 1);
    expect(r.integrityOk, isTrue);
    expectNoFilesLeft();
  });

  test('real and sample results never mix', () async {
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    await s.start();
    expect(c.read(recordsProvider).keys, <String>['2026-11']);
    await c.read(appSettingsProvider.notifier).setSampleMode(true);
    expect(c.read(recordsProvider), isEmpty);
    expect(c.read(holdersProvider).map((h) => h.id),
        <String>['sample-holder', 'sample-grandad']);
    await c.read(appSettingsProvider.notifier).setSampleMode(false);
    expect(c.read(recordsProvider).keys, <String>['2026-11']);
    expect(c.read(holdersProvider).map((h) => h.id), <String>['me', 'gran']);
  });

  // ---- Fix round 2 -------------------------------------------------------

  NsiIndex months(List<String> ids) => NsiIndex(
    draws: <RemoteList>[
      for (final String id in ids)
        RemoteList(
          id: id,
          label: NsiIndexParser.labelFor(id),
          url: Uri.parse('https://www.nsandi.com/files/$id.zip'),
        ),
    ],
    unclaimed: RemoteList(
      id: 'unclaimed',
      label: 'Unclaimed prizes',
      url: Uri.parse('https://www.nsandi.com/files/u.zip'),
    ),
  );

  group('M1: the index is not trusted for the whole session', () {
    // The audit's specified regression test.
    test('"latest" is re-fetched even with a cached index', () async {
      source.index = months(<String>['2026-11']);
      final ProviderContainer c = await make();
      final CheckSessionController s = c.read(checkSessionProvider.notifier);
      await s.prepare(const CheckRequest.draw('latest'));
      expect(st(c).list!.id, '2026-11');
      // Results day: NS&I now lists December.
      source.index = months(<String>['2026-12', '2026-11']);
      await s.prepare(const CheckRequest.draw('latest'));
      expect(st(c).list!.id, '2026-12');
      expect(source.fetches, 2);
    });

    test('a named month reuses a fresh index, refetches after the TTL', () async {
      source.index = months(<String>['2026-11', '2026-10']);
      final ProviderContainer c = await make();
      final CheckSessionController s = c.read(checkSessionProvider.notifier);
      await s.prepare(const CheckRequest.draw('2026-10'));
      now = now.add(const Duration(minutes: 5));
      await s.prepare(const CheckRequest.draw('2026-10'));
      expect(source.fetches, 1);
      now = now.add(IndexController.ttl);
      await s.prepare(const CheckRequest.draw('2026-10'));
      expect(source.fetches, 2);
    });

    test('crossing a results day makes the index stale even within the TTL',
        () async {
      // 1 Dec 2026 is the first working day; results are due 2 Dec.
      now = DateTime(2026, 12, 1, 23, 58);
      source.index = months(<String>['2026-11']);
      final ProviderContainer c = await make();
      await c.read(indexProvider.notifier).ensure();
      now = DateTime(2026, 12, 2, 0, 3);
      expect(c.read(indexProvider.notifier).isStale(), isTrue);
      source.index = months(<String>['2026-12', '2026-11']);
      final NsiIndex i = await c.read(indexProvider.notifier).ensure();
      expect(i.latest!.id, '2026-12');
    });

    test('on resume a stale index is dropped (and nothing is fetched)',
        () async {
      source.index = months(<String>['2026-11']);
      final ProviderContainer c = await make();
      await c.read(indexProvider.notifier).ensure();
      c.read(indexProvider.notifier).dropIfStale();
      expect(c.read(indexProvider).value, isNotNull, reason: 'still fresh');
      now = now.add(const Duration(hours: 1));
      c.read(indexProvider.notifier).dropIfStale();
      expect(c.read(indexProvider).value, isNull);
      expect(source.fetches, 1);
    });
  });

  // Regression (code review m3): the month printed in the file was never
  // compared with the month the link claimed to be.
  test('m3: a link whose file is for another month is refused, nothing saved',
      () async {
    source.index = months(<String>['2026-12', '2026-11']);
    source.zips['2026-12'] = buildZip('PWREP.txt', goodWinners); // November's
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('2026-12'));
    await s.start();
    expect(st(c).phase, CheckPhase.failed);
    expect(st(c).error, contains('leads to the November 2026 list'));
    expect(st(c).layoutChanged, isTrue);
    expect(c.read(recordsProvider), isEmpty);
    expectNoFilesLeft();
  });

  test('m3: the matching month is accepted', () async {
    source.index = months(<String>['2026-12', '2026-11']);
    source.zips['2026-12'] = buildZip(
      'PWREP.txt',
      winnersFile(<int, List<String>>{25: <String>['312KM104000']}, month: 'December 2026'),
    );
    final ProviderContainer c = await make();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('2026-12'));
    await s.start();
    expect(st(c).phase, CheckPhase.done, reason: st(c).error);
  });
}
