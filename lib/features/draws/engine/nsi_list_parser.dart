import 'range_matcher.dart';

/// Which of NS&I's two published lists a file is.
enum ListKind { winners, unclaimed }

/// A number in NS&I's list that is one of the user's bonds.
class ScanHit {
  const ScanHit({
    required this.bond,
    required this.prize,
    required this.holderIds,
    this.anonymous = false,
  });

  final String bond;

  /// Prize in whole pounds.
  final int prize;
  final List<String> holderIds;

  /// Unclaimed list only: the "LGS ANONYMOUS" section, prizes won by
  /// bondholders whose names NS&I does not know.
  final bool anonymous;
}

/// What a scan found, plus enough bookkeeping to tell whether the file was
/// read the way NS&I laid it out.
class ScanSummary {
  ScanSummary({
    required this.kind,
    required this.drawLabel,
    required this.numbersScanned,
    required this.expectedTotal,
    required this.countsByPrize,
    required this.expectedByPrize,
    required this.hits,
    required this.unassigned,
    required this.fileName,
  });

  final ListKind kind;

  /// "November 2026" from the winners file heading; null for unclaimed.
  final String? drawLabel;
  final int numbersScanned;

  /// Winners: "a total of 6,575,175 prizes" from the notes. Unclaimed: the
  /// sum of the "TOTAL BSN" lines.
  final int? expectedTotal;
  final Map<int, int> countsByPrize;
  final Map<int, int> expectedByPrize;
  final List<ScanHit> hits;

  /// Bond numbers that appeared before any prize heading (format drift).
  final int unassigned;
  final String fileName;

  /// True when every number was read under a prize heading and the counts
  /// agree with the totals NS&I prints in the same file.
  bool get integrityOk {
    if (numbersScanned == 0 || unassigned > 0) return false;
    if (expectedTotal != null && expectedTotal != numbersScanned) return false;
    for (final MapEntry<int, int> e in expectedByPrize.entries) {
      if ((countsByPrize[e.key] ?? 0) != e.value) return false;
    }
    return expectedTotal != null || expectedByPrize.isNotEmpty;
  }
}

/// Line-by-line reader for NS&I's fixed-width text lists.
///
/// Winners file (`PWREP_ddmmyyyy.txt`): a heading with the draw month, a
/// table of prize tiers ("IX.  2,381,417 prizes of £100"), then
/// "Part I - Number(s) drawn for Prize(s) of £1,000,000" sections of
/// 11-character right-aligned numbers, 8 per line, with "(contd.)" headings
/// and "Page No." lines repeated through it.
///
/// Unclaimed file (`UAREP_ddmmyyyy.txt`): "LGS UNCLAIMED £25" headings
/// (repeated per page) over numbers, each value ending
/// "END OF £25, TOTAL BSN = 1808470", then "LGS ANONYMOUS" sections.
///
/// The text is Latin-1 (£ is byte 0xA3).
class NsiListParser {
  NsiListParser(this.kind, this.matcher);

  final ListKind kind;
  final RangeMatcher matcher;

  String? _drawLabel;
  int? _currentPrize;
  bool _anonymousSection = false;
  int _scanned = 0;
  int _unassigned = 0;
  int? _noteTotal;
  int _bsnTotal = 0;
  bool _sawBsn = false;
  final Map<int, int> _counts = <int, int>{};
  final Map<int, int> _expected = <int, int>{};
  final List<ScanHit> _hits = <ScanHit>[];

  static final RegExp _drawRe =
      RegExp(r'PREMIUM BOND PRIZE DRAW\s+([A-Za-z]+\s+\d{4})');
  static final RegExp _noteRe =
      RegExp(r'total of ([\d,]+) prizes', caseSensitive: false);
  static final RegExp _tierRe = RegExp(
    r'([IVXL]+)\.\s+([\d,]+)\s+prize(?:s|\(s\))\s+of\s+£([\d,]+)',
  );
  static final RegExp _partRe = RegExp(r'^\s*Part\s+[IVXL]+\s*-.*?£([\d,]+)');
  static final RegExp _lgsRe =
      RegExp(r'LGS\s+(UNCLAIMED|ANONYMOUS)\s+£([\d,]+)');
  static final RegExp _endRe =
      RegExp(r'END OF £([\d,]+),\s*TOTAL BSN\s*=\s*([\d,]+)');

  static int _int(String s) => int.parse(s.replaceAll(',', ''));

  void addLine(String line) {
    if (line.isEmpty) return;
    // Data lines are all bond tokens; anything else is text.
    final List<String> parts = line.split(' ');
    int tokens = 0;
    bool allBonds = true;
    for (final String p in parts) {
      if (p.isEmpty) continue;
      tokens++;
      if (!isBondToken(p)) {
        allBonds = false;
        break;
      }
    }
    if (tokens == 0) return;
    if (allBonds) {
      for (final String p in parts) {
        if (p.isEmpty) continue;
        _scanned++;
        final int? prize = _currentPrize;
        if (prize == null) {
          _unassigned++;
          continue;
        }
        _counts[prize] = (_counts[prize] ?? 0) + 1;
        final List<String>? owners = matcher.match(p);
        if (owners != null) {
          _hits.add(ScanHit(
            bond: p,
            prize: prize,
            holderIds: owners,
            anonymous: _anonymousSection,
          ));
        }
      }
      return;
    }
    _textLine(line);
  }

  void _textLine(String line) {
    if (!line.contains('£') && !line.contains('PRIZE DRAW')) return;
    if (kind == ListKind.winners) {
      final RegExpMatch? d = _drawRe.firstMatch(line);
      if (d != null) _drawLabel ??= d.group(1)!.trim();
      final RegExpMatch? n = _noteRe.firstMatch(line);
      if (n != null) _noteTotal ??= _int(n.group(1)!);
      if (line.trimLeft().startsWith('|')) {
        for (final RegExpMatch t in _tierRe.allMatches(line)) {
          _expected[_int(t.group(3)!)] = _int(t.group(2)!);
        }
        return;
      }
      final RegExpMatch? p = _partRe.firstMatch(line);
      if (p != null) _currentPrize = _int(p.group(1)!);
      return;
    }
    final RegExpMatch? l = _lgsRe.firstMatch(line);
    if (l != null) {
      _anonymousSection = l.group(1) == 'ANONYMOUS';
      _currentPrize = _int(l.group(2)!);
      return;
    }
    final RegExpMatch? e = _endRe.firstMatch(line);
    if (e != null) {
      _sawBsn = true;
      _bsnTotal += _int(e.group(2)!);
      _currentPrize = null;
    }
  }

  ScanSummary finish(String fileName) => ScanSummary(
    kind: kind,
    drawLabel: _drawLabel,
    numbersScanned: _scanned,
    expectedTotal: kind == ListKind.winners
        ? _noteTotal
        : (_sawBsn ? _bsnTotal : null),
    countsByPrize: Map<int, int>.unmodifiable(_counts),
    // The unclaimed file splits one value across UNCLAIMED and ANONYMOUS,
    // so only the grand total is checked there.
    expectedByPrize: kind == ListKind.winners
        ? Map<int, int>.unmodifiable(_expected)
        : const <int, int>{},
    hits: List<ScanHit>.unmodifiable(_hits),
    unassigned: _unassigned,
    fileName: fileName,
  );
}
