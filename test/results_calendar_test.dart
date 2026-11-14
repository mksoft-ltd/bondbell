import 'package:bondbell/core/calendar/results_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime d(int y, int m, int day) => DateTime(y, m, day);

  group('first working day matches NS&I upload dates (Last-Modified)', () {
    // 1 Jun, 1 Jul, 3 Aug, 1 Sep, 1 Oct, 2 Nov 2026 (checked 14 Nov 2026).
    final Map<int, DateTime> observed = <int, DateTime>{
      6: d(2026, 6, 1),
      7: d(2026, 7, 1),
      8: d(2026, 8, 3),
      9: d(2026, 9, 1),
      10: d(2026, 10, 1),
      11: d(2026, 11, 2),
    };
    observed.forEach((int m, DateTime expected) {
      test('2026-$m', () {
        expect(ResultsCalendar.firstWorkingDay(2026, m), expected);
      });
    });
  });

  test('December 2026 results day is 2 Dec, as nsandi.com says', () {
    expect(ResultsCalendar.resultsDay(2026, 12), d(2026, 12, 2));
  });

  test('bank holidays push the first working day', () {
    // 1 Jan 2027 is a Friday bank holiday.
    expect(ResultsCalendar.firstWorkingDay(2027, 1), d(2027, 1, 4));
    // 1 May 2028 is the early May bank holiday (Monday).
    expect(ResultsCalendar.firstWorkingDay(2028, 5), d(2028, 5, 2));
    // New Year 2028 substitute day is Monday 3 Jan.
    expect(ResultsCalendar.firstWorkingDay(2028, 1), d(2028, 1, 4));
  });

  test('nextResultsDay rolls into the next month and year', () {
    expect(ResultsCalendar.nextResultsDay(DateTime(2026, 11, 14, 10)),
        d(2026, 12, 2));
    expect(ResultsCalendar.nextResultsDay(DateTime(2026, 12, 20)),
        d(2027, 1, 5));
    expect(ResultsCalendar.nextResultsDay(DateTime(2026, 12, 2, 23)),
        d(2026, 12, 2));
  });

  test('upcomingResultsDays at 9am, strictly after now', () {
    final List<DateTime> days = ResultsCalendar.upcomingResultsDays(
        DateTime(2026, 12, 2, 10), 3);
    expect(days, <DateTime>[
      DateTime(2027, 1, 5, 9),
      DateTime(2027, 2, 2, 9),
      DateTime(2027, 3, 2, 9),
    ]);
  });

  test('rule-based fallback reproduces the published 2026-2028 table', () {
    // Proves the post-2028 fallback logic against GOV.UK's own data.
    for (int y = 2026; y <= 2028; y++) {
      for (DateTime day = d(y, 1, 1);
          day.year == y;
          day = DateTime(day.year, day.month, day.day + 1)) {
        expect(ResultsCalendar.isBankHoliday(day),
            ResultsCalendar.ruleBasedForTest(y).contains(day),
            reason: '$day');
      }
    }
  });

  test('table must be extended before it runs out', () {
    // Fails from 1 Jan 2028 so the 2029 holidays get added in time.
    expect(DateTime.now().year < ResultsCalendar.tableCoversUntil, isTrue,
        reason: 'Add the next year of GOV.UK bank holidays.');
  });
}
