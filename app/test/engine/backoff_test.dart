// Port of frontend/src/lib/backoff.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/backoff.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/progression.dart';
import 'package:klora_app/engine/session_start.dart';
import 'package:klora_app/engine/workout_model.dart';

import '_exdb.dart';
import '_helpers.dart';

const lift = '0025';

void main() {
  setUpAll(loadTestExerciseDb);

  group('backoffAt / backoffWeights', () {
    test('steps each set down by the step', () {
      expect(backoffWeights(26, 3, 2), jeq([26, 24, 22]));
      expect(backoffWeights(80, 4, 5), jeq([80, 75, 70, 65]));
      expect(backoffWeights(60, 3, 2.5), jeq([60, 57.5, 55]));
    });

    test('stays on the grid the top set is on, and steps from an off-grid top set as typed', () {
      expect(backoffWeights(62.5, 3, 1.25), jeq([62.5, 61.3, 60]));
      expect(backoffWeights(27, 3, 2), jeq([27, 25, 23]));
    });

    test('never goes below one step, and never above the top set', () {
      expect(backoffWeights(6, 5, 2), jeq([6, 4, 2, 2, 2]));
      expect(backoffAt(1, 3, 2), 1);
    });

    test('leaves a missing load alone', () {
      expect(backoffAt(0, 2, 2), 0);
      expect(backoffAt(30, 2, 0), 30);
    });
  });

  group('isBackoff', () {
    test('is off unless switched on, so older plans build as before', () {
      expect(isBackoff({'id': lift, 'sets': 3, 'reps': 6, 'weight': 26}), isFalse);
      expect(isBackoff({'id': lift, 'sets': 3, 'reps': 6, 'weight': 26, 'backoff': true}), isTrue);
    });
    test('does not apply to a timed hold, a pyramid or a rest-pause', () {
      expect(isBackoff({'mode': 'time', 'backoff': true}), isFalse);
      expect(isBackoff({'backoff': true, 'pyramid': [12, 10, 8]}), isFalse);
      expect(isBackoff({'backoff': true, 'intensifier': {'type': 'restpause'}}), isFalse);
      expect(isBackoff({'backoff': true, 'intensifier': {'type': 'dropset', 'count': 1, 'pct': 20}}), isTrue);
    });
  });

  group('applyBackoff', () {
    test('steps the work rows from the first one and leaves warm-ups and logged rows alone', () {
      final rows = [
        {'w': 10, 'r': 6, 'phase': 'warmup', 'done': false},
        {'w': 26, 'r': 6, 'done': false},
        {'w': 26, 'r': 6, 'done': true},
        {'w': 26, 'r': 6, 'done': false},
      ];
      expect(applyBackoff(rows, 2).map((r) => r['w']).toList(), jeq([10, 26, 26, 22]));
    });
    test('steps both sides of a per-side row', () {
      final rows = [makeSideSet({'w': 20, 'r': 12}), makeSideSet({'w': 20, 'r': 12})];
      final out = applyBackoff(rows, 2);
      expect(out[1]['sides']['L']['w'], 18);
      expect(out[1]['sides']['R']['w'], 18);
      expect(out[1]['w'], 18);
    });
  });

  group('a routine with back-off sets, session by session', () {
    JMap cfg() => {'id': lift, 'sets': 3, 'reps': 6, 'weight': 26, 'inc': 2, 'backoff': true};
    JMap routine() => {'id': 'r', 'prog': 'linear', 'ex': [cfg()]};
    JMap start(List<dynamic> workouts) =>
        buildSessionEntries({'unit': 'kg', 'exWeights': {}, 'routines': [routine()], 'workouts': workouts}, routine())[0] as JMap;
    List<dynamic> work(dynamic entry) => (entry['sets'] as List).where((s) => !isWarmupRow(s)).toList();
    List<dynamic> weights(dynamic entry) => work(entry).map((s) => s['w']).toList();
    // Log the session: `reps` per planned set, at the weights on the screen unless `ws` overrides.
    JMap perform(JMap entry, List<num> reps, [List<num>? ws, List<dynamic> extra = const []]) {
      final w = work(entry);
      return {
        ...entry,
        'sets': [
          for (var i = 0; i < w.length; i++) {...w[i] as Map<String, dynamic>, 'r': reps[i], 'w': ws != null ? ws[i] : w[i]['w'], 'done': true},
          ...extra,
        ],
      };
    }

    var day = 0;
    List<dynamic> save(List<dynamic> workouts, JMap entry) {
      day++;
      return [
        ...workouts,
        {'d': '2026-01-${'$day'.padLeft(2, '0')}', 'routineIds': ['r'], 'entries': [entry]},
      ];
    }

    test('opens at the plan with every set one step lighter', () {
      final first = start([]);
      expect(weights(first), jeq([26, 24, 22]));
      expect(first['target']['backoffStep'], 2);
      expect(work(first).every((s) => s['r'] == 6), isTrue);
    });

    test('TEST 1: every planned set hit → the whole sequence goes up one step', () {
      final hist = save([], perform(start([]), [6, 6, 6]));
      expect(weights(start(hist)), jeq([28, 26, 24]));
    });

    for (final c in [
      ('TEST 2: last back-off short', <num>[6, 6, 5]),
      ('TEST 3: middle back-off short', <num>[6, 5, 6]),
      ('TEST 4: top set short', <num>[5, 6, 6]),
    ]) {
      test('${c.$1} → the same sequence again', () {
        final hist = save([], perform(start([]), c.$2));
        final next = start(hist);
        expect(next['plan']['kind'], 'hold');
        expect(weights(next), jeq([26, 24, 22]));
      });
    }

    test('TEST 5: an extra set on top does not count either way', () {
      final hist = save([], perform(start([]), [6, 6, 6], null, [{'w': 18, 'r': 3, 'done': true}]));
      expect(weights(start(hist)), jeq([28, 26, 24]));
    });

    test('a back-off set taken lighter than planned is not the sequence done', () {
      final lighter = perform(start([]), [6, 6, 6], [26, 24, 20]);
      expect(readSession(lighter)['ok'], isFalse);
      expect(weights(start(save([], lighter))), jeq([26, 24, 22]));
      expect(readSession(perform(start([]), [6, 6, 6], [26, 25, 24]))['ok'], isTrue);
    });

    test('TEST 7: a failed session retries, and the next clean one moves on', () {
      var hist = save([], perform(start([]), [6, 6, 6]));
      expect(weights(start(hist)), jeq([28, 26, 24]));
      hist = save(hist, perform(start(hist), [6, 6, 5]));
      expect(weights(start(hist)), jeq([28, 26, 24]));
      hist = save(hist, perform(start(hist), [6, 6, 6]));
      expect(weights(start(hist)), jeq([30, 28, 26]));
      hist = save(hist, perform(start(hist), [6, 6, 5]));
      expect(weights(start(hist)), jeq([30, 28, 26]));
    });

    test('repeated misses fall into the existing deload, and the back-off sets follow it down', () {
      var hist = <dynamic>[];
      for (var i = 0; i < 3; i++) {
        hist = save(hist, perform(start(hist), [6, 6, 4]));
      }
      final next = start(hist);
      expect(next['plan']['kind'], 'deload');
      final w = weights(next);
      expect(w[0], lessThan(26));
      expect(w, jeq(backoffWeights(w[0], 3, 2)));
    });

    test('uses the exercise step, whatever it is: a 5 kg lever machine', () {
      final lever = {...cfg(), 'weight': 80, 'inc': 5};
      final r = {...routine(), 'ex': [lever]};
      final first = buildSessionEntries({'unit': 'kg', 'exWeights': {}, 'routines': [r], 'workouts': []}, r)[0];
      expect(weights(first), jeq([80, 75, 70]));
    });

    test('warm-ups still ramp toward the top set', () {
      final r = {...routine(), 'ex': [{...cfg(), 'weight': 40, 'warmupSets': 2}]};
      final entry = buildSessionEntries({'unit': 'kg', 'exWeights': {}, 'routines': [r], 'workouts': []}, r)[0];
      final warm = (entry['sets'] as List).where(isWarmupRow).map((s) => s['w'] as num);
      expect(warm.every((w) => w < 40), isTrue);
      expect(weights(entry), jeq([40, 38, 36]));
    });

    test('works under double progression too: the top set moves when every set reaches the top of the range', () {
      final dbl = {...cfg(), 'prog': 'double', 'reps': 8, 'repsMin': 6};
      final r = {...routine(), 'ex': [dbl]};
      JMap go(List<dynamic> workouts) => buildSessionEntries({'unit': 'kg', 'exWeights': {}, 'routines': [r], 'workouts': workouts}, r)[0] as JMap;
      var hist = save([], perform(go([]), [7, 7, 6]));
      expect(weights(go(hist)), jeq([26, 24, 22]));
      hist = save(hist, perform(go(hist), [8, 8, 8]));
      final up = go(hist);
      expect(weights(up), jeq([28, 26, 24]));
      expect(work(up).every((s) => s['r'] == 6), isTrue);
    });
  });

  group('TEST 8: nothing changes without the switch', () {
    test('a plan without back-off opens every set at the same weight and stamps no step', () {
      final r = {'id': 'r', 'prog': 'linear', 'ex': [{'id': lift, 'sets': 3, 'reps': 6, 'weight': 26, 'inc': 2}]};
      final entry = buildSessionEntries({'unit': 'kg', 'exWeights': {}, 'routines': [r], 'workouts': []}, r)[0];
      expect((entry['sets'] as List).map((s) => s['w']).toList(), jeq([26, 26, 26]));
      expect(entry['target']['backoffStep'], isNull);
    });
    test('a session without a stamped step reads exactly as before, lighter sets and all', () {
      final entry = {'id': lift, 'target': {'sets': 3, 'reps': 6, 'weight': 26}, 'sets': [for (final w in [26, 24, 20]) {'w': w, 'r': 6, 'done': true}]};
      expect(readSession(entry)['ok'], isTrue);
    });
    test('an assistance machine is left out, where lighter is harder', () {
      final r = {'id': 'r', 'prog': 'linear', 'ex': [{'id': lift, 'assisted': true, 'sets': 3, 'reps': 6, 'weight': 30, 'inc': 5, 'backoff': true}]};
      final entry = buildSessionEntries({'unit': 'kg', 'exWeights': {}, 'routines': [r], 'workouts': []}, r)[0];
      expect((entry['sets'] as List).map((s) => s['w']).toList(), jeq([30, 30, 30]));
    });
  });

  group('editing a weight mid-session', () {
    List<dynamic> rows() => <dynamic>[
          {'w': 26, 'r': 6, 'done': false},
          {'w': 24, 'r': 6, 'done': false},
          {'w': 22, 'r': 6, 'done': false},
        ];
    test('carries a top-set change down the sequence', () {
      expect(cascadeWeight(rows(), 0, 28, null, 2).map((r) => r['w']).toList(), jeq([26, 26, 24]));
    });
    test('from a back-off set, steps down from there', () {
      expect(cascadeWeight(rows(), 1, 20, null, 2).map((r) => r['w']).toList(), jeq([26, 24, 18]));
    });
    test('keeps the old flat cascade when the session has no back-off', () {
      expect(cascadeWeight(rows(), 0, 28).map((r) => r['w']).toList(), jeq([26, 28, 28]));
    });
    test('a logged set in between keeps its place in the sequence', () {
      final r = rows();
      r[1] = {...r[1] as Map, 'done': true};
      expect(cascadeWeight(r, 0, 30, null, 2).map((x) => x['w']).toList(), jeq([26, 24, 26]));
    });
  });
  group('nextPrescription with back-off', () {
    test('decides only the top set; the rows derive the rest', () {
      final cfg = {'id': lift, 'sets': 3, 'reps': 6, 'weight': 26, 'inc': 2, 'backoff': true, 'prog': 'linear'};
      final S = {'unit': 'kg', 'workouts': [{'d': '2026-01-01', 'entries': [{'id': lift, 'target': {...cfg, 'backoffStep': 2}, 'sets': [for (final w in [26, 24, 22]) {'w': w, 'r': 6, 'done': true}]}]}]};
      final p = nextPrescription(S, cfg);
      expect(p['kind'], 'up');
      expect(p['weight'], 28);
    });
  });
}
