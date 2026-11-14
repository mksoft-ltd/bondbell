import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'nsi_list_parser.dart';
import 'range_matcher.dart';
import 'zip_entry_stream.dart';

/// Bounds on what the scan will read (security audit M-1). Real files,
/// Nov 2026: winners 82 MB of text, unclaimed 35 MB; the longest line is
/// the ~250-character notes line, data lines are under 100.
abstract final class ScanLimits {
  /// Never inflate past this, whatever the ZIP claims.
  static const int maxInflatedBytes = 512 * 1024 * 1024;

  /// Slack allowed over the entry's declared uncompressed size.
  static const int declaredSlack = 1024 * 1024;

  /// A line longer than this is not NS&I's layout (and an unbroken one is
  /// how a small ZIP would ask for a huge string).
  static const int maxLineChars = 4096;
}

/// The list broke a [ScanLimits] bound; its message is shown to the user.
class ScanLimitException implements Exception {
  const ScanLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}

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
  final int declared = entry.uncompressedSize;
  final int inflateCap = declared > 0 &&
          declared + ScanLimits.declaredSlack < ScanLimits.maxInflatedBytes
      ? declared + ScanLimits.declaredSlack
      : ScanLimits.maxInflatedBytes;
  int inflated = 0;
  int lastReported = -1;
  final Stream<List<int>> bytes = entry
      .bytes(
        onCompressedBytes: (int read) {
          final int pct = read * 100 ~/ total;
          if (pct != lastReported) {
            lastReported = pct;
            onProgress?.call(read / total);
          }
        },
      )
      .map((List<int> chunk) {
        inflated += chunk.length;
        if (inflated > inflateCap) {
          throw const ScanLimitException(
            'NS&I\'s file unpacks to far more than expected, so Bondbell '
            'stopped reading it.',
          );
        }
        return chunk;
      });
  await for (final String line in bytes
      .transform(latin1.decoder)
      .transform(const BoundedLineSplitter(ScanLimits.maxLineChars))) {
    parser.addLine(line);
  }
  return parser.finish(entry.name);
}

/// Splits text into lines exactly as [LineSplitter] does (it IS
/// [LineSplitter]), but first refuses any run of more than [maxChars]
/// characters without a line break, so [LineSplitter] never buffers an
/// unbounded partial line.
///
/// The guard is a synchronous `map` that only looks for the last line break
/// in each chunk, so the splitting stays in [LineSplitter]'s fast chunked
/// path (review N3: a hand-written `async*` splitter doubled scan time).
class BoundedLineSplitter extends StreamTransformerBase<String, String> {
  const BoundedLineSplitter(this.maxChars);
  final int maxChars;

  @override
  Stream<String> bind(Stream<String> stream) {
    int run = 0; // characters since the last \n or \r
    return stream.map((String chunk) {
      int first = -1;
      int last = -1;
      for (int i = 0; i < chunk.length; i++) {
        final int c = chunk.codeUnitAt(i);
        if (c == 10 || c == 13) {
          first = i;
          break;
        }
      }
      if (first < 0) {
        run += chunk.length;
      } else {
        // The stretch carried over from earlier chunks ends here.
        if (run + first > maxChars) _tooLong();
        for (int i = chunk.length - 1; i >= first; i--) {
          final int c = chunk.codeUnitAt(i);
          if (c == 10 || c == 13) {
            last = i;
            break;
          }
        }
        run = chunk.length - last - 1;
      }
      // Stretches wholly inside one chunk are emitted by LineSplitter at
      // once, so they can't grow its buffer; only the open tail can.
      if (run > maxChars) _tooLong();
      return chunk;
    }).transform(const LineSplitter());
  }

  static Never _tooLong() => throw const ScanLimitException(
    'NS&I\'s file has a line far longer than its usual layout, so '
    'Bondbell stopped reading it.',
  );
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
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<_ScanRequest>(
        _entry,
        _ScanRequest(port.sendPort, zipPath, kind, targets),
        onError: port.sendPort,
        onExit: port.sendPort,
        debugName: 'bondbell-scan',
      );
    } on Object {
      port.close(); // review n3: never leak the port when spawn fails.
      rethrow;
    }
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
    } on ScanLimitException catch (e) {
      r.reply.send(_ScanFailure(e.message));
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
