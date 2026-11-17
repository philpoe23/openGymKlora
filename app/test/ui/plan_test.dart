import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/data/store.dart';
import 'package:klora_app/engine/exercises.dart' show CATALOGUE;
import 'package:klora_app/engine/format.dart' show jsDay, todayISO;
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/ui/screens/plan.dart';
import 'package:klora_app/ui/shell.dart';
import 'package:klora_app/ui/widgets/common.dart';
import 'package:klora_app/ui/widgets/start_action.dart';

import '../engine/_exdb.dart';
import 'ui_harness.dart';

List<dynamic> _routines() => [
  {
    'id': 'r1',
    'name': 'Push A',
    'ex': [
      {'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60, 'note': 'pause on the chest'},
      {'id': '0289', 'sets': 3, 'reps': 10, 'weight': 24},
    ],
  },
  {
    'id': 'r2',
    'name': 'Legs',
    'ex': [
      {'id': '0043', 'sets': 5, 'reps': 5, 'weight': 100},
    ],
  },
];

void main() {
  setUpAll(loadTestExerciseDb);

  Future<AppStore> seeded(WidgetTester tester, void Function(JMap s) fn) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    store.update(fn);
    return store;
  }

  Future<(List<List<String>?>, List<int>)> pumpPlan(WidgetTester tester, AppStore store) async {
    final starts = <List<String>?>[];
    final tabs = <int>[];
    await tester.pumpWidget(
      wrap(
        store,
        ShellNav(
          index: 1,
          goTo: tabs.add,
          child: StartAction(
            start: (context, {routineIds}) async => starts.add(routineIds),
            child: const Scaffold(body: PlanScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (starts, tabs);
  }

  testWidgets('the week and the routines render; a routine opens to its exercises', (tester) async {
    final store = await seeded(tester, (s) {
      s['routines'] = _routines();
      s['week'] = {'1': 'r1', '3': 'r2', '5': 'r1'};
    });
    final (starts, _) = await pumpPlan(tester, store);

    expect(find.widgetWithText(KHeader, 'Plan'), findsOneWidget);
    expect(find.text('Your weekly routine'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('Rest day'), findsNWidgets(4));
    expect(find.text('Push A'), findsNWidgets(3)); // Mon, Fri, and its card
    expect(find.text('2 exercises · Mo, Fr'), findsOneWidget);
    expect(find.text('1 exercise · We'), findsOneWidget);

    // Collapsed until tapped.
    expect(find.text('Barbell Bench Press'), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('routine-r1')), 200);
    await tester.tap(find.byKey(const ValueKey('routine-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('3 × 5 · 60 kg'), findsOneWidget);
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('start-r1')), 200);
    await tester.tap(find.byKey(const ValueKey('start-r1')));
    await tester.pump();
    expect(starts, [
      ['r1'],
    ]);
  });

  testWidgets('swap replaces the exercise id in that slot and keeps its sets, reps and load', (tester) async {
    final store = await seeded(tester, (s) {
      s['routines'] = _routines();
      s['week'] = {'1': 'r1'};
    });
    await pumpPlan(tester, store);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('routine-r1')), 200);
    await tester.tap(find.byKey(const ValueKey('routine-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap-r1-0')));
    await tester.pumpAndSettle();
    expect(find.text('Swap exercise'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('exercise-search')), 'smith bench press');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-0748')));
    await tester.pumpAndSettle();

    final ex = (store.S['routines'] as List)[0]['ex'] as List;
    expect(ex[0], {'id': '0748', 'sets': 3, 'reps': 5, 'weight': 60, 'note': 'pause on the chest'});
    expect(ex[1]['id'], '0289');
    expect((store.S['routines'] as List)[1]['ex'][0]['id'], '0043');
    expect(find.text('Smith Bench Press'), findsWidgets);
  });

  testWidgets('a live coach week shows the loop in order with what is next', (tester) async {
    final store = await seeded(tester, (s) {
      s['routines'] = _routines();
      s['week'] = <String, dynamic>{};
      s['queue'] = {
        'ids': ['r1', 'r2'],
        'label': 'Week 1',
        'since': 0,
        'startsOn': todayISO(),
      };
      s['workouts'] = [
        {
          'id': 'w1',
          'd': todayISO(),
          'start': DateTime.now().millisecondsSinceEpoch,
          'routineIds': ['r1'],
          'name': 'Push A',
          'entries': <dynamic>[],
        },
      ];
    });
    await pumpPlan(tester, store);
    expect(find.text('Your routines in a loop'), findsOneWidget);
    expect(find.text('WEEK 1'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsNothing);
  });

  testWidgets('no routines: the coach has not sent a plan, and a way to the Coach tab', (tester) async {
    final store = await seeded(tester, (s) {});
    final (_, tabs) = await pumpPlan(tester, store);
    expect(find.text('No plan yet'), findsOneWidget);
    expect(find.text('Your coach hasn’t sent a plan yet — routines they assign show up here.'), findsOneWidget);
    await tester.tap(find.text('Go to Coach'));
    expect(tabs, [3]);
  });

  group('swapSlot', () {
    test('keeps everything but the id; same id is a copy', () {
      final slot = {'id': '0025', 'sets': 4, 'reps': 8, 'repsMin': 6, 'weight': 70, 'sg': 'a', 'restSec': 120};
      expect(swapSlot(slot, '0289'), {'id': '0289', 'sets': 4, 'reps': 8, 'repsMin': 6, 'weight': 70, 'sg': 'a', 'restSec': 120});
      expect(swapSlot(slot, '0025'), slot);
    });

    test('loaded to bodyweight resets the load and drops the rep ceiling', () {
      final pushUp = _firstWithEq('body weight', 'pectorals');
      final out = swapSlot({'id': '0025', 'sets': 3, 'reps': 10, 'repsMax': 15, 'weight': 60}, pushUp);
      expect(out['id'], pushUp);
      expect(out['weight'], 0);
      expect(out.containsKey('repsMax'), isFalse);
      expect(out['sets'], 3);
    });

    test("the new exercise's last session in the routine sets the slot's weight", () {
      final slot = {'id': '0025', 'sets': 2, 'mode': 'reps', 'reps': 10, 'weight': 80};
      Map<String, dynamic> workout(String rid, Map<String, dynamic> entry) => {
        'id': 'w-$rid', 'd': '2026-08-01', 'start': 1000, 'routineIds': [rid], 'routineId': rid, 'name': 'x',
        'entries': [entry],
      };
      final dbSets = [
        {'w': 30, 'r': 10, 'done': true},
        {'w': 30, 'r': 10, 'done': true},
      ];
      // Planned at 28, lifted 30: the planned weight goes in (the restart rule sees no edit).
      final planned = {
        'workouts': [
          workout('A', {'id': '0289', 'sets': dbSets, 'planned': {'sets': 2, 'reps': 10, 'weight': 28}}),
        ],
      };
      expect(swapSlot(slot, '0289', planned, 'A')['weight'], 28);
      // A session saved before plans were stamped: what was lifted.
      final unplanned = {
        'workouts': [workout('B', {'id': '0289', 'sets': dbSets})],
      };
      expect(swapSlot(slot, '0289', unplanned, 'A')['weight'], 30);
      // Never logged: the slot's own weight stays.
      expect(swapSlot(slot, '0289', {'workouts': <dynamic>[]}, 'A')['weight'], 80);
    });

    test('lifting to cardio starts from the cardio defaults, keeping superset, note and rest', () {
      final run = _firstCardio();
      final out = swapSlot({'id': '0025', 'sets': 3, 'reps': 10, 'weight': 60, 'sg': 'x', 'note': 'n', 'restSec': 60}, run);
      expect(out, {'id': run, 'sets': 1, 'min': 20, 'speed': 8, 'sg': 'x', 'note': 'n', 'restSec': 60});
    });
  });

  test('dayRoutineIds reads one id or a list and skips routines that are gone', () {
    final S = {
      'routines': _routines(),
      'week': {
        '1': 'r1',
        '2': ['r1', 'gone', 'r2'],
      },
    };
    expect(dayRoutineIds(S, 1), ['r1']);
    expect(dayRoutineIds(S, 2), ['r1', 'r2']);
    expect(dayRoutineIds(S, jsDay(DateTime(2026, 11, 15))), isEmpty);
  });
}

String _firstWithEq(String eq, String tg) {
  for (final e in _catalogue()) {
    if (e['eq'] == eq && e['tg'] == tg && e['bp'] != 'cardio') return e['id'] as String;
  }
  throw StateError('none');
}

String _firstCardio() {
  for (final e in _catalogue()) {
    if (e['bp'] == 'cardio') return e['id'] as String;
  }
  throw StateError('none');
}

List<Map<String, dynamic>> _catalogue() => [for (final e in CATALOGUE) asMap(e)];
