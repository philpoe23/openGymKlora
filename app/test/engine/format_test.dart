// format.js has no test file of its own. These pin the port to what the JS gives in Node for the
// 'en-GB' locale (values produced by running format.js), so the Intl stand-ins stay honest.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/format.dart';

void main() {
  tearDown(() => setWeightDecimals(1));

  test('fmtDate / fmtDateRange read as en-GB', () {
    expect(fmtDate('2026-02-03'), '3 Feb');
    expect(fmtDate('2026-02-03', true), 'Tue 3 Feb');
    expect(fmtDate('2026-02-03', false, true), '3 Feb 2026');
    expect(fmtDate('2026-02-03', true, true), 'Tue, 3 Feb 2026');
    expect(fmtDate('nope'), 'Invalid Date');
    expect(fmtDateRange('2025-12-30', '2026-01-02', false, DateTime(2026, 6, 1)), '30 Dec 2025 – 2 Jan 2026');
    expect(fmtDateRange('2026-02-03', null, false, DateTime(2026, 6, 1)), '3 Feb');
    expect(fmtDateRange(null, null), '');
  });

  test('numbers group with commas and keep the weight decimals', () {
    expect(fmtNum(7535.25), '7,535.3');
    expect(fmtNum(62.5), '62.5');
    expect(fmtNum(60), '60');
    setWeightDecimals(2);
    expect(fmtNum(21.25), '21.25');
    expect(fmtPlate(1234567.891), '1,234,567.89');
    expect(fmtVol(18800, 'kg'), '18,800 kg');
  });

  test('durations, counts and relative times', () {
    expect(fmtDur(65 * 60000), '1h 5m');
    expect(fmtDur(5 * 60000), '5 min');
    expect(durPart(30000), isEmpty);
    expect(exCount(1), '1 exercise');
    expect(setsWorkCount(3, 2), '3 sets · 2 work');
    expect(fmtAgo(0, 30 * 1000), 'now');
    expect(fmtAgo(0, 60 * 1000), '1 minute ago');
    expect(fmtAgo(0, 5 * 60 * 1000), '5 minutes ago');
    expect(fmtAgo(0, 86400 * 1000), 'yesterday');
    expect(fmtDaysAgo('2026-10-08', '2026-10-09'), 'yesterday');
    expect(fmtDaysAgo('2026-10-09', '2026-10-09'), 'today');
    expect(fmtDaysAgo('2026-09-25', '2026-10-09'), '2 weeks ago');
    expect(fmtDaysAgo('2026-09-01', '2026-10-09'), 'last month');
    expect(fmtDaysAgo('2025-09-01', '2026-10-09'), '1 Sep 2025');
  });

  test('weeks start on the profile weekday', () {
    expect(weekKey('2026-08-27'), '2026-08-24');
    expect(weekKey('2026-08-27', SUNDAY), '2026-08-23');
    expect(weekOrder(), [1, 2, 3, 4, 5, 6, 0]);
    expect(weekDayOffset(0), 6);
    expect(weekStartOf({'weekStart': 0}), SUNDAY);
    expect(capWords('barbell bench-press (wide)'), 'Barbell Bench-Press (Wide)');
    expect(argb('#cf3a76'), 0xffcf3a76);
  });
}
