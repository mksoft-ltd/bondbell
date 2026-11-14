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
  final int held = uniqueBondCount(holders);
  CheckRecord rec(String id, String label, List<(String, int)> wins) =>
      CheckRecord(
        listId: id,
        label: label,
        checkedAt: DateTime.parse('$id-02T09:05:00Z'),
        fingerprint: fp,
        wins: <Win>[
          for (int i = 0; i < wins.length; i++)
            Win(
              bond: wins[i].$1,
              prize: wins[i].$2,
              // Grandad's certificates are the 9JN series.
              holderId: wins[i].$1.startsWith('9JN')
                  ? holders.last.id
                  : holders.first.id,
              holderName: wins[i].$1.startsWith('9JN')
                  ? holders.last.name
                  : holders.first.name,
              hit: i,
            ),
        ],
        numbersScanned: 6500000,
        integrityOk: true,
        bondsChecked: held,
      );
  final List<CheckRecord> records = <CheckRecord>[
    rec('2026-11', 'November 2026 (sample)', <(String, int)>[
      ('312KM104217', 100),
      ('312KM104388', 25),
    ]),
    // Matches the bundled October sample list.
    rec('2026-10', 'October 2026 (sample)', <(String, int)>[
      ('9JN000120', 50),
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
