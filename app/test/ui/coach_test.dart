import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/app_wiring.dart';
import 'package:klora_app/data/store.dart';
import 'package:klora_app/engine/plan_share.dart';
import 'package:klora_app/ui/screens/coach.dart';
import 'package:klora_app/ui/shell.dart';
import 'package:klora_app/ui/widgets/common.dart';

import '../engine/_exdb.dart';
import 'ui_harness.dart';

void main() {
  final now = DateTime.now().millisecondsSinceEpoch;

  UiServer serverWithTraining() => UiServer()
    ..training = {
      'trainer': {'name': 'Klora Coach'},
      'assignments': [
        {
          'id': 'a1',
          'at': now,
          'name': 'Leg day',
          'note': 'Go easy in week one.',
          'routines': 1,
          'exercises': 5,
          'bundle': {
            'opengym_plan': 1,
            'routines': [
              {'name': 'Leg day', 'ex': []},
            ],
          },
          'accepted': null,
        },
        {'id': 'a0', 'at': now - 86400000 * 3, 'name': 'Push A', 'note': '', 'exercises': 4, 'bundle': {}, 'accepted': now - 86400000},
      ],
      'messages': [
        {'id': 'm1', 'from': 'trainer', 'text': 'How did the squats feel?', 'at': now - 60000},
        {'id': 'm2', 'from': 'client', 'text': 'Heavy but good!', 'at': now - 30000},
      ],
      'unread': 1,
    };

  Future<AppStore> pumpCoach(WidgetTester tester, UiServer server, ValueNotifier<int> badge,
      {AddPlan? addPlan, AddPlan Function(AppStore store)? wire}) async {
    phone(tester);
    final store = await makeStore(server, signedIn: true);
    addTearDown(store.dispose);
    await tester.runAsync(store.boot);
    addPlan ??= wire?.call(store);
    await tester.pumpWidget(
      wrap(
        store,
        CoachBadge(
          notifier: badge,
          child: Scaffold(body: CoachScreen(addPlan: addPlan)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('renders the trainer, a new assignment, the thread and the plan list', (tester) async {
    final server = serverWithTraining();
    final badge = ValueNotifier<int>(0);
    await pumpCoach(tester, server, badge);

    expect(find.widgetWithText(KHeader, 'Coach'), findsOneWidget);
    expect(find.text('A new routine from your coach'), findsOneWidget);
    expect(find.text('Klora Coach'), findsOneWidget);
    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Go easy in week one.'), findsOneWidget);
    expect(find.text('Add to my plan'), findsOneWidget);
    expect(find.text('How did the squats feel?'), findsOneWidget);
    expect(find.text('Heavy but good!'), findsOneWidget);
    expect(find.text('Finished today’s session'), findsOneWidget);
    await tester.ensureVisible(find.text('Push A'));
    expect(find.text('Push A'), findsOneWidget);

    // On screen, the thread is marked read: the badge counts the new routine only.
    final training = server.requests.where((r) => r.url.path == '/api/client/training').first;
    expect(training.url.query, 'read=1');
    expect(badge.value, 1);
  });

  testWidgets('Add to my plan without the engine says it is coming', (tester) async {
    final badge = ValueNotifier<int>(0);
    await pumpCoach(tester, serverWithTraining(), badge);
    await tester.tap(find.text('Add to my plan'));
    await tester.pump();
    expect(find.text('Coming soon'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('Add to my plan hands over the bundle and accepts the assignment', (tester) async {
    final server = serverWithTraining();
    final badge = ValueNotifier<int>(0);
    Map<String, dynamic>? got;
    await pumpCoach(
      tester,
      server,
      badge,
      addPlan: (b) async {
        got = b;
        return 1;
      },
    );
    await tester.tap(find.text('Add to my plan'));
    await tester.pumpAndSettle();
    expect(got?['opengym_plan'], 1);
    expect(server.requests.any((r) => r.url.path == '/api/client/assignment/accept'), isTrue);
    expect(find.text('Added 1 routine to your plan'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('Add to my plan with the engine adds the trainer’s routines to the plan', (tester) async {
    loadTestExerciseDb();
    // The bundle the trainer side sends (trainer.js draftBundle): buildPlanBundle over the days.
    final bundle = buildPlanBundle({
      'unit': 'kg',
      'customEx': <dynamic>[],
      'week': <String, dynamic>{},
      'routines': <dynamic>[
        {'id': 'd1', 'name': 'Leg day', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60}]},
        {'id': 'd2', 'name': 'Push day', 'ex': [{'id': '0031', 'sets': 3, 'reps': 8}]},
      ],
    }, 'Leg day');
    final server = serverWithTraining();
    ((server.training['assignments'] as List)[0] as Map)['bundle'] = bundle;
    final badge = ValueNotifier<int>(0);
    final store = await pumpCoach(tester, server, badge, wire: addPlanFor);
    final before = (store.S['routines'] as List? ?? const []).length;

    await tester.tap(find.text('Add to my plan'));
    await tester.pumpAndSettle();

    final routines = store.S['routines'] as List;
    expect(routines.length, before + 2);
    final added = routines.sublist(before);
    expect(added.map((r) => r['name']).toList(), ['Leg day', 'Push day']);
    expect(added.first['id'], isNot('d1')); // new routines, fresh ids
    expect(added.first['ex'][0], containsPair('weight', 60));
    expect(server.requests.any((r) => r.url.path == '/api/client/assignment/accept'), isTrue);
    expect(find.text('Added 2 routines to your plan'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('Add to my plan with a bundle that is not a plan says why, and adds nothing', (tester) async {
    loadTestExerciseDb();
    final server = serverWithTraining();
    ((server.training['assignments'] as List)[0] as Map)['bundle'] = {'routines': []};
    final badge = ValueNotifier<int>(0);
    final store = await pumpCoach(tester, server, badge, wire: addPlanFor);
    final before = (store.S['routines'] as List? ?? const []).length;

    await tester.tap(find.text('Add to my plan'));
    await tester.pump();
    expect(find.text('Couldn’t read that plan: this isn’t an openGym plan file'), findsOneWidget);
    expect((store.S['routines'] as List? ?? const []).length, before);
    expect(server.requests.any((r) => r.url.path == '/api/client/assignment/accept'), isFalse);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('a quick reply is sent to the coach', (tester) async {
    final server = serverWithTraining();
    final badge = ValueNotifier<int>(0);
    await pumpCoach(tester, server, badge);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feeling sore today'));
    await tester.pumpAndSettle();
    expect(server.sent, ['Feeling sore today']);
    expect(find.text('Feeling sore today'), findsNWidgets(2)); // the chip and the new bubble
  });

  testWidgets('a failed load offers Try again', (tester) async {
    final server = UiServer();
    final badge = ValueNotifier<int>(0);
    final store = await makeStore(server); // signed out: no api
    addTearDown(store.dispose);
    await tester.pumpWidget(
      wrap(
        store,
        CoachBadge(
          notifier: badge,
          child: const Scaffold(body: CoachScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load your coaching'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
