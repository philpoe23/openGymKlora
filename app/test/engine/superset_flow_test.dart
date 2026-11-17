// Port of frontend/src/lib/supersetFlow.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/superset_flow.dart';

import '_helpers.dart';

Map<String, dynamic> entry(List<bool> done) => {
      'sets': [for (final value in done) <String, dynamic>{'done': value}],
    };

void main() {
  group('restAfterSet', () {
    test('rests between the sets of an exercise', () {
      expect(restAfterSet(unitDone: false, lastUnit: false), isTrue);
      expect(restAfterSet(unitDone: false, lastUnit: true), isTrue);
    });

    test('rests after the closing set when another exercise follows', () {
      expect(restAfterSet(unitDone: true, lastUnit: false), isTrue);
    });

    test('stays quiet only on the very last set of the session', () {
      expect(restAfterSet(unitDone: true, lastUnit: true), isFalse);
    });
  });

  group('supersetFlowStep', () {
    test('does not create navigation or rest flow for a normal singleton exercise', () {
      final entries = [entry([true]), entry([false])];
      expect(supersetFlowStep(entries, [0], 0), isNull);
    });

    test('does not count an uncheck/re-check of previously completed work as new progress', () {
      final finished = entry([true, true, true]);
      expect(setProgressHighWater(finished, 3), jeq({'isNew': false, 'highWater': 3}));
      expect(setProgressHighWater(finished, 2), jeq({'isNew': true, 'highWater': 3}));
    });

    test('skips a spent short member and uses the last member with work as the round boundary', () {
      final entries = [entry([true, true, false]), entry([true])];
      expect(supersetFlowStep(entries, [0, 1], 0), jeq({'unitDone': false, 'roundDone': true, 'nextIdx': 0}));
    });

    test('wraps to the next member with work at a normal round boundary', () {
      final entries = [entry([true, false, false]), entry([true])];
      expect(supersetFlowStep(entries, [0, 1], 1), jeq({'unitDone': false, 'roundDone': true, 'nextIdx': 0}));
    });
  });

  group('active workout unit ordering', () {
    test('inserts after the whole current unit', () {
      expect(insertionIndexAfterCurrentUnit([[0, 1], [2]], 0, 3), 2);
      expect(insertionIndexAfterCurrentUnit([[0], [1]], 1, 2), 2);
      expect(insertionIndexAfterCurrentUnit([], 0, 0), 0);
    });

    test('finds the next unfinished unit, skips completed units, and wraps once', () {
      final entries = [entry([false]), entry([true]), entry([false]), entry([true])];
      final units = [[0], [1], [2, 3]];
      expect(nextUnfinishedUnit(entries, units, 0), jeq([2, 3]));
      expect(nextUnfinishedUnit(entries, units, 2), jeq([0]));
    });

    test('returns null only when every unit is complete', () {
      final entries = [entry([true]), entry([true])];
      expect(nextUnfinishedUnit(entries, [[0], [1]], 1), isNull);
    });
  });

  group('rest on a re-check', () {
    test('starts the rest a swallowed re-check would otherwise cost you', () {
      expect(restOnRecheck(timerRunning: false, unitDone: false, lastUnit: false), isTrue);
    });

    test('leaves a rest that is already counting alone', () {
      expect(restOnRecheck(timerRunning: true, unitDone: false, lastUnit: false), isFalse);
    });

    test('still stays quiet on the last set of the last exercise', () {
      expect(restOnRecheck(timerRunning: false, unitDone: true, lastUnit: true), isFalse);
    });

    test('rests after closing an exercise that is not the last one', () {
      expect(restOnRecheck(timerRunning: false, unitDone: true, lastUnit: false), isTrue);
    });
  });

  group('restSecFor', () {
    final entries = [
      {'id': 'a', 'target': {'mode': 'reps'}},
      {'id': 'b', 'target': {'mode': 'reps', 'restSec': 180}},
      {'id': 'c', 'target': {'mode': 'reps', 'restSec': 45}},
    ];

    test('prefers the exercise’s own rest over the global default', () {
      expect(restSecFor(entries, [1], 90), 180);
      expect(restSecFor(entries, [2], 90), 45);
    });

    test('falls back to the global default when the exercise sets none', () {
      expect(restSecFor(entries, [0], 90), 90);
    });

    test('gives a superset the longest rest its members asked for', () {
      expect(restSecFor(entries, [1, 2], 90), 180);
      expect(restSecFor(entries, [0, 2], 90), 90);
    });

    test('honours an explicit rest even with the global timer switched off', () {
      expect(restSecFor(entries, [1], 0), 180);
      expect(restSecFor(entries, [0, 1], 0), 180);
    });

    test('stays off when the timer is off and nothing asked for a rest', () {
      expect(restSecFor(entries, [0], 0), 0);
      expect(restSecFor(entries, [0, 0], 0), 0);
    });

    test('survives a missing unit or entry rather than timing NaN', () {
      expect(restSecFor(entries, null, 90), 90);
      expect(restSecFor(entries, [], 90), 90);
      expect(restSecFor(entries, [7], 90), 90);
      expect(restSecFor(null, [0], null), 0);
    });
  });

  group('warmupRestSecFor', () {
    Map<String, dynamic> ramp(num? warmupRestSec, [List<bool> done = const [false, false, false, false]]) => {
          'target': {'restSec': 150, if (warmupRestSec != null && warmupRestSec != 0) 'warmupRestSec': warmupRestSec},
          'sets': [
            {'phase': 'warmup', 'w': 60, 'r': 8, 'done': done[0]},
            {'phase': 'warmup', 'w': 95, 'r': 5, 'done': done[1]},
            {'phase': 'work', 'w': 125, 'r': 6, 'done': done[2]},
            {'phase': 'work', 'w': 125, 'r': 6, 'done': done[3]},
          ],
        };

    test('rests the warm-up rest between ramp sets', () {
      expect(warmupRestSecFor(ramp(45), 0, 150), 45);
    });

    test('rests the working rest after the last ramp set, into the first work set', () {
      expect(warmupRestSecFor(ramp(45), 1, 150), 150);
    });

    test('rests the working rest after a work set', () {
      expect(warmupRestSecFor(ramp(45), 2, 150), 150);
      expect(warmupRestSecFor(ramp(45), 3, 150), 150);
    });

    test('without the field a ramp set rests like a work set (the pre-field behaviour)', () {
      expect(warmupRestSecFor(ramp(null), 0, 150), 150);
      expect(warmupRestSecFor({'target': {'warmupRestSec': 0}, 'sets': ramp(null)['sets']}, 0, 90), 90);
    });

    test('looks at the next UNFINISHED set: a ramp set re-checked after the work began rests the working rest', () {
      expect(warmupRestSecFor(ramp(45, [true, true, false, false]), 0, 150), 150);
    });

    test('is safe on a legacy warmup boolean and on missing entries', () {
      final legacy = {
        'target': {'warmupRestSec': 45},
        'sets': [{'warmup': true, 'done': false}, {'warmup': true, 'done': false}, {'done': false}],
      };
      expect(warmupRestSecFor(legacy, 0, 120), 45);
      expect(warmupRestSecFor(null, 0, 120), 120);
      expect(warmupRestSecFor({'target': {}, 'sets': []}, 0, 120), 120);
    });
  });

  group('restSecFor with a pyramid set’s own rest', () {
    final entries = [
      {'target': {'restSec': 90}},
      {'target': {'restSec': 60}},
    ];
    test('the set’s rest stands in for its exercise’s', () {
      expect(restSecFor(entries, [0], 120, {'idx': 0, 'sec': 180}), 180);
      expect(restSecFor(entries, [0], 120, {'idx': 0, 'sec': 30}), 30);
    });
    test('0 falls back to the exercise’s rest', () {
      expect(restSecFor(entries, [0], 120, {'idx': 0, 'sec': 0}), 90);
    });
    test('a superset still takes the longest of the group', () {
      expect(restSecFor(entries, [0, 1], 120, {'idx': 1, 'sec': 30}), 90);
      expect(restSecFor(entries, [0, 1], 120, {'idx': 1, 'sec': 200}), 200);
    });
  });
}
