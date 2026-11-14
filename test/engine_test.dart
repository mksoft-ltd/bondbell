import 'dart:io';

import 'package:bondbell/features/draws/engine/nsi_list_parser.dart';
import 'package:bondbell/features/draws/engine/range_matcher.dart';
import 'package:bondbell/features/draws/engine/scan_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

/// Synthetic text in the layout measured from NS&I's files (Nov 2026).
const String winnersText = '''
_______________________________________________________________________________________________

PREMIUM BOND PRIZE DRAW                                                          November 2026
_______________________________________________________________________________________________
Notes:
(i)  The amount for distribution is £1,175 which sum gives, in accordance with the prospectus, a total of 13 prizes. Bond Unit Serial Numbers drawn for these prizes are Parts I - II as follows:
| I.   1 prize(s) of £1,000                 | II.   12 prizes of £25                  |
_______________________________________________________________________________________________

(iv)  This draw affects only bonds sold between November 1956 and October 2026 inclusive.

                     Part I - Number(s) drawn for Prize(s) of £1,000 

                                              652GW962089

                         Part II - Numbers drawn for Prizes of £25 each 

534AG096581 604AY450745 618AS446760 663AF705822 312BK800162 355BJ949387  85LV272879   3JA171611
                                                                             Page No. 2
                          Part II - Prizes of £25 each (contd.)

    DW369715 688ZY673096 688ZY673097 100AA000000
''';

const String unclaimedText = '''
LGS UNCLAIMED £100
  5ET395766 118EQ236890
END OF £100, TOTAL BSN = 2

LGS UNCLAIMED £25
 47DW185533  47DW185533
LGS UNCLAIMED £25
 12AB000001
END OF £25, TOTAL BSN = 3

LGS ANONYMOUS £25
  8AA814111
END OF £25, TOTAL BSN = 1
''';

ScanSummary parse(ListKind kind, String text, List<ScanTarget> targets) {
  final NsiListParser p = NsiListParser(kind, RangeMatcher(targets));
  for (final String line in text.split('\n')) {
    p.addLine(line);
  }
  return p.finish('fixture');
}

void main() {
  group('isBondToken', () {
    test('accepts all four observed shapes', () {
      for (final String t in <String>[
        '652GW962089', '85LV272879', '3JA171611', 'DW369715',
      ]) {
        expect(isBondToken(t), isTrue, reason: t);
      }
    });
    test('rejects text and near-misses', () {
      for (final String t in <String>[
        'Page', '2', '£25', '(contd.)', '0AB123456', '1234AB123456',
        'ab123456', 'AB12345', 'November',
      ]) {
        expect(isBondToken(t), isFalse, reason: t);
      }
    });
  });

  test('winners layout: prizes per part, totals check, matches', () {
    final ScanSummary s = parse(ListKind.winners, winnersText, const <ScanTarget>[
      ScanTarget(series: '688ZY', lo: 673000, hi: 673096, holderId: 'me'),
      ScanTarget(series: 'DW', lo: 369700, hi: 369799, holderId: 'gran'),
      ScanTarget(series: '652GW', lo: 962089, hi: 962089, holderId: 'me'),
    ]);
    expect(s.drawLabel, 'November 2026');
    expect(s.numbersScanned, 13);
    expect(s.expectedTotal, 13);
    expect(s.countsByPrize, <int, int>{1000: 1, 25: 12});
    expect(s.integrityOk, isTrue);
    expect(
      s.hits.map((ScanHit h) => '${h.bond}:${h.prize}:${h.holderIds}'),
      <String>['652GW962089:1000:[me]', 'DW369715:25:[gran]', '688ZY673096:25:[me]'],
    );
  });

  test('a dropped line breaks integrity', () {
    final String broken = winnersText.replaceFirst(
        '    DW369715 688ZY673096 688ZY673097 100AA000000\n', '');
    expect(parse(ListKind.winners, broken, const <ScanTarget>[]).integrityOk,
        isFalse);
  });

  test('numbers before any heading are flagged, not assigned', () {
    final ScanSummary s =
        parse(ListKind.winners, '652GW962089\n$winnersText', const <ScanTarget>[]);
    expect(s.unassigned, 1);
    expect(s.integrityOk, isFalse);
  });

  test('unclaimed layout: repeated headings, END totals, anonymous section', () {
    final ScanSummary s = parse(ListKind.unclaimed, unclaimedText, const <ScanTarget>[
      ScanTarget(series: '47DW', lo: 185520, hi: 185569, holderId: 'gran'),
      ScanTarget(series: '8AA', lo: 814100, hi: 814200, holderId: 'me'),
    ]);
    expect(s.numbersScanned, 6);
    expect(s.expectedTotal, 6);
    expect(s.integrityOk, isTrue);
    // The same bond can hold two unclaimed prizes: both are reported.
    expect(s.hits.where((ScanHit h) => h.bond == '47DW185533').length, 2);
    final ScanHit anon = s.hits.firstWhere((ScanHit h) => h.bond == '8AA814111');
    expect(anon.anonymous, isTrue);
    expect(anon.prize, 25);
  });

  test('a holder with overlapping ranges is reported once per number', () {
    final RangeMatcher m = RangeMatcher(const <ScanTarget>[
      ScanTarget(series: 'DW', lo: 1, hi: 500000, holderId: 'a'),
      ScanTarget(series: 'DW', lo: 300000, hi: 400000, holderId: 'a'),
      ScanTarget(series: 'DW', lo: 369715, hi: 369715, holderId: 'b'),
    ]);
    expect(m.match('DW369715'), <String>['a', 'b']);
    expect(m.match('DX369715'), isNull);
    expect(m.match('1DW369715'), isNull);
  });

  group('streaming from a real ZIP (bundled synthetic sample)', () {
    const List<ScanTarget> sample = <ScanTarget>[
      ScanTarget(series: '312KM', lo: 104000, hi: 104499, holderId: 'h'),
      ScanTarget(series: '47DW', lo: 185520, hi: 185569, holderId: 'h'),
    ];

    test('winners', () async {
      final ScanSummary s = await scanZipFile(
          File('assets/sample/sample_winners.zip'), ListKind.winners, sample);
      expect(s.integrityOk, isTrue);
      expect(s.hits.map((ScanHit h) => '${h.bond}:${h.prize}'),
          <String>['312KM104217:100', '312KM104388:25']);
    });

    test('unclaimed', () async {
      final ScanSummary s = await scanZipFile(
          File('assets/sample/sample_unclaimed.zip'), ListKind.unclaimed, sample);
      expect(s.integrityOk, isTrue);
      expect(s.hits.single.bond, '47DW185533');
      expect(s.hits.single.prize, 50);
    });

    test('in a background isolate, with progress', () async {
      final List<double> progress = <double>[];
      final ScanJob job = await ScanJob.start(
        zipPath: 'assets/sample/sample_winners.zip',
        kind: ListKind.winners,
        targets: sample,
        onProgress: progress.add,
      );
      final ScanSummary s = await job.result;
      expect(s.hits, hasLength(2));
      expect(progress, isNotEmpty);
      expect(progress.last, closeTo(1.0, 0.001));
    });

    test('a non-ZIP fails with a readable error', () async {
      final Directory d = Directory.systemTemp.createTempSync('bb');
      final File f = File('${d.path}/x.zip')..writeAsStringSync('<html>nope</html>' * 10);
      final ScanJob job = await ScanJob.start(
          zipPath: f.path, kind: ListKind.winners, targets: sample);
      await expectLater(job.result, throwsA(isA<ScanException>()));
      d.deleteSync(recursive: true);
    });
  });

  // ---- Fix round 2: security audit M-1 (inflate and line bounds) --------
  group('M-1: bounded scan', () {
    late Directory d;
    setUp(() => d = Directory.systemTemp.createTempSync('bb_scan'));
    tearDown(() => d.deleteSync(recursive: true));

    test('a newline-free text is refused at the line cap, not buffered', () async {
      final File f = File('${d.path}/a.zip')
        ..writeAsBytesSync(buildZip('X.txt', 'A' * (ScanLimits.maxLineChars * 50)));
      await expectLater(
        scanZipFile(f, ListKind.winners, const <ScanTarget>[]),
        throwsA(isA<ScanLimitException>()),
      );
    });

    test('inflating past the declared size (+slack) is refused', () async {
      final String text = '$winnersText\r\n${'652GW962089 ' * 8}\r\n' * 1;
      final List<int> big = buildZip('X.txt', text + ('\r\n' * (2 * ScanLimits.declaredSlack)));
      // Lie in the central directory: claim the entry is 100 bytes.
      final List<int> z = List<int>.of(big);
      int cd = -1;
      for (int i = z.length - 22; i >= 0; i--) {
        if (z[i] == 0x50 && z[i + 1] == 0x4b && z[i + 2] == 1 && z[i + 3] == 2) {
          cd = i;
          break;
        }
      }
      z.setRange(cd + 24, cd + 28, <int>[100, 0, 0, 0]);
      final File f = File('${d.path}/b.zip')..writeAsBytesSync(z);
      await expectLater(
        scanZipFile(f, ListKind.winners, const <ScanTarget>[]),
        throwsA(isA<ScanLimitException>()),
      );
    });

    test('the isolate reports a limit breach in words', () async {
      final File f = File('${d.path}/c.zip')
        ..writeAsBytesSync(buildZip('X.txt', 'A' * (ScanLimits.maxLineChars * 4)));
      final ScanJob job = await ScanJob.start(
          zipPath: f.path, kind: ListKind.winners, targets: const <ScanTarget>[]);
      await expectLater(
        job.result,
        throwsA(isA<ScanException>().having(
            (ScanException e) => e.message, 'message', contains('stopped reading'))),
      );
    });

    test('BoundedLineSplitter matches LineSplitter on CRLF split across chunks',
        () async {
      final List<String> got = await Stream<String>.fromIterable(
        <String>['a\r', '\nb\r\n', 'c', '\n\nd'],
      ).transform(const BoundedLineSplitter(100)).toList();
      expect(got, <String>['a', 'b', 'c', '', 'd']);
    });

    test('the bounds have headroom over the real files', () {
      expect(ScanLimits.maxInflatedBytes, greaterThan(5 * 82 * 1024 * 1024));
      expect(ScanLimits.maxLineChars, greaterThan(10 * 260));
    });
  });
}
