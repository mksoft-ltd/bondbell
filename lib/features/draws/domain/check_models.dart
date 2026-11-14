import 'package:flutter/foundation.dart';

import '../../bonds/domain/holder.dart';

/// One of the user's bonds found in a list.
@immutable
class Win {
  const Win({
    required this.bond,
    required this.prize,
    required this.holderId,
    required this.holderName,
    this.anonymous = false,
  });

  final String bond;
  final int prize;
  final String holderId;
  final String holderName;
  final bool anonymous;

  Map<String, Object?> toJson() => <String, Object?>{
    'bond': bond,
    'prize': prize,
    'holderId': holderId,
    'holderName': holderName,
    if (anonymous) 'anonymous': true,
  };

  factory Win.fromJson(Map<String, Object?> j) => Win(
    bond: j['bond']! as String,
    prize: j['prize']! as int,
    holderId: j['holderId']! as String,
    holderName: j['holderName']! as String,
    anonymous: (j['anonymous'] as bool?) ?? false,
  );
}

/// The stored outcome of checking one list against the user's bonds.
@immutable
class CheckRecord {
  const CheckRecord({
    required this.listId,
    required this.label,
    required this.checkedAt,
    required this.fingerprint,
    required this.wins,
    required this.numbersScanned,
    required this.integrityOk,
    required this.bondsChecked,
    this.singleNumber,
  });

  /// `2026-11`, or `unclaimed`.
  final String listId;
  final String label;
  final DateTime checkedAt;

  /// [holdingsFingerprint] of the bonds at check time; a mismatch means the
  /// user's bonds have changed since and the result is stale.
  final String fingerprint;
  final List<Win> wins;
  final int numbersScanned;

  /// The numbers read agreed with the totals NS&I prints in the same file.
  final bool integrityOk;

  /// How many of the user's bonds were compared.
  final int bondsChecked;

  /// Unclaimed single-number search: the number that was looked up.
  final String? singleNumber;

  int get totalWon => wins.fold(0, (int s, Win w) => s + w.prize);
  bool get hasWins => wins.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'listId': listId,
    'label': label,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'fingerprint': fingerprint,
    'wins': wins.map((Win w) => w.toJson()).toList(),
    'numbersScanned': numbersScanned,
    'integrityOk': integrityOk,
    'bondsChecked': bondsChecked,
    if (singleNumber != null) 'singleNumber': singleNumber,
  };

  factory CheckRecord.fromJson(Map<String, Object?> j) => CheckRecord(
    listId: j['listId']! as String,
    label: j['label']! as String,
    checkedAt: DateTime.parse(j['checkedAt']! as String),
    fingerprint: j['fingerprint']! as String,
    wins: (j['wins']! as List<Object?>)
        .map((Object? e) => Win.fromJson(e! as Map<String, Object?>))
        .toList(),
    numbersScanned: j['numbersScanned']! as int,
    integrityOk: j['integrityOk']! as bool,
    bondsChecked: (j['bondsChecked'] as int?) ?? 0,
    singleNumber: j['singleNumber'] as String?,
  );
}

/// A stable digest of every holder's ranges, so a stored check can tell
/// whether it still covers the user's current bonds.
String holdingsFingerprint(List<Holder> holders) {
  final List<String> parts = <String>[
    for (final Holder h in holders)
      for (final BondRange r in h.ranges) '${h.id}:${r.start}-${r.end}',
  ]..sort();
  // FNV-1a, 64-bit-ish via two 32-bit lanes; collisions are harmless here
  // (the worst case is a "check again" prompt not shown).
  int a = 0x811c9dc5;
  int b = 0x01000193;
  for (final int c in parts.join('|').codeUnits) {
    a = ((a ^ c) * 0x01000193) & 0xFFFFFFFF;
    b = ((b ^ c) * 0x811c9dc5) & 0xFFFFFFFF;
  }
  return '${a.toRadixString(16)}${b.toRadixString(16)}';
}
