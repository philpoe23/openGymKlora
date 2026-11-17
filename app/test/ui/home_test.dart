import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/data/store.dart';
import 'package:klora_app/engine/format.dart' show DAYN, isoOf, jsDay, todayISO;
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/ui/screens/home.dart';
import 'package:klora_app/ui/shell.dart';
import 'package:klora_app/ui/widgets/common.dart';
import 'package:klora_app/ui/widgets/start_action.dart';
import 'package:klora_app/ui/widgets/workout_tile.dart';

import '../engine/_exdb.dart';
import 'ui_harness.dart';

JMap _push() => {
  'id': 'r1',
  'name': 'Push A',
  'ex': [
    {'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60},
    {'id': '0289', 'sets': 3, 'reps': 10, 'weight': 24},
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

  Future<List<List<String>?>> pumpHome(WidgetTester tester, AppStore store) async {
    final starts = <List<String>?>[];
    await tester.pumpWidget(
      wrap(
        store,
        StartAction(
          start: (context, {routineIds}) async => starts.add(routineIds),
          child: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return starts;
  }

  testWidgets('a planned day shows the routine, its exercises as chips, and Start', (tester) async {
    final dow = jsDay(DateTime.now());
    final store = await seeded(tester, (s) {
      s['routines'] = [_push()];
      s['week'] = {'$dow': 'r1'};
    });
    store.user = {'id': 'u1', 'name': 'Ana Silva'};
    final starts = await pumpHome(tester, store);

    expect(find.text('${greetingFor(DateTime.now())}, Ana'), findsOneWidget);
    expect(find.text('Push A'), findsOneWidget);
    expect(find.widgetWithText(KChip, 'Barbell Bench Press'), findsOneWidget);
    expect(find.widgetWithText(KChip, 'Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('2 exercises · 6 sets'), findsOneWidget);

    await tester.tap(find.text('Start workout'));
    await tester.pump();
    expect(starts, [
      ['r1'],
    ]);
  });

  testWidgets('a rest day says what is next and when', (tester) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final store = await seeded(tester, (s) {
      s['routines'] = [_push()];
      s['week'] = {'${jsDay(tomorrow)}': 'r1'};
    });
    await pumpHome(tester, store);

    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Next up: Push A on ${DAYN[jsDay(tomorrow)]}'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Train anyway'), findsOneWidget);
  });

  testWidgets('no routines at all: the coach has not sent a plan', (tester) async {
    final store = await seeded(tester, (s) {});
    await pumpHome(tester, store);
    expect(find.text('No plan yet'), findsOneWidget);
    expect(find.text('Open Coach'), findsOneWidget);
  });

  testWidgets('a quick weigh-in writes today’s entry into S.bodyweight', (tester) async {
    final yesterday = isoOf(DateTime.now().subtract(const Duration(days: 1)));
    final store = await seeded(tester, (s) {
      s['bodyweight'] = [
        {'d': yesterday, 'w': 73, 't': 1},
      ];
    });
    await pumpHome(tester, store);
    expect(find.text('73 kg'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log-weight')));
    await tester.pumpAndSettle();
    expect(find.text('Log body weight'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('weight-input')), '72.4');
    await tester.tap(find.byKey(const ValueKey('save-weight')));
    await tester.pumpAndSettle();

    final bw = store.S['bodyweight'] as List;
    expect(bw, hasLength(2));
    expect(bw.first, {'d': yesterday, 'w': 73, 't': 1});
    expect(bw.last['d'], todayISO());
    expect(bw.last['w'], 72.4);
    expect(bw.last['t'], isA<int>());
    expect(find.text('72.4 kg'), findsOneWidget);

    // A second weigh-in the same day replaces it.
    await tester.tap(find.byKey(const ValueKey('log-weight')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('weight-input')), '72');
    await tester.tap(find.byKey(const ValueKey('save-weight')));
    await tester.pumpAndSettle();
    expect(store.S['bodyweight'], hasLength(2));
    expect((store.S['bodyweight'] as List).last['w'], 72);
  });

  testWidgets('the coach card names the coach and what is waiting, and opens the Coach tab', (tester) async {
    phone(tester);
    final server = UiServer()
      ..training = {
        'trainer': {'name': 'Klora Coach'},
        'assignments': [
          {'id': 'a1', 'name': 'Leg day', 'accepted': null},
        ],
        'messages': <dynamic>[],
        'unread': 0,
      };
    final store = await makeStore(server, signedIn: true);
    addTearDown(store.dispose);
    await tester.runAsync(store.boot);
    final tabs = <int>[];
    await tester.pumpWidget(
      wrap(
        store,
        ShellNav(index: 0, goTo: tabs.add, child: const Scaffold(body: HomeScreen())),
        mode: ThemeMode.dark,
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('A new routine from your coach'), findsOneWidget);
    expect(find.text('From Klora Coach'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach-nudge')));
    expect(tabs, [3]);
  });

  test('logBodyWeight keeps the list in day order', () {
    final s = <String, dynamic>{
      'bodyweight': [
        {'d': '2026-11-10', 'w': 70, 't': 1},
      ],
    };
    logBodyWeight(s, 69.96, today: '2026-11-01', now: 5);
    expect(s['bodyweight'], [
      {'d': '2026-11-01', 'w': 70, 't': 5},
      {'d': '2026-11-10', 'w': 70, 't': 1},
    ]);
  });

  testWidgets('recent workouts show and lead to History', (tester) async {
    final today = todayISO();
    final store = await seeded(tester, (s) {
      s['workouts'] = [
        for (var i = 0; i < 4; i++)
          {
            'id': 'w$i',
            'name': 'Session $i',
            'd': today,
            'start': 1000,
            'end': 1000 + 45 * 60000,
            'entries': <dynamic>[],
          },
      ];
    });
    await pumpHome(tester, store);
    await tester.scrollUntilVisible(find.text('See all'), 200);
    expect(find.widgetWithText(WorkoutTile, 'Session 3'), findsOneWidget);
    expect(find.text('Session 0'), findsNothing);
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(KHeader, 'History'), findsOneWidget);
  });
}
