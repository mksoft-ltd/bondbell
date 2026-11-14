import 'package:flutter/foundation.dart';

/// When NS&I's monthly results become available, for England.
///
/// What the evidence shows (checked 14 Nov 2026):
/// * The draw is announced on the first working day of the month.
/// * NS&I's winners files are uploaded late that same evening — the
///   June–November 2026 ZIPs carry Last-Modified times of 22:55–23:58 UTC
///   on the 1st working day (1 Jun, 1 Jul, 3 Aug, 1 Sep, 1 Oct, 2 Nov).
/// * nsandi.com's prize checker said "Next results available 2 December"
///   for December 2026 (1st working day: Tue 1 Dec).
///
/// So results are due on the calendar day after the first working day of
/// the month. Working days exclude weekends and England & Wales bank
/// holidays.
abstract final class ResultsCalendar {
  /// England & Wales bank holidays, from GOV.UK's bank-holidays.json
  /// (fetched 14 Nov 2026). Includes substitute days.
  static final Set<DateTime> _bankHolidays = <DateTime>{
    // 2026
    DateTime(2026, 1, 1), DateTime(2026, 4, 3), DateTime(2026, 4, 6),
    DateTime(2026, 5, 4), DateTime(2026, 5, 25), DateTime(2026, 8, 31),
    DateTime(2026, 12, 25), DateTime(2026, 12, 28),
    // 2027
    DateTime(2027, 1, 1), DateTime(2027, 3, 26), DateTime(2027, 3, 29),
    DateTime(2027, 5, 3), DateTime(2027, 5, 31), DateTime(2027, 8, 30),
    DateTime(2027, 12, 27), DateTime(2027, 12, 28),
    // 2028
    DateTime(2028, 1, 3), DateTime(2028, 4, 14), DateTime(2028, 4, 17),
    DateTime(2028, 5, 1), DateTime(2028, 5, 29), DateTime(2028, 8, 28),
    DateTime(2028, 12, 25), DateTime(2028, 12, 26),
  };

  /// The last year covered by the published table above.
  static const int tableCoversUntil = 2028;

  static bool isBankHoliday(DateTime d) {
    final DateTime day = DateTime(d.year, d.month, d.day);
    if (day.year <= tableCoversUntil) return _bankHolidays.contains(day);
    return _ruleBasedHolidays(day.year).contains(day);
  }

  static bool isWorkingDay(DateTime d) =>
      d.weekday != DateTime.saturday &&
      d.weekday != DateTime.sunday &&
      !isBankHoliday(d);

  static DateTime firstWorkingDay(int year, int month) {
    DateTime d = DateTime(year, month, 1);
    while (!isWorkingDay(d)) {
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return d;
  }

  /// The date results for [year]/[month]'s draw are due.
  static DateTime resultsDay(int year, int month) {
    final DateTime f = firstWorkingDay(year, month);
    return DateTime(f.year, f.month, f.day + 1);
  }

  /// The next results day on or after [now]'s date (today counts).
  static DateTime nextResultsDay(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    DateTime r = resultsDay(now.year, now.month);
    // DateTime normalises month 13 to January of the next year.
    if (r.isBefore(today)) r = resultsDay(now.year, now.month + 1);
    return r;
  }

  /// The next [count] results days strictly after [now] at [hour]:00.
  static List<DateTime> upcomingResultsDays(DateTime now, int count,
      {int hour = 9}) {
    final List<DateTime> out = <DateTime>[];
    int y = now.year;
    int m = now.month;
    while (out.length < count) {
      final DateTime r = resultsDay(y, m);
      final DateTime at = DateTime(r.year, r.month, r.day, hour);
      if (at.isAfter(now)) out.add(at);
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
    }
    return out;
  }

  /// Fallback beyond the table: the standing England & Wales rules (New
  /// Year, Good Friday, Easter Monday, early May, spring, summer, Christmas,
  /// Boxing Day, with weekend substitutes). One-off holidays (coronations,
  /// jubilees) cannot be predicted; the table should be extended yearly.
  @visibleForTesting
  static Set<DateTime> ruleBasedForTest(int y) => _ruleBasedHolidays(y);

  static Set<DateTime> _ruleBasedHolidays(int y) {
    final Set<DateTime> s = <DateTime>{};
    DateTime sub(DateTime d) {
      while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
        d = DateTime(d.year, d.month, d.day + 1);
      }
      return d;
    }

    s.add(sub(DateTime(y, 1, 1)));
    final DateTime easter = _easterSunday(y);
    s.add(DateTime(easter.year, easter.month, easter.day - 2));
    s.add(DateTime(easter.year, easter.month, easter.day + 1));
    s.add(_firstMonday(y, 5));
    s.add(_lastMonday(y, 5));
    s.add(_lastMonday(y, 8));
    final DateTime xmas = DateTime(y, 12, 25);
    final DateTime boxing = DateTime(y, 12, 26);
    if (xmas.weekday == DateTime.saturday) {
      s.add(DateTime(y, 12, 27));
      s.add(DateTime(y, 12, 28));
    } else if (xmas.weekday == DateTime.sunday) {
      s.add(DateTime(y, 12, 26));
      s.add(DateTime(y, 12, 27));
    } else if (boxing.weekday == DateTime.saturday) {
      s.add(xmas);
      s.add(DateTime(y, 12, 28));
    } else {
      s.add(xmas);
      s.add(boxing);
    }
    return s;
  }

  static DateTime _firstMonday(int y, int m) {
    DateTime d = DateTime(y, m, 1);
    while (d.weekday != DateTime.monday) {
      d = DateTime(y, m, d.day + 1);
    }
    return d;
  }

  static DateTime _lastMonday(int y, int m) {
    DateTime d = DateTime(y, m + 1, 0);
    while (d.weekday != DateTime.monday) {
      d = DateTime(y, m, d.day - 1);
    }
    return d;
  }

  /// Anonymous Gregorian algorithm.
  static DateTime _easterSunday(int y) {
    final int a = y % 19;
    final int b = y ~/ 100;
    final int c = y % 100;
    final int d = b ~/ 4;
    final int e = b % 4;
    final int f = (b + 8) ~/ 25;
    final int g = (b - f + 1) ~/ 3;
    final int h = (19 * a + b - d - g + 15) % 30;
    final int i = c ~/ 4;
    final int k = c % 4;
    final int l = (32 + 2 * e + 2 * i - h - k) % 7;
    final int m = (a + 11 * h + 22 * l) ~/ 451;
    final int month = (h + l - 7 * m + 114) ~/ 31;
    final int day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(y, month, day);
  }
}
