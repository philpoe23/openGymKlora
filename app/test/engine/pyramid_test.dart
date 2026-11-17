// Port of frontend/src/lib/pyramid.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/progression.dart';
import 'package:klora_app/engine/pyramid.dart';

import '_exdb.dart';
import '_helpers.dart';

const lift = '0025';
const pyr = [12, 8, 6, PYRAMID_MAX, 12];
Map<String, dynamic> pyramidCfg([Map<String, dynamic> extra = const {}]) =>
    {'id': lift, 'mode': 'reps', 'sets': 5, 'reps': 12, 'weight': 0, 'pyramid': pyr, ...extra};

Map<String, dynamic> lastTimeS() => {
      'exWeights': {},
      'workouts': [
        {'id': 'w1', 'd': '2026-09-28', 'entries': [
          {'id': lift, 'sets': [
            {'w': 60, 'r': 12, 'done': true}, {'w': 70, 'r': 8, 'done': true}, {'w': 80, 'r': 6, 'done': true},
            {'w': 85, 'r': 9, 'done': true, 'max': true}, {'w': 50, 'r': 12, 'done': true},
          ]},
        ]},
      ],
    };
Map<String, dynamic> emptyS() => {'exWeights': {}, 'workouts': []};
List<dynamic> ws(List<dynamic> rows) => rows.map((r) => r['w']).toList();

void main() {
  setUpAll(loadTestExerciseDb);

  group('isPyramid', () {
    test('is true for a reps exercise with a non-empty list', () {
      expect(isPyramid(pyramidCfg()), isTrue);
    });
    test('is false without the list, with an empty one, or off reps mode', () {
      expect(isPyramid({'id': lift, 'mode': 'reps', 'sets': 3, 'reps': 10}), isFalse);
      expect(isPyramid(pyramidCfg({'pyramid': []})), isFalse);
      expect(isPyramid(pyramidCfg({'mode': 'time', 'sec': 45})), isFalse);
      expect(isPyramid(null), isFalse);
    });
  });

  group('normalizePyramid', () {
    test('keeps whole positive targets and max, in order', () {
      expect(normalizePyramid([12, 8, 6, 'max', 12]), jeq([12, 8, 6, 'max', 12]));
    });
    test('rounds typed numbers and holds them to at least one rep', () {
      expect(normalizePyramid([7.6, 0, -3, '5']), jeq([8, 1, 1, 5]));
    });
    test('drops what is neither a number nor max', () {
      expect(normalizePyramid([10, 'abc', null, null, 'max']), jeq([10, 'max']));
    });
    test('rounds a per-side target up to even, leaving max alone', () {
      expect(normalizePyramid([11, 8, 'max', 1], 2), jeq([12, 8, 'max', 2]));
    });
    test('caps the list at $MAX_PYRAMID_SETS sets', () {
      expect(MAX_PYRAMID_SETS, 10);
      expect(normalizePyramid(List.filled(14, 8)), hasLength(10));
    });
    test('returns an empty list for anything that is not a list', () {
      expect(normalizePyramid(null), jeq([]));
      expect(normalizePyramid('12-8-6'), jeq([]));
    });
  });

  group('switching the toggle (Q14)', () {
    test('turning it on starts from the flat sets × reps', () {
      expect(pyramidFromFlat({'sets': 3, 'reps': 10}), jeq([10, 10, 10]));
    });
    test('turning it on holds the count to 1..10 and an empty reps to 10', () {
      expect(pyramidFromFlat({'sets': 0, 'reps': 8}), jeq([8]));
      expect(pyramidFromFlat({'sets': 20, 'reps': 5}), hasLength(10));
      expect(pyramidFromFlat({'sets': 2}), jeq([10, 10]));
    });
    test('turning it off gives the set count and the first numeric target', () {
      expect(flatFromPyramid([12, 8, 6, 'max', 12]), jeq({'sets': 5, 'reps': 12}));
      expect(flatFromPyramid(['max', 6, 4]), jeq({'sets': 3, 'reps': 6}));
    });
    test('turning it off with only max targets falls back to 10 reps', () {
      expect(flatFromPyramid(['max', 'max']), jeq({'sets': 2, 'reps': 10}));
    });
  });

  group('pyramidLabel (Q12)', () {
    test('reads as the targets joined by a dot', () {
      expect(pyramidLabel(pyr), '12 · 8 · 6 · Max · 12');
    });
  });

  group('pyramidTargetAt (Q16)', () {
    test('is the set’s own target inside the list', () {
      expect(pyramidTargetAt(pyr, 0), 12);
      expect(pyramidTargetAt(pyr, 3), 'max');
    });
    test('copies the last target for an extra set past the list', () {
      expect(pyramidTargetAt(pyr, 5), 12);
      expect(pyramidTargetAt([10, 'max'], 7), 'max');
    });
  });

  group('plan and history read the pyramid (Q12)', () {
    test('setsRepsOf prints the pyramid instead of "5 × 12"', () {
      expect(setsRepsOf(pyramidCfg()), '12 · 8 · 6 · Max · 12');
    });
    test('a flat config still reads the way it did', () {
      expect(setsRepsOf({'id': lift, 'mode': 'reps', 'sets': 3, 'reps': 10}), '3 × 10');
    });
  });

  group('pyramid sets are never progressed (Q7)', () {
    test('policyFor is off even when the exercise or the routine names a rule', () {
      expect(policyFor(pyramidCfg(), null, 'reps'), 'off');
      expect(policyFor(pyramidCfg({'prog': 'linear'}), {'prog': 'greyskull'}, 'reps'), 'off');
    });
  });

  group('buildSets with pyramid sets (Q9, Q13)', () {
    test('a first session opens at each set’s own target, the max set empty and marked', () {
      expect(buildSets(emptyS(), pyramidCfg()), jeq([
        {'w': 0, 'r': 12, 'done': false},
        {'w': 0, 'r': 8, 'done': false},
        {'w': 0, 'r': 6, 'done': false},
        {'w': 0, 'r': 0, 'done': false, 'max': true},
        {'w': 0, 'r': 12, 'done': false},
      ]));
    });
    test('later sessions take each set’s weight from the same set last time, and the max set its reps', () {
      final S = {
        'exWeights': {},
        'workouts': [
          {'id': 'w1', 'd': '2026-09-28', 'entries': [
            {'id': lift, 'sets': [
              {'w': 60, 'r': 10, 'done': true},
              {'w': 70, 'r': 8, 'done': true},
              {'w': 80, 'r': 6, 'done': true},
              {'w': 85, 'r': 9, 'done': true, 'max': true},
              {'w': 50, 'r': 12, 'done': true},
            ]},
          ]},
        ],
      };
      expect(buildSets(S, pyramidCfg()), jeq([
        {'w': 60, 'r': 12, 'done': false},
        {'w': 70, 'r': 8, 'done': false},
        {'w': 80, 'r': 6, 'done': false},
        {'w': 85, 'r': 9, 'done': false, 'max': true},
        {'w': 50, 'r': 12, 'done': false},
      ]));
    });
    test('planned warm-ups still go in front of the pyramid (Q10)', () {
      final rows = buildSets(emptyS(), pyramidCfg({'weight': 0, 'warmupSets': 1}), {'step': 2.5});
      expect(rows, hasLength(6));
      expect(rows[0]['phase'], 'warmup');
      expect(rows.sublist(1).map((r) => r['r']).toList(), jeq([12, 8, 6, 0, 12]));
    });
  });

  // skipped: 'a shared plan keeps the pyramid' (2 cases) — plan-share.js (Task 6).

  group('a planned session builds the pyramid with useTarget (progression off)', () {
    test('the max set still opens at what it did last time, each weight at the same set’s', () {
      final rows = buildSets(lastTimeS(), pyramidCfg(), {'useTarget': true, 'planReps': true});
      expect(ws(rows), jeq([60, 70, 80, 85, 50]));
      expect(rows.map((r) => r['r']).toList(), jeq([12, 8, 6, 9, 12]));
      expect(rows[3]['max'], true);
    });
  });

  group('presets', () {
    test('are four valid pyramids, the back-off one with a max set', () {
      expect(PYRAMID_PRESETS, hasLength(4));
      for (final p in PYRAMID_PRESETS) {
        expect(normalizePyramid(p), jeq(p));
      }
      expect(PYRAMID_PRESETS.map(pyramidLabel).toList(), contains('12 · 8 · 6 · Max · 12'));
    });
  });

  group('rest per set (pyramidRest)', () {
    test('normalizePyramidRest sizes the list and drops an all-zero one', () {
      expect(normalizePyramidRest([90, 120], 4), jeq([90, 120, 0, 0]));
      expect(normalizePyramidRest([90, 120, 60, 30, 15], 3), jeq([90, 120, 60]));
      expect(normalizePyramidRest([0, 0], 2), jeq([]));
      expect(normalizePyramidRest(null, 3), jeq([]));
      expect(normalizePyramidRest([-5, 'x', 44.6], 3), jeq([0, 0, 45]));
    });
    final target = pyramidCfg({'pyramidRest': [60, 90, 180, 120, 0]});
    final rows = [
      {'w': 30, 'r': 5, 'phase': 'warmup'}, {'r': 12}, {'r': 8}, {'r': 6}, {'r': 0, 'max': true}, {'r': 12}, {'r': 12},
    ];
    test('pyramidRestFor counts work sets only, past warm-ups', () {
      expect(pyramidRestFor(target, rows, 1), 60);
      expect(pyramidRestFor(target, rows, 3), 180);
      expect(pyramidRestFor(target, rows, 5), 0);
    });
    test('a warm-up row and an extra set past the list', () {
      expect(pyramidRestFor(target, rows, 0), 0);
      expect(pyramidRestFor(target, rows, 6), 0);
      expect(pyramidRestFor(pyramidCfg({'pyramidRest': [60, 90]}), [{'r': 1}, {'r': 1}, {'r': 1}], 2), 90);
    });
    test('is 0 without a rest list or off a pyramid', () {
      expect(pyramidRestFor(pyramidCfg(), rows, 1), 0);
      expect(pyramidRestFor({'mode': 'reps', 'sets': 3, 'reps': 10, 'pyramidRest': [60]}, [{'r': 10}], 0), 0);
    });
    // skipped: 'travels with a shared plan' — plan-share.js (Task 6).
  });

  group('weight per set (pyramidWeight, #445)', () {
    test('normalizePyramidWeight sizes the list, keeps decimals and drops an all-zero one', () {
      expect(normalizePyramidWeight([40, 52.5], 4), jeq([40, 52.5, 0, 0]));
      expect(normalizePyramidWeight([40, 50, 60, 70], 2), jeq([40, 50]));
      expect(normalizePyramidWeight([0, 0], 2), jeq([]));
      expect(normalizePyramidWeight(null, 3), jeq([]));
      expect(normalizePyramidWeight([-5, 'x', 61.256], 3), jeq([0, 0, 61.26]));
    });
    test('pyramidWeightAt is the set’s own weight, the last one past the list, 0 without one', () {
      final cfg = pyramidCfg({'pyramidWeight': [40, 50, 60, 0, 40]});
      expect(pyramidWeightAt(cfg, 1), 50);
      expect(pyramidWeightAt(cfg, 3), 0);
      expect(pyramidWeightAt(cfg, 7), 40);
      expect(pyramidWeightAt(pyramidCfg(), 0), 0);
      expect(pyramidWeightAt({'mode': 'reps', 'sets': 3, 'reps': 10, 'pyramidWeight': [40]}, 0), 0);
    });
    test('a first session opens each set at its planned weight', () {
      final rows = buildSets(emptyS(), pyramidCfg({'pyramidWeight': [40, 50, 60, 70, 40]}));
      expect(ws(rows), jeq([40, 50, 60, 70, 40]));
    });
    test('a planned session uses each set’s planned weight, and last time’s for a set left at 0', () {
      final rows = buildSets(lastTimeS(), pyramidCfg({'pyramidWeight': [65, 0, 90, 0, 0]}), {'useTarget': true, 'planReps': true});
      expect(ws(rows), jeq([65, 70, 90, 85, 50]));
    });
    test('a hidden flat weight no longer overrides last time in a planned session', () {
      final rows = buildSets(lastTimeS(), pyramidCfg({'weight': 100}), {'useTarget': true, 'planReps': true});
      expect(ws(rows), jeq([60, 70, 80, 85, 50]));
    });
    test('the flat weight is still the first session’s fallback', () {
      final rows = buildSets(emptyS(), pyramidCfg({'weight': 40}), {'useTarget': true, 'planReps': true});
      expect(ws(rows), jeq([40, 40, 40, 40, 40]));
    });
    test('freestyle copies what you lifted, and the plan only when there is nothing to copy', () {
      final cfg = pyramidCfg({'pyramidWeight': [65, 75, 90, 95, 55]});
      expect(ws(buildSets(lastTimeS(), cfg, {'preferLast': true})), jeq([60, 70, 80, 85, 50]));
      expect(ws(buildSets(emptyS(), cfg, {'preferLast': true})), jeq([65, 75, 90, 95, 55]));
    });
    // skipped: 'travels with a shared plan and converts between kg and lb' — plan-share.js (Task 6).
  });

  group('Max set records (Q20, Q21)', () {
    final workouts = [
      {'id': 'a', 'd': '2026-09-01', 'start': 1, 'entries': [{'id': lift, 'sets': [{'w': 85, 'r': 9, 'done': true, 'max': true}, {'w': 50, 'r': 12, 'done': true}]}]},
      {'id': 'b', 'd': '2026-09-08', 'start': 2, 'entries': [{'id': lift, 'sets': [{'w': 80, 'r': 11, 'done': true, 'max': true}]}]},
      {'id': 'c', 'd': '2026-09-15', 'start': 3, 'entries': [{'id': lift, 'sets': [{'w': 90, 'r': 20, 'done': false, 'max': true}, {'w': 85, 'r': 10, 'done': true}]}]},
      {'id': 'd', 'd': '2026-09-22', 'start': 4, 'entries': [{'id': '9999', 'sets': [{'w': 100, 'r': 30, 'done': true, 'max': true}]}]},
    ];
    test('more reps on less weight is not a record', () {
      expect(maxRecordAt(workouts, lift, 85), matchObj({'w': 85, 'r': 9, 'd': '2026-09-01'}));
    });
    test('at a lighter weight every heavier Max set counts', () {
      expect(maxRecordAt(workouts, lift, 80), matchObj({'w': 80, 'r': 11}));
    });
    test('only done Max sets of this exercise count; none heavier is no record', () {
      expect(maxRecordAt(workouts, lift, 86), isNull);
      expect(maxRecordAt([], lift, 0), isNull);
    });
    test('maxRepsSeries is the most reps in a Max set per workout', () {
      expect(maxRepsSeries(workouts, lift), jeq([
        {'t': 1, 'y': 9, 'd': '2026-09-01', 'w': 85},
        {'t': 2, 'y': 11, 'd': '2026-09-08', 'w': 80},
      ]));
    });
  });
}
