// The workout logger end to end: starting (a routine, the Start pill's chooser, the weigh-in),
// the stepper and the number pad, ticking a set into the rest bar, Prev / Next, and Finish into
// the summary with its PR and the coach check-in.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/data/store.dart';
import 'package:klora_app/engine/format.dart' show todayISO;
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/progression.dart' show weightIncrement;
import 'package:klora_app/ui/screens/finish.dart';
import 'package:klora_app/ui/screens/home.dart';
import 'package:klora_app/ui/screens/workout.dart';
import 'package:klora_app/ui/shell.dart';
import 'package:klora_app/ui/widgets/start_action.dart';
import 'package:klora_app/ui/workout/rest_timer.dart';
import 'package:klora_app/ui/workout/session_ops.dart';
import 'package:klora_app/ui/workout/workout_device.dart';

import '../engine/_exdb.dart';
import 'ui_harness.dart';

List<dynamic> _routines() => [
  {
    'id': 'r1',
    'name': 'Push A',
    'ex': [
      {'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60},
      {'id': '0289', 'sets': 2, 'reps': 10, 'weight': 24},
    ],
  },
];

JMap _history() => {
  'id': 'w0',
  'd': '2026-11-01',
  'start': 1,
  'end': 2,
  'routineIds': ['r1'],
  'routineId': 'r1',
  'name': 'Push A',
  'entries': [
    {
      'id': '0025',
      'rid': 'r1',
      'sets': [
        {'w': 50, 'r': 5, 'done': true},
      ],
    },
  ],
};

void main() {
  setUpAll(loadTestExerciseDb);

  late FakeWorkoutDevice device;
  late DateTime now;

  setUp(() {
    device = FakeWorkoutDevice();
    WorkoutDevice.instance = device;
    now = DateTime(2026, 11, 13, 10);
    RestTimer.instance = RestTimer(clock: () => now);
  });

  /// Unmounts and stops the rest, so no clock is left ticking past the test.
  Future<void> done(WidgetTester tester) async {
    RestTimer.instance.stop();
    await tester.pumpWidget(const SizedBox());
  }

  JMap active(AppStore store) => asMap(store.S['active']);
  List<dynamic> sets(AppStore store, int idx) => asList(asMap((active(store)['entries'] as List)[idx])['sets']);

  Future<AppStore> logger(WidgetTester tester, {UiServer? server, bool signedIn = false, List<dynamic>? workouts}) async {
    phone(tester);
    final store = await makeStore(server ?? UiServer(), signedIn: signedIn);
    addTearDown(store.dispose);
    if (signedIn) await tester.runAsync(store.boot);
    store.update((s) {
      s['routines'] = _routines();
      s['workouts'] = workouts ?? <dynamic>[];
      s['active'] = buildActive(s, ['r1'], null);
    });
    await tester.pumpWidget(wrap(store, const WorkoutScreen()));
    await tester.pumpAndSettle();
    return store;
  }

  group('starting', () {
    testWidgets('starting from a routine creates S.active with its entries and opens the logger', (tester) async {
      phone(tester);
      final store = await makeStore(UiServer());
      addTearDown(store.dispose);
      store.update((s) => s['routines'] = _routines());
      await tester.pumpWidget(wrap(store, const Shell()));
      await tester.pump();

      unawaited(startWorkout(tester.element(find.byType(HomeScreen)), routineIds: ['r1']));
      await tester.pumpAndSettle();

      final A = active(store);
      expect(A['name'], 'Push A');
      expect(A['routineIds'], ['r1']);
      expect(A['d'], todayISO());
      expect((A['entries'] as List).map((e) => e['id']), ['0025', '0289']);
      expect(find.byType(WorkoutScreen), findsOneWidget);
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(device.calls, contains('permissions'));
      expect(device.awake, isTrue);

      // Back out: the session keeps running, the pill reads Resume, and it opens the same one.
      await tester.tap(find.byKey(const ValueKey('workout-close')));
      await tester.pumpAndSettle();
      expect(device.awake, isFalse);
      expect(find.text('Resume'), findsOneWidget);
      final id = A['id'];
      await tester.tap(find.byKey(const ValueKey('start-pill')));
      await tester.pumpAndSettle();
      expect(active(store)['id'], id);
      expect(find.byType(WorkoutScreen), findsOneWidget);
      await done(tester);
    });

    testWidgets('the Start pill with nothing planned today offers the routines or freestyle', (tester) async {
      phone(tester);
      final store = await makeStore(UiServer());
      addTearDown(store.dispose);
      store.update((s) => s['routines'] = _routines());
      await tester.pumpWidget(wrap(store, const Shell()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('start-pill')));
      await tester.pumpAndSettle();
      expect(find.text('Start a workout'), findsOneWidget);
      expect(store.S['active'], isNull);

      await tester.tap(find.byKey(const ValueKey('start-freestyle')));
      await tester.pumpAndSettle();
      expect(active(store)['name'], 'Freestyle');
      expect(active(store)['entries'], isEmpty);
      expect(find.text('Add your first exercise and off you go.'), findsOneWidget);
      await done(tester);
    });

    testWidgets('with the weigh-in on, the body weight is asked first and stored on the session', (tester) async {
      phone(tester);
      final store = await makeStore(UiServer());
      addTearDown(store.dispose);
      store.update((s) {
        s['routines'] = _routines();
        s['weighIn'] = true;
        s['bodyweight'] = [
          {'d': '2026-11-01', 'w': 71.5},
        ];
      });
      await tester.pumpWidget(wrap(store, const Shell()));
      await tester.pump();

      unawaited(startWorkout(tester.element(find.byType(HomeScreen)), routineIds: ['r1']));
      await tester.pumpAndSettle();
      expect(find.text('Weigh in'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('weighin-start')));
      await tester.pumpAndSettle();

      expect(active(store)['bw'], 71.6);
      expect((store.S['bodyweight'] as List).last['d'], todayISO());
      expect((store.S['bodyweight'] as List).last['w'], 71.6);
      await done(tester);
    });
  });

  group('logging', () {
    testWidgets('the weight stepper moves by the exercise’s increment and carries to later sets', (tester) async {
      final store = await logger(tester);
      final inc = weightIncrement(cfgOf((active(store)['entries'] as List)[0]), 'kg');

      await tester.tap(find.byKey(const ValueKey('plus-w-0-0')));
      await tester.pump();
      expect(sets(store, 0).map((s) => s['w']), [60 + inc, 60 + inc, 60 + inc]);

      await tester.tap(find.byKey(const ValueKey('minus-w-0-0')));
      await tester.tap(find.byKey(const ValueKey('minus-w-0-0')));
      await tester.pump();
      expect(sets(store, 0)[0]['w'], 60 - inc);

      await tester.tap(find.byKey(const ValueKey('plus-r-0-0')));
      await tester.pump();
      expect(sets(store, 0).map((s) => s['r']), [6, 5, 5]);
      await done(tester);
    });

    testWidgets('tapping a value opens the number pad', (tester) async {
      final store = await logger(tester);
      await tester.tap(find.byKey(const ValueKey('val-r-0-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pad-8')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pad-done')));
      await tester.pumpAndSettle();
      expect(sets(store, 0)[0]['r'], 8);

      await tester.tap(find.byKey(const ValueKey('val-w-0-0')));
      await tester.pumpAndSettle();
      for (final k in ['6', '2', '.', '5']) {
        await tester.tap(find.byKey(ValueKey('pad-$k')));
        await tester.pump();
      }
      expect(find.textContaining('62.5', findRichText: true), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pad-done')));
      await tester.pumpAndSettle();
      expect(sets(store, 0)[0]['w'], 62.5);
      await done(tester);
    });

    testWidgets('ticking a set marks it done, buzzes, and docks the rest timer', (tester) async {
      final store = await logger(tester);
      expect(find.byKey(const ValueKey('rest-bar')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tick-0-0')));
      await tester.pumpAndSettle();
      expect(sets(store, 0)[0]['done'], isTrue);
      expect(sets(store, 0)[0]['at'], isA<int>());
      expect(device.calls, contains('tick'));
      expect(find.byKey(const ValueKey('rest-bar')), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);

      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1:20'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rest-plus')));
      await tester.pump();
      expect(find.text('1:35'), findsOneWidget);

      // The next open row is set 2 now.
      expect(find.byKey(const ValueKey('plus-w-0-1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rest-skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rest-bar')), findsNothing);

      // Unticking puts it back.
      await tester.tap(find.byKey(const ValueKey('tick-0-0')));
      await tester.pumpAndSettle();
      expect(sets(store, 0)[0]['done'], isFalse);
      expect(find.byKey(const ValueKey('rest-bar')), findsNothing);
      await done(tester);
    });

    testWidgets('Next and Prev walk the exercises; the set menu copies and removes', (tester) async {
      final store = await logger(tester);
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      expect(active(store)['cur'], 1);
      expect(find.text('Exercise 2 of 2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('badge-1-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-copy-set')));
      await tester.pumpAndSettle();
      expect(sets(store, 1).length, 3);

      await tester.tap(find.byKey(const ValueKey('badge-1-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-remove-set')));
      await tester.pumpAndSettle();
      expect(sets(store, 1).length, 2);

      // Let the "Copied" toast go from over the buttons.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('prev')));
      await tester.pumpAndSettle();
      expect(active(store)['cur'], 0);
      await done(tester);
    });

    testWidgets('dark mode renders the logger, a superset and the rest bar', (tester) async {
      phone(tester);
      final store = await makeStore(UiServer());
      addTearDown(store.dispose);
      store.update((s) {
        s['routines'] = [
          {
            'id': 'r1',
            'name': 'Arms',
            'ex': [
              {'id': '0025', 'sets': 2, 'reps': 5, 'weight': 60, 'sg': 'a'},
              {'id': '0289', 'sets': 2, 'reps': 10, 'weight': 24, 'sg': 'a'},
            ],
          },
        ];
        s['active'] = buildActive(s, ['r1'], null);
      });
      await tester.pumpWidget(wrap(store, const WorkoutScreen(), mode: ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(find.text('Superset 1 of 1'), findsOneWidget);
      expect(find.text('Superset · do these back-to-back, rest when done'), findsOneWidget);
      // Ticking the first member moves on to the second, with no rest until the round is done.
      await tester.tap(find.byKey(const ValueKey('tick-0-0')));
      await tester.pumpAndSettle();
      expect(active(store)['cur'], 1);
      expect(find.byKey(const ValueKey('rest-bar')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tick-1-0')));
      await tester.pumpAndSettle();
      expect(active(store)['cur'], 0);
      expect(find.byKey(const ValueKey('rest-bar')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await done(tester);
    });

    testWidgets('Discard ends the session without saving it', (tester) async {
      final store = await logger(tester);
      await tester.tap(find.byKey(const ValueKey('workout-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(store.S['active'], isNull);
      expect(store.S['workouts'], isEmpty);
      await done(tester);
    });
  });

  group('finishing', () {
    testWidgets('finish saves the workout with its volume and PR, keeps the best weight and shows the summary', (tester) async {
      final store = await logger(tester, workouts: [_history()]);
      store.update((s) {
        for (final r in asList((s['active']['entries'] as List)[0]['sets'])) {
          (r as Map)
            ..['w'] = 70
            ..['done'] = true
            ..['at'] = DateTime.now().millisecondsSinceEpoch;
        }
      });
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('workout-finish')));
      await tester.pumpAndSettle();
      // Two sets of the second exercise are still unchecked.
      expect(find.text('Finish early?'), findsOneWidget);
      expect(find.text('2 sets still unchecked. Finish the workout now?'), findsOneWidget);
      await tester.tap(find.text('Finish workout'));
      await tester.pumpAndSettle();

      expect(store.S['active'], isNull);
      final workouts = store.S['workouts'] as List;
      expect(workouts.length, 2);
      final w = asMap(workouts.last);
      expect(w['vol'], 70 * 5 * 3);
      expect(w['prs'], ['0025']);
      expect(w['name'], 'Push A');
      expect((w['entries'] as List).map((e) => e['id']), ['0025']);
      expect(store.S['exWeights']['0025']['w'], 70);

      expect(find.byType(FinishScreen), findsOneWidget);
      expect(find.text('Workout complete!'), findsOneWidget);
      expect(find.byKey(const ValueKey('pr-0025')), findsOneWidget);
      expect(find.text('New PR · 70 kg'), findsOneWidget);
      // Signed out: no coach to check in with.
      expect(find.byKey(const ValueKey('send-checkin')), findsNothing);
      await done(tester);
    });

    testWidgets('ticking the last set offers to finish; the check-in goes to the coach', (tester) async {
      final server = UiServer();
      final store = await logger(tester, server: server, signedIn: true);
      store.update((s) {
        for (final e in asList(s['active']['entries'])) {
          final rows = asList(e['sets']);
          for (var i = 0; i < rows.length; i++) {
            if (e['id'] == '0289' && i == rows.length - 1) continue;
            (rows[i] as Map)
              ..['done'] = true
              ..['at'] = DateTime.now().millisecondsSinceEpoch;
          }
        }
        s['active']['cur'] = 1;
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tick-1-1')));
      await tester.pumpAndSettle();
      // The session's last set: no rest, the finish question instead.
      expect(find.byKey(const ValueKey('rest-bar')), findsNothing);
      expect(find.text('Every set done'), findsOneWidget);
      await tester.tap(find.text('Finish workout'));
      await tester.pumpAndSettle();
      expect(find.byType(FinishScreen), findsOneWidget);

      final w = asMap((store.S['workouts'] as List).last);
      final text = checkInText(w, 'kg');
      expect(text, startsWith('Finished Push A — 5 sets, '));
      await tester.tap(find.byKey(const ValueKey('send-checkin')));
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('checkin-send')));
      await tester.pumpAndSettle();
      expect(server.sent, [text]);
      expect(find.text('Sent to your coach'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 4));
      await done(tester);
    });
  });
}
