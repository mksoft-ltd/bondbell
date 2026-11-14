import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../../settings/presentation/app_settings.dart';
import '../domain/check_models.dart';

/// Stored check results for the current data scope, keyed by list id
/// (`2026-11`, `unclaimed`). Only Bondbell's own findings are stored —
/// never NS&I's lists.
class RecordsController extends Notifier<Map<String, CheckRecord>> {
  LocalStore get _store => ref.read(localStoreProvider);
  late String _key;

  @override
  Map<String, CheckRecord> build() {
    _key = '${ref.watch(dataScopeProvider)}records';
    final Object? raw = _store.readJson(_key);
    final Map<String, CheckRecord> out = <String, CheckRecord>{};
    if (raw is Map) {
      for (final MapEntry<Object?, Object?> e in raw.entries) {
        try {
          out[e.key! as String] = CheckRecord.fromJson(
            e.value! as Map<String, Object?>,
          );
        } on Object {
          // Skip a corrupt entry rather than lose the rest.
        }
      }
    }
    return out;
  }

  /// Writes first and shows second: a failed write throws
  /// [SaveFailedException] and changes nothing (code review N1).
  Future<void> put(CheckRecord r) =>
      _write(<String, CheckRecord>{...state, r.listId: r});

  Future<void> replaceAll(Map<String, CheckRecord> all) =>
      _write(Map<String, CheckRecord>.of(all));

  Future<void> _write(Map<String, CheckRecord> next) async {
    final bool ok = await _store.writeJson(_key, <String, Object?>{
      for (final MapEntry<String, CheckRecord> e in next.entries)
        e.key: e.value.toJson(),
    });
    if (!ok) throw const SaveFailedException();
    if (ref.mounted) state = next;
  }
}

final NotifierProvider<RecordsController, Map<String, CheckRecord>>
recordsProvider = NotifierProvider<RecordsController, Map<String, CheckRecord>>(
  RecordsController.new,
);

/// Draw records (not the unclaimed search), newest draw first.
final Provider<List<CheckRecord>> drawHistoryProvider =
    Provider<List<CheckRecord>>((Ref ref) {
      final List<CheckRecord> list =
          ref
              .watch(recordsProvider)
              .values
              .where((CheckRecord r) => !r.listId.startsWith('unclaimed'))
              .toList()
            ..sort(
              (CheckRecord a, CheckRecord b) => b.listId.compareTo(a.listId),
            );
      return list;
    });
