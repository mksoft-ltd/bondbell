import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_constants.dart';
import 'nsi_index.dart';

/// Where the lists come from. The live source reads nsandi.com on the
/// user's device; the sample source reads bundled synthetic files. Both
/// produce a ZIP on disk that the same scanner reads.
abstract class DrawSource {
  bool get isSample;
  Future<NsiIndex> fetchIndex();

  /// Download size in bytes, if the server says.
  Future<int?> sizeOf(RemoteList list);

  /// Downloads [list] to a fresh temporary file. The caller deletes it.
  Future<File> download(
    RemoteList list, {
    void Function(int received, int? total)? onProgress,
    DownloadCancel? cancel,
  });
}

/// Lets the UI abort a download mid-stream.
class DownloadCancel {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final void Function() l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() l) => _listeners.add(l);
}

/// Thrown for anything the user should see in words.
class SourceException implements Exception {
  const SourceException(this.message, {this.layoutChanged = false});
  final String message;

  /// The downloads page no longer looks the way Bondbell expects; the UI
  /// offers "Open NS&I's page" instead of a retry loop.
  final bool layoutChanged;
  @override
  String toString() => message;
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();
}

/// Temporary files go in their own folder so a crash mid-check can be
/// cleaned up on next launch.
Future<Directory> scratchDir() async {
  final Directory tmp = await getTemporaryDirectory();
  final Directory d = Directory('${tmp.path}/bondbell_lists');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

/// Deletes any list left behind by an interrupted check.
Future<void> clearScratch() async {
  try {
    final Directory d = await scratchDir();
    for (final FileSystemEntity e in d.listSync()) {
      e.deleteSync(recursive: true);
    }
  } on Object catch (e) {
    debugPrint('clearScratch: $e');
  }
}

class NsiDrawSource implements DrawSource {
  NsiDrawSource({http.Client Function()? clientFactory, String? platform})
    : _clientFactory = clientFactory ?? http.Client.new,
      _ua = AppConstants.userAgent(
        platform ?? (Platform.isIOS ? 'iOS' : 'Android'),
      );

  final http.Client Function() _clientFactory;
  final String _ua;

  static const Duration _timeout = Duration(seconds: 30);

  @override
  bool get isSample => false;

  Map<String, String> get _headers => <String, String>{'User-Agent': _ua};

  @override
  Future<NsiIndex> fetchIndex() async {
    final http.Client c = _clientFactory();
    try {
      final Uri page = Uri.parse(AppConstants.nsiDownloadsPage);
      final http.Response r = await c
          .get(page, headers: _headers)
          .timeout(_timeout);
      if (r.statusCode != 200) {
        throw SourceException(
          'NS&I\'s site answered with an error (${r.statusCode}). '
          'Try again in a little while.',
        );
      }
      final NsiIndex index = NsiIndexParser.parse(r.body, page);
      if (index.draws.isEmpty) {
        throw const SourceException(
          'Bondbell couldn\'t find the winning-numbers files on NS&I\'s '
          'downloads page. The page may have changed. You can still open it '
          'and check there.',
          layoutChanged: true,
        );
      }
      return index;
    } on SourceException {
      rethrow;
    } on TimeoutException {
      throw const SourceException(
        'NS&I\'s site took too long to answer. Check your connection and try '
        'again.',
      );
    } on Object catch (e) {
      debugPrint('fetchIndex: $e');
      throw const SourceException(
        'Couldn\'t reach NS&I\'s site. Check your internet connection and '
        'try again.',
      );
    } finally {
      c.close();
    }
  }

  @override
  Future<int?> sizeOf(RemoteList list) async {
    final http.Client c = _clientFactory();
    try {
      final http.Response r = await c
          .head(list.url, headers: _headers)
          .timeout(_timeout);
      if (r.statusCode != 200) return null;
      return int.tryParse(r.headers['content-length'] ?? '');
    } on Object {
      return null;
    } finally {
      c.close();
    }
  }

  /// Not starting with "PK" means NS&I (or something in between, such as
  /// a bot-protection page) answered with something other than the file.
  static void _checkZipMagic(List<int> head) {
    if (head.length >= 2 && head[0] == 0x50 && head[1] == 0x4b) return;
    throw const SourceException(webPageInsteadOfFile, layoutChanged: true);
  }

  static const String webPageInsteadOfFile =
      'NS&I returned a web page instead of the file. Their site may be busy '
      'or checking for automated traffic. Try again later, or open their '
      'page.';

  @override
  Future<File> download(
    RemoteList list, {
    void Function(int received, int? total)? onProgress,
    DownloadCancel? cancel,
  }) async {
    final http.Client c = _clientFactory();
    final Directory dir = await scratchDir();
    final File out = File(
      '${dir.path}/${list.id}-${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    IOSink? sink;
    cancel?.onCancel(c.close);
    try {
      final http.Request req = http.Request('GET', list.url)
        ..headers.addAll(_headers);
      final http.StreamedResponse r = await c.send(req).timeout(_timeout);
      if (r.statusCode != 200) {
        throw SourceException(
          'NS&I\'s site didn\'t send the file (error ${r.statusCode}). Try '
          'again later, or open their page to download it there.',
        );
      }
      final String type = r.headers['content-type'] ?? '';
      if (type.contains('html')) {
        throw const SourceException(webPageInsteadOfFile, layoutChanged: true);
      }
      final int? total = r.contentLength;
      sink = out.openWrite();
      int received = 0;
      // The first bytes must be the ZIP signature "PK". They are held back
      // until at least two have arrived, however the server splits its
      // chunks (a 1-byte first chunk must not skip the check).
      final List<int> head = <int>[];
      bool checkedMagic = false;
      await for (final List<int> chunk in r.stream.timeout(_timeout)) {
        if (cancel?.isCancelled ?? false) {
          throw const DownloadCancelledException();
        }
        received += chunk.length;
        if (!checkedMagic) {
          head.addAll(chunk);
          if (head.length < 2) continue;
          checkedMagic = true;
          _checkZipMagic(head);
          sink.add(head);
        } else {
          sink.add(chunk);
        }
        onProgress?.call(received, total);
      }
      // A response shorter than two bytes never reached the check.
      if (!checkedMagic && !(cancel?.isCancelled ?? false)) {
        _checkZipMagic(head);
      }
      await sink.close();
      sink = null;
      if (cancel?.isCancelled ?? false) {
        throw const DownloadCancelledException();
      }
      if (total != null && received != total) {
        throw const SourceException(
          'The download stopped part-way. Check your connection and try '
          'again.',
        );
      }
      return out;
    } on Object catch (e) {
      await sink?.close().catchError((Object _) {});
      if (out.existsSync()) out.deleteSync();
      if (cancel?.isCancelled ?? false) {
        throw const DownloadCancelledException();
      }
      if (e is SourceException || e is DownloadCancelledException) rethrow;
      debugPrint('download: $e');
      if (e is TimeoutException) {
        throw const SourceException(
          'The download stalled. Check your connection and try again.',
        );
      }
      throw const SourceException(
        'The download failed. Check your connection and try again.',
      );
    } finally {
      c.close();
    }
  }
}

/// Bundled, synthetic lists in NS&I's layout. Generated by
/// `tool/generate_sample_data.py` from random numbers; nothing here comes
/// from NS&I's files.
class SampleDrawSource implements DrawSource {
  SampleDrawSource({AssetBundle? bundle, this.simulateDelay = true})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final bool simulateDelay;

  static const String sampleDrawId = '2026-11';
  static const String winnersAsset = 'assets/sample/sample_winners.zip';
  static const String unclaimedAsset = 'assets/sample/sample_unclaimed.zip';

  static final NsiIndex index = NsiIndex(
    draws: <RemoteList>[
      RemoteList(
        id: sampleDrawId,
        label: 'November 2026 (sample)',
        url: Uri.parse('asset:///$winnersAsset'),
      ),
    ],
    unclaimed: RemoteList(
      id: 'unclaimed',
      label: 'Unclaimed prizes list (sample)',
      url: Uri.parse('asset:///$unclaimedAsset'),
    ),
  );

  @override
  bool get isSample => true;

  @override
  Future<NsiIndex> fetchIndex() async => index;

  @override
  Future<int?> sizeOf(RemoteList list) async =>
      (await _bundle.load(_asset(list))).lengthInBytes;

  String _asset(RemoteList l) =>
      l.id == 'unclaimed' ? unclaimedAsset : winnersAsset;

  @override
  Future<File> download(
    RemoteList list, {
    void Function(int received, int? total)? onProgress,
    DownloadCancel? cancel,
  }) async {
    final ByteData data = await _bundle.load(_asset(list));
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    // A short, visible progress run so the sample shows the real flow.
    const int steps = 20;
    for (int i = 1; i <= steps; i++) {
      if (cancel?.isCancelled ?? false) {
        throw const DownloadCancelledException();
      }
      if (simulateDelay) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      onProgress?.call(bytes.length * i ~/ steps, bytes.length);
    }
    final Directory dir = await scratchDir();
    final File out = File(
      '${dir.path}/sample-${list.id}-${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }
}
