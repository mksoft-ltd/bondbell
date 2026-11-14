import 'package:flutter/foundation.dart';

/// A single £1 bond unit serial number.
///
/// Format, measured against NS&I's own winners and unclaimed-prize files
/// (Nov 2026: 6,575,175 + 2,878,934 numbers, every one of them matched):
///
///   [optional 1-3 digit prefix, no leading zero] [2 letters] [6 digits]
///
/// e.g. `688ZY673096` (modern), `85LV272879`, `3JA171611`, and the oldest
/// certificates with no prefix at all, e.g. `DW369715`. The letters never
/// include I, O or U (none of the 9.4 million numbers inspected use them).
///
/// A "series" is everything before the six digits (`688ZY`); consecutive
/// bonds in one purchase share a series and differ only in the serial.
@immutable
class BondNumber implements Comparable<BondNumber> {
  const BondNumber._(this.series, this.serial);

  /// Prefix + letters, e.g. `688ZY` or `DW`.
  final String series;

  /// The trailing six digits, 0..999999.
  final int serial;

  static const String allowedLetters = 'ABCDEFGHJKLMNPQRSTVWXYZ';
  static const int maxSerial = 999999;

  /// Parses user input or a token from NS&I's file. Spaces and the odd
  /// separator are tolerated in user input (certificates print
  /// `12 AB 345678`). Returns a [BondNumberResult] explaining any problem in
  /// words a non-technical user can act on.
  static BondNumberResult tryParse(String input) {
    final String s = input.toUpperCase().replaceAll(RegExp(r'[\s.\-/]'), '');
    if (s.isEmpty) {
      return const BondNumberResult.error('Enter a bond number.');
    }
    if (RegExp(r'^\d+$').hasMatch(s)) {
      return const BondNumberResult.error(
        'That looks like a holder\'s number, not a bond number. Bond numbers '
        'have two letters in them, like 688ZY673096.',
      );
    }
    if (!RegExp(r'^[0-9A-Z]+$').hasMatch(s)) {
      return const BondNumberResult.error(
        'Use only letters and digits, like 688ZY673096.',
      );
    }
    final RegExpMatch? m = RegExp(r'^(\d*)([A-Z]+)(\d*)$').firstMatch(s);
    if (m == null) {
      return const BondNumberResult.error(
        'A bond number has digits, then two letters, then six digits, '
        'like 688ZY673096.',
      );
    }
    final String prefix = m.group(1)!;
    final String letters = m.group(2)!;
    final String digits = m.group(3)!;
    if (letters.length != 2) {
      return BondNumberResult.error(
        'A bond number has exactly two letters in the middle; '
        'this one has ${letters.length}.',
      );
    }
    for (final int c in letters.codeUnits) {
      final String ch = String.fromCharCode(c);
      if (!allowedLetters.contains(ch)) {
        final String hint = switch (ch) {
          'O' => ' Did you mean the number 0?',
          'I' => ' Did you mean the number 1?',
          _ => '',
        };
        return BondNumberResult.error(
          'Bond numbers never use the letters I, O or U.$hint',
        );
      }
    }
    if (digits.length != 6) {
      return BondNumberResult.error(
        'A bond number ends in exactly six digits after the letters; '
        'this one has ${digits.length}.',
      );
    }
    if (prefix.length > 3) {
      return const BondNumberResult.error(
        'There are at most three digits before the letters.',
      );
    }
    if (prefix.startsWith('0')) {
      return const BondNumberResult.error(
        'The digits before the letters never start with 0.',
      );
    }
    return BondNumberResult.ok(
      BondNumber._('$prefix$letters', int.parse(digits)),
    );
  }

  /// Parses a value known to be valid (stored data, tests). Throws otherwise.
  factory BondNumber.parse(String input) {
    final BondNumberResult r = tryParse(input);
    if (r.value == null) throw FormatException(r.error!, input);
    return r.value!;
  }

  /// Builds a number in [series] with [serial]; used to walk a range.
  factory BondNumber.inSeries(String series, int serial) {
    assert(serial >= 0 && serial <= maxSerial);
    return BondNumber._(series, serial);
  }

  /// Canonical form, e.g. `688ZY673096`.
  @override
  String toString() => '$series${serial.toString().padLeft(6, '0')}';

  @override
  bool operator ==(Object other) =>
      other is BondNumber && other.series == series && other.serial == serial;

  @override
  int get hashCode => Object.hash(series, serial);

  @override
  int compareTo(BondNumber other) {
    final int c = series.compareTo(other.series);
    return c != 0 ? c : serial.compareTo(other.serial);
  }
}

@immutable
class BondNumberResult {
  const BondNumberResult.ok(BondNumber this.value) : error = null;
  const BondNumberResult.error(String this.error) : value = null;
  final BondNumber? value;
  final String? error;
}
