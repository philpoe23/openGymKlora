// Port of frontend/src/lib/session-start.plan.test.js — a routine saved as "2 × 10" has to open as
// 2 × 10 (#275). Every scenario starts the session the way beginWorkout does
// (buildCombinedEntries → buildSessionEntries) and logs it the way the finish path does
// (buildCompletedWorkout).
// ignore_for_file: constant_identifier_names
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/finish_workout.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/progression.dart';
import 'package:klora_app/engine/session_merge.dart';
import 'package:klora_app/engine/session_start.dart';
import 'package:klora_app/engine/workout_model.dart';

import '_exdb.dart';
import '_helpers.dart';

const BENCH = '0025';
List<dynamic> work(dynamic e) => (e['sets'] as List).where((s) => !isWarmupRow(s)).toList();
List<dynamic> reps(dynamic e) => work(e).map((s) => s['r']).toList();
JMap state(List<dynamic> routines, [JMap extra = const {}]) => {
      'unit': 'kg', 'exWeights': <String, dynamic>{}, 'routines': clone(routines), 'workouts': <dynamic>[],
      'week': <String, dynamic>{}, 'dayPlan': <String, dynamic>{}, ...clone(extra) as Map<String, dynamic>,
    };
JMap cfgOf(JMap st, String rid, [String exId = BENCH]) =>
    jsFind(jsFind(st['routines'] as List, (r) => r['id'] == rid)['ex'] as List, (c) => c['id'] == exId) as JMap;
List<dynamic> start(JMap st, List<String> rids) => buildCombinedEntries(st, rids)['entries'] as List;

var day = 1;

/// Train the given routines: start them for real, optionally type something else into the work
/// rows ([typed]: a map, or a function of the row index), tick everything and finish.
void train(JMap st, List<String> rids, [dynamic typed]) {
  final entries = start(st, rids).map((e) {
    var i = -1;
    return {
      ...e as Map<String, dynamic>,
      'sets': [
        for (final s in e['sets'] as List)
          if (isWarmupRow(s))
            {...s as Map<String, dynamic>, 'done': true}
          else
            {
              ...s as Map<String, dynamic>,
              ...(typed is Function ? typed(++i) as Map : (typed ?? const {}) as Map),
              'done': true,
            },
      ],
    };
  }).toList();
  final d = '2026-08-${'$day'.padLeft(2, '0')}';
  final active = {'id': 'w$day', 'd': d, 'start': day * 1000, 'routineIds': rids, 'name': 'x', 'entries': entries};
  day++;
  (st['workouts'] as List).add(buildCompletedWorkout(active, end: (active['start'] as num) + 1));
}

String why0(dynamic e) => (e['plan']['why'] as List)[0] as String;

void main() {
  setUpAll(loadTestExerciseDb);

  group("a planned session opens at the plan's reps", () {
    test('when the same exercise was trained at 15 in another routine', () {
      final st = state([
        {'id': 'A', 'name': 'Plan A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 60}]},
        {'id': 'B', 'name': 'Plan B', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 15, 'weight': 40}]},
      ]);
      train(st, ['B']);
      final a = start(st, ['A'])[0];
      expect(work(a), hasLength(2));
      expect(reps(a), jeq([10, 10]));
      expect(a['target']['reps'], 10);
      expect(work(a).map((s) => s['w']).toList(), jeq([60, 60]));
      expect(why0(a), 'First time in this routine, so starting from its own target.');
      train(st, ['A']);
      train(st, ['B'], {'r': 9});
      final again = start(st, ['A'])[0];
      expect(work(again).map((s) => [s['w'], s['r']]).toList(), jeq([[62.5, 10], [62.5, 10]]));
    });

    test("from the exercise's last weight when the other routine planned the same one", () {
      final st = state([
        {'id': 'A', 'name': 'Plan A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 40}]},
        {'id': 'B', 'name': 'Plan B', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 15, 'weight': 40}]},
      ]);
      train(st, ['B']);
      train(st, ['B']);
      final a = start(st, ['A'])[0];
      expect(work(a).map((s) => [s['w'], s['r']]).toList(), jeq([[42.5, 10], [42.5, 10]]));
    });

    for (final prog in [null, 'linear', 'greyskull', 'off']) {
      test('after the routine was edited from 15 to 10 · policy ${prog ?? '(default)'}', () {
        final st = state([
          {'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 15, 'weight': 50, 'prog': ?prog}]},
        ]);
        train(st, ['A']);
        train(st, ['A']);
        cfgOf(st, 'A')['reps'] = 10;
        final e = start(st, ['A'])[0];
        expect(reps(e), jeq([10, 10]));
        expect(e['target']['reps'], 10);
      });
    }

    test('after one session logged at 15 on a 10 target — it does not stick', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 50}]}]);
      expect(reps(start(st, ['A'])[0]), jeq([10, 10]));
      train(st, ['A'], {'r': 15});
      final next = start(st, ['A'])[0];
      expect(reps(next), jeq([10, 10]));
      expect(next['plan']['kind'], 'up');
      expect(work(next).map((s) => s['w']).toList(), jeq([52.5, 52.5]));
      train(st, ['A']);
      expect(reps(start(st, ['A'])[0]), jeq([10, 10]));
    });

    test('under Greyskull, whose AMRAP set carried its own count before', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 50, 'prog': 'greyskull'}]}]);
      train(st, ['A'], (int i) => i == 1 ? {'r': 15} : {});
      final e = start(st, ['A'])[0];
      expect(e['plan']['reps'], isNull);
      expect(reps(e), jeq([10, 10]));
    });

    test("with planned warm-ups, which follow the plan's reps too", () {
      final st = state([
        {'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 60, 'warmupSets': 1}]},
        {'id': 'B', 'name': 'B', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 15, 'weight': 40}]},
      ]);
      train(st, ['B']);
      final e = start(st, ['A'])[0];
      expect((e['sets'] as List).where(isWarmupRow).map((s) => s['r']).toList(), jeq([10]));
    });

    test('on a combined day that holds the exercise twice, each block at its own plan', () {
      final st = state([
        {'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 60}]},
        {'id': 'B', 'name': 'B', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 15, 'weight': 40}]},
      ]);
      train(st, ['B']);
      final ab = start(st, ['A', 'B']);
      expect(reps(ab[0]), jeq([10, 10]));
      expect(reps(ab[1]), jeq([15, 15]));
    });

    test("for a new routine's default policy, with a legacy session logged at 15", () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 50, 'mode': 'reps'}]}]);
      (st['workouts'] as List).add({'id': 'p', 'd': '2026-09-01', 'entries': [{'id': BENCH, 'target': {'sets': 2, 'reps': 10, 'weight': 50}, 'sets': [{'w': 50, 'r': 15, 'done': true}, {'w': 50, 'r': 15, 'done': true}]}]});
      final e = buildSessionEntries(st, (st['routines'] as List)[0])[0];
      expect(e['plan']['policy'], 'linear');
      expect(reps(e), jeq([10, 10]));
    });

    final priors = <String, JMap?>{
      'target 15': {'sets': 2, 'reps': 15, 'weight': 50, 'mode': 'reps'},
      'target 10, did 15': {'sets': 2, 'reps': 10, 'weight': 50, 'mode': 'reps'},
      'no target': null,
    };
    for (final prior in priors.entries) {
      for (final prog in POLICIES) {
        test('every policy at 2 × 10 after a logged 2 × 15 · prior ${prior.key} · $prog', () {
          final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 50, 'mode': 'reps', 'prog': prog}]}]);
          (st['workouts'] as List).add({'id': 'p', 'd': '2026-09-01', 'entries': [{'id': BENCH, 'target': prior.value, 'sets': [{'w': 50, 'r': 15, 'done': true}, {'w': 50, 'r': 15, 'done': true}]}]});
          final e = start(st, ['A'])[0];
          if (prog == 'double') {
            expect(reps(e).every((r) => r >= 8 && r <= 10), isTrue);
          } else {
            expect(reps(e), jeq([10, 10]));
          }
        });
      }
    }
  });

  group('a routine whose only history is freestyle or imported', () {
    test("starts from its own sets × reps at the last weight, not from the other session's shape", () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 50, 'mode': 'reps'}]}]);
      (st['workouts'] as List).add({'id': 'imp', 'd': '2026-09-01', 'routineId': null, 'entries': [{'id': BENCH, 'sets': [{'w': 30, 'r': 15, 'done': true}, {'w': 30, 'r': 15, 'done': true}, {'w': 30, 'r': 15, 'done': true}]}]});
      final e = start(st, ['A'])[0];
      expect(work(e).map((s) => [s['w'], s['r']]).toList(), jeq([[30, 10], [30, 10]]));
      expect(why0(e), 'First time in this routine, so starting from its own target.');
    });
  });

  group('an edited routine starts again from its new plan', () {
    test('holds the weight at the new reps under the default policy', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 15, 'weight': 50}]}]);
      train(st, ['A']);
      cfgOf(st, 'A')['reps'] = 10;
      final e = start(st, ['A'])[0];
      expect(work(e).map((s) => [s['w'], s['r']]).toList(), jeq([[50, 10], [50, 10]]));
      expect(why0(e), 'Plan changed, so starting from your new target.');
      train(st, ['A']);
      expect(start(st, ['A'])[0]['plan']['kind'], 'up');
    });

    test("opens at the plan's new weight when the edit changed it too", () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 3, 'reps': 5, 'weight': 100}]}]);
      train(st, ['A']);
      train(st, ['A']);
      expect(work(start(st, ['A'])[0]).map((s) => s['w']).toList(), jeq([105, 105, 105]));
      cfgOf(st, 'A').addAll({'reps': 10, 'weight': 70});
      final e = start(st, ['A'])[0];
      expect(work(e).map((s) => [s['w'], s['r']]).toList(), jeq([[70, 10], [70, 10], [70, 10]]));
      expect(why0(e), 'Plan changed, so starting from your new target.');
      train(st, ['A']);
      expect(work(start(st, ['A'])[0]).map((s) => [s['w'], s['r']]).toList(), jeq([[72.5, 10], [72.5, 10], [72.5, 10]]));
    });

    test('aims inside the new range under double progression', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 15, 'repsMin': 13, 'weight': 50, 'prog': 'double'}]}]);
      train(st, ['A']);
      cfgOf(st, 'A').addAll({'reps': 10, 'repsMin': 8});
      final e = start(st, ['A'])[0];
      expect(e['plan']['kind'], 'hold');
      expect(reps(e), jeq([10, 10]));
    });

    test('restarts a bodyweight rep goal from the new count, not from the old one plus a rep', () {
      const ARCHER = '3294';
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': ARCHER, 'sets': 2, 'reps': 15, 'weight': 0, 'mode': 'reps'}]}]);
      train(st, ['A']);
      cfgOf(st, 'A', ARCHER)['reps'] = 10;
      final e = start(st, ['A'])[0];
      expect(reps(e), jeq([10, 10]));
      train(st, ['A']);
      expect(reps(start(st, ['A'])[0]), jeq([11, 11]));
    });

    test('does not deload toward the old reps, or grow back a removed set, after three misses', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 3, 'reps': 15, 'weight': 50}]}]);
      for (var i = 0; i < 3; i++) {
        train(st, ['A'], {'r': 12});
      }
      cfgOf(st, 'A').addAll({'sets': 2, 'reps': 10});
      final e = start(st, ['A'])[0];
      expect(e['plan']['kind'], 'hold');
      expect(work(e).map((s) => [s['w'], s['r']]).toList(), jeq([[50, 10], [50, 10]]));
    });

    test('does not raise the weight off a bottom stamped after switching to double (#278)', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 3, 'reps': 8, 'weight': 36, 'inc': 6}]}]);
      train(st, ['A']);
      final ex = (st['routines'] as List)[0]['ex'] as List;
      ex[0] = {...ex[0] as Map<String, dynamic>, 'reps': 12, 'repsMin': 8, 'prog': 'double'};
      final e = start(st, ['A'])[0];
      expect(e['plan'], matchObj({'kind': 'hold', 'weight': 36, 'reps': 9}));
      train(st, ['A'], {'r': 8, 'w': 42});
      final next = start(st, ['A'])[0];
      expect(next['plan']['kind'], isNot('up'));
      expect(work(next).map((s) => s['w']).toList(), jeq([42, 42, 42]));
    });
  });

  group('bodyweight progression and a lift logged without a weight', () {
    const PUSHUP = '0662';

    test('adds a set at the rep ceiling and keeps it: 2 × 10, 2 × 11, 3 × 10, 3 × 11, 4 × 10 (#33)', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': PUSHUP, 'sets': 2, 'reps': 10, 'repsMax': 11, 'weight': 0, 'bodyweight': true}]}]);
      final shape = <String>[];
      for (var i = 0; i < 5; i++) {
        final e = start(st, ['A'])[0];
        shape.add('${work(e).length}x${jsString(reps(e)[0])}');
        train(st, ['A']);
      }
      expect(shape, ['2x10', '2x11', '3x10', '3x11', '4x10']);
    });

    test('climbs reps on an ab wheel logged at 0 kg — it has no load to enter', () {
      const WHEEL = '0857';
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': WHEEL, 'sets': 3, 'reps': 10, 'weight': 0}]}]);
      train(st, ['A']);
      train(st, ['A']);
      final e = start(st, ['A'])[0];
      expect(e['plan']['kind'], 'up');
      expect(reps(e), jeq([12, 12, 12]));
    });

    test('does not climb reps on a loaded lift whose rows were logged at 0 kg', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 0}]}]);
      train(st, ['A']);
      final e = start(st, ['A'])[0];
      expect(e['plan']['kind'], 'hold');
      expect(reps(e), jeq([10, 10]));
    });
  });

  group('"Your last session" keeps the old carry-over', () {
    test('opens at the reps logged last time, judged against the plan', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 50}]}], {'startFrom': 'last'});
      train(st, ['A'], {'r': 15});
      final e = start(st, ['A'])[0];
      expect(reps(e), jeq([15, 15]));
      expect(e['target']['reps'], 10);
    });

    test('still lets a policy that decides reps decide them', () {
      final st = state([{'id': 'A', 'name': 'A', 'ex': [{'id': BENCH, 'sets': 2, 'reps': 12, 'repsMin': 8, 'weight': 40, 'prog': 'double'}]}], {'startFrom': 'last'});
      train(st, ['A'], {'r': 9});
      final e = start(st, ['A'])[0];
      expect(e['plan']['kind'], 'hold');
      expect(reps(e), jeq([10, 10]));
    });
  });
}
