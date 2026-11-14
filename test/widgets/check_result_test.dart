import 'package:bondbell/features/bonds/domain/holder.dart';
import 'package:bondbell/features/draws/data/nsi_index.dart';
import 'package:bondbell/features/draws/domain/check_models.dart';
import 'package:bondbell/features/draws/presentation/check_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

void main() {
  final RemoteList nov = RemoteList(
    id: '2026-11',
    label: 'November 2026',
    url: Uri.parse('https://www.nsandi.com/files/n.zip'),
  );
  final String fp = holdingsFingerprint(<Holder>[meHolder]);

  CheckRecord record({
    List<Win> wins = const <Win>[],
    bool integrityOk = true,
    String fingerprint = '',
    String listId = '2026-11',
    String label = 'November 2026',
  }) => CheckRecord(
    listId: listId,
    label: label,
    checkedAt: DateTime.utc(2026, 11, 3, 9, 5),
    fingerprint: fingerprint.isEmpty ? fp : fingerprint,
    wins: wins,
    numbersScanned: 6575175,
    integrityOk: integrityOk,
    bondsChecked: 1001,
  );

  const List<Win> twoWins = <Win>[
    Win(bond: '312KM104217', prize: 100, holderId: 'me', holderName: 'Me'),
    Win(bond: '47DW185533', prize: 25, holderId: 'me', holderName: 'Me'),
  ];

  Map<String, Object> seeded([List<CheckRecord> records = const <CheckRecord>[]]) =>
      <String, Object>{
        'real.holders': holdersJson(<Holder>[meHolder]),
        if (records.isNotEmpty) 'real.records': recordsJson(records),
      };

  group('check flow states', () {
    late ScriptedCheckSession session;

    Future<Harness> open(
      WidgetTester tester,
      CheckSessionState Function(CheckRequest) script, {
      bool sample = false,
    }) async {
      session = ScriptedCheckSession(script);
      final Harness h = await pumpBondbell(
        tester,
        prefs: <String, Object>{
          ...seeded(),
          if (sample) 'settings.sampleMode': true,
        },
        extra: [checkSessionProvider.overrideWith(() => session)],
      );
      h.push('/check/draw/latest');
      // Not pumpAndSettle: an indeterminate progress bar never settles.
      await pumpFrames(tester);
      return h;
    }

    testWidgets('looking up NS&I: indeterminate progress with Cancel',
        (WidgetTester tester) async {
      await open(tester, (CheckRequest r) =>
          CheckSessionState(phase: CheckPhase.preparing, request: r));
      expect(find.text('Looking up NS&I\'s downloads page…'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester);
      expect(session.cancels, 1);
      expect(find.text('Check stopped'), findsOneWidget);
    });

    testWidgets('ready: file size, Wi-Fi advice, privacy line, and a go button',
        (WidgetTester tester) async {
      await open(tester, (CheckRequest r) => CheckSessionState(
        phase: CheckPhase.ready,
        request: const CheckRequest.draw('2026-11'),
        list: nov,
        sizeBytes: 33606244,
      ));
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Download size: 32.0 MB'), findsOneWidget);
      expect(find.textContaining('Wi-Fi recommended'), findsOneWidget);
      expect(find.textContaining('never leave your phone'), findsOneWidget);
      await tester.tap(find.text('Download and check'));
      await tester.pump();
      expect(session.starts, 1);
    });

    testWidgets('ready with an unknown size says so', (WidgetTester tester) async {
      await open(tester, (CheckRequest r) => CheckSessionState(
        phase: CheckPhase.ready,
        request: const CheckRequest.draw('2026-11'),
        list: nov,
      ));
      expect(find.text('Download size: an unknown size'), findsOneWidget);
    });

    testWidgets('sample ready: no Wi-Fi warning, says nothing is downloaded',
        (WidgetTester tester) async {
      await open(
        tester,
        (CheckRequest r) => CheckSessionState(
          phase: CheckPhase.ready,
          request: const CheckRequest.draw('2026-11'),
          list: nov,
          sizeBytes: 14000,
        ),
        sample: true,
      );
      expect(find.textContaining('Wi-Fi'), findsNothing);
      expect(find.text('Check the sample'), findsOneWidget);
      expect(find.text('Sample mode: made-up numbers, not real results'),
          findsOneWidget);
    });

    testWidgets('downloading: megabytes of total, and back asks before stopping',
        (WidgetTester tester) async {
      await open(tester, (CheckRequest r) => CheckSessionState(
        phase: CheckPhase.downloading,
        request: const CheckRequest.draw('2026-11'),
        list: nov,
        sizeBytes: 33554432,
        progress: 0.5,
      ));
      expect(find.text('Downloading from NS&I…'), findsOneWidget);
      expect(find.text('16.0 MB of 32.0 MB'), findsOneWidget);
      final LinearProgressIndicator bar = tester.widget(find.byType(LinearProgressIndicator));
      expect(bar.value, 0.5);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Stop checking?'), findsOneWidget);
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(session.cancels, 0);
      expect(find.text('Downloading from NS&I…'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(session.cancels, 1);
      expect(find.text('Downloading from NS&I…'), findsNothing);
    });

    testWidgets('scanning: percentage and Cancel', (WidgetTester tester) async {
      await open(tester, (CheckRequest r) => CheckSessionState(
        phase: CheckPhase.scanning,
        request: const CheckRequest.draw('2026-11'),
        list: nov,
        progress: 0.42,
      ));
      expect(find.text('Checking every winning number against yours…'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(session.cancels, 1);
    });

    testWidgets('failed because the page changed: offers NS&I\'s page and retry',
        (WidgetTester tester) async {
      await open(tester, (CheckRequest r) => CheckSessionState(
        phase: CheckPhase.failed,
        request: r,
        error: 'The page may have changed.',
        layoutChanged: true,
      ));
      expect(find.text('That didn\'t work'), findsOneWidget);
      expect(find.text('The page may have changed.'), findsOneWidget);
      expect(find.text('Open NS&I\'s page'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(session.prepares, 2);
    });

    testWidgets('failed for a network reason: retry only, no NS&I page button',
        (WidgetTester tester) async {
      await open(tester, (CheckRequest r) => CheckSessionState(
        phase: CheckPhase.failed,
        request: r,
        error: 'Couldn\'t reach NS&I\'s site.',
      ));
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Open NS&I\'s page'), findsNothing);
    });

    testWidgets('leaving a ready check by navigating elsewhere (deep link, '
        'tour) resets it without modifying providers mid-build',
        (WidgetTester tester) async {
      // Regression: PopScope's callback ran reset() while the Navigator was
      // rebuilding its pages, which Riverpod rejects ("Tried to modify a
      // provider while the widget tree was building").
      final Harness h = await open(tester, (CheckRequest r) => CheckSessionState(
        phase: CheckPhase.ready,
        request: const CheckRequest.draw('2026-11'),
        list: nov,
        sizeBytes: 1000,
      ));
      h.go('/bonds');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('My bonds'), findsWidgets);
      expect(h.container.read(checkSessionProvider).phase, CheckPhase.idle);
    });

    testWidgets('back from a ready check resets the session',
        (WidgetTester tester) async {
      final Harness h = await open(tester, (CheckRequest r) => CheckSessionState(
        phase: CheckPhase.ready,
        request: const CheckRequest.draw('2026-11'),
        list: nov,
        sizeBytes: 1000,
      ));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.container.read(checkSessionProvider).phase, CheckPhase.idle);
    });

    testWidgets('done shows the result in place', (WidgetTester tester) async {
      await open(tester, (CheckRequest r) => CheckSessionState(
        phase: CheckPhase.done,
        request: r,
        list: nov,
        record: record(wins: twoWins),
      ));
      expect(find.text('Congratulations!'), findsOneWidget);
    });
  });

  group('results', () {
    Future<Harness> showResult(
      WidgetTester tester,
      CheckRecord r, {
      bool sample = false,
      Map<String, Object> prefs = const <String, Object>{},
    }) async {
      final Harness h = await pumpBondbell(tester, prefs: <String, Object>{
        ...seeded(),
        ...prefs,
        if (sample) 'settings.sampleMode': true,
        if (sample)
          'sample.records': recordsJson(<CheckRecord>[r])
        else
          'real.records': recordsJson(<CheckRecord>[r]),
      });
      h.push('/result/${r.listId}');
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('a win: total, each bond and prize, how to claim, confirm with '
        'NS&I, and a quiet tip card', (WidgetTester tester) async {
      await showResult(tester, record(wins: twoWins));
      expect(find.text('Congratulations!'), findsOneWidget);
      expect(find.textContaining('2 prizes worth £125 in the November 2026'),
          findsOneWidget);
      expect(find.text('312KM104217'), findsOneWidget);
      expect(find.text('£100'), findsOneWidget);
      expect(find.text('£25'), findsOneWidget);
      await scrollTo(tester, find.text('How to claim'));
      expect(find.text('Contact NS&I'), findsOneWidget);
      await scrollTo(tester, find.textContaining('Always confirm results'));
      await scrollTo(tester, find.text('Glad Bondbell helped?'));
      expect(find.textContaining('Tips don\'t unlock anything'), findsOneWidget);
    });

    testWidgets('no win: clear message, no claim steps, no tip card',
        (WidgetTester tester) async {
      await showResult(tester, record());
      expect(find.text('No prizes this time'), findsOneWidget);
      expect(find.textContaining('Every bond stays in the draw'), findsOneWidget);
      expect(find.text('How to claim'), findsNothing);
      expect(find.text('Glad Bondbell helped?'), findsNothing);
      expect(find.textContaining('Always confirm results'), findsOneWidget);
    });

    testWidgets('integrity failure is shown above the result',
        (WidgetTester tester) async {
      await showResult(tester, record(integrityOk: false));
      expect(find.textContaining('didn\'t add up the way NS&I\'s own totals'),
          findsOneWidget);
    });

    testWidgets('a result for bonds that have since changed says so',
        (WidgetTester tester) async {
      await showResult(tester, record(wins: twoWins, fingerprint: 'old'));
      expect(find.textContaining('Your bonds have changed since this check'),
          findsOneWidget);
    });

    testWidgets('a sample win never shows the tip jar and keeps the banner',
        (WidgetTester tester) async {
      await showResult(tester, record(wins: twoWins), sample: true);
      expect(find.text('Congratulations!'), findsOneWidget);
      expect(find.text('Sample mode: made-up numbers, not real results'),
          findsOneWidget);
      await scrollTo(tester, find.textContaining('Always confirm results'));
      expect(find.text('Glad Bondbell helped?'), findsNothing);
    });

    testWidgets('wins are grouped under each holder\'s name',
        (WidgetTester tester) async {
      await showResult(tester, record(wins: const <Win>[
        Win(bond: '9XY000001', prize: 1000, holderId: 'gran', holderName: 'Gran'),
        Win(bond: '312KM104217', prize: 100, holderId: 'me', holderName: 'Me'),
      ]));
      expect(find.text('Gran'), findsOneWidget);
      expect(find.text('Me'), findsOneWidget);
      expect(find.textContaining('worth £1,100'), findsOneWidget);
    });

    testWidgets('unclaimed anonymous entries are labelled',
        (WidgetTester tester) async {
      await showResult(tester, record(
        listId: 'unclaimed',
        label: 'Unclaimed prizes',
        wins: const <Win>[
          Win(bond: '8AA814111', prize: 25, holderId: 'me', holderName: 'Me', anonymous: true),
        ],
      ));
      expect(find.text('Found 1 unclaimed prize'), findsOneWidget);
      expect(find.textContaining('holder\'s name is unknown'), findsOneWidget);
    });

    testWidgets('a missing result says so instead of crashing',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, prefs: seeded());
      h.push('/result/2026-05');
      await tester.pumpAndSettle();
      expect(find.text('No result saved'), findsOneWidget);
    });
  });

  group('home', () {
    testWidgets('no bonds yet: invites adding them, no draw card',
        (WidgetTester tester) async {
      await pumpBondbell(tester);
      expect(find.textContaining('Next results expected'), findsOneWidget);
      expect(find.text('Add bond numbers'), findsOneWidget);
      expect(find.text('Check the latest draw'), findsNothing);
      await scrollTo(tester, find.textContaining('not affiliated with'));
      expect(find.textContaining('not affiliated with'), findsOneWidget);
    });

    testWidgets('with bonds and a fresh result: shows the win summary',
        (WidgetTester tester) async {
      await pumpBondbell(tester, prefs: seeded(<CheckRecord>[record(wins: twoWins)]));
      expect(find.textContaining('1,001 bonds (£1,001) across 1 holder'), findsOneWidget);
      expect(find.text('You have 2 prizes worth £125.'), findsOneWidget);
      expect(find.text('See the details'), findsOneWidget);
    });

    testWidgets('a result for changed bonds asks for a re-check instead',
        (WidgetTester tester) async {
      await pumpBondbell(
        tester,
        prefs: seeded(<CheckRecord>[record(wins: twoWins, fingerprint: 'old')]),
      );
      expect(find.text('You have 2 prizes worth £125.'), findsNothing);
      expect(find.textContaining('Your bonds have changed since you last checked'),
          findsOneWidget);
      expect(find.text('Check the latest draw'), findsOneWidget);
    });

    testWidgets('reminder card asks for permission only when tapped',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, prefs: seeded());
      expect(h.reminders.permissionRequests, 0);
      await scrollTo(tester, find.text('Turn on reminders'));
      await tester.tap(find.text('Turn on reminders'));
      await tester.pumpAndSettle();
      expect(h.reminders.permissionRequests, 1);
      expect(h.reminders.schedules, 1);
      expect(find.textContaining('Reminders are on'), findsOneWidget);
      expect(find.text('Turn on reminders'), findsNothing);
    });

    testWidgets('free: earlier draws point to Pro', (WidgetTester tester) async {
      await pumpBondbell(tester, prefs: seeded());
      await scrollTo(tester, find.text('Earlier draws'));
      expect(find.text('About Bondbell Pro'), findsOneWidget);
    });
  });
}
