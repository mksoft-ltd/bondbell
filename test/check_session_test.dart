import 'dart:io';

import 'package:bondbell/core/storage/local_store.dart';
import 'package:bondbell/features/bonds/presentation/holders_controller.dart';
import 'package:bondbell/features/draws/data/draw_source.dart';
import 'package:bondbell/features/draws/data/nsi_index.dart';
import 'package:bondbell/features/draws/domain/check_models.dart';
import 'package:bondbell/features/draws/presentation/check_session.dart';
import 'package:bondbell/features/draws/presentation/records_controller.dart';
import 'package:bondbell/features/purchases/presentation/purchase_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves the bundled synthetic ZIPs as if they were NS&I's two latest
/// months, and records every file it hands out.
class FakeSource implements DrawSource {
  FakeSource(this.dir);
  final Directory dir;
  final List<File> handedOut = <File>[];

  @override
  bool get isSample => false;

  @override
  Future<NsiIndex> fetchIndex() async => NsiIndex(
    draws: <RemoteList>[
      RemoteList(id: '2026-11', label: 'November 2026', url: Uri.parse('https://www.nsandi.com/a.zip')),
      RemoteList(id: '2026-10', label: 'October 2026', url: Uri.parse('https://www.nsandi.com/b.zip')),
    ],
    unclaimed: RemoteList(id: 'unclaimed', label: 'Unclaimed', url: Uri.parse('https://www.nsandi.com/u.zip')),
  );

  @override
  Future<int?> sizeOf(RemoteList list) async => 14132;

  @override
  Future<File> download(RemoteList list,
      {void Function(int, int?)? onProgress, DownloadCancel? cancel}) async {
    final String src = list.id == 'unclaimed'
        ? 'assets/sample/sample_unclaimed.zip'
        : 'assets/sample/sample_winners.zip';
    final File f = File(src).copySync('${dir.path}/${list.id}-${handedOut.length}.zip');
    handedOut.add(f);
    onProgress?.call(1, 1);
    return f;
  }
}

void main() {
  late Directory dir;
  late FakeSource source;

  Future<ProviderContainer> container({bool pro = false}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'real.holders': '[{"id":"h","name":"Me","ranges":['
          '{"id":"r1","start":"312KM104000","end":"312KM104499"},'
          '{"id":"r2","start":"47DW185520","end":"47DW185569"}]}]',
    });
    final ProviderContainer c = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(
          LocalStore(await SharedPreferences.getInstance())),
      liveDrawSourceProvider.overrideWithValue(source),
      forceProProvider.overrideWithValue(pro),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bondbell_test');
    source = FakeSource(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('latest draw: finds wins, stores only matches, deletes the download',
      () async {
    final ProviderContainer c = await container();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    expect(c.read(checkSessionProvider).phase, CheckPhase.ready);
    expect(c.read(checkSessionProvider).request!.drawId, '2026-11');
    await s.start();
    final CheckSessionState st = c.read(checkSessionProvider);
    expect(st.phase, CheckPhase.done, reason: st.error);
    expect(st.record!.totalWon, 125);
    expect(st.record!.integrityOk, isTrue);
    expect(st.record!.bondsChecked, 550);
    expect(c.read(recordsProvider)['2026-11']!.wins, hasLength(2));
    expect(source.handedOut.single.existsSync(), isFalse,
        reason: 'the downloaded list must be deleted after the check');
  });

  test('free tier cannot check an earlier draw or bulk unclaimed', () async {
    final ProviderContainer c = await container();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('2026-10'));
    expect(c.read(checkSessionProvider).phase, CheckPhase.failed);
    expect(c.read(checkSessionProvider).error, contains('Pro'));
    await s.prepare(const CheckRequest.unclaimedAll());
    expect(c.read(checkSessionProvider).error, contains('Pro'));
    expect(source.handedOut, isEmpty);
  });

  test('Pro can check an earlier draw and all bonds against unclaimed',
      () async {
    final ProviderContainer c = await container(pro: true);
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('2026-10'));
    await s.start();
    expect(c.read(checkSessionProvider).phase, CheckPhase.done);
    await s.prepare(const CheckRequest.unclaimedAll());
    await s.start();
    final CheckRecord r = c.read(checkSessionProvider).record!;
    expect(r.listId, 'unclaimed');
    expect(r.wins.single.bond, '47DW185533');
  });

  test('changing bonds makes a stored result stale', () async {
    final ProviderContainer c = await container();
    final CheckSessionController s = c.read(checkSessionProvider.notifier);
    await s.prepare(const CheckRequest.draw('latest'));
    await s.start();
    final String before = c.read(recordsProvider)['2026-11']!.fingerprint;
    expect(before, holdingsFingerprint(c.read(holdersProvider)));
    await c.read(holdersProvider.notifier).deleteRange('h', 'r2');
    expect(before, isNot(holdingsFingerprint(c.read(holdersProvider))));
  });
}
