import 'package:bondbell/features/draws/domain/check_models.dart';
import 'package:bondbell/features/history/history_screen.dart';
import 'package:flutter_test/flutter_test.dart';

CheckRecord rec(List<Win> wins) => CheckRecord(
  listId: 'unclaimed',
  label: 'Unclaimed',
  checkedAt: DateTime.utc(2026, 11, 14),
  fingerprint: 'x',
  wins: wins,
  numbersScanned: 10,
  integrityOk: true,
  bondsChecked: 10,
);

void main() {
  test('two separate unclaimed prizes on one bond are two prizes', () {
    final CheckRecord r = rec(const <Win>[
      Win(bond: '47DW185533', prize: 25, holderId: 'h', holderName: 'Me', hit: 0),
      Win(bond: '47DW185533', prize: 25, holderId: 'h', holderName: 'Me', hit: 1),
    ]);
    expect(r.prizeCount, 2);
    expect(r.totalWon, 50);
  });

  test('one prize listed under two holders is one prize', () {
    final CheckRecord r = rec(const <Win>[
      Win(bond: '312KM104217', prize: 100, holderId: 'a', holderName: 'Me', hit: 3),
      Win(bond: '312KM104217', prize: 100, holderId: 'b', holderName: 'Gran', hit: 3),
    ]);
    expect(r.prizeCount, 1);
    expect(r.totalWon, 100);
    expect(r.alsoListedUnder(r.wins.first), <String>['Gran']);
    expect(r.alsoListedUnder(r.wins.last), <String>['Me']);
  });

  test('records saved before the hit index existed dedupe by bond + prize', () {
    final CheckRecord r = CheckRecord.fromJson(rec(const <Win>[
      Win(bond: '312KM104217', prize: 100, holderId: 'a', holderName: 'Me'),
      Win(bond: '312KM104217', prize: 100, holderId: 'b', holderName: 'Gran'),
    ]).toJson());
    expect(r.prizeCount, 1);
    expect(r.totalWon, 100);
  });

  test('History stats count a shared bond once', () {
    final WinStats stats = WinStats(<CheckRecord>[
      rec(const <Win>[
        Win(bond: '312KM104217', prize: 100, holderId: 'a', holderName: 'Me', hit: 0),
        Win(bond: '312KM104217', prize: 100, holderId: 'b', holderName: 'Gran', hit: 0),
      ]),
    ], 1000);
    expect(stats.prizes, 1);
    expect(stats.totalWon, 100);
  });
}
