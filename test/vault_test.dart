import 'dart:io';

import 'package:bondbell/core/storage/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Security audit L-2: bond numbers and holder names live in a vault file
/// (whose folder iOS excludes from backup), never in SharedPreferences.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bb_vault'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('private keys go to the vault file, flags stay in prefs', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final LocalStore s = LocalStore.withVault(prefs, await DataVault.open(dir));
    await s.writeJson('real.holders', <Object>['Gran 47DW185520']);
    await s.setBool('settings.onboarded', true);
    expect(prefs.getKeys(), <String>{'settings.onboarded'});
    expect(File('${dir.path}/vault.json').readAsStringSync(), contains('47DW185520'));
    // A fresh process reads it back.
    final LocalStore again = LocalStore.withVault(prefs, await DataVault.open(dir));
    expect(again.readJson('real.holders'), <Object>['Gran 47DW185520']);
  });

  test('existing installs are migrated out of SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'real.holders': '[{"id":"me","name":"Me","ranges":[]}]',
      'sample.records': '{}',
      'settings.sampleMode': true,
      'purchases.proOwned': true,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final DataVault v = await DataVault.open(dir);
    await v.migrateFrom(prefs);
    expect(prefs.getKeys(), <String>{'settings.sampleMode', 'purchases.proOwned'});
    final LocalStore s = LocalStore.withVault(prefs, v);
    expect(s.getString('real.holders'), '[{"id":"me","name":"Me","ranges":[]}]');
    expect(s.getString('sample.records'), '{}');
  });

  test('"Delete all my data" clears the vault too', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final LocalStore s = LocalStore.withVault(prefs, await DataVault.open(dir));
    await s.setString('real.holders', 'x');
    await s.setString('sample.holders', 'y');
    await s.clearPrefix('real.');
    await s.clearPrefix('sample.');
    expect(s.getString('real.holders'), isNull);
    expect((await DataVault.open(dir)).keys, isEmpty);
  });

  test('a corrupt vault is kept aside, not overwritten', () async {
    File('${dir.path}/vault.json').writeAsStringSync('{"real.holders": ');
    final DataVault v = await DataVault.open(dir);
    expect(v.keys, isEmpty);
    expect(File('${dir.path}/vault.json.bak').readAsStringSync(), '{"real.holders": ');
  });

  test('quick successive saves land in order', () async {
    final DataVault v = await DataVault.open(dir);
    final List<Future<void>> w = <Future<void>>[
      for (int i = 0; i < 20; i++) v.set('real.n', '$i'),
    ];
    await Future.wait(w);
    expect((await DataVault.open(dir)).get('real.n'), '19');
  });
}
