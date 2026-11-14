import 'dart:io';

import 'package:bondbell/features/draws/data/nsi_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final Uri base =
      Uri.parse('https://www.nsandi.com/get-to-know-us/winning-bonds-downloads');

  test('finds six months newest first, ignores comments and other hosts', () {
    final NsiIndex i = NsiIndexParser.parse(
      File('test/fixtures/downloads_page.html').readAsStringSync(),
      base,
    );
    expect(i.draws.map((RemoteList l) => l.id), <String>[
      '2026-11', '2026-10', '2026-09', '2026-08', '2026-07', '2026-06',
    ]);
    expect(i.latest!.label, 'November 2026');
    expect(i.latest!.url.toString(),
        'https://www.nsandi.com/files/asset/zip/premium-bonds-winning-bond-numbers-11-2026.zip');
    expect(i.unclaimed!.url.path, endsWith('unclaimed-prizes-june-1957-to-march-2025.zip'));
    expect(i.unclaimed!.label, contains('June 1957 – March 2025'));
  });

  test('falls back to the URL when link text has no month', () {
    final NsiIndex i = NsiIndexParser.parse(
      '<a href="/files/asset/zip/premium-bonds-winning-bond-numbers-12-2026.zip">Download</a>',
      base,
    );
    expect(i.draws.single.id, '2026-12');
    expect(i.draws.single.label, 'December 2026');
  });

  test('a redesigned page with no zips yields an empty index', () {
    final NsiIndex i = NsiIndexParser.parse('<p>Coming soon</p>', base);
    expect(i.draws, isEmpty);
    expect(i.unclaimed, isNull);
  });
}
