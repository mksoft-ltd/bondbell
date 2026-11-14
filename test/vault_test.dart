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

  // ---- Fix round 3 (code review N1, security N-1) -----------------------

  void readOnly(bool on) =>
      Process.runSync('chmod', <String>[on ? '555' : '755', dir.path]);

  test('a failed write reports false and changes nothing', () async {
    final DataVault v = await DataVault.open(dir);
    expect(await v.set('real.holders', 'first'), isTrue);
    readOnly(true);
    addTearDown(() => readOnly(false));
    expect(await v.set('real.holders', 'second'), isFalse);
    expect(v.get('real.holders'), 'first', reason: 'not shown as saved');
    readOnly(false);
    expect(await v.set('real.holders', 'second'), isTrue, reason: 'retry works');
    expect((await DataVault.open(dir)).get('real.holders'), 'second');
  });

  test('a damaged vault is restored from the last good copy, and said so',
      () async {
    final DataVault first = await DataVault.open(dir);
    await first.set('real.holders', 'good');
    // Next launch: opens cleanly, which refreshes the last-good copy.
    expect((await DataVault.open(dir)).status, VaultOpenStatus.ok);
    File('${dir.path}/vault.json').writeAsStringSync('{"real.holders": ');
    final DataVault v = await DataVault.open(dir);
    expect(v.status, VaultOpenStatus.recovered);
    expect(v.get('real.holders'), 'good');
    // The damaged file is kept aside, not overwritten, and vault.json is
    // healthy again.
    expect(dir.listSync().where((FileSystemEntity e) => e.path.contains('.corrupt-')), hasLength(1));
    expect((await DataVault.open(dir)).status, VaultOpenStatus.ok);
  });

  test('with no usable copy the vault opens empty and says the data was lost',
      () async {
    File('${dir.path}/vault.json').writeAsStringSync('not json');
    final DataVault v = await DataVault.open(dir);
    expect(v.status, VaultOpenStatus.lost);
    expect(v.keys, isEmpty);
    expect(vaultStatusMessage(v.status), contains("couldn't be recovered"));
    expect(vaultStatusMessage(VaultOpenStatus.ok), isNull);
  });

  test('"Delete all my data" leaves no copy behind (.bak, .tmp, .corrupt)',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.onboarded': true});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final DataVault v = await DataVault.open(dir);
    final LocalStore s = LocalStore.withVault(prefs, v);
    await s.setString('real.holders', '47DW185520');
    File('${dir.path}/vault.json.bak').writeAsStringSync('{"real.holders":"47DW185520"}');
    File('${dir.path}/vault.json.tmp').writeAsStringSync('{"real.holders":"47DW185520"}');
    File('${dir.path}/vault.json.corrupt-1').writeAsStringSync('{"real.holders": 47DW');
    expect(await s.deleteAllPrivateData(), isTrue);
    final List<String> left = dir
        .listSync()
        .map((FileSystemEntity e) => e.uri.pathSegments.last)
        .toList();
    expect(left, <String>['vault.json']);
    expect(File('${dir.path}/vault.json').readAsStringSync(), isNot(contains('47DW')));
    expect(prefs.getBool('settings.onboarded'), isTrue, reason: 'settings kept');
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
