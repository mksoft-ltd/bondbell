import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../../purchases/presentation/purchase_controller.dart';
import '../../settings/presentation/app_settings.dart';
import '../domain/bond_number.dart';
import '../domain/holder.dart';

/// The sample holders: one with a modern statement range and an old
/// certificate, and a relative with old paper certificates. The bundled
/// sample lists contain wins for both (see tool/generate_sample_data.py).
List<Holder> sampleHolders() => <Holder>[
  Holder(
    id: 'sample-holder',
    name: 'Sample holder',
    ranges: <BondRange>[
      BondRange(
        id: 'sample-r1',
        start: BondNumber.parse('312KM100000'),
        end: BondNumber.parse('312KM119999'),
      ),
      BondRange(
        id: 'sample-r2',
        start: BondNumber.parse('47DW185520'),
        end: BondNumber.parse('47DW185569'),
      ),
    ],
  ),
  // A second holder, so the Pro "more than one holder" feature has
  // something to show in sample mode: a relative's old paper certificates.
  Holder(
    id: 'sample-grandad',
    name: 'Grandad (sample)',
    ranges: <BondRange>[
      BondRange(
        id: 'sample-r3',
        start: BondNumber.parse('9JN000100'),
        end: BondNumber.parse('9JN000149'),
      ),
    ],
  ),
];

/// Parses stored holders one holder and one range at a time, skipping only
/// what is unreadable. `lossy` is true when anything was skipped (or the
/// value wasn't a list at all).
({List<Holder> holders, bool lossy}) parseHoldersTolerant(Object? raw) {
  if (raw is! List) return (holders: const <Holder>[], lossy: true);
  bool lossy = false;
  final List<Holder> out = <Holder>[];
  for (final Object? h in raw) {
    try {
      final Map<String, Object?> m = h! as Map<String, Object?>;
      final List<BondRange> ranges = <BondRange>[];
      for (final Object? r
          in (m['ranges'] as List<Object?>?) ?? const <Object?>[]) {
        try {
          ranges.add(BondRange.fromJson(r! as Map<String, Object?>));
        } on Object {
          lossy = true;
        }
      }
      out.add(
        Holder(
          id: m['id']! as String,
          name: m['name']! as String,
          ranges: ranges,
        ),
      );
    } on Object {
      lossy = true;
    }
  }
  return (holders: out, lossy: lossy);
}

String newId() {
  final Random r = Random();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${r.nextInt(1 << 30).toRadixString(36)}';
}

/// The holders for the current data scope (real or sample).
class HoldersController extends Notifier<List<Holder>> {
  LocalStore get _store => ref.read(localStoreProvider);
  late String _key;

  @override
  List<Holder> build() {
    final bool sample = ref.watch(sampleModeProvider);
    _key = '${ref.watch(dataScopeProvider)}holders';
    final String? text = _store.getString(_key);
    if (text == null) return sample ? sampleHolders() : const <Holder>[];
    final ({List<Holder> holders, bool lossy}) parsed = parseHoldersTolerant(
      _store.readJson(_key),
    );
    if (parsed.lossy) {
      // Something didn't parse. Keep the original text so the next save
      // (which rewrites the key from what did parse) can never be the end
      // of the user's bonds (code review m5).
      _store.setString('$_key.bak', text);
    }
    return parsed.holders;
  }

  Future<void> _pending = Future<void>.value();

  /// Applies [change] to the current holders, writes the result, and only
  /// then shows it. Mutations run one after another, each from the state
  /// the previous one left. A failed write throws [SaveFailedException] and
  /// changes nothing (code review N1).
  Future<void> _mutate(List<Holder> Function(List<Holder> state) change) {
    final Completer<void> done = Completer<void>();
    _pending = _pending.then((_) async {
      try {
        final List<Holder> next = change(state);
        final bool ok = await _store.writeJson(
          _key,
          next.map((Holder h) => h.toJson()).toList(),
        );
        if (!ok) throw const SaveFailedException();
        if (ref.mounted) state = next;
        done.complete();
      } on Object catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Throws [FreeTierLimitException] past [FreeTier.maxHolders] without
  /// Pro. The screens explain this first; the check here makes the gate
  /// hold whichever path calls it.
  Future<Holder> addHolder(String name) async {
    if (!ref.read(proFeaturesProvider) && state.length >= FreeTier.maxHolders) {
      throw const FreeTierLimitException();
    }
    final Holder h = Holder(id: newId(), name: name.trim());
    await _mutate((List<Holder> state) => <Holder>[...state, h]);
    return h;
  }

  Future<void> rename(String id, String name) => _mutate(
    (List<Holder> state) => <Holder>[
      for (final Holder h in state) h.id == id ? h.copyWith(name: name) : h,
    ],
  );

  Future<void> deleteHolder(String id) => _mutate(
    (List<Holder> state) => state.where((Holder h) => h.id != id).toList(),
  );

  Future<void> addRange(String holderId, BondNumber start, BondNumber end) =>
      _mutate(
        (List<Holder> state) => <Holder>[
          for (final Holder h in state)
            h.id == holderId
                ? h.copyWith(
                    ranges: <BondRange>[
                      ...h.ranges,
                      BondRange(id: newId(), start: start, end: end),
                    ],
                  )
                : h,
        ],
      );

  Future<void> updateRange(
    String holderId,
    String rangeId,
    BondNumber start,
    BondNumber end,
  ) => _mutate(
    (List<Holder> state) => <Holder>[
      for (final Holder h in state)
        h.id == holderId
            ? h.copyWith(
                ranges: <BondRange>[
                  for (final BondRange r in h.ranges)
                    r.id == rangeId
                        ? BondRange(id: r.id, start: start, end: end)
                        : r,
                ],
              )
            : h,
    ],
  );

  Future<void> deleteRange(String holderId, String rangeId) => _mutate(
    (List<Holder> state) => <Holder>[
      for (final Holder h in state)
        h.id == holderId
            ? h.copyWith(
                ranges: h.ranges
                    .where((BondRange r) => r.id != rangeId)
                    .toList(),
              )
            : h,
    ],
  );

  Future<void> replaceAll(List<Holder> holders) =>
      _mutate((List<Holder> _) => holders);
}

class FreeTierLimitException implements Exception {
  const FreeTierLimitException();
  @override
  String toString() => 'More than one holder needs Bondbell Pro.';
}

final NotifierProvider<HoldersController, List<Holder>> holdersProvider =
    NotifierProvider<HoldersController, List<Holder>>(HoldersController.new);

/// Which of [holders]' existing ranges overlap [start]–[end] (same series,
/// overlapping serials), so the UI can warn about double entry.
List<String> overlappingRanges(
  List<Holder> holders,
  BondNumber start,
  BondNumber end, {
  String? ignoreRangeId,
}) {
  final List<String> out = <String>[];
  for (final Holder h in holders) {
    for (final BondRange r in h.ranges) {
      if (r.id == ignoreRangeId || r.series != start.series) continue;
      if (start.serial <= r.end.serial && end.serial >= r.start.serial) {
        out.add('${r.label} (${h.name})');
      }
    }
  }
  return out;
}
