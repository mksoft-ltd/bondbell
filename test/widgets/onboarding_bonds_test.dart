import 'package:bondbell/features/bonds/domain/holder.dart';
import 'package:bondbell/features/bonds/presentation/holders_controller.dart';
import 'package:bondbell/features/settings/presentation/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

void main() {
  group('onboarding', () {
    testWidgets('first launch: three pages, independence notice, then My bonds',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, onboarded: false);
      expect(find.text('Check your bonds without logging in'), findsOneWidget);
      expect(h.reminders.permissionRequests, 0,
          reason: 'notification permission is never asked at launch');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Your numbers stay on this phone'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not affiliated with'), findsOneWidget);
      await tester.tap(find.text('Add my bond numbers'));
      await tester.pumpAndSettle();
      expect(find.text('No bonds yet'), findsOneWidget);
      final AppSettings s = h.container.read(appSettingsProvider);
      expect(s.onboarded, isTrue);
      expect(s.sampleMode, isFalse);
      expect(find.textContaining('Sample mode'), findsNothing);
    });

    testWidgets('"Try with sample numbers" opens Check in sample mode with the '
        'sample holder and the banner', (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, onboarded: false);
      for (int i = 0; i < 2; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Try with sample numbers'));
      await tester.pumpAndSettle();
      expect(find.text('Sample mode: made-up numbers, not real results'),
          findsOneWidget);
      expect(find.textContaining('20,050 bonds'), findsOneWidget);
      expect(h.container.read(holdersProvider).single.id, 'sample-holder');
    });

    testWidgets('the sample banner\'s Exit returns to the user\'s own (empty) '
        'bonds', (WidgetTester tester) async {
      final Harness h = await pumpBondbell(
        tester,
        prefs: const <String, Object>{'settings.sampleMode': true},
      );
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
      expect(find.text('Sample mode: made-up numbers, not real results'),
          findsNothing);
      expect(h.container.read(holdersProvider), isEmpty);
      expect(find.text('Add your bond numbers'), findsOneWidget);
    });
  });

  group('holders and ranges', () {
    testWidgets('add a holder: a blank name is explained, then the holder opens',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(tester, route: '/bonds');
      await tester.tap(find.text('Add a holder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.textContaining('Enter a name'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  Gran  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(h.container.read(holdersProvider).single.name, 'Gran');
      expect(find.text('Add their bond numbers'), findsOneWidget);
    });

    Future<Harness> openHolder(WidgetTester tester, {String? holders}) async {
      final Harness h = await pumpBondbell(
        tester,
        prefs: <String, Object>{
          'real.holders': holders ?? '[{"id":"me","name":"Me","ranges":[]}]',
        },
        route: '/bonds',
      );
      h.push('/holder/me');
      await tester.pumpAndSettle();
      return h;
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Add bond numbers').last);
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.widgetWithText(TextField, label);

    testWidgets('validation errors are shown in plain English and nothing is '
        'saved', (WidgetTester tester) async {
      final Harness h = await openHolder(tester);
      await openSheet(tester);
      final Map<String, String> cases = <String, String>{
        '12AO345678': 'Did you mean the number 0?',
        '1234567890': 'holder\'s number',
        '12AB34567': 'exactly six digits',
        '1234AB345678': 'at most three digits',
        '012AB345678': 'never start with 0',
        '12A345678': 'exactly two letters',
      };
      for (final MapEntry<String, String> e in cases.entries) {
        await tester.enterText(field('First (or only) bond number'), e.key);
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pump();
        expect(find.textContaining(e.value), findsOneWidget, reason: e.key);
      }
      expect(h.container.read(holdersProvider).single.ranges, isEmpty);
    });

    testWidgets('a reversed or cross-series range is refused',
        (WidgetTester tester) async {
      await openHolder(tester);
      await openSheet(tester);
      await tester.enterText(field('First (or only) bond number'), '312KM104999');
      await tester.enterText(field('Last bond number (optional)'), '312KM104000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      expect(find.textContaining('Swap them round'), findsOneWidget);
      await tester.enterText(field('Last bond number (optional)'), '313KM104999');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      expect(find.textContaining('start the same way'), findsOneWidget);
    });

    testWidgets('a statement range is counted live, upper-cased and saved',
        (WidgetTester tester) async {
      final Harness h = await openHolder(tester);
      await openSheet(tester);
      await tester.enterText(field('First (or only) bond number'), '312km104000');
      await tester.enterText(field('Last bond number (optional)'), '312KM104999');
      await tester.pump();
      expect(find.text('1,000 bonds · £1,000'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final ranges = h.container.read(holdersProvider).single.ranges;
      expect(ranges.single.start.toString(), '312KM104000');
      expect(ranges.single.count, 1000);
      expect(find.text('1,000 bonds · £1,000'), findsWidgets);
    });

    testWidgets('an overlapping range warns (across holders too) but is allowed',
        (WidgetTester tester) async {
      await openHolder(
        tester,
        holders: '[{"id":"me","name":"Me","ranges":[]},'
            '{"id":"gran","name":"Gran","ranges":[{"id":"g1",'
            '"start":"312KM104500","end":"312KM104600"}]}]',
      );
      await openSheet(tester);
      await tester.enterText(field('First (or only) bond number'), '312KM104000');
      await tester.enterText(field('Last bond number (optional)'), '312KM104550');
      await tester.pump();
      expect(find.textContaining('overlaps numbers you\'ve already added'),
          findsOneWidget);
      expect(find.textContaining('(Gran)'), findsOneWidget);
    });

    testWidgets('more than £50,000 for one person is a gentle warning',
        (WidgetTester tester) async {
      await openHolder(
        tester,
        holders: '[{"id":"me","name":"Me","ranges":[{"id":"a",'
            '"start":"100AA000000","end":"100AA050000"}]}]',
      );
      expect(find.textContaining('more than NS&I\'s £50,000 limit'), findsOneWidget);
    });

    testWidgets('free: a second holder opens the Pro explanation, not a form',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(
        tester,
        prefs: <String, Object>{'real.holders': holdersJson(<Holder>[meHolder])},
        route: '/bonds',
      );
      await tester.tap(find.text('Add holder'));
      await tester.pumpAndSettle();
      expect(find.text('More holders with Pro'), findsOneWidget);
      await tester.tap(find.text('See Pro'));
      await tester.pumpAndSettle();
      expect(find.text('Do more with Bondbell Pro'), findsOneWidget);
      expect(h.container.read(holdersProvider), hasLength(1));
    });

    testWidgets('Pro: a second holder can be added',
        (WidgetTester tester) async {
      final Harness h = await pumpBondbell(
        tester,
        forcePro: true,
        prefs: <String, Object>{'real.holders': holdersJson(<Holder>[meHolder])},
        route: '/bonds',
      );
      await tester.tap(find.text('Add holder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Gran');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(h.container.read(holdersProvider), hasLength(2));
    });

    testWidgets('deleting a holder asks first', (WidgetTester tester) async {
      final Harness h = await openHolder(tester);
      await tester.tap(find.byTooltip('Delete holder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.container.read(holdersProvider), hasLength(1));
      await tester.tap(find.byTooltip('Delete holder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(h.container.read(holdersProvider), isEmpty);
    });
  });
}
