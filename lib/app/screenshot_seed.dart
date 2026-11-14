import '../core/storage/local_store.dart';
import '../features/bonds/domain/holder.dart';
import '../features/bonds/presentation/holders_controller.dart';
import '../features/draws/domain/check_models.dart';

/// Store-screenshot data (SCREENSHOT_MODE, debug/profile only): sample mode
/// on, the sample holder, and six months of sample results so History has
/// something to show. Every number is made up and labelled as a sample.
Future<void> seedScreenshotData(LocalStore store) async {
  await store.setBool('settings.onboarded', true);
  await store.setBool('settings.sampleMode', true);
  final List<Holder> holders = sampleHolders();
  await store.writeJson(
    'sample.holders',
    holders.map((Holder h) => h.toJson()).toList(),
  );
  final String fp = holdingsFingerprint(holders);
  final int held = holders.fold(0, (int a, Holder h) => a + h.bondCount);
  CheckRecord rec(String id, String label, List<(String, int)> wins) =>
      CheckRecord(
        listId: id,
        label: label,
        checkedAt: DateTime.parse('$id-02T09:05:00Z'),
        fingerprint: fp,
        wins: <Win>[
          for (final (String bond, int prize) in wins)
            Win(
              bond: bond,
              prize: prize,
              holderId: holders.first.id,
              holderName: holders.first.name,
            ),
        ],
        numbersScanned: 6500000,
        integrityOk: true,
        bondsChecked: held,
      );
  final List<CheckRecord> records = <CheckRecord>[
    rec('2026-11', 'Sample', <(String, int)>[
      ('312KM104217', 100),
      ('312KM104388', 25),
    ]),
    rec('2026-10', 'October 2026 (sample)', <(String, int)>[
      ('47DW185541', 25),
    ]),
    rec('2026-09', 'September 2026 (sample)', <(String, int)>[]),
    rec('2026-08', 'August 2026 (sample)', <(String, int)>[
      ('312KM104050', 50),
    ]),
    rec('2026-07', 'July 2026 (sample)', <(String, int)>[]),
    rec('2026-06', 'June 2026 (sample)', <(String, int)>[
      ('312KM104476', 25),
    ]),
  ];
  await store.writeJson('sample.records', <String, Object?>{
    for (final CheckRecord r in records) r.listId: r.toJson(),
  });
}
