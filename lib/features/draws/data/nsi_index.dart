import 'package:flutter/foundation.dart';

/// A downloadable list on NS&I's site (or the bundled sample).
@immutable
class RemoteList {
  const RemoteList({required this.id, required this.label, required this.url});

  /// `2026-11` for a draw month, `unclaimed` for the unclaimed list.
  final String id;

  /// What NS&I calls it: "November 2026", or the unclaimed link's text.
  final String label;
  final Uri url;

  int? get year => id.length == 7 ? int.tryParse(id.substring(0, 4)) : null;
  int? get month => id.length == 7 ? int.tryParse(id.substring(5)) : null;
}

/// What the downloads page currently offers.
@immutable
class NsiIndex {
  const NsiIndex({required this.draws, required this.unclaimed});

  /// Newest first.
  final List<RemoteList> draws;
  final RemoteList? unclaimed;

  RemoteList? get latest => draws.isEmpty ? null : draws.first;
}

/// Reads NS&I's "winning bonds downloads" page.
///
/// Measured layout (14 Nov 2026): a `<ul>` of `<a href="/files/asset/zip/
/// premium-bonds-winning-bond-numbers-MM-YYYY.zip">Month YYYY</a>` links for
/// the last six draws, one link to
/// `/files/asset/zip/unclaimed-prizes-june-1957-to-march-2025.zip`, and an
/// older link left inside an HTML comment (which must be ignored).
///
/// The parse keys on what a link points at (a .zip) and what it says, not
/// on CSS classes, so cosmetic redesigns don't break it.
abstract final class NsiIndexParser {
  static const List<String> _months = <String>[
    'january', 'february', 'march', 'april', 'may', 'june', 'july',
    'august', 'september', 'october', 'november', 'december',
  ];

  static NsiIndex parse(String html, Uri base) {
    final String clean = html.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    final RegExp anchor = RegExp(
      r'''<a\b[^>]*?href\s*=\s*["']([^"']+?\.zip)(?:\?[^"']*)?["'][^>]*>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    );
    final Map<String, RemoteList> draws = <String, RemoteList>{};
    RemoteList? unclaimed;
    for (final RegExpMatch m in anchor.allMatches(clean)) {
      final String href = m.group(1)!.trim();
      final String text = _text(m.group(2)!);
      final Uri url = base.resolve(href);
      if (url.scheme != 'https' || !isNsiHost(url.host)) continue;
      final String lower = '${href.toLowerCase()} ${text.toLowerCase()}';
      if (lower.contains('unclaimed')) {
        unclaimed ??= RemoteList(
          id: 'unclaimed',
          label: text.isEmpty ? 'Unclaimed prizes' : text,
          url: url,
        );
        continue;
      }
      final String? id = _monthId(text) ?? _monthIdFromHref(href);
      if (id == null) continue;
      draws.putIfAbsent(
        id,
        () => RemoteList(id: id, label: _label(id), url: url),
      );
    }
    final List<RemoteList> sorted = draws.values.toList()
      ..sort((RemoteList a, RemoteList b) => b.id.compareTo(a.id));
    return NsiIndex(draws: sorted, unclaimed: unclaimed);
  }

  /// nsandi.com or a subdomain of it; not a look-alike such as
  /// `evilnsandi.com`.
  static bool isNsiHost(String host) {
    final String h = host.toLowerCase();
    return h == 'nsandi.com' || h.endsWith('.nsandi.com');
  }

  static String _text(String inner) => inner
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&ndash;', '–')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String? _monthId(String text) {
    final RegExpMatch? m =
        RegExp(r'\b([A-Za-z]+)\s+(\d{4})\b').firstMatch(text);
    if (m == null) return null;
    final int idx = _months.indexOf(m.group(1)!.toLowerCase());
    if (idx < 0) return null;
    return '${m.group(2)}-${(idx + 1).toString().padLeft(2, '0')}';
  }

  static String? _monthIdFromHref(String href) {
    final RegExpMatch? m =
        RegExp(r'winning[^/]*?(\d{2})-(\d{4})\.zip$').firstMatch(href);
    if (m == null) return null;
    final int month = int.parse(m.group(1)!);
    if (month < 1 || month > 12) return null;
    return '${m.group(2)}-${m.group(1)}';
  }

  /// `2026-11` → `November 2026`.
  static String _label(String id) {
    final int month = int.parse(id.substring(5));
    final String name = _months[month - 1];
    return '${name[0].toUpperCase()}${name.substring(1)} ${id.substring(0, 4)}';
  }

  static String labelFor(String id) =>
      id.length == 7 ? _label(id) : id;
}
