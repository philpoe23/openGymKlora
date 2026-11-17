import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/data/store.dart';
import 'package:klora_app/engine/format.dart' show isoOf;
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/theme/theme.dart';
import 'package:klora_app/ui/screens/stats.dart';
import 'package:klora_app/ui/stats/stats_data.dart';
import 'package:klora_app/ui/widgets/charts.dart';
import 'package:klora_app/ui/widgets/common.dart';

import '../engine/_exdb.dart';
import 'ui_harness.dart';

DateTime _day(int ago) {
  final d = DateTime.now();
  return DateTime(d.year, d.month, d.day - ago, 12);
}

/// A bench session [ago] days back: two work sets of [w] × 5 (and a warm-up, not counted),
/// an hour long.
JMap _bench(String id, int ago, num w, {List<dynamic> prs = const [], List<dynamic> more = const []}) {
  final start = _day(ago).millisecondsSinceEpoch;
  return {
    'id': id,
    'name': 'Push $id',
    'd': isoOf(_day(ago)),
    'start': start,
    'end': start + 60 * 60000,
    'prs': prs,
    'entries': [
      {
        'id': '0025',
        'sets': [
          {'w': 20, 'r': 10, 'done': true, 'warmup': true},
          {'w': w, 'r': 5, 'done': true},
          {'w': w, 'r': 5, 'done': true},
        ],
      },
      ...more,
    ],
  };
}

/// Five sessions: today, 7, 14, 60 and 200 days back (4W holds 3, 12W 4, 1Y and All 5).
List<JMap> _fixture() => [
  _bench('w5', 200, 60),
  _bench('w4', 60, 62.5),
  _bench('w3', 14, 65, more: [
    {
      'id': '0289',
      'sets': [
        {'w': 24, 'r': 10, 'done': true},
      ],
    },
  ]),
  _bench('w2', 7, 67.5),
  _bench('w1', 0, 70, prs: ['0025']),
];

Finder _stat(String label, String value, [String? unit]) =>
    find.byWidgetPredicate((w) => w is KStatNumber && w.label == label && w.value == value && w.unit == unit, description: '$label = $value');

void main() {
  setUpAll(loadTestExerciseDb);

  Future<AppStore> seeded(WidgetTester tester, void Function(JMap s) fn) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    store.update(fn);
    return store;
  }

  Future<void> pumpStats(WidgetTester tester, AppStore store, {ThemeMode mode = ThemeMode.light}) async {
    await tester.pumpWidget(wrap(store, const Scaffold(body: StatsScreen()), mode: mode));
    await tester.pumpAndSettle();
  }

  testWidgets('summary numbers for the default 12-week period', (tester) async {
    final store = await seeded(tester, (s) => s['workouts'] = _fixture());
    await pumpStats(tester, store);

    expect(find.widgetWithText(KHeader, 'Stats'), findsOneWidget);
    expect(_stat('Workouts', '4'), findsOneWidget);
    // 2 × 5 × (62.5 + 65 + 67.5 + 70) + the dumbbell set's 240; warm-ups left out.
    expect(_stat('Volume', '2,890', 'kg'), findsOneWidget);
    expect(_stat('Time trained', '4', 'h'), findsOneWidget);
    expect(_stat('Per week', '0.3'), findsOneWidget);
    expect(find.byType(KBarChart), findsOneWidget);
    expect(find.text('VOLUME PER WEEK'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget); // the bar caption starts on the current week
  });

  testWidgets('switching the period changes the counts', (tester) async {
    final store = await seeded(tester, (s) => s['workouts'] = _fixture());
    await pumpStats(tester, store);

    await tester.tap(find.text('4W'));
    await tester.pumpAndSettle();
    expect(_stat('Workouts', '3'), findsOneWidget);
    expect(_stat('Volume', '2,265', 'kg'), findsOneWidget);
    expect(_stat('Time trained', '3', 'h'), findsOneWidget);
    expect(_stat('Per week', '0.8'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(_stat('Workouts', '5'), findsOneWidget);
    expect(_stat('Volume', '3,490', 'kg'), findsOneWidget);
    expect(find.text('VOLUME PER MONTH'), findsOneWidget);

    await tester.tap(find.text('1Y'));
    await tester.pumpAndSettle();
    expect(_stat('Workouts', '5'), findsOneWidget);
  });

  testWidgets('the e1RM chart follows the picked exercise and shows a point on tap', (tester) async {
    final store = await seeded(tester, (s) => s['workouts'] = _fixture());
    await pumpStats(tester, store);

    // The most-logged exercise is picked first: bench, 4 sessions in 12 weeks.
    expect(find.text('Barbell Bench Press'), findsWidgets);
    expect(_stat('Best est. 1RM', '81.7', 'kg'), findsOneWidget); // 70 × (1 + 5/30)
    expect(_stat('Best weight', '70', 'kg'), findsOneWidget);
    var chart = tester.widget<KLineChart>(find.byType(KLineChart));
    expect(chart.points.length, 4);
    expect(chart.points.last.y, 81.7);
    expect(chart.points.last.label, contains('70 kg × 5'));

    await tester.ensureVisible(find.byType(KLineChart));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(KLineChart));
    await tester.tapAt(Offset(box.right - 14, box.center.dy));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Dumbbell Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dumbbell Bench Press'));
    await tester.pumpAndSettle();
    chart = tester.widget<KLineChart>(find.byType(KLineChart));
    expect(chart.points.length, 1);
    expect(_stat('Best weight', '24', 'kg'), findsOneWidget);
  });

  testWidgets('a record opens its workout', (tester) async {
    final store = await seeded(tester, (s) => s['workouts'] = _fixture());
    await pumpStats(tester, store);

    expect(find.text('RECENT RECORDS'), findsOneWidget);
    final tile = find.ancestor(of: find.textContaining('70 kg × 5'), matching: find.byType(KCard));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(KHeader, 'Push w1'), findsOneWidget);
  });

  testWidgets('consistency and muscles this week render, in dark mode too', (tester) async {
    final store = await seeded(tester, (s) => s['workouts'] = _fixture());
    await pumpStats(tester, store, mode: ThemeMode.dark);

    expect(find.byType(KHeatGrid), findsOneWidget);
    expect(find.text('MUSCLES THIS WEEK'), findsOneWidget);
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('See all workouts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no workouts: the empty state', (tester) async {
    final store = await seeded(tester, (s) {});
    await pumpStats(tester, store);
    expect(find.text('Your progress shows up here after your first workout.'), findsOneWidget);
    expect(find.byType(KBarChart), findsNothing);
  });

  testWidgets('charts draw zero, one and NaN points, and lb', (tester) async {
    phone(tester);
    Future<void> chart(List<KPoint> pts) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: kloraLight(),
          home: Scaffold(body: Center(child: KLineChart(points: pts, empty: 'Nothing'))),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(KLineChart));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await chart(const []);
    expect(find.text('Nothing'), findsOneWidget);
    await chart(const [KPoint(x: double.nan, y: 100)]);
    expect(find.text('Nothing'), findsOneWidget);
    await chart(const [KPoint(x: 1, y: 100, label: '1 Jan')]);
    expect(find.text('Nothing'), findsNothing);
    await chart(const [KPoint(x: 1, y: 100), KPoint(x: double.nan, y: 1), KPoint(x: 2, y: 100)]);

    await tester.pumpWidget(
      MaterialApp(
        theme: kloraDark(),
        home: const Scaffold(body: KBarChart(bars: [])),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: kloraDark(),
        home: const Scaffold(
          body: KBarChart(bars: [KBar(value: 0, label: 'a'), KBar(value: double.nan, label: 'b'), KBar(value: 12345, label: 'c', hot: true)]),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    final store = await seeded(tester, (s) {
      s['unit'] = 'lb';
      s['workouts'] = _fixture();
    });
    await pumpStats(tester, store);
    expect(_stat('Volume', '2,890', 'lb'), findsOneWidget);
    expect(_stat('Best est. 1RM', '81.7', 'lb'), findsOneWidget);
  });

  group('stats data', () {
    const today = '2026-11-12'; // a Thursday
    final S = {
      'workouts': [
        {'id': 'a', 'd': '2026-01-05', 'entries': <dynamic>[]},
        {'id': 'b', 'd': '2026-10-20', 'entries': <dynamic>[]},
        {'id': 'c', 'd': '2026-11-10', 'entries': <dynamic>[]},
        {'id': 'd', 'd': '2026-11-12', 'entries': <dynamic>[]},
      ],
    };

    test('a period starts on the first day of its first week', () {
      final w4 = statsWindow(S, StatsPeriod.w4, today: today);
      expect(w4.from, '2026-10-19');
      expect(w4.weeks, 4);
      expect(workoutsIn(S, w4).map((w) => w['id']), ['d', 'c', 'b']);
      expect(statsWindow({...S, 'weekStart': 0}, StatsPeriod.w4, today: today).from, '2026-10-18');
      final all = statsWindow(S, StatsPeriod.all, today: today);
      expect(all.from, isNull);
      expect(all.weeks, 45); // the week of 5 Jan to the week of 9 Nov
    });

    test('weekly buckets end on the current week; long spans bucket by month', () {
      final b = volumeBuckets(S, statsWindow(S, StatsPeriod.w4, today: today));
      expect(b.map((x) => x.key), ['2026-10-19', '2026-10-26', '2026-11-02', '2026-11-09']);
      expect(b.map((x) => x.workouts), [1, 0, 0, 2]);
      expect(b.last.current, isTrue);
      final m = volumeBuckets(S, statsWindow(S, StatsPeriod.all, today: today));
      expect(m.length, 11);
      expect(m.first.key, '2026-01-01');
      expect(m.last.workouts, 2);
    });

    test('the average divides by the weeks trained so far, not the whole period', () {
      final fresh = {
        'workouts': [
          {'id': 'x', 'd': '2026-11-10', 'entries': <dynamic>[]},
        ],
      };
      final w = statsWindow(fresh, StatsPeriod.w12, today: today);
      expect(w.weeks, 1);
      expect(statsSummary(fresh, w).perWeek, 1);
    });

    test('the consistency grid stops at today', () {
      final g = consistencyGrid(S, today: today);
      expect(g.weekKeys.length, 12);
      expect(g.weekKeys.last, '2026-11-09');
      expect(g.cells.last, [0, 1, 0, 1, null, null, null]);
      expect(g.trainingDays, 3); // 20 Oct is inside the 12 weeks too
    });

    test('logged exercises: most sessions first, warm-up-only entries ignored', () {
      final s = {
        'workouts': [
          {
            'entries': [
              {'id': 'a', 'sets': [{'w': 1, 'r': 1, 'done': true}]},
              {'id': 'b', 'sets': [{'w': 1, 'r': 1, 'done': true}]},
              {'id': 'c', 'sets': [{'w': 1, 'r': 1, 'done': true, 'warmup': true}]},
            ],
          },
          {
            'entries': [
              {'id': 'b', 'sets': [{'w': 1, 'r': 1, 'done': true}]},
            ],
          },
        ],
      };
      expect(loggedExercises(s), ['b', 'a']);
    });
  });
}
