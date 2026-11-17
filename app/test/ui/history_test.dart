import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/data/store.dart';
import 'package:klora_app/engine/format.dart' show isoOf;
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/ui/screens/history.dart';
import 'package:klora_app/ui/widgets/common.dart';
import 'package:klora_app/ui/widgets/workout_tile.dart';

import '../engine/_exdb.dart';
import 'ui_harness.dart';

String _daysAgo(int n) {
  final d = DateTime.now();
  return isoOf(DateTime(d.year, d.month, d.day - n, 12));
}

JMap _bench(String id, String d, {List<dynamic> prs = const []}) => {
  'id': id,
  'name': 'Push A',
  'd': d,
  'start': 1700000000000,
  'end': 1700000000000 + 52 * 60000,
  'routineIds': ['r1'],
  'prs': prs,
  'entries': [
    {
      'id': '0025',
      'sets': [
        {'w': 40, 'r': 8, 'done': true, 'warmup': true},
        {'w': 60, 'r': 5, 'done': true},
        {'w': 60, 'r': 5, 'done': true},
        {'w': 60, 'r': 5, 'done': false},
      ],
    },
    {
      'id': '0289',
      'sets': [
        {'w': 24, 'r': 10, 'done': true},
      ],
    },
  ],
};

void main() {
  setUpAll(loadTestExerciseDb);

  Future<AppStore> seeded(WidgetTester tester, void Function(JMap s) fn) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    store.update(fn);
    return store;
  }

  testWidgets('groups workouts by week, newest first', (tester) async {
    final store = await seeded(tester, (s) {
      s['workouts'] = [
        {..._bench('w3', _daysAgo(14)), 'name': 'Legs'},
        {..._bench('w2', _daysAgo(7)), 'name': 'Pull A'},
        _bench('w1', _daysAgo(0), prs: ['0025']),
      ];
    });
    await tester.pumpWidget(wrap(store, const HistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(KHeader, 'History'), findsOneWidget);
    expect(find.text('3 workouts'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('LAST WEEK'), findsOneWidget);
    expect(find.byType(WorkoutTile), findsNWidgets(3));

    final y = [for (final n in ['Push A', 'Pull A', 'Legs']) tester.getTopLeft(find.text(n)).dy];
    expect(y[0] < y[1] && y[1] < y[2], isTrue);
    expect(tester.getTopLeft(find.text('THIS WEEK')).dy < y[0], isTrue);
    expect(tester.getTopLeft(find.text('LAST WEEK')).dy, inExclusiveRange(y[0], y[1]));

    // Duration · sets done (work and warm-up) · volume of work sets.
    expect(find.text('52 min · 4 sets · 840 kg'), findsNWidgets(3));
    expect(find.text('PR'), findsOneWidget);
  });

  testWidgets('the detail lists each exercise’s sets, warm-ups marked', (tester) async {
    final store = await seeded(tester, (s) {
      s['workouts'] = [
        _bench('w1', _daysAgo(0), prs: ['0025']),
      ];
    });
    await tester.pumpWidget(wrap(store, const HistoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WorkoutTile));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(KHeader, 'Push A'), findsOneWidget);
    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('40×8'), findsOneWidget);
    expect(find.text('60×5'), findsNWidgets(2)); // the unfinished third set is not listed
    expect(find.text('24×10'), findsOneWidget);
    expect(find.text('warm-up'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.byKey(const ValueKey('set-0-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('set-0-2')), findsOneWidget);
    expect(find.text('A personal record'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(KHeader, 'History'), findsOneWidget);
  });

  testWidgets('no workouts: an empty state', (tester) async {
    final store = await seeded(tester, (s) {});
    await tester.pumpWidget(wrap(store, const HistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('No workouts yet'), findsOneWidget);
  });

  test('historyWeeks keeps same-day workouts in stored-later-first order', () {
    final S = {
      'weekStart': 1,
      'workouts': [
        {'id': 'a', 'd': '2026-11-10'},
        {'id': 'b', 'd': '2026-11-10'},
        {'id': 'c', 'd': '2026-11-02'},
      ],
    };
    final weeks = historyWeeks(S);
    expect(weeks.map((w) => w.key), ['2026-11-09', '2026-11-02']);
    expect(weeks[0].workouts.map((w) => w['id']), ['b', 'a']);
    expect(weekLabel('2026-10-26', S, today: '2026-11-13'), '26 Oct – 1 Nov');
    expect(weekLabel('2026-11-02', S, today: '2026-11-13'), 'Last week');
  });
}
