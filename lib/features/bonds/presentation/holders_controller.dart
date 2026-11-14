import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../../settings/presentation/app_settings.dart';
import '../domain/bond_number.dart';
import '../domain/holder.dart';

/// The sample holder: one modern statement range and an old certificate.
/// The bundled sample lists contain wins for both (see
/// tool/generate_sample_data.py).
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
];

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
    final Object? raw = _store.readJson(_key);
    if (raw is List) {
      try {
        return raw
            .map((Object? e) => Holder.fromJson(e! as Map<String, Object?>))
            .toList();
      } on Object {
        // Fall through to the default rather than crash on bad data.
      }
    }
    return sample ? sampleHolders() : const <Holder>[];
  }

  Future<void> _save(List<Holder> next) async {
    state = next;
    await _store.writeJson(_key, next.map((Holder h) => h.toJson()).toList());
  }

  Future<Holder> addHolder(String name) async {
    final Holder h = Holder(id: newId(), name: name.trim());
    await _save(<Holder>[...state, h]);
    return h;
  }

  Future<void> rename(String id, String name) => _save(<Holder>[
    for (final Holder h in state) h.id == id ? h.copyWith(name: name) : h,
  ]);

  Future<void> deleteHolder(String id) =>
      _save(state.where((Holder h) => h.id != id).toList());

  Future<void> addRange(String holderId, BondNumber start, BondNumber end) =>
      _save(<Holder>[
        for (final Holder h in state)
          h.id == holderId
              ? h.copyWith(ranges: <BondRange>[
                  ...h.ranges,
                  BondRange(id: newId(), start: start, end: end),
                ])
              : h,
      ]);

  Future<void> updateRange(
    String holderId,
    String rangeId,
    BondNumber start,
    BondNumber end,
  ) => _save(<Holder>[
    for (final Holder h in state)
      h.id == holderId
          ? h.copyWith(ranges: <BondRange>[
              for (final BondRange r in h.ranges)
                r.id == rangeId
                    ? BondRange(id: r.id, start: start, end: end)
                    : r,
            ])
          : h,
  ]);

  Future<void> deleteRange(String holderId, String rangeId) =>
      _save(<Holder>[
        for (final Holder h in state)
          h.id == holderId
              ? h.copyWith(
                  ranges: h.ranges
                      .where((BondRange r) => r.id != rangeId)
                      .toList(),
                )
              : h,
      ]);

  Future<void> replaceAll(List<Holder> holders) => _save(holders);
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
