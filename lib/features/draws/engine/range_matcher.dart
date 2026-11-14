/// One range of the user's bonds, flattened to primitives so it can cross
/// into the scanning isolate.
class ScanTarget {
  const ScanTarget({
    required this.series,
    required this.lo,
    required this.hi,
    required this.holderId,
  });

  final String series;
  final int lo;
  final int hi;
  final String holderId;
}

/// Answers "is this bond number one of the user's?" for millions of tokens.
///
/// Keyed by series (`688ZY`), then a linear scan of that series' ranges —
/// a household has a handful of ranges, so this is effectively O(1) per
/// token. A quick reject on the two letters avoids building a substring for
/// the ~all tokens that cannot match.
class RangeMatcher {
  RangeMatcher(List<ScanTarget> targets) {
    for (final ScanTarget t in targets) {
      (_bySeries[t.series] ??= <ScanTarget>[]).add(t);
      final int n = t.series.length;
      _letterPairs.add(
        (t.series.codeUnitAt(n - 2) << 8) | t.series.codeUnitAt(n - 1),
      );
    }
  }

  final Map<String, List<ScanTarget>> _bySeries = <String, List<ScanTarget>>{};
  final Set<int> _letterPairs = <int>{};

  bool get isEmpty => _bySeries.isEmpty;

  /// Holder ids owning [token] (a validated bond token), or null.
  /// [token] is `prefix + 2 letters + 6 digits` with no padding.
  List<String>? match(String token) {
    final int n = token.length;
    final int pair =
        (token.codeUnitAt(n - 8) << 8) | token.codeUnitAt(n - 7);
    if (!_letterPairs.contains(pair)) return null;
    final List<ScanTarget>? list = _bySeries[token.substring(0, n - 6)];
    if (list == null) return null;
    int serial = 0;
    for (int i = n - 6; i < n; i++) {
      serial = serial * 10 + (token.codeUnitAt(i) - 48);
    }
    List<String>? out;
    for (final ScanTarget t in list) {
      if (serial >= t.lo && serial <= t.hi) {
        out ??= <String>[];
        if (!out.contains(t.holderId)) out.add(t.holderId);
      }
    }
    return out;
  }
}

/// Fast structural check of a whitespace-free token from NS&I's files:
/// 0-3 digits (no leading zero), two capital letters, six digits.
bool isBondToken(String t) {
  final int n = t.length;
  if (n < 8 || n > 11) return false;
  for (int i = n - 6; i < n; i++) {
    final int c = t.codeUnitAt(i);
    if (c < 48 || c > 57) return false;
  }
  for (int i = n - 8; i < n - 6; i++) {
    final int c = t.codeUnitAt(i);
    if (c < 65 || c > 90) return false;
  }
  for (int i = 0; i < n - 8; i++) {
    final int c = t.codeUnitAt(i);
    if (c < 48 || c > 57) return false;
    if (i == 0 && c == 48) return false;
  }
  return true;
}
