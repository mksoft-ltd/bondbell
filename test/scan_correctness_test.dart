import 'dart:io';

import 'package:bondbell/features/bonds/domain/bond_number.dart';
import 'package:bondbell/features/bonds/domain/holder.dart';
import 'package:bondbell/features/draws/engine/nsi_list_parser.dart';
import 'package:bondbell/features/draws/engine/range_matcher.dart';
import 'package:bondbell/features/draws/engine/scan_worker.dart';
import 'package:bondbell/features/draws/engine/zip_entry_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

/// "You won" must never be wrong and a win must never be missed. Every
/// expectation below is worked out by hand from the bond-number format in
/// docs/PRODUCT_SPEC.md, not recorded from what the engine returns. All
/// numbers are synthetic.
void main() {
  ScanTarget t(String start, String end, [String holder = 'h']) {
    final RangeResult r = BondRange.validate(start, end);
    if (r.error != null) throw StateError('$start–$end: ${r.error}');
    return ScanTarget(
      series: r.start!.series,
      lo: r.start!.serial,
      hi: r.end!.serial,
      holderId: holder,
    );
  }

  /// Winners file with every number at £25, scanned against [targets].
  ScanSummary scan(List<String> numbers, List<ScanTarget> targets) {
    final NsiListParser p = NsiListParser(ListKind.winners, RangeMatcher(targets));
    for (final String line in winnersFile(<int, List<String>>{25: numbers}).split('\r\n')) {
      p.addLine(line);
    }
    return p.finish('fixture');
  }

  Set<String> hits(List<String> numbers, List<ScanTarget> targets) =>
      scan(numbers, targets).hits.map((ScanHit h) => h.bond).toSet();

  group('range boundaries are inclusive and exact', () {
    final List<ScanTarget> range = <ScanTarget>[t('312KM100000', '312KM119999')];

    test('both ends match; one either side does not', () {
      expect(
        hits(<String>['312KM099999', '312KM100000', '312KM119999', '312KM120000'], range),
        <String>{'312KM100000', '312KM119999'},
      );
    });

    test('a single-bond entry matches only itself', () {
      final List<ScanTarget> one = <ScanTarget>[t('47DW185533', '')];
      expect(hits(<String>['47DW185532', '47DW185533', '47DW185534'], one),
          <String>{'47DW185533'});
    });

    test('serial 000000 and 999999 at the edges of a series', () {
      final List<ScanTarget> whole = <ScanTarget>[t('5AB000000', '5AB999999')];
      expect(hits(<String>['5AB000000', '5AB999999', '5AC000000'], whole),
          <String>{'5AB000000', '5AB999999'});
    });

    test('same letters and serial but a different prefix never match', () {
      // 312KM / 12KM / 2KM / KM are four different series.
      final Set<String> h = hits(
        <String>['12KM100005', '2KM100005', 'KM100005', '412KM100005', '312KM100005'],
        range,
      );
      expect(h, <String>{'312KM100005'});
    });

    test('a range in a short series is not fooled by a longer number ending '
        'the same way', () {
      // "99AB000005" is the tail of "999AB000005"; only the exact series
      // may match.
      final List<ScanTarget> short = <ScanTarget>[t('99AB000000', '99AB999999')];
      expect(hits(<String>['999AB000005', '99AB000005', '9AB000005'], short),
          <String>{'99AB000005'});
    });

    test('prefix-less certificates (oldest bonds) match their own series only',
        () {
      final List<ScanTarget> old = <ScanTarget>[t('DW369700', 'DW369720')];
      expect(hits(<String>['DW369715', '1DW369715', 'DX369715'], old),
          <String>{'DW369715'});
    });

    test('all four observed shapes match in one scan', () {
      final List<ScanTarget> mixed = <ScanTarget>[
        t('688ZY673096', ''),
        t('85LV272879', ''),
        t('3JA171611', ''),
        t('DW369715', ''),
      ];
      expect(
        hits(<String>['688ZY673096', '85LV272879', '3JA171611', 'DW369715', '688ZY673095'],
            mixed),
        <String>{'688ZY673096', '85LV272879', '3JA171611', 'DW369715'},
      );
    });
  });

  group('ranges the user cannot enter', () {
    String? err(String a, String b) => BondRange.validate(a, b).error;

    test('a range across a prefix-length boundary (99… to 100…) is two series',
        () {
      expect(err('99AB999999', '100AB000000'), contains('start the same way'));
    });

    test('I, O and U are refused in either letter, with the right hint', () {
      expect(err('12AI345678', ''), contains('I, O or U'));
      expect(err('12OA345678', ''), contains('number 0'));
      expect(err('12AU345678', ''), contains('I, O or U'));
      expect(err('12AB345678', '12AU345679'), startsWith('Last number'));
    });

    test('the 23 letters used are exactly A–Z without I, O, U', () {
      expect(BondNumber.allowedLetters.length, 23);
      for (final String c in 'IOU'.split('')) {
        expect(BondNumber.allowedLetters.contains(c), isFalse);
      }
    });

    test('lower-case and spaced input matches the canonical number', () {
      final RangeResult r = BondRange.validate(' 312 km 104217 ', '');
      expect(r.start.toString(), '312KM104217');
    });
  });

  group('overlaps and holders', () {
    test('two overlapping ranges for one holder report the number once', () {
      final ScanSummary s = scan(<String>['100AA000050'], <ScanTarget>[
        t('100AA000000', '100AA000099'),
        t('100AA000040', '100AA000060'),
      ]);
      expect(s.hits.single.holderIds, <String>['h']);
    });

    test('each holder\'s win is attributed to that holder', () {
      final ScanSummary s = scan(<String>['100AA000005', '200BB000005'], <ScanTarget>[
        t('100AA000000', '100AA000009', 'me'),
        t('200BB000000', '200BB000009', 'gran'),
      ]);
      final Map<String, List<String>> by = <String, List<String>>{
        for (final ScanHit h in s.hits) h.bond: h.holderIds,
      };
      expect(by, <String, List<String>>{
        '100AA000005': <String>['me'],
        '200BB000005': <String>['gran'],
      });
    });

    test('a number entered under two holders names both (overlap warning is '
        'shown at entry)', () {
      final ScanSummary s = scan(<String>['100AA000005'], <ScanTarget>[
        t('100AA000000', '100AA000009', 'me'),
        t('100AA000005', '', 'gran'),
      ]);
      expect(s.hits.single.holderIds, unorderedEquals(<String>['me', 'gran']));
    });

    test('the same number drawn twice is two prizes', () {
      final NsiListParser p = NsiListParser(
        ListKind.unclaimed,
        RangeMatcher(<ScanTarget>[t('47DW185533', '')]),
      );
      for (final String l in <String>[
        'LGS UNCLAIMED £100',
        ' 47DW185533',
        'END OF £100, TOTAL BSN = 1',
        'LGS UNCLAIMED £25',
        ' 47DW185533',
        'END OF £25, TOTAL BSN = 1',
      ]) {
        p.addLine(l);
      }
      final ScanSummary s = p.finish('u');
      expect(s.hits.map((ScanHit h) => h.prize).toList(), <int>[100, 25]);
      expect(s.integrityOk, isTrue);
    });
  });

  group('prize amounts come from the section, across page breaks', () {
    test('every tier keeps its own prize, including after (contd.) headings',
        () {
      final List<String> many = <String>[
        for (int i = 0; i < 60; i++) '100AA${i.toString().padLeft(6, '0')}',
      ];
      final NsiListParser p = NsiListParser(
        ListKind.winners,
        RangeMatcher(<ScanTarget>[
          t('100AA000000', '100AA000099'),
          t('7XY000001', ''),
          t('50BC000002', ''),
        ]),
      );
      final String text = winnersFile(<int, List<String>>{
        1000000: <String>['7XY000001'],
        100: many,
        25: <String>['50BC000002'],
      });
      for (final String l in text.split('\r\n')) {
        p.addLine(l);
      }
      final ScanSummary s = p.finish('f');
      final Map<String, int> prize = <String, int>{
        for (final ScanHit h in s.hits) h.bond: h.prize,
      };
      expect(prize['7XY000001'], 1000000);
      expect(prize['100AA000000'], 100);
      expect(prize['100AA000059'], 100, reason: 'after a page break');
      expect(prize['50BC000002'], 25);
      expect(s.hits, hasLength(62));
      expect(s.integrityOk, isTrue);
      expect(s.drawLabel, 'November 2026');
    });
  });

  group('integrity check', () {
    test('a tier table that disagrees with the numbers fails integrity', () {
      final NsiListParser p = NsiListParser(ListKind.winners, RangeMatcher(<ScanTarget>[]));
      final String text = winnersFile(
        <int, List<String>>{100: <String>['1AA000001', '1AA000002'], 25: <String>['1AA000003']},
        claimedTierCounts: <int, int>{100: 3},
        claimedTotal: 3,
      );
      for (final String l in text.split('\r\n')) {
        p.addLine(l);
      }
      final ScanSummary s = p.finish('f');
      expect(s.numbersScanned, 3);
      expect(s.integrityOk, isFalse,
          reason: 'the grand total agrees but one tier does not');
    });

    test('a grand total that disagrees fails integrity', () {
      final NsiListParser p = NsiListParser(ListKind.winners, RangeMatcher(<ScanTarget>[]));
      for (final String l in winnersFile(
        <int, List<String>>{25: <String>['1AA000001']},
        claimedTotal: 2,
      ).split('\r\n')) {
        p.addLine(l);
      }
      expect(p.finish('f').integrityOk, isFalse);
    });

    test('a file with neither notes total nor tier table cannot pass', () {
      final NsiListParser p = NsiListParser(ListKind.winners, RangeMatcher(<ScanTarget>[]));
      for (final String l in <String>[
        'Part I - Numbers drawn for Prizes of £25 each',
        '1AA000001 1AA000002',
      ]) {
        p.addLine(l);
      }
      final ScanSummary s = p.finish('f');
      expect(s.numbersScanned, 2);
      expect(s.integrityOk, isFalse);
    });

    test('an unclaimed file whose END totals disagree fails integrity', () {
      final NsiListParser p = NsiListParser(ListKind.unclaimed, RangeMatcher(<ScanTarget>[]));
      for (final String l in <String>[
        'LGS UNCLAIMED £50',
        ' 1AA000001 1AA000002',
        'END OF £50, TOTAL BSN = 3',
      ]) {
        p.addLine(l);
      }
      expect(p.finish('u').integrityOk, isFalse);
    });

    test('an empty file never passes', () {
      expect(
        NsiListParser(ListKind.winners, RangeMatcher(<ScanTarget>[]))
            .finish('f')
            .integrityOk,
        isFalse,
      );
    });
  });

  group('ZIPs as they arrive from the network', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bondbell_zip'));
    tearDown(() => dir.deleteSync(recursive: true));

    File write(String name, List<int> bytes) =>
        File('${dir.path}/$name')..writeAsBytesSync(bytes);

    final String text = winnersFile(<int, List<String>>{
      100: <String>['312KM104217'],
      25: <String>['312KM104388', '9ZZ000001'],
    });
    final List<ScanTarget> mine = <ScanTarget>[t('312KM100000', '312KM119999')];

    test('deflated and stored entries both scan the same', () async {
      for (final bool deflate in <bool>[true, false]) {
        final ScanSummary s = await scanZipFile(
          write('w$deflate.zip', buildZip('PWREP_02112026.txt', text, deflate: deflate)),
          ListKind.winners,
          mine,
        );
        expect(s.hits.map((ScanHit h) => (h.bond, h.prize)).toSet(),
            <(String, int)>{('312KM104217', 100), ('312KM104388', 25)});
        expect(s.integrityOk, isTrue);
        expect(s.fileName, 'PWREP_02112026.txt');
      }
    });

    test('a truncated download is rejected before scanning', () async {
      final List<int> z = buildZip('PWREP.txt', text);
      for (final int keep in <int>[z.length - 10, z.length ~/ 2, 30, 5]) {
        await expectLater(
          ZipEntryStream.open(write('t$keep.zip', z.sublist(0, keep))),
          throwsA(isA<ZipFormatException>()),
          reason: 'kept $keep of ${z.length} bytes',
        );
      }
    });

    test('corrupt compressed data fails the scan rather than reporting a '
        'partial result', () async {
      final List<int> z = List<int>.of(buildZip('PWREP.txt', text * 30));
      // Scribble over the middle of the deflate stream.
      for (int i = 40; i < 140; i++) {
        z[i] = 0xFF;
      }
      final ScanJob job = await ScanJob.start(
        zipPath: write('c.zip', z).path,
        kind: ListKind.winners,
        targets: mine,
      );
      await expectLater(job.result, throwsA(isA<ScanException>()));
    });

    test('an HTML page saved as .zip is not a ZIP', () async {
      await expectLater(
        ZipEntryStream.open(write('h.zip', '<html><body>blocked</body></html>'.codeUnits)),
        throwsA(isA<ZipFormatException>()),
      );
    });

    test('an empty archive is refused', () async {
      // End-of-central-directory record only, zero entries.
      final List<int> eocd = <int>[0x50, 0x4b, 0x05, 0x06, ...List<int>.filled(18, 0)];
      await expectLater(
        ZipEntryStream.open(write('e.zip', eocd)),
        throwsA(isA<ZipFormatException>()),
      );
    });

    test('cancelling a background scan ends it as cancelled', () async {
      final List<String> lots = <String>[
        for (int i = 0; i < 400000; i++) '5AB${i.toString().padLeft(6, '0')}',
      ];
      final File big = write(
        'big.zip',
        buildZip('PWREP.txt', winnersFile(<int, List<String>>{25: lots})),
      );
      final ScanJob job = await ScanJob.start(
        zipPath: big.path,
        kind: ListKind.winners,
        targets: mine,
      );
      job.cancel();
      await expectLater(job.result, throwsA(isA<ScanCancelled>()));
    });
  });
}
