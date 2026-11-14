import 'package:bondbell/core/calendar/results_calendar.dart';
import 'package:bondbell/features/reminders/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Results-day dates worked out by hand from a calendar and GOV.UK's
/// England & Wales bank holidays (rule: results are due the calendar day
/// after the month's first working day). Weekday derivations are in the
/// comments so a reviewer can re-check them without running anything.
void main() {
  DateTime d(int y, int m, int day) => DateTime(y, m, day);

  group('results day', () {
    test('Friday first working day → results on the Saturday', () {
      // 1 May 2026 is a Friday (1 Jan 2026 Thu + 120 days, 120 % 7 = 1).
      expect(ResultsCalendar.firstWorkingDay(2026, 5), d(2026, 5, 1));
      expect(ResultsCalendar.resultsDay(2026, 5), d(2026, 5, 2));
      // 1 Oct 2027 is a Friday (1 Jan 2027 Fri + 273 days, 273 % 7 = 0).
      expect(ResultsCalendar.resultsDay(2027, 10), d(2027, 10, 2));
      // 1 Dec 2028 is a Friday (1 Jan 2028 Sat, leap year, + 335, % 7 = 6).
      expect(ResultsCalendar.resultsDay(2028, 12), d(2028, 12, 2));
    });

    test('weekend start → Monday is the first working day, results Tuesday',
        () {
      // 1 Nov 2026 is a Sunday.
      expect(ResultsCalendar.resultsDay(2026, 11), d(2026, 11, 3));
      // 1 Aug 2026 is a Saturday.
      expect(ResultsCalendar.resultsDay(2026, 8), d(2026, 8, 4));
    });

    test('weekend then a bank holiday Monday → Tuesday, results Wednesday', () {
      // 1 May 2027 Sat, 2 Sun, 3 Mon early May bank holiday.
      expect(ResultsCalendar.firstWorkingDay(2027, 5), d(2027, 5, 4));
      expect(ResultsCalendar.resultsDay(2027, 5), d(2027, 5, 5));
    });

    test('New Year: holiday, substitute day and the year boundary', () {
      // 1 Jan 2027 Fri (holiday) → Mon 4 → results Tue 5.
      expect(ResultsCalendar.resultsDay(2027, 1), d(2027, 1, 5));
      // 1 Jan 2028 Sat, substitute Mon 3 → Tue 4 → results Wed 5.
      expect(ResultsCalendar.resultsDay(2028, 1), d(2028, 1, 5));
      // 1 Jan 2029 Mon (holiday, rule-based table) → Tue 2 → results Wed 3.
      expect(ResultsCalendar.resultsDay(2029, 1), d(2029, 1, 3));
    });

    test('results day never falls in the next month', () {
      for (int y = 2026; y <= 2032; y++) {
        for (int m = 1; m <= 12; m++) {
          expect(ResultsCalendar.resultsDay(y, m).month, m, reason: '$y-$m');
        }
      }
    });

    test('the first working day is never a weekend or bank holiday', () {
      for (int y = 2026; y <= 2032; y++) {
        for (int m = 1; m <= 12; m++) {
          final DateTime f = ResultsCalendar.firstWorkingDay(y, m);
          expect(f.weekday, lessThanOrEqualTo(DateTime.friday), reason: '$f');
          expect(ResultsCalendar.isBankHoliday(f), isFalse, reason: '$f');
        }
      }
    });

    test('Christmas substitute days (2027: 25 Sat, 26 Sun → 27 and 28)', () {
      expect(ResultsCalendar.isBankHoliday(d(2027, 12, 27)), isTrue);
      expect(ResultsCalendar.isBankHoliday(d(2027, 12, 28)), isTrue);
      // Rule-based: 25 Dec 2032 is a Saturday → 27 and 28 Dec.
      expect(ResultsCalendar.ruleBasedForTest(2032),
          containsAll(<DateTime>[d(2032, 12, 27), d(2032, 12, 28)]));
      expect(ResultsCalendar.ruleBasedForTest(2032).contains(d(2032, 12, 25)), isFalse);
    });
  });

  group('next results day around the year boundary', () {
    test('on results day itself, today counts', () {
      expect(ResultsCalendar.nextResultsDay(DateTime(2026, 12, 2, 8)), d(2026, 12, 2));
    });
    test('the day after rolls over into January', () {
      expect(ResultsCalendar.nextResultsDay(DateTime(2026, 12, 3)), d(2027, 1, 5));
      expect(ResultsCalendar.nextResultsDay(DateTime(2026, 12, 31, 23, 59)), d(2027, 1, 5));
    });
    test('New Year\'s Day itself waits for the holiday to pass', () {
      expect(ResultsCalendar.nextResultsDay(DateTime(2027, 1, 1)), d(2027, 1, 5));
    });
  });

  group('upcoming reminders', () {
    test('09:00 exactly on results day is "now", so it moves to next month',
        () {
      expect(
        ResultsCalendar.upcomingResultsDays(DateTime(2026, 12, 2, 9), 1),
        <DateTime>[DateTime(2027, 1, 5, 9)],
      );
      expect(
        ResultsCalendar.upcomingResultsDays(DateTime(2026, 12, 2, 8, 59), 1),
        <DateTime>[DateTime(2026, 12, 2, 9)],
      );
    });

    test('six months ahead crosses the year without gaps', () {
      expect(
        ResultsCalendar.upcomingResultsDays(DateTime(2026, 11, 14), 6),
        <DateTime>[
          DateTime(2026, 12, 2, 9),
          DateTime(2027, 1, 5, 9),
          // 1 Feb 2027 Mon → results Tue 2.
          DateTime(2027, 2, 2, 9),
          // 1 Mar 2027 Mon → Tue 2.
          DateTime(2027, 3, 2, 9),
          // 1 Apr 2027 Thu → Fri 2 (Good Friday 2027 is 26 Mar).
          DateTime(2027, 4, 2, 9),
          DateTime(2027, 5, 5, 9),
        ],
      );
    });
  });

  group('09:00 UK time whatever the phone\'s time zone', () {
    late tz.Location london;
    late tz.Location newYork;
    late tz.Location sydney;
    setUpAll(() {
      tzdata.initializeTimeZones();
      london = tz.getLocation('Europe/London');
      newYork = tz.getLocation('America/New_York');
      sydney = tz.getLocation('Australia/Sydney');
    });

    test('winter (GMT): 09:00 UK is 09:00 UTC', () {
      final List<tz.TZDateTime> t = LocalReminderService.reminderTimes(
        tz.TZDateTime(london, 2026, 11, 14, 10),
        london,
        count: 1,
      );
      expect(t.single.toUtc(), DateTime.utc(2026, 12, 2, 9));
    });

    test('summer (BST): 09:00 UK is 08:00 UTC', () {
      // June 2027: 1 Jun Tue → results Wed 2 Jun, BST.
      final List<tz.TZDateTime> t = LocalReminderService.reminderTimes(
        tz.TZDateTime(london, 2027, 5, 20),
        london,
        count: 1,
      );
      expect(t.single.toUtc(), DateTime.utc(2027, 6, 2, 8));
    });

    test('a phone in New York at 03:30 local on results day (08:30 UK) still '
        'gets today\'s 09:00 UK reminder', () {
      final List<tz.TZDateTime> t = LocalReminderService.reminderTimes(
        tz.TZDateTime(newYork, 2026, 12, 2, 3, 30),
        london,
        count: 1,
      );
      expect(t.single.toUtc(), DateTime.utc(2026, 12, 2, 9));
    });

    test('a phone in Sydney where it is already 3 Dec still gets the 2 Dec '
        'reminder if it is before 09:00 in the UK', () {
      // 3 Dec 05:00 AEDT (UTC+11) = 2 Dec 18:00 UTC, after 09:00 UK, so
      // the next reminder is January's.
      final List<tz.TZDateTime> after = LocalReminderService.reminderTimes(
        tz.TZDateTime(sydney, 2026, 12, 3, 5),
        london,
        count: 1,
      );
      expect(after.single.toUtc(), DateTime.utc(2027, 1, 5, 9));
      // 2 Dec 19:30 AEDT = 08:30 UTC = 08:30 UK: today's reminder is due.
      final List<tz.TZDateTime> before = LocalReminderService.reminderTimes(
        tz.TZDateTime(sydney, 2026, 12, 2, 19, 30),
        london,
        count: 1,
      );
      expect(before.single.toUtc(), DateTime.utc(2026, 12, 2, 9));
    });

    test('the clock-change month (results 2 Apr 2027, BST from 28 Mar)', () {
      final List<tz.TZDateTime> t = LocalReminderService.reminderTimes(
        tz.TZDateTime(london, 2027, 3, 3),
        london,
        count: 1,
      );
      expect(t.single.toUtc(), DateTime.utc(2027, 4, 2, 8));
    });

    test('six are queued, all at 09:00 UK wall-clock time', () {
      final List<tz.TZDateTime> t = LocalReminderService.reminderTimes(
        tz.TZDateTime(london, 2026, 11, 14),
        london,
      );
      expect(t, hasLength(LocalReminderService.monthsAhead));
      for (final tz.TZDateTime x in t) {
        expect(tz.TZDateTime.from(x, london).hour, 9);
      }
    });
  });
}
