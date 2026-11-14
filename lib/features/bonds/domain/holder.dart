import 'package:flutter/foundation.dart';

import 'bond_number.dart';

/// An inclusive run of consecutive bonds within one series, e.g.
/// `688ZY673000 – 688ZY673999` (1,000 bonds, £1,000). A single bond is a
/// range whose start and end are the same.
@immutable
class BondRange {
  const BondRange({required this.id, required this.start, required this.end});

  final String id;
  final BondNumber start;
  final BondNumber end;

  String get series => start.series;
  int get count => end.serial - start.serial + 1;
  bool get isSingle => count == 1;

  bool contains(BondNumber n) =>
      n.series == start.series &&
      n.serial >= start.serial &&
      n.serial <= end.serial;

  String get label => isSingle ? '$start' : '$start – $end';

  /// Validates two typed values into a range, or explains what is wrong.
  /// An empty [endInput] means a single bond.
  static RangeResult validate(String startInput, String endInput) {
    final BondNumberResult s = BondNumber.tryParse(startInput);
    if (s.error != null) return RangeResult.error('First number: ${s.error}');
    if (endInput.trim().isEmpty) {
      return RangeResult.ok(s.value!, s.value!);
    }
    final BondNumberResult e = BondNumber.tryParse(endInput);
    if (e.error != null) return RangeResult.error('Last number: ${e.error}');
    final BondNumber a = s.value!;
    final BondNumber b = e.value!;
    if (a.series != b.series) {
      return RangeResult.error(
        'Both numbers in a range must start the same way (${a.series}… and '
        '${b.series}… differ). If your statement lists them separately, add '
        'them as two ranges.',
      );
    }
    if (b.serial < a.serial) {
      return const RangeResult.error(
        'The last number is lower than the first. Swap them round.',
      );
    }
    return RangeResult.ok(a, b);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'start': start.toString(),
    'end': end.toString(),
  };

  factory BondRange.fromJson(Map<String, Object?> j) => BondRange(
    id: j['id']! as String,
    start: BondNumber.parse(j['start']! as String),
    end: BondNumber.parse(j['end']! as String),
  );

  @override
  bool operator ==(Object other) =>
      other is BondRange &&
      other.id == id &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, start, end);
}

@immutable
class RangeResult {
  const RangeResult.ok(BondNumber this.start, BondNumber this.end)
    : error = null;
  const RangeResult.error(String this.error) : start = null, end = null;
  final BondNumber? start;
  final BondNumber? end;
  final String? error;
}

/// A person whose bonds are tracked: the user, a partner, a child, or a
/// relative whose old paper certificates turned up in a drawer.
@immutable
class Holder {
  const Holder({required this.id, required this.name, this.ranges = const []});

  /// NS&I's per-person holding limit. Old paper bonds can push a total past
  /// it, so this is a gentle warning, never a block.
  static const int holdingLimit = 50000;

  final String id;
  final String name;
  final List<BondRange> ranges;

  int get bondCount => ranges.fold(0, (int sum, BondRange r) => sum + r.count);

  /// £1 per bond.
  int get totalValue => bondCount;

  Holder copyWith({String? name, List<BondRange>? ranges}) =>
      Holder(id: id, name: name ?? this.name, ranges: ranges ?? this.ranges);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'ranges': ranges.map((BondRange r) => r.toJson()).toList(),
  };

  factory Holder.fromJson(Map<String, Object?> j) => Holder(
    id: j['id']! as String,
    name: j['name']! as String,
    ranges: (j['ranges']! as List<Object?>)
        .map((Object? e) => BondRange.fromJson(e! as Map<String, Object?>))
        .toList(),
  );

  @override
  bool operator ==(Object other) =>
      other is Holder &&
      other.id == id &&
      other.name == name &&
      listEquals(other.ranges, ranges);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(ranges));
}

/// Distinct bonds across [holders]: the same number saved twice (under two
/// holders, or twice under one) counts once. Overlapping ranges in a series
/// are merged before counting. Used for every household total (code review
/// m6); a holder's own total still uses [Holder.bondCount].
int uniqueBondCount(Iterable<Holder> holders) {
  final Map<String, List<(int, int)>> bySeries = <String, List<(int, int)>>{};
  for (final Holder h in holders) {
    for (final BondRange r in h.ranges) {
      (bySeries[r.series] ??= <(int, int)>[]).add((r.start.serial, r.end.serial));
    }
  }
  int total = 0;
  for (final List<(int, int)> spans in bySeries.values) {
    spans.sort(((int, int) a, (int, int) b) => a.$1.compareTo(b.$1));
    int? lo;
    int? hi;
    for (final (int a, int b) in spans) {
      if (hi != null && a <= hi + 1) {
        if (b > hi) hi = b;
      } else {
        if (lo != null) total += hi! - lo + 1;
        lo = a;
        hi = b;
      }
    }
    if (lo != null) total += hi! - lo + 1;
  }
  return total;
}
