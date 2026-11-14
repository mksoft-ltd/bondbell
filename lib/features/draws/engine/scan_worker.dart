import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'nsi_list_parser.dart';
import 'range_matcher.dart';
import 'zip_entry_stream.dart';

/// Scans one downloaded NS&I ZIP against the user's ranges, streaming:
/// compressed bytes → raw inflate → Latin-1 → lines → token check. Nothing
/// but the matches is kept, so memory stays flat however big the list is.
Future<ScanSummary> scanZipFile(
  File zip,
  ListKind kind,
  List<ScanTarget> targets, {
  void Function(double fraction)? onProgress,
}) async {
  final ZipEntryStream entry = await ZipEntryStream.open(zip);
  final NsiListParser parser = NsiListParser(kind, RangeMatcher(targets));
  final int total = entry.compressedSize == 0 ? 1 : entry.compressedSize;
  int lastReported = -1;
  await for (final String line in entry
      .bytes(
        onCompressedBytes: (int read) {
          final int pct = read * 100 ~/ total;
          if (pct != lastReported) {
            lastReported = pct;
            onProgress?.call(read / total);
          }
        },
      )
      .transform(latin1.decoder)
      .transform(const LineSplitter())) {
    parser.addLine(line);
  }
  return parser.finish(entry.name);
}

/// Runs [scanZipFile] on a background isolate so the UI never stutters,
/// with progress and a hard cancel (the isolate is killed).
class ScanJob {
  ScanJob._(this._isolate, this.result);

  final Isolate _isolate;
  final Future<ScanSummary> result;
  bool _done = false;

  static Future<ScanJob> start({
    required String zipPath,
    required ListKind kind,
    required List<ScanTarget> targets,
    void Function(double fraction)? onProgress,
  }) async {
    final ReceivePort port = ReceivePort();
    final Completer<ScanSummary> completer = Completer<ScanSummary>();
    final Isolate isolate = await Isolate.spawn<_ScanRequest>(
      _entry,
      _ScanRequest(port.sendPort, zipPath, kind, targets),
      onError: port.sendPort,
      onExit: port.sendPort,
      debugName: 'bondbell-scan',
    );
    late final ScanJob job;
    port.listen((Object? msg) {
      if (completer.isCompleted) return;
      if (msg is double) {
        onProgress?.call(msg);
      } else if (msg is ScanSummary) {
        completer.complete(msg);
      } else if (msg is _ScanFailure) {
        completer.completeError(ScanException(msg.message));
      } else if (msg is List && msg.length == 2) {
        // Uncaught isolate error: [message, stack].
        completer.completeError(ScanException('${msg.first}'));
      } else if (msg == null) {
        completer.completeError(const ScanCancelled());
      }
    });
    job = ScanJob._(isolate, completer.future);
    unawaited(completer.future.then((_) {}, onError: (_) {}).whenComplete(() {
      job._done = true;
      port.close();
    }));
    return job;
  }

  void cancel() {
    if (_done) return;
    _isolate.kill(priority: Isolate.immediate);
  }

  static Future<void> _entry(_ScanRequest r) async {
    try {
      final ScanSummary s = await scanZipFile(
        File(r.zipPath),
        r.kind,
        r.targets,
        onProgress: r.reply.send,
      );
      r.reply.send(s);
    } on ZipFormatException catch (e) {
      r.reply.send(_ScanFailure('The file is not in the expected format '
          '(${e.message}).'));
    } on Object catch (e) {
      r.reply.send(_ScanFailure('Could not read the file: $e'));
    }
  }
}

class _ScanRequest {
  const _ScanRequest(this.reply, this.zipPath, this.kind, this.targets);
  final SendPort reply;
  final String zipPath;
  final ListKind kind;
  final List<ScanTarget> targets;
}

class _ScanFailure {
  const _ScanFailure(this.message);
  final String message;
}

class ScanException implements Exception {
  const ScanException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ScanCancelled implements Exception {
  const ScanCancelled();
}
