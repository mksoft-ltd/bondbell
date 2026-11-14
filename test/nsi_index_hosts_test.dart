import 'package:bondbell/features/draws/data/nsi_index.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which links on the downloads page Bondbell will follow. The app only
/// ever downloads from nsandi.com over https.
void main() {
  final Uri page = Uri.parse(
    'https://www.nsandi.com/get-to-know-us/winning-bonds-downloads',
  );

  NsiIndex parse(String href, [String text = 'November 2026']) =>
      NsiIndexParser.parse('<a href="$href">$text</a>', page);

  test('relative links resolve against nsandi.com', () {
    final NsiIndex i = parse('/files/asset/zip/x-11-2026.zip');
    expect(i.latest!.url.host, 'www.nsandi.com');
  });

  test('nsandi.com and its subdomains are accepted', () {
    expect(parse('https://nsandi.com/a-11-2026.zip').draws, hasLength(1));
    expect(parse('https://files.nsandi.com/a-11-2026.zip').draws, hasLength(1));
  });

  test('a look-alike host ending in "nsandi.com" is refused', () {
    // Regression: the check was host.endsWith('nsandi.com'), which let
    // evilnsandi.com through.
    expect(parse('https://evilnsandi.com/a-11-2026.zip').draws, isEmpty);
    expect(parse('https://www.notnsandi.com/a-11-2026.zip').draws, isEmpty);
    expect(parse('https://nsandi.com.example.org/a-11-2026.zip').draws, isEmpty);
  });

  test('plain http is refused even on nsandi.com', () {
    expect(parse('http://www.nsandi.com/a-11-2026.zip').draws, isEmpty);
  });

  test('a link with a query string still counts as a zip', () {
    expect(parse('/files/a-11-2026.zip?v=3').latest!.id, '2026-11');
  });

  test('month comes from the link text before the URL', () {
    // NS&I's URLs use MM-YYYY; the text wins when both are present.
    expect(parse('/files/winning-10-2026.zip', 'November 2026').latest!.id,
        '2026-11');
    expect(parse('/files/winning-bond-numbers-10-2026.zip', 'Download').latest!.id,
        '2026-10');
  });

  test('the same month listed twice is kept once', () {
    final NsiIndex i = NsiIndexParser.parse(
      '<a href="/a-11-2026.zip">November 2026</a>'
      '<a href="/b-11-2026.zip">November 2026</a>',
      page,
    );
    expect(i.draws, hasLength(1));
    expect(i.draws.single.url.path, '/a-11-2026.zip');
  });
}
