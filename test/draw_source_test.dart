import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bondbell/features/draws/data/draw_source.dart';
import 'package:bondbell/features/draws/data/nsi_index.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers/fakes.dart';

/// NsiDrawSource against a scripted HTTP server: every way nsandi.com can
/// answer other than "here is the ZIP", and proof that no partial download
/// is ever left on the device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Directory scratch;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bondbell_src');
    scratch = Directory('${tmp.path}/bondbell_lists');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => tmp.path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    tmp.deleteSync(recursive: true);
  });

  final RemoteList list = RemoteList(
    id: '2026-11',
    label: 'November 2026',
    url: Uri.parse('https://www.nsandi.com/files/asset/zip/x-11-2026.zip'),
  );
  final List<int> zip = buildZip(
    'PWREP.txt',
    winnersFile(<int, List<String>>{25: <String>['100AA000001']}),
  );

  List<FileSystemEntity> leftovers() =>
      scratch.existsSync() ? scratch.listSync() : const <FileSystemEntity>[];

  NsiDrawSource source(MockClient client) =>
      NsiDrawSource(clientFactory: () => client, platform: 'iOS');

  /// Streams [chunks] with [headers]; [contentLength] may lie.
  MockClient streaming(
    List<List<int>> chunks, {
    int status = 200,
    Map<String, String> headers = const <String, String>{
      'content-type': 'application/zip',
    },
    int? contentLength,
    Object? errorAfter,
  }) => MockClient.streaming((http.BaseRequest r, _) async {
    Stream<List<int>> s() async* {
      yield* Stream<List<int>>.fromIterable(chunks);
      if (errorAfter != null) throw errorAfter;
    }

    return http.StreamedResponse(
      s(),
      status,
      headers: headers,
      contentLength:
          contentLength ?? chunks.fold<int>(0, (int a, List<int> c) => a + c.length),
    );
  });

  group('downloads page', () {
    test('sends an honest User-Agent and parses the listed months', () async {
      String? ua;
      final MockClient c = MockClient((http.Request r) async {
        ua = r.headers['User-Agent'];
        return http.Response(
          File('test/fixtures/downloads_page.html').readAsStringSync(),
          200,
          headers: <String, String>{'content-type': 'text/html'},
        );
      });
      final NsiIndex i = await source(c).fetchIndex();
      expect(ua, startsWith('Bondbell/'));
      expect(ua, contains('iOS'));
      expect(ua, contains('bondbell.froggyeye.com'));
      expect(i.latest!.id, '2026-11');
      expect(i.unclaimed, isNotNull);
    });

    test('a server error is reported in words with the status', () async {
      final MockClient c = MockClient((_) async => http.Response('', 503));
      await expectLater(
        source(c).fetchIndex(),
        throwsA(isA<SourceException>()
            .having((SourceException e) => e.message, 'message', contains('503'))
            .having((SourceException e) => e.layoutChanged, 'layoutChanged', isFalse)),
      );
    });

    test('a redesigned page (no zip links) offers NS&I\'s page, not a retry loop',
        () async {
      final MockClient c = MockClient(
        (_) async => http.Response('<html><a href="/a.pdf">May 2026</a></html>', 200),
      );
      await expectLater(
        source(c).fetchIndex(),
        throwsA(isA<SourceException>().having(
            (SourceException e) => e.layoutChanged, 'layoutChanged', isTrue)),
      );
    });

    test('a bot-check page in place of the downloads page reads as changed',
        () async {
      final MockClient c = MockClient((_) async => http.Response(
            '<html><body>Request unsuccessful. Incapsula incident ID</body></html>',
            200,
          ));
      await expectLater(
        source(c).fetchIndex(),
        throwsA(isA<SourceException>().having(
            (SourceException e) => e.layoutChanged, 'layoutChanged', isTrue)),
      );
    });

    test('no connection is a plain-English error', () async {
      final MockClient c =
          MockClient((_) async => throw const SocketException('offline'));
      await expectLater(
        source(c).fetchIndex(),
        throwsA(isA<SourceException>().having(
            (SourceException e) => e.message, 'message', contains('internet'))),
      );
    });
  });

  group('size', () {
    test('reads Content-Length from a HEAD, null when unknown or refused',
        () async {
      expect(
        await source(MockClient((http.Request r) async {
          expect(r.method, 'HEAD');
          return http.Response('', 200, headers: <String, String>{
            'content-length': '33606244',
          });
        })).sizeOf(list),
        33606244,
      );
      expect(
        await source(MockClient((_) async => http.Response('', 403))).sizeOf(list),
        isNull,
      );
      expect(
        await source(MockClient((_) async => throw const SocketException('x')))
            .sizeOf(list),
        isNull,
      );
    });
  });

  group('download', () {
    test('a good ZIP lands in the scratch folder byte for byte', () async {
      final File f = await source(streaming(<List<int>>[
        zip.sublist(0, 10),
        zip.sublist(10),
      ])).download(list);
      expect(f.readAsBytesSync(), zip);
      expect(f.parent.path, scratch.path);
    });

    test('progress reports bytes received against the total', () async {
      final List<(int, int?)> seen = <(int, int?)>[];
      await source(streaming(<List<int>>[zip.sublist(0, 10), zip.sublist(10)]))
          .download(list, onProgress: (int r, int? t) => seen.add((r, t)));
      expect(seen.last, (zip.length, zip.length));
      expect(seen.first.$1, 10);
    });

    test('an HTML page instead of the ZIP (bot protection) is refused, nothing '
        'kept', () async {
      await expectLater(
        source(streaming(
          <List<int>>[utf8.encode('<html>checking your browser</html>')],
          headers: const <String, String>{'content-type': 'text/html; charset=utf-8'},
        )).download(list),
        throwsA(isA<SourceException>().having(
            (SourceException e) => e.layoutChanged, 'layoutChanged', isTrue)),
      );
      expect(leftovers(), isEmpty);
    });

    test('HTML served with a binary content type is caught by the ZIP magic',
        () async {
      await expectLater(
        source(streaming(
          <List<int>>[utf8.encode('<!DOCTYPE html><html></html>')],
          headers: const <String, String>{'content-type': 'application/octet-stream'},
        )).download(list),
        throwsA(isA<SourceException>().having(
            (SourceException e) => e.message, 'message', contains('ZIP'))),
      );
      expect(leftovers(), isEmpty);
    });

    test('a non-200 answer keeps nothing', () async {
      await expectLater(
        source(streaming(<List<int>>[<int>[]], status: 404)).download(list),
        throwsA(isA<SourceException>().having(
            (SourceException e) => e.message, 'message', contains('404'))),
      );
      expect(leftovers(), isEmpty);
    });

    test('a connection that ends early (fewer bytes than promised) is a '
        'failure and the partial file is deleted', () async {
      await expectLater(
        source(streaming(
          <List<int>>[zip.sublist(0, zip.length ~/ 2)],
          contentLength: zip.length,
        )).download(list),
        throwsA(isA<SourceException>().having(
            (SourceException e) => e.message, 'message', contains('part-way'))),
      );
      expect(leftovers(), isEmpty);
    });

    test('a network error mid-stream deletes the partial file', () async {
      await expectLater(
        source(streaming(
          <List<int>>[zip.sublist(0, 100)],
          contentLength: zip.length,
          errorAfter: const SocketException('reset'),
        )).download(list),
        throwsA(isA<SourceException>()),
      );
      expect(leftovers(), isEmpty);
    });

    test('cancel mid-download stops, deletes the partial file and says '
        'cancelled (not failed)', () async {
      final DownloadCancel cancel = DownloadCancel();
      final StreamController<List<int>> body = StreamController<List<int>>();
      final MockClient c = MockClient.streaming((_, _) async =>
          http.StreamedResponse(body.stream, 200,
              headers: const <String, String>{'content-type': 'application/zip'},
              contentLength: zip.length));
      final Future<File> f = source(c).download(list, cancel: cancel);
      body.add(zip.sublist(0, 100));
      await Future<void>.delayed(Duration.zero);
      expect(leftovers(), hasLength(1), reason: 'the partial file exists');
      cancel.cancel();
      body.add(zip.sublist(100, 200));
      await expectLater(f, throwsA(isA<DownloadCancelledException>()));
      await body.close();
      expect(leftovers(), isEmpty);
    });
  });

  test('clearScratch removes a list left by a check the OS killed', () async {
    scratch.createSync(recursive: true);
    File('${scratch.path}/2026-11-123.zip').writeAsBytesSync(zip);
    await clearScratch();
    expect(leftovers(), isEmpty);
  });
}
