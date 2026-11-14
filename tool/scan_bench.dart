// Developer benchmark: scans a locally downloaded NS&I ZIP with the app's
// engine and prints timing, counts and integrity. NS&I files are never
// committed; pass a path outside the repo.
//   dart run tool/scan_bench.dart <zip> winners|unclaimed [series:lo:hi ...]
import 'dart:io';

import 'package:bondbell/features/draws/engine/nsi_list_parser.dart';
import 'package:bondbell/features/draws/engine/range_matcher.dart';
import 'package:bondbell/features/draws/engine/scan_worker.dart';

Future<void> main(List<String> args) async {
  final ListKind kind = ListKind.values.byName(args[1]);
  final List<ScanTarget> targets = <ScanTarget>[
    for (final String a in args.skip(2))
      ScanTarget(
        series: a.split(':')[0],
        lo: int.parse(a.split(':')[1]),
        hi: int.parse(a.split(':')[2]),
        holderId: 'h',
      ),
  ];
  final Stopwatch sw = Stopwatch()..start();
  final ScanJob job = await ScanJob.start(
    zipPath: args[0],
    kind: kind,
    targets: targets,
  );
  final ScanSummary s = await job.result;
  sw.stop();
  stdout.writeln('file=${s.fileName} draw=${s.drawLabel}');
  stdout.writeln('scanned=${s.numbersScanned} expected=${s.expectedTotal} '
      'unassigned=${s.unassigned} integrity=${s.integrityOk}');
  stdout.writeln('counts=${s.countsByPrize}');
  stdout.writeln('expectedByPrize=${s.expectedByPrize}');
  for (final ScanHit h in s.hits) {
    stdout.writeln('HIT ${h.bond} £${h.prize} anon=${h.anonymous}');
  }
  stdout.writeln('elapsed_ms=${sw.elapsedMilliseconds} '
      'maxrss_bytes=${ProcessInfo.maxRss}');
}
