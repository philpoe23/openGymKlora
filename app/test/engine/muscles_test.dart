// Port of frontend/src/lib/muscles.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';
import 'package:klora_app/engine/muscles.dart';

import '_exdb.dart';
import '_helpers.dart';

void main() {
  setUpAll(loadTestExerciseDb);

  group('multi-muscle exercise metadata', () {
    test('normalizes legacy primary/secondary fields and removes duplicate groups', () {
      final ex = {'tg': 'pectorals', 'mg': 'triceps', 'sm': ['triceps', 'chest']};
      expect(muscleGroupsOf(ex), ['chest', 'triceps']);
      expect(musclesOf(ex), jeq({'chest': 1, 'triceps': 0.4}));
    });

    test('uses explicit multi-group metadata when present and supports legacy single groups', () {
      expect(muscleGroupsOf({'muscleGroups': ['chest', 'pectorals', 'triceps']}), ['chest', 'triceps']);
      expect(muscleGroupsOf({'tg': 'chest'}), ['chest']);
      expect(MUSCLE_NAME['chest'], 'Chest');
    });

    test('falls back to the legacy body-part map when an optional multi-group field is empty', () {
      expect(muscleGroupsOf({'bp': 'back', 'muscleGroups': []}), ['upper-back', 'lower-back']);
      expect(matchesMuscleGroups({'bp': 'back', 'muscleGroups': []}, ['lower-back']), isTrue);
    });

    test('falls back consistently when explicit groups contain only unknown names', () {
      final ex = {'bp': 'back', 'muscleGroups': ['not-a-drawable-name']};
      expect(muscleGroupsOf(ex), ['upper-back', 'lower-back']);
      expect(musclesOf(ex), jeq({'upper-back': 0.75, 'lower-back': 0.25}));
    });

    test('matches an exercise when any requested muscle group matches', () {
      final ex = {'muscleGroups': ['chest', 'triceps']};
      expect(matchesMuscleGroups(ex, ['hamstring', 'triceps']), isTrue);
      expect(matchesMuscleGroups(ex, ['hamstring', 'gluteal']), isFalse);
      expect(matchesMuscleGroups(ex, []), isTrue);
    });

    test('counts one effective set per unique group instead of double counting duplicates', () {
      expect(loadOf([{'id': 'inline', 'ex': {'tg': 'chest', 'sm': ['chest', 'triceps']}, 'sets': 2}]), jeq({'chest': 2, 'triceps': 0.8}));
    });

    test('uses multi-muscle metadata carried by a history entry when its catalogue id is unavailable', () {
      expect(loadOfWorkouts([{'entries': [{'id': 'deleted-custom', 'muscleGroups': ['chest', 'chest', 'triceps'], 'sets': [{'done': true}]}]}]),
          jeq({'chest': 1, 'triceps': 1}));
    });
  });

  group('explicit muscle weights', () {
    final complete = {'chest': 1, 'deltoids': 0.4, 'triceps': 0};

    test('preserves every finite explicit weight from zero through one', () {
      expect(muscleWeightsOf({'muscleWeights': complete}), jeq(complete));
    });
    test('keeps effective stimulus positive-only', () {
      expect(musclesOf({'muscleWeights': complete}), jeq({'chest': 1, 'deltoids': 0.4}));
    });
    test('treats a recognized all-zero map as authoritative instead of using body-part defaults', () {
      final ex = {'bp': 'chest', 'muscleWeights': {'chest': 0, 'triceps': 0}};
      expect(muscleWeightsOf(ex), jeq({'chest': 0, 'triceps': 0}));
      expect(musclesOf(ex), jeq({}));
    });
    test('preserves complete weights in history snapshots', () {
      expect(exerciseMuscleSnapshot({'n': 'Press', 'bp': 'chest', 'muscleWeights': complete}), matchObj({'n': 'Press', 'bp': 'chest', 'muscleWeights': complete}));
    });
    test('keeps legacy primary and secondary fallback weights', () {
      expect(muscleWeightsOf({'tg': 'pectorals', 'mg': 'triceps'}), jeq({'chest': 1, 'triceps': 0.4}));
    });
  });

  group('catalogue secondary muscles', () {
    test('maps a bench press to chest, triceps and deltoids', () {
      expect(musclesOf(EXIDX['0025']), matchObj({'chest': 1, 'triceps': 0.4, 'deltoids': 0.4}));
    });
    test('maps a squat to glutes, quads and hamstrings', () {
      expect(musclesOf(EXIDX['0043']), matchObj({'gluteal': 1, 'quadriceps': 1, 'hamstring': 0.4}));
    });
    test('maps common row variations to the upper back, biceps and rear deltoids', () {
      for (final id in ['0027', '0293', '0499', '0861']) {
        expect(musclesOf(EXIDX[id]), matchObj({'upper-back': 1, 'biceps': 0.4, 'deltoids': 0.4}), reason: id);
      }
    });
  });

  group('catalogue secondary additions', () {
    test('enriches the muscle map without mutating the raw dataset', () {
      final raw = EXDB.firstWhere((e) => e['id'] == '0027');
      expect(raw['sm'], isNot(contains('rear deltoids')));
      expect(smOf(raw), contains('rear deltoids'));
      expect(musclesOf(raw).containsKey('deltoids'), isTrue);
    });
  });

  group('explicit multi-primary metadata', () {
    test('gives every primary full weight and secondaries supporting weight', () {
      final ex = {
        'bp': 'chest', 'tg': 'abs', 'mg': 'triceps', 'sm': ['lower back'],
        'primaries': ['chest', 'triceps', 'chest'], 'secondaries': ['deltoids', 'triceps'],
      };
      expect(muscleGroupsOf(ex), ['chest', 'triceps', 'deltoids']);
      expect(musclesOf(ex), jeq({'chest': 1, 'triceps': 1, 'deltoids': 0.4}));
    });
    test('keeps the body-part fallback when primaries are absent or explicitly empty', () {
      final expected = {'upper-back': 0.75, 'lower-back': 0.25};
      expect(musclesOf({'bp': 'back'}), jeq(expected));
      expect(musclesOf({'bp': 'back', 'primaries': []}), jeq(expected));
    });
    test('keeps legacy metadata when a new array field is present but empty', () {
      expect(exerciseMuscleSnapshot({'bp': 'chest', 'tg': 'abs', 'primaries': []}), matchObj({'muscleGroups': ['abs']}));
    });
    test('provides a conservative Full body fallback for legacy custom exercises', () {
      expect(muscleGroupsOf({'bp': 'full body'}), ['chest', 'upper-back', 'gluteal', 'quadriceps', 'hamstring', 'abs']);
      expect(musclesOf({'bp': 'full body'}), jeq({'chest': 0.2, 'upper-back': 0.2, 'gluteal': 0.2, 'quadriceps': 0.2, 'hamstring': 0.1, 'abs': 0.1}));
    });
    test('preserves explicit primary and secondary arrays in history snapshots', () {
      expect(
        exerciseMuscleSnapshot({'n': 'Deadlift', 'bp': 'full body', 'primaries': ['gluteal', 'lower-back'], 'secondaries': ['hamstring']}),
        matchObj({
          'n': 'Deadlift', 'bp': 'full body', 'primaries': ['gluteal', 'lower-back'], 'secondaries': ['hamstring'],
          'muscleGroups': ['gluteal', 'lower-back', 'hamstring'],
        }),
      );
    });
  });

  group('map load with warm-up phases', () {
    test('excludes warm-up sets from the by-sets-worked map', () {
      final w = {
        'id': 'w1', 'd': '2026-08-01', 'start': DateTime.utc(2026, 8, 1, 10).millisecondsSinceEpoch, 'unit': 'kg',
        'entries': [{'id': '0025', 'sets': [{'done': true, 'phase': 'warmup', 'w': 20, 'r': 8}, {'done': true, 'phase': 'work', 'w': 60, 'r': 8}]}],
      };
      expect(loadOfWorkouts([w], null)['chest'], 1);
    });
  });

  group('planned weekly muscle volume', () {
    final state = <String, dynamic>{
      'customEx': [
        {'id': 'press', 'primaries': ['chest'], 'secondaries': ['triceps']},
        {'id': 'curl', 'primaries': ['biceps'], 'secondaries': []},
      ],
      'routines': [
        {'id': 'push', 'ex': [{'id': 'press', 'sets': 2}]},
        {'id': 'arms', 'ex': [{'id': 'curl', 'sets': 3}]},
      ],
      'week': {'0': 'arms', '1': ['push', 'missing'], '3': ['push']},
      'dayPlan': {'2026-08-18': 'arms'},
      'workouts': [{'entries': [{'id': 'snapshot-only', 'muscleSnapshot': {'muscleWeights': {'quadriceps': 1}}}]}],
    };

    test('aggregates arrays and legacy scalar assignments, including routines repeated in the week', () {
      expect(loadOfWeeklyPlan(state), jeq({'chest': 4, 'triceps': 1.6, 'biceps': 3}));
    });
    test('ignores stale routine ids, date overrides, and completed-workout snapshots', () {
      final load = loadOfWeeklyPlan(state);
      expect(load.containsKey('quadriceps'), isFalse);
      expect(load['biceps'], 3);
    });
    test('counts a floating week once per session, beside the weekday routines it does not cover', () {
      final queued = {...state, 'queue': {'ids': ['push', 'push', 'gone'], 'since': 0, 'startsOn': '2026-08-17'}};
      expect(loadOfWeeklyPlan(queued), jeq({'chest': 2, 'triceps': 0.8, 'biceps': 3}));
    });
    test('returns an empty projection for missing or empty plans', () {
      expect(loadOfWeeklyPlan(), jeq({}));
      expect(loadOfWeeklyPlan({'routines': [], 'week': {'1': ['missing']}}), jeq({}));
    });
  });

  group('deleted custom exercises', () {
    final snapshotEntry = <String, dynamic>{
      'id': 'gone-custom-1',
      'sets': [{'w': 60, 'r': 8, 'done': true}],
      'muscleSnapshot': {'n': 'Deleted custom', 'bp': 'chest', 'muscleGroups': ['chest'], 'muscleWeights': {'chest': 1}},
    };
    test('reads muscle load back out of the snapshot', () {
      expect(loadOfWorkouts([{'d': '2026-08-01', 'entries': [snapshotEntry]}]), jeq({'chest': 1}));
    });
    test('reports the snapshot groups as explicit metadata', () {
      expect(hasExplicitMuscleMetadata(snapshotEntry), isTrue);
      expect(muscleGroupsOf(snapshotEntry), ['chest']);
    });
    test("still prefers the entry's own metadata when it has any", () {
      final withOwn = {...snapshotEntry, 'tg': 'quadriceps'};
      expect(muscleGroupsOf(withOwn), ['quadriceps']);
    });
  });

  group('warm-up boundary', () {
    test('excludes every phase spelling the workout model treats as a warm-up', () {
      List<dynamic> entries(String spelling) => [{'id': '0025', 'sets': [{'w': 100, 'r': 5, 'done': true, 'phase': spelling}]}];
      for (final spelling in ['warmup', 'warm-up', 'warm_up', 'Warmup', ' warmup ']) {
        expect(loadOfWorkouts([{'d': '2026-08-01', 'entries': entries(spelling)}]), jeq({}), reason: spelling);
      }
    });
  });

  group('muscle balance windows and ranking', () {
    final now = DateTime.parse('2026-08-27T12:00:00').millisecondsSinceEpoch;
    final workouts = [
      {'id': 'monday', 'd': '2026-08-24', 'start': DateTime.parse('2026-08-24T12:00:00').millisecondsSinceEpoch},
      {'id': 'sunday', 'd': '2026-08-23', 'start': DateTime.parse('2026-08-23T12:00:00').millisecondsSinceEpoch},
      {'id': 'boundary', 'd': '2026-07-28', 'start': now - 30 * 86400000},
      {'id': 'inside', 'd': '2026-07-29', 'start': now - 29 * 86400000},
    ];

    test('preserves calendar-week, strict trailing-day, and all-history semantics', () {
      expect(muscleBalanceWindow(workouts, 7, now, '2026-08-27').map((w) => w['id']).toList(), ['monday']);
      expect(muscleBalanceWindow(workouts, 30, now, '2026-08-27').map((w) => w['id']).toList(), ['monday', 'sunday', 'inside']);
      expect(muscleBalanceWindow(workouts, 0, now, '2026-08-27'), jeq(workouts));
    });

    test('uses relative levels and canonical order to break load ties', () {
      final load = {'chest': 2, 'deltoids': 2, 'biceps': 1};
      expect(rankOf(load)['worked'], ['deltoids', 'chest', 'biceps']);
      expect(levelsOf(load), matchObj({'deltoids': 4, 'chest': 4, 'biceps': 2, 'abs': 0}));
    });

    test('keeps catalogue precedence and deleted-custom snapshot weights', () {
      final known = {'id': '0025', 'muscleGroups': ['quadriceps'], 'sets': [{'done': true}]};
      final deleted = {'id': 'deleted', 'muscleSnapshot': {'muscleWeights': {'chest': 1}}, 'sets': [{'done': true}]};
      expect(loadOfWorkouts([{'entries': [known]}]), jeq({'chest': 1, 'triceps': 0.4, 'deltoids': 0.4}));
      expect(loadOfWorkouts([{'entries': [deleted]}]), jeq({'chest': 1}));
    });
  });

  // skipped: 'MUSCLE_NAME as i18n keys' — checks every non-English locale pack (catalogue).
}
