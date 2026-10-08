import 'package:bookends_cleaning/core/dates.dart';
import 'package:bookends_cleaning/data/constants.dart';
import 'package:bookends_cleaning/data/logic.dart';
import 'package:bookends_cleaning/screens/expiry.dart' show parseLabelCode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weekId matches the website (ISO weeks)', () {
    expect(weekId(DateTime(2026, 10, 8)), '2026-W41');
    expect(weekId(DateTime(2026, 1, 1)), '2026-W01');
    expect(weekId(DateTime(2027, 1, 1)), '2026-W53');
    expect(weekId(DateTime(2024, 12, 30)), '2025-W01');
    expect(ymd(weekStart('2026-W41')), '2026-10-05');
    expect(monthOfWeek('2026-W40'), '2026-10');
  });

  test('date formatting', () {
    expect(fmtD('2026-10-08'), '08 Oct 26');
    expect(fmtD(null), '—');
    expect(daysBetween('2026-10-08', '2026-10-15'), 7);
  });

  test('template slot keys', () {
    expect(kBuiltinWeekly.length, 33);
    expect(kBuiltinMonthly.length, 13);
    expect(kBuiltinWeekly[12].t.area, 'Under-counter fridges — inside, trays & seals');
    expect(kBuiltinWeekly[32].t.area, 'Housekeeping area cleaning');
    expect(kBuiltinWeekly[32].t.day, 1);
    expect(kBuiltinMonthly[3].t.area, 'Pull out every machine — clean behind & underneath');
  });

  test('initials', () {
    expect(initials('Rahul'), 'RA');
    expect(initials('Husen Khan'), 'HK');
    expect(initials('Suresh Kumar Patel'), 'SP');
  });

  test('expiry states', () {
    final t = today();
    expect(expiryState(ymd(addDays(t, -1))).k, 'expired');
    expect(expiryState(ymd(addDays(t, 7))).k, 'soon');
    expect(expiryState(ymd(addDays(t, 30))).k, 'month');
    expect(expiryState(ymd(addDays(t, 31))).k, 'safe');
    expect(expiryStatus(ymd(addDays(t, 3))).$2, 'EXPIRING SOON');
  });

  test('label codes', () {
    expect(parseLabelCode('https://x.vercel.app/#p=P-CPP-03'), 'P-CPP-03');
    expect(parseLabelCode('BOOKENDS|P-CPP-03|Paneer|EXP:2026-10-11'), 'P-CPP-03');
    expect(parseLabelCode('BK|1|p-aka-9'), 'P-AKA-9');
    expect(parseLabelCode(' p-cpp-mf3k9q-7t2 '), 'P-CPP-MF3K9Q-7T2');
  });

  test('score bands', () {
    expect(scoreBand(90), 'Excellent');
    expect(scoreBand(75), 'On track');
    expect(scoreBand(60), 'Needs attention');
    expect(scoreBand(59), 'Critical');
  });
}
