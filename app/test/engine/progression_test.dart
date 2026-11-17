// Port of frontend/src/lib/progression.test.js.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/progression.dart';

import '_exdb.dart';
import '_helpers.dart';

const _HEAVY_BP = ['upper legs', 'lower legs', 'back', 'hips', 'glutes'];
const _BW_EQ = ['body weight', 'band', 'resistance band'];

// A plainly loaded lift: more weight is harder (assistance machines excluded, issue #232).
String get LIFT => jsFind(EXDB, (e) => e['bp'] != 'cardio' && !_HEAVY_BP.contains(e['bp']) && !_BW_EQ.contains(e['eq']) && !isAssisted(e['id']))['id'] as String;
String get HEAVY => jsFind(EXDB, (e) => e['bp'] == 'upper legs')['id'] as String;
String get CARDIO => jsFind(EXDB, (e) => e['bp'] == 'cardio')['id'] as String;

// A state whose history is a list of sessions given as [weight, ...repsPerSet]; a null rep count
// means "the set was never checked off".
JMap hist(String id, List<List<num?>> rows, [JMap? target]) => {
      'unit': 'kg',
      'workouts': [
        for (var i = 0; i < rows.length; i++)
          {
            'd': '2026-01-0${i + 1}',
            'entries': [
              {
                'id': id,
                'target': target ?? {'sets': 3, 'reps': 5, 'weight': rows[i][0]},
                'sets': [
                  for (final r in rows[i].skip(1))
                    r == null ? {'w': rows[i][0], 'r': 0, 'done': false} : {'w': rows[i][0], 'r': r, 'done': true},
                ],
              },
            ],
          },
      ],
    };

// The same history with the plan each session was built from stamped on its entries (#275).
JMap stamped(JMap st, JMap planned) => {
      ...st,
      'workouts': [
        for (final w in st['workouts'] as List)
          {
            ...w as Map<String, dynamic>,
            'entries': [for (final e in w['entries'] as List) {...e as Map<String, dynamic>, 'planned': planned}],
          },
      ],
    };

JMap cp(JMap a, JMap b) => {...a, ...b};

void main() {
  setUpAll(loadTestExerciseDb);

  group('readSession', () {
    final T = {'sets': 3, 'reps': 5};
    test('counts a session where every set made its reps as a hit', () {
      final s = readSession({'id': LIFT, 'target': T, 'sets': [{'w': 60, 'r': 5, 'done': true}, {'w': 60, 'r': 5, 'done': true}, {'w': 60, 'r': 6, 'done': true}]});
      expect(s['ok'], isTrue);
      expect(s['weight'], 60);
      expect(s['amrap'], 6);
      expect(s['low'], 5);
    });

    test('counts short reps as a miss even when the set was checked off', () {
      expect(readSession({'id': LIFT, 'target': T, 'sets': [{'w': 60, 'r': 5, 'done': true}, {'w': 60, 'r': 5, 'done': true}, {'w': 60, 'r': 3, 'done': true}]})['ok'], isFalse);
    });

    test('counts an unchecked set as a miss — it was not performed', () {
      final s = readSession({'id': LIFT, 'target': T, 'sets': [{'w': 60, 'r': 5, 'done': true}, {'w': 60, 'r': 5, 'done': true}, {'w': 60, 'r': 0, 'done': false}]});
      expect(s['ok'], isFalse);
      expect(s['weight'], 60);
    });

    test('counts fewer sets than prescribed as a miss', () {
      expect(readSession({'id': LIFT, 'target': T, 'sets': [{'w': 60, 'r': 5, 'done': true}, {'w': 60, 'r': 5, 'done': true}]})['ok'], isFalse);
    });

    test('refuses to call a session a hit when nothing was prescribed', () {
      expect(readSession({'id': LIFT, 'target': {}, 'sets': [{'w': 60, 'r': 5, 'done': true}]})['ok'], isFalse);
    });

    test('reads a timed session by the hold, not by reps', () {
      final s = readSession({'id': LIFT, 'target': {'sets': 2, 'sec': 45, 'mode': 'time'}, 'sets': [{'sec': 45, 'w': 0, 'done': true}, {'sec': 50, 'w': 0, 'done': true}]});
      expect(s['mode'], 'time');
      expect(s['ok'], isTrue);
      expect(s['best'], 50);
      expect(readSession({'id': LIFT, 'target': {'sets': 2, 'sec': 45, 'mode': 'time'}, 'sets': [{'sec': 45, 'done': true}, {'sec': 30, 'done': true}]})['ok'], isFalse);
    });

    test("reads all of a per-side timed hold's doubled rows, not just the first pair", () {
      final T = {'sets': 2, 'sec': 30, 'mode': 'time', 'side': true};
      final allHeld = readSession({'id': LIFT, 'target': T, 'sets': [
        {'sec': 30, 'done': true, 'side': 'L'}, {'sec': 30, 'done': true, 'side': 'R'},
        {'sec': 30, 'done': true, 'side': 'L'}, {'sec': 30, 'done': true, 'side': 'R'},
      ]});
      expect(allHeld['ok'], isTrue);
      final secondPairShort = readSession({'id': LIFT, 'target': T, 'sets': [
        {'sec': 30, 'done': true, 'side': 'L'}, {'sec': 30, 'done': true, 'side': 'R'},
        {'sec': 15, 'done': true, 'side': 'L'}, {'sec': 30, 'done': true, 'side': 'R'},
      ]});
      expect(secondPairShort['ok'], isFalse);
      expect(readSession({'id': LIFT, 'target': T, 'sets': [
        {'sec': 30, 'done': true, 'side': 'L'}, {'sec': 30, 'done': true, 'side': 'R'},
      ]})['ok'], isFalse);
    });
  });

  group('stallCount', () {
    test('counts consecutive misses back from the most recent session', () {
      expect(stallCount([{'ok': true}, {'ok': true}]), 0);
      expect(stallCount([{'ok': true}, {'ok': false}]), 1);
      expect(stallCount([{'ok': false}, {'ok': false}, {'ok': false}]), 3);
      expect(stallCount([{'ok': false}, {'ok': true}, {'ok': false}]), 1);
      expect(stallCount([]), 0);
    });

    JMap miss(num weight, num low) => {'ok': false, 'weight': weight, 'low': low};

    test('measures progress against the best of the run, not merely the session before', () {
      final oscillating = [miss(40, 8), miss(40, 9), miss(40, 8), miss(40, 9), miss(40, 8)];
      expect(stallCount(oscillating, 'double'), 3);
    });

    test('ends the streak at a session that made progress rather than skipping past it', () {
      final improvedLast = [miss(40, 9), miss(40, 9), miss(40, 9), miss(40, 10)];
      expect(stallCount(improvedLast, 'double'), 0);
    });
  });

  group('policyFor', () {
    test("keeps the app's long-standing behaviour as the default for reps work", () {
      expect(policyFor({'id': LIFT}, null, 'reps'), 'linear');
    });
    test('leaves timed and cardio work alone unless asked', () {
      expect(policyFor({'id': LIFT, 'mode': 'time'}, null, 'time'), 'off');
      expect(policyFor({'id': CARDIO}, null, 'cardio'), 'off');
    });
    test('lets the exercise override the routine, and the routine override the default', () {
      expect(policyFor({'id': LIFT}, {'prog': 'greyskull'}, 'reps'), 'greyskull');
      expect(policyFor({'id': LIFT, 'prog': 'double'}, {'prog': 'greyskull'}, 'reps'), 'double');
    });
    test('refuses a policy that makes no sense for the mode', () {
      expect(policyFor({'id': LIFT, 'mode': 'time', 'prog': 'greyskull'}, null, 'time'), 'off');
      expect(policyFor({'id': CARDIO, 'prog': 'linear'}, null, 'cardio'), 'off');
      expect(POLICIES_FOR['cardio'], ['off']);
    });
  });

  group('defaultIncrement', () {
    test('gives lower-body lifts the bigger jump', () {
      expect(defaultIncrement(LIFT, 'kg'), 2.5);
      expect(defaultIncrement(HEAVY, 'kg'), 5);
    });
    test('scales to pounds', () {
      expect(defaultIncrement(LIFT, 'lb'), 5);
      expect(defaultIncrement(HEAVY, 'lb'), 10);
    });
    test('falls back for an unknown exercise', () {
      expect(defaultIncrement('nope', 'kg'), 2.5);
    });
  });

  group('weightIncrement', () {
    test('uses a positive exercise override and otherwise the exercise/unit default', () {
      expect(weightIncrement({'id': LIFT, 'inc': 1}, 'kg'), 1);
      expect(weightIncrement({'id': LIFT}, 'kg'), 2.5);
      expect(weightIncrement({'id': HEAVY, 'inc': 0}, 'kg'), 5);
    });
  });

  group('Epley deload helpers', () {
    test('maps a prescribed target pair to the requested Epley 1RM factor', () {
      expect(epley1RM(60, 8), 76);
      expect(deloadTarget1RM(60, 8), 68.4);
      expect(deloadTarget1RM(60, 8, 0.8), 60.8);
    });

    test('uses the configured factor and keeps the ratio backward-compatible', () {
      expect(DELOAD_FACTOR, 0.9);
      expect(deloadFactorOf({}), 0.9);
      expect(deloadFactorOf({'deloadFactor': 0.8}), 0.8);
      expect(deloadFactorOf({'deloadFactor': 0.1}), 0.9);
    });
  });

  group('linear progression', () {
    JMap cfg() => {'id': LIFT, 'sets': 3, 'reps': 5, 'weight': 60, 'prog': 'linear'};

    test('says nothing useful before there is any history', () {
      final p = nextPrescription({'unit': 'kg', 'workouts': []}, cfg());
      expect(p['kind'], 'first');
      expect(p['weight'], isNull);
    });

    test('adds the increment after a clean session', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 5]]), cfg());
      expect(p['kind'], 'up');
      expect(p['weight'], 62.5);
    });

    test('repeats the weight after a miss instead of advancing', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 3]]), cfg());
      expect(p['kind'], 'hold');
      expect(p['weight'], 60);
    });

    test('does not advance when the last set was left unchecked', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, null]]), cfg());
      expect(p['kind'], 'hold');
      expect(p['weight'], 60);
    });

    test('deloads after three misses in a row, onto a loadable weight', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 3], [60, 5, 4, 4], [60, 5, 5, 4]]), cfg());
      expect(p['kind'], 'deload');
      expect(p['weight'], 55);
      expect(DELOAD_AFTER['linear'], 3);
    });

    test('deloads from the prescribed target reps, not partial actual reps', () {
      final target = {'sets': 3, 'reps': 8, 'weight': 60};
      final p = nextPrescription(hist(LIFT, [[60, 6, 6, 6], [60, 6, 6, 6], [60, 6, 6, 6]], target), cp(cfg(), {'reps': 8}));
      expect(p['kind'], 'deload');
      expect(p['target1RM'], deloadTarget1RM(60, 8));
      expect(p['target1RM'], isNot(deloadTarget1RM(60, 6)));
      expect(p['reps'], 8);
    });

    test('uses a configured Epley factor when selecting the deload load', () {
      final p = nextPrescription(hist(LIFT, [[60, 4, 4, 4], [60, 4, 4, 4], [60, 4, 4, 4]], {'sets': 3, 'reps': 5, 'weight': 60}), cp(cfg(), {'deloadFactor': 0.8}));
      expect(p['kind'], 'deload');
      expect(p['deloadFactor'], 0.8);
      expect(p['target1RM'], 56);
      expect(p['weight'], 47.5);
    });

    test('holds a below-step load instead of deloading upward', () {
      final p = nextPrescription(hist(LIFT, [[1, 1, 1, 1], [1, 1, 1, 1], [1, 1, 1, 1]]), cp(cfg(), {'weight': 1, 'inc': 2.5}));
      expect(p['kind'], 'deload');
      expect(p['weight'], 1);
      expect((p['why'] as List)[0], matches(RegExp('hold', caseSensitive: false)));
    });

    test('a good session in between clears the stall', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 3], [60, 5, 5, 5], [60, 5, 5, 3]]), cfg());
      expect(p['kind'], 'hold');
    });

    test('a deload starts a new streak, so one miss at the new weight does not deload again', () {
      final stalled = <List<num?>>[[60, 4, 4, 4], [60, 4, 4, 4], [60, 4, 4, 4]];
      final deload = nextPrescription(hist(LIFT, stalled), cfg());
      expect(deload['kind'], 'deload');
      final next = nextPrescription(hist(LIFT, [...stalled, [deload['weight'] as num, 4, 4, 4]]), cfg());
      expect(next['kind'], 'hold');
      expect(next['weight'], deload['weight']);
    });

    test('never deloads below one increment, however light the lift already is', () {
      final p = nextPrescription(hist(LIFT, [[2.5, 1, 1, 1], [2.5, 1, 1, 1], [2.5, 1, 1, 1]]), cfg());
      expect(p['kind'], 'deload');
      expect(p['weight'], 2.5);
    });

    test('always makes a deload actually lighter, even when rounding would not', () {
      final p = nextPrescription(hist(LIFT, [[5, 1, 1, 1], [5, 1, 1, 1], [5, 1, 1, 1]]), cfg());
      expect(p['weight'], lessThan(5));
    });

    test('uses the heavier step for a lower-body lift', () {
      final p = nextPrescription(hist(HEAVY, [[100, 5, 5, 5]]), {'id': HEAVY, 'sets': 3, 'reps': 5, 'prog': 'linear'});
      expect(p['weight'], 105);
    });

    test('honours a per-exercise increment override', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 5]]), cp(cfg(), {'inc': 1}));
      expect(p['weight'], 61);
    });

    test('works in pounds', () {
      final S = cp(hist(LIFT, [[135, 5, 5, 5]]), {'unit': 'lb'});
      expect(nextPrescription(S, cfg())['weight'], 140);
    });
  });

  group('bodyweight exercises', () {
    JMap cfg() => {'id': LIFT, 'sets': 3, 'reps': 10, 'weight': 0, 'prog': 'linear', 'bodyweight': true};
    JMap bw(List<List<num?>> rows) => hist(LIFT, rows, {'sets': 3, 'reps': 10});

    test('never invents a weight to deload to — there is nothing to take off a push-up', () {
      final p = nextPrescription(bw([[0, 10, 10, 8], [0, 10, 10, 9], [0, 10, 10, 8]]), cfg());
      expect(p['kind'], 'hold');
      expect(p['weight'], 0);
      expect(p['reps'], 10);
    });

    test('progresses in reps instead of load after a clean session', () {
      final p = nextPrescription(bw([[0, 10, 10, 10]]), cfg());
      expect(p['kind'], 'up');
      expect(p['weight'], 0);
      expect(p['reps'], 11);
    });

    test('climbs to the ceiling one rep at a time', () {
      final p = nextPrescription(bw([[0, 10, 10, 10]]), cp(cfg(), {'repsMax': 15}));
      expect(p['kind'], 'up');
      expect(p['reps'], 11);
      expect(p['sets'], isNull);
    });

    test('adds a set and restarts the range once the ceiling is reached', () {
      final at15 = hist(LIFT, [[0, 15, 15, 15]], {'sets': 3, 'reps': 15});
      final p = nextPrescription(at15, cp(cfg(), {'reps': 10, 'repsMax': 15}));
      expect(p['kind'], 'up');
      expect(p['sets'], 4);
      expect(p['reps'], 10);
      expect(p['weight'], 0);
    });

    test('stops adding sets at the cap and says what to do instead', () {
      final at15 = hist(LIFT, [[0, 15, 15, 15]], {'sets': 3, 'reps': 15});
      final p = nextPrescription(at15, cp(cfg(), {'sets': MAX_BW_SETS, 'reps': 10, 'repsMax': 15}));
      expect(p['kind'], 'hold');
      expect(p['sets'], isNull);
      expect((p['why'] as List)[0], contains('harder variation'));
    });

    test('leaves a belted set to the normal policies — there is a load to add now', () {
      final belted = hist(LIFT, [[10, 10, 10, 10]], {'sets': 3, 'reps': 10});
      final p = nextPrescription(belted, cp(cfg(), {'bodyweight': true, 'repsMax': 15}));
      expect(p['kind'], 'up');
      expect(p['weight'], greaterThan(10));
      expect(p['sets'], isNull);
    });

    test('steps a unilateral total by two, so it lands on 16, 18, 20 (issue #31)', () {
      final at16 = hist(LIFT, [[0, 16, 16, 16]], {'sets': 3, 'reps': 16});
      expect(nextPrescription(at16, cp(cfg(), {'reps': 16, 'side': true}))['reps'], 18);
      expect(nextPrescription(at16, cp(cfg(), {'reps': 16}))['reps'], 17);
    });

    test('keeps climbing reps forever when no ceiling was set — the old behaviour', () {
      final at30 = hist(LIFT, [[0, 30, 30, 30]], {'sets': 3, 'reps': 30});
      final p = nextPrescription(at30, cfg());
      expect(p['kind'], 'up');
      expect(p['reps'], 31);
      expect(p['sets'], isNull);
    });

    test('applies to every policy, not just linear', () {
      for (final prog in ['linear', 'greyskull', 'double']) {
        final p = nextPrescription(bw([[0, 10, 10, 4], [0, 10, 10, 4], [0, 10, 10, 4]]), cp(cfg(), {'prog': prog}));
        expect(p['weight'], 0, reason: prog);
        expect(p['kind'], 'hold', reason: prog);
      }
    });

    test('keeps a set the ceiling added: the next clean session climbs reps at the new count (issue #33)', () {
      final grown = stamped(hist(LIFT, [[0, 10, 10, 10, 10]], {'sets': 4, 'reps': 10}), plannedOf(cfg()));
      final p = nextPrescription(grown, cp(cfg(), {'repsMax': 15}));
      expect(p, matchObj({'kind': 'up', 'reps': 11, 'sets': 4}));
      final missed = stamped(hist(LIFT, [[0, 10, 10, 10, 8]], {'sets': 4, 'reps': 10}), plannedOf(cfg()));
      expect(nextPrescription(missed, cp(cfg(), {'repsMax': 15})), matchObj({'kind': 'hold', 'reps': 10, 'sets': 4}));
    });

    test("opens at the plan's set count after an older session with more sets", () {
      final legacy = hist(LIFT, [[0, 10, 10, 10, 10]], {'sets': 4, 'reps': 10});
      final clean = nextPrescription(legacy, cp(cfg(), {'repsMax': 15}));
      expect(clean, matchObj({'kind': 'up', 'reps': 11}));
      expect(clean['sets'], isNull);
      final missed = nextPrescription(hist(LIFT, [[0, 10, 10, 10, 8]], {'sets': 4, 'reps': 10}), cp(cfg(), {'repsMax': 15}));
      expect(missed, matchObj({'kind': 'hold', 'reps': 10}));
      expect(missed['sets'], isNull);
    });

    test('still adds load the moment the exercise is actually weighted', () {
      final p = nextPrescription(hist(LIFT, [[10, 10, 10, 10]], {'sets': 3, 'reps': 10}), cfg());
      expect(p['kind'], 'up');
      expect(p['weight'], 12.5);
    });
  });

  group('a loaded lift logged at 0 kg', () {
    const BENCH = '0025';
    final zero = hist(BENCH, [[0, 10, 10, 10]], {'sets': 3, 'reps': 10});

    test('holds and asks for the weight instead of climbing reps', () {
      final p = nextPrescription(zero, {'id': BENCH, 'sets': 3, 'reps': 10, 'weight': 0, 'prog': 'linear'});
      expect(p['kind'], 'hold');
      expect(p['reps'], isNull);
      expect(p['weight'], isNull);
      expect((p['why'] as List)[0], contains('No weight logged'));
    });

    test("falls back to the plan's weight when the routine has one", () {
      expect(nextPrescription(zero, {'id': BENCH, 'sets': 3, 'reps': 10, 'weight': 60, 'prog': 'double'}), matchObj({'kind': 'hold', 'weight': 60}));
    });

    const noLoad = {'0857': 'wheel rollerout', '0271': 'crunch on a stability ball', '0653': 'push-up on a bosu ball', '0011': 'assisted hanging knee raise'};
    for (final e in noLoad.entries) {
      test('climbs reps on a ${e.value}, which has nothing to load', () {
        final cfg = {'id': e.key, 'sets': 3, 'reps': 10, 'weight': 0};
        final twice = stamped(hist(e.key, [[0, 10, 10, 10], [0, 10, 10, 10]], {'sets': 3, 'reps': 10}), plannedOf(cfg));
        expect(nextPrescription(twice, cfg), matchObj({'kind': 'up', 'weight': 0, 'reps': 11}));
      });
    }
  });

  group('Greyskull LP', () {
    JMap cfg() => {'id': LIFT, 'sets': 3, 'reps': 5, 'weight': 60, 'prog': 'greyskull'};

    test('advances when the final set makes the target', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 5]]), cfg());
      expect(p['kind'], 'up');
      expect(p['weight'], 62.5);
    });

    test('takes a double jump when the last set doubles the target reps', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 10]]), cfg());
      expect(p['kind'], 'up');
      expect(p['weight'], 65);
      expect((p['why'] as List)[0], contains('double'));
    });

    test('resets 10 % on the very first failure, unlike plain linear', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 3]]), cfg());
      expect(p['kind'], 'deload');
      expect(p['weight'], 55);
      expect(DELOAD_AFTER['greyskull'], 1);
    });

    test('keeps resetting from the reduced weight, not the original', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 3], [55, 5, 5, 2]]), cfg());
      expect(p['kind'], 'deload');
      expect(p['weight'], 50);
    });
  });

  group('double progression', () {
    JMap cfg() => {'id': LIFT, 'sets': 3, 'reps': 12, 'repsMin': 8, 'weight': 40, 'prog': 'double'};

    test('adds weight and drops back to the bottom of the range at the top of it', () {
      final p = nextPrescription(hist(LIFT, [[40, 12, 12, 12]], {'sets': 3, 'reps': 12}), cfg());
      expect(p['kind'], 'up');
      expect(p['weight'], 42.5);
      expect(p['reps'], 8);
    });

    test('does not raise the weight for a session that only matched its own recorded target, short of the top of the range (issue #278)', () {
      final target = {'sets': 3, 'reps': 8, 'weight': 40};
      final p = nextPrescription(hist(LIFT, [[40, 8, 8, 8]], target), cfg());
      expect(p['kind'], isNot('up'));
      expect(p['weight'], 40);
    });

    test('does not deload again when the deload was performed exactly as prescribed', () {
      final target = {'sets': 3, 'reps': 12};
      final stalled = <List<num?>>[[40, 9, 9, 9], [40, 9, 9, 9], [40, 9, 9, 9]];
      final deload = nextPrescription(hist(LIFT, stalled, target), cfg());
      expect(deload['kind'], 'deload');

      final effectiveTarget = {...target, 'weight': deload['weight'], 'reps': deload['reps']};
      final completed = hist(LIFT, stalled, target);
      (completed['workouts'] as List).add({
        'd': '2026-01-04',
        'entries': [
          {
            'id': LIFT,
            'target': effectiveTarget,
            'sets': [for (var i = 0; i < 3; i++) {'w': deload['weight'], 'r': deload['reps'], 'done': true}],
          },
        ],
      });
      final next = nextPrescription(completed, cfg());
      expect(next['kind'], isNot('deload'));
      expect(next['weight'], greaterThanOrEqualTo(deload['weight'] as num));
    });

    test('keeps the weight and asks for one more rep while inside the range', () {
      final p = nextPrescription(hist(LIFT, [[40, 10, 9, 9]], {'sets': 3, 'reps': 12}), cfg());
      expect(p['kind'], 'hold');
      expect(p['weight'], 40);
      expect(p['reps'], 10);
    });

    test('never asks for more than the top of the range', () {
      final p = nextPrescription(hist(LIFT, [[40, 12, 12, 11]], {'sets': 3, 'reps': 12}), cfg());
      expect(p['reps'], lessThanOrEqualTo(12));
    });

    test('deloads after a run of stalls and restarts at the bottom of the range', () {
      final p = nextPrescription(hist(LIFT, [[40, 9, 9, 9], [40, 9, 9, 9], [40, 9, 9, 9]], {'sets': 3, 'reps': 12}), cfg());
      expect(p['kind'], 'deload');
      expect(p['reps'], 8);
      expect(p['weight'], 40);
    });

    test('climbs a range wider than the deload budget instead of cutting on the way up', () {
      final c = cfg();
      expect((c['reps'] as num) - (c['repsMin'] as num), greaterThan(DELOAD_AFTER['double']! - 1));
      final target = {'sets': 3, 'reps': c['reps']};
      final rows = <List<num?>>[];
      JMap p = {'weight': c['weight'], 'reps': c['repsMin']};
      for (var session = 1; session <= 5; session++) {
        rows.add([p['weight'] as num, for (var i = 0; i < 3; i++) p['reps'] as num]);
        p = nextPrescription(hist(LIFT, rows, target), c);
        expect(p['kind'], isNot('deload'));
      }
      expect(p['kind'], 'up');
      expect(p['weight'], greaterThan(c['weight'] as num));
      expect(p['reps'], c['repsMin']);
    });

    test('normalizes persisted per-side bounds before prescribing', () {
      final perSide = cp(cfg(), {'reps': 13, 'repsMin': 7, 'side': true});
      final p = nextPrescription(hist(LIFT, [[40, 12, 12, 12]], {'sets': 3, 'reps': 13}), perSide);
      expect(p['kind'], 'hold');
      expect(p['reps'], 14);
    });

    test('selects a lower in-range rep target and never increases the attempted load', () {
      final target = {'sets': 3, 'reps': 12, 'weight': 40};
      final p = nextPrescription(hist(LIFT, [[40, 9, 9, 9], [40, 9, 9, 9], [40, 9, 9, 9]], target), cfg());
      expect(p['kind'], 'deload');
      expect(p['reps'], greaterThanOrEqualTo(8));
      expect(p['reps'], lessThanOrEqualTo(12));
      expect(p['weight'], lessThanOrEqualTo(40));
      expect(p['target1RM'], deloadTarget1RM(40, 12));
    });

    test('keeps a 5 kg load and lowers reps when that is closer than a 50% weight cut', () {
      final small = {'id': LIFT, 'sets': 3, 'reps': 8, 'repsMin': 4, 'weight': 5, 'inc': 2.5, 'prog': 'double'};
      final target = {'sets': 3, 'reps': 8, 'weight': 5};
      final p = nextPrescription(hist(LIFT, [[5, 6, 6, 6], [5, 6, 6, 6], [5, 6, 6, 6]], target), small);
      expect(p['kind'], 'deload');
      expect(p['weight'], 5);
      expect(p['reps'], 4);
      expect(p['target1RM'], deloadTarget1RM(5, 8));
    });

    test('uses half the reps for per-side Epley and returns an even total', () {
      final perSide = cp(cfg(), {'reps': 8, 'side': true});
      final target = {'sets': 3, 'reps': 8, 'weight': 60, 'side': true};
      final p = nextPrescription(hist(LIFT, [[60, 6, 6, 6], [60, 6, 6, 6], [60, 6, 6, 6]], target), perSide);
      expect(p['kind'], 'deload');
      expect((p['reps'] as num) % 2, 0);
      expect(p['target1RM'], deloadTarget1RM(60, 8, 0.9, true));
    });
  });

  group('timed progression', () {
    JMap cfg() => {'id': LIFT, 'mode': 'time', 'sets': 2, 'sec': 45, 'prog': 'time'};
    final T = {'sets': 2, 'sec': 45, 'mode': 'time'};
    JMap timeHist(List<List<num>> rows) => {
          'unit': 'kg',
          'workouts': [
            for (var i = 0; i < rows.length; i++)
              {
                'd': '2026-02-0${i + 1}',
                'entries': [
                  {'id': LIFT, 'target': T, 'sets': [for (final sec in rows[i]) {'sec': sec, 'w': 0, 'done': true}]},
                ],
              },
          ],
        };

    test('adds time when every set went the full duration', () {
      final p = nextPrescription(timeHist([[45, 45]]), cfg());
      expect(p['kind'], 'up');
      expect(p['sec'], 50);
      expect(p['weight'], isNull);
    });

    test('repeats the target when a hold came up short', () {
      final p = nextPrescription(timeHist([[45, 38]]), cfg());
      expect(p['kind'], 'hold');
      expect(p['sec'], 45);
    });

    test('backs the target off after a run of short sessions', () {
      final p = nextPrescription(timeHist([[45, 30], [45, 32], [45, 31]]), cfg());
      expect(p['kind'], 'deload');
      expect(p['sec'], 40);
    });

    test('ignores reps history when the exercise switched to time', () {
      final S = hist(LIFT, [[60, 5, 5, 5]]);
      final p = nextPrescription(cp(S, {'unit': 'kg'}), cfg());
      expect(p['kind'], 'first');
    });
  });

  group('policy "off"', () {
    test('has no opinion at all', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 5]]), {'id': LIFT, 'sets': 3, 'reps': 5, 'prog': 'off'});
      expect(p['kind'], 'off');
      expect(p['weight'], isNull);
    });
    test('is what cardio always gets', () {
      expect(nextPrescription({'unit': 'kg', 'workouts': []}, {'id': CARDIO, 'sets': 1, 'min': 20})['kind'], 'off');
    });
  });

  group('sessionsFor', () {
    test('skips workouts where the exercise was never actually logged', () {
      final S = {
        'unit': 'kg',
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'target': {'sets': 1, 'reps': 5}, 'sets': [{'w': 60, 'r': 5, 'done': true}]}]},
          {'d': '2026-01-02', 'entries': [{'id': LIFT, 'target': {'sets': 1, 'reps': 5}, 'sets': [{'w': 60, 'r': 0, 'done': false}]}]},
          {'d': '2026-01-03', 'entries': [{'id': 'other', 'target': {}, 'sets': [{'w': 20, 'r': 5, 'done': true}]}]},
        ],
      };
      expect(sessionsFor(S, LIFT).map((s) => s['d']).toList(), ['2026-01-01']);
    });

    test('ignores marked deload workouts when it calculates the next regular target', () {
      final target = {'sets': 3, 'reps': 5, 'weight': 60};
      JMap entry(num weight, List<num> reps) => {
            'id': LIFT,
            'target': {...target, 'weight': weight},
            'sets': [for (final r in reps) {'w': weight, 'r': r, 'done': true}],
          };
      final S = {
        'unit': 'kg',
        'workouts': [
          {'d': '2026-01-01', 'entries': [entry(60, [5, 5, 5])]},
          {'d': '2026-01-08', 'excludeFromProgression': true, 'entries': [entry(30, [8, 8])]},
        ],
      };
      expect(sessionsFor(S, LIFT).map((s) => s['d']).toList(), ['2026-01-01']);
      expect(nextPrescription(S, {'id': LIFT, ...target, 'prog': 'linear'})['weight'], 62.5);
    });

    test('reads a legacy entry that has no target without crashing', () {
      final S = {'unit': 'kg', 'workouts': [{'d': '2026-01-01', 'entries': [{'id': LIFT, 'sets': [{'w': 60, 'r': 5, 'done': true}]}]}]};
      expect(sessionsFor(S, LIFT), hasLength(1));
    });
  });

  group('routine slots (#216)', () {
    JMap entry(String rid, num w, num r) => {
          'id': LIFT, 'rid': rid, 'target': {'sets': 2, 'reps': r, 'weight': w},
          'sets': [{'w': w, 'r': r, 'done': true}, {'w': w, 'r': r, 'done': true}],
        };
    JMap S() => {
          'unit': 'kg',
          'workouts': [
            {'d': '2026-03-01', 'routineIds': ['heavy'], 'entries': [entry('heavy', 60, 10)]},
            {'d': '2026-03-03', 'routineIds': ['light'], 'entries': [entry('light', 40, 15)]},
          ],
        };
    final heavy = {'id': 'heavy', 'prog': 'linear', 'ex': []};
    final light = {'id': 'light', 'prog': 'linear', 'ex': []};

    test("reads only the routine's own sessions, each marked with its routine", () {
      expect(sessionsFor(S(), LIFT, null, 'heavy').map((s) => [s['d'], s['rid'], s['weight']]).toList(), jeq([['2026-03-01', 'heavy', 60]]));
      expect(sessionsFor(S(), LIFT, null, 'light').map((s) => [s['d'], s['rid'], s['weight']]).toList(), jeq([['2026-03-03', 'light', 40]]));
      expect(sessionsFor(S(), LIFT), hasLength(2));
    });

    test('progresses each routine from its own last session', () {
      expect(nextPrescription(S(), {'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 60}, heavy)['weight'], 62.5);
      expect(nextPrescription(S(), {'id': LIFT, 'sets': 2, 'reps': 15, 'weight': 40}, light)['weight'], 42.5);
    });

    test("falls back to the exercise's history for a routine that never trained it", () {
      expect(sessionsFor(S(), LIFT, null, 'new').map((s) => s['rid']).toList(), ['heavy', 'light']);
    });

    test("reads a combined day by the routine's own entry, not the first one", () {
      final combined = {'unit': 'kg', 'workouts': [{'d': '2026-03-05', 'routineIds': ['heavy', 'light'], 'entries': [entry('heavy', 60, 10), entry('light', 40, 15)]}]};
      expect(sessionsFor(combined, LIFT, null, 'light').map((s) => s['weight']).toList(), [40]);
      expect(nextPrescription(combined, {'id': LIFT, 'sets': 2, 'reps': 15, 'weight': 40}, light)['weight'], 42.5);
    });

    test('does not let a stall on one routine deload the other', () {
      JMap miss(String d, String rid, num w) => {
            'd': d, 'routineIds': [rid],
            'entries': [{'id': LIFT, 'rid': rid, 'target': {'sets': 2, 'reps': 10, 'weight': w}, 'sets': [{'w': w, 'r': 6, 'done': true}, {'w': w, 'r': 6, 'done': true}]}],
          };
      final st = {'unit': 'kg', 'workouts': [miss('2026-03-01', 'heavy', 60), (S()['workouts'] as List)[1], miss('2026-03-05', 'heavy', 60), miss('2026-03-07', 'heavy', 60)]};
      expect(nextPrescription(st, {'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 60}, heavy)['kind'], 'deload');
      expect(nextPrescription(st, {'id': LIFT, 'sets': 2, 'reps': 15, 'weight': 40}, light)['kind'], 'up');
    });

    test("reads a session saved before per-entry routine ids by the workout's routine", () {
      final legacy = {'unit': 'kg', 'workouts': [{'d': '2026-03-01', 'routineId': 'heavy', 'entries': [{'id': LIFT, 'target': {'sets': 2, 'reps': 10, 'weight': 60}, 'sets': [{'w': 60, 'r': 10, 'done': true}, {'w': 60, 'r': 10, 'done': true}]}]}]};
      expect(sessionsFor(legacy, LIFT, null, 'heavy').map((s) => s['rid']).toList(), ['heavy']);
    });
  });

  group('an edited plan restarts progression (#275)', () {
    String PUSH() => jsFind(EXDB, (e) => e['eq'] == 'body weight' && e['bp'] != 'cardio')['id'] as String;
    JMap logged(String id, JMap planned, JMap target, num w, List<num> reps, [JMap extra = const {}]) => {
          'd': '2026-04-01', 'routineIds': ['r'],
          'entries': [{'id': id, 'planned': planned, 'target': target, 'sets': [for (final r in reps) {'w': w, 'r': r, 'done': true}], ...extra}],
        };
    final R = {'id': 'r', 'ex': []};

    test('stamps only what the routine asks for, and tells an edit from a progression', () {
      expect(plannedOf({'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 60, 'prog': 'linear', 'note': 'x'}), jeq({'sets': 2, 'reps': 10, 'weight': 60}));
      expect(plannedOf({'id': LIFT, 'sets': 3, 'reps': 12, 'repsMin': 8, 'weight': 40}), jeq({'sets': 3, 'reps': 12, 'repsMin': 8, 'weight': 40}));
      expect(plannedOf({'id': LIFT, 'mode': 'time', 'sets': 2, 'sec': 45, 'weight': 0}), jeq({'sets': 2, 'sec': 45, 'weight': 0}));
      final planned = plannedOf({'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 60});
      expect(planChanged(planned, {'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 80}), isFalse);
      expect(planChanged(planned, {'id': LIFT, 'sets': 2, 'reps': 12, 'weight': 60}), isTrue);
      expect(planChanged(planned, {'id': LIFT, 'sets': 3, 'reps': 10, 'weight': 60}), isTrue);
      expect(planChanged(planned, {'id': LIFT, 'sets': 2, 'reps': 12, 'repsMin': 10, 'weight': 60}), isTrue);
      expect(planChanged(null, {'id': LIFT, 'sets': 2, 'reps': 12}), isFalse);
    });

    test("holds the weight at the new sets × reps when a loaded lift's plan was edited", () {
      final S = {'unit': 'kg', 'workouts': [logged(LIFT, {'sets': 2, 'reps': 15, 'weight': 40}, {'sets': 2, 'reps': 15, 'weight': 40}, 40, [15, 15])]};
      final p = nextPrescription(S, {'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 40, 'prog': 'linear'}, R);
      expect(p, matchObj({'kind': 'hold', 'weight': 40, 'reps': 10}));
      expect((p['why'] as List)[0], 'Plan changed, so starting from your new target.');
      expect(nextPrescription(S, {'id': LIFT, 'sets': 2, 'reps': 15, 'weight': 40, 'prog': 'linear'}, R), matchObj({'kind': 'up', 'weight': 42.5}));
    });

    test("opens at the plan's new weight when the edit changed it along with the reps", () {
      final five = logged(LIFT, {'sets': 3, 'reps': 5, 'weight': 100}, {'sets': 3, 'reps': 5, 'weight': 102.5}, 102.5, [5, 5, 5]);
      final S = {'unit': 'kg', 'workouts': [five]};
      final p = nextPrescription(S, {'id': LIFT, 'sets': 3, 'reps': 10, 'weight': 70, 'prog': 'linear'}, R);
      expect(p, matchObj({'kind': 'hold', 'weight': 70, 'reps': 10}));
      expect((p['why'] as List)[0], 'Plan changed, so starting from your new target.');
      expect(nextPrescription(S, {'id': LIFT, 'sets': 3, 'reps': 10, 'weight': 100, 'prog': 'linear'}, R), matchObj({'kind': 'hold', 'weight': 102.5, 'reps': 10}));
      expect(nextPrescription(S, {'id': LIFT, 'sets': 3, 'reps': 5, 'weight': 70, 'prog': 'linear'}, R), matchObj({'kind': 'up', 'weight': 105}));
    });

    test('starts a new weight at the bottom of a double-progression range', () {
      final twelve = logged(LIFT, {'sets': 3, 'reps': 12, 'weight': 40}, {'sets': 3, 'reps': 12, 'weight': 40}, 40, [12, 12, 12]);
      final p = nextPrescription({'unit': 'kg', 'workouts': [twelve]}, {'id': LIFT, 'sets': 3, 'reps': 12, 'repsMin': 8, 'weight': 60, 'prog': 'double'}, R);
      expect(p, matchObj({'kind': 'hold', 'weight': 60, 'reps': 8}));
    });

    test('restarts a bodyweight goal from the new reps instead of climbing from the old ones', () {
      final S = {'unit': 'kg', 'workouts': [logged(PUSH(), {'sets': 2, 'reps': 15, 'weight': 0}, {'sets': 2, 'reps': 15, 'weight': 0}, 0, [15, 15])]};
      final p = nextPrescription(S, {'id': PUSH(), 'sets': 2, 'reps': 10, 'weight': 0, 'bodyweight': true}, R);
      expect(p, matchObj({'kind': 'hold', 'weight': 0, 'reps': 10}));
    });

    test('does not deload toward the old target after three misses and an edit', () {
      final miss = {'d': '2026-04-01', 'routineIds': ['r'], 'entries': [{'id': LIFT, 'planned': {'sets': 3, 'reps': 15, 'weight': 50}, 'target': {'sets': 3, 'reps': 15, 'weight': 50}, 'sets': [for (final r in [12, 12, 12]) {'w': 50, 'r': r, 'done': true}]}]};
      final S = {'unit': 'kg', 'workouts': [miss, miss, miss]};
      expect(nextPrescription(S, {'id': LIFT, 'sets': 3, 'reps': 15, 'weight': 50, 'prog': 'linear'}, R)['kind'], 'deload');
      final p = nextPrescription(S, {'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 50, 'prog': 'linear'}, R);
      expect(p, matchObj({'kind': 'hold', 'weight': 50, 'reps': 10}));
      expect(p['sets'], isNull);
    });

    test('ends a stall streak at the edit — misses against the old plan do not count', () {
      JMap atP(JMap planned, List<num> reps) => {
            'd': '2026-04-01', 'routineIds': ['r'],
            'entries': [{'id': LIFT, 'planned': planned, 'target': {...planned}, 'sets': [for (final r in reps) {'w': 50, 'r': r, 'done': true}]}],
          };
      final old = {'sets': 3, 'reps': 15, 'weight': 50};
      final now = {'sets': 3, 'reps': 10, 'weight': 50};
      final S = {'unit': 'kg', 'workouts': [atP(old, [12, 12, 12]), atP(old, [12, 12, 12]), atP(now, [9, 9, 9])]};
      expect(stallCount(sessionsFor(S, LIFT, null, 'r')), 1);
      expect(nextPrescription(S, {'id': LIFT, ...now, 'prog': 'linear'}, R)['kind'], 'hold');
    });

    test('aims inside the new range under double progression, from what you managed', () {
      final S = {'unit': 'kg', 'workouts': [logged(LIFT, {'sets': 3, 'reps': 8, 'weight': 36}, {'sets': 3, 'reps': 8, 'weight': 36}, 36, [8, 8, 8])]};
      final p = nextPrescription(S, {'id': LIFT, 'sets': 3, 'reps': 12, 'repsMin': 8, 'weight': 36, 'prog': 'double'}, R);
      expect(p, matchObj({'kind': 'hold', 'weight': 36, 'reps': 9}));
    });

    test('restarts a timed hold at its new duration', () {
      final S = {'unit': 'kg', 'workouts': [logged(LIFT, {'sets': 2, 'sec': 60, 'weight': 0}, {'mode': 'time', 'sets': 2, 'sec': 60}, 0, [], {'sets': [{'sec': 60, 'done': true}, {'sec': 60, 'done': true}]})]};
      final p = nextPrescription(S, {'id': LIFT, 'mode': 'time', 'sets': 2, 'sec': 30, 'weight': 0, 'prog': 'time'}, R);
      expect(p, matchObj({'kind': 'hold', 'sec': 30}));
    });

    test("starts a routine from its own target when the only history is another routine's", () {
      final B = {'d': '2026-04-01', 'routineIds': ['b'], 'entries': [{'id': PUSH(), 'rid': 'b', 'planned': {'sets': 2, 'reps': 15, 'weight': 0}, 'target': {'sets': 2, 'reps': 15, 'weight': 0}, 'sets': [{'w': 0, 'r': 15, 'done': true}, {'w': 0, 'r': 15, 'done': true}]}]};
      final p = nextPrescription({'unit': 'kg', 'workouts': [B]}, {'id': PUSH(), 'sets': 2, 'reps': 10, 'weight': 0, 'bodyweight': true}, {'id': 'a', 'ex': []});
      expect(p, matchObj({'kind': 'hold', 'reps': 10}));
      expect((p['why'] as List)[0], 'First time in this routine, so starting from its own target.');
    });

    test('starts a routine at its own weight when the routine it borrows from planned another', () {
      final B = {'d': '2026-04-01', 'routineIds': ['b'], 'entries': [{'id': LIFT, 'rid': 'b', 'planned': {'sets': 2, 'reps': 15, 'weight': 40}, 'target': {'sets': 2, 'reps': 15, 'weight': 40}, 'sets': [{'w': 40, 'r': 15, 'done': true}, {'w': 40, 'r': 15, 'done': true}]}]};
      final p = nextPrescription({'unit': 'kg', 'workouts': [B]}, {'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 60, 'prog': 'linear'}, {'id': 'a', 'ex': []});
      expect(p, matchObj({'kind': 'hold', 'weight': 60, 'reps': 10}));
      expect((p['why'] as List)[0], 'First time in this routine, so starting from its own target.');
    });

    test("opens a loaded lift logged at 0 kg at the plan's weight when the plan changed", () {
      const BENCH = '0025';
      final S = {'unit': 'kg', 'workouts': [logged(BENCH, {'sets': 2, 'reps': 15, 'weight': 0}, {'sets': 2, 'reps': 15, 'weight': 0}, 0, [15, 15])]};
      expect(nextPrescription(S, {'id': BENCH, 'sets': 2, 'reps': 10, 'weight': 50, 'prog': 'linear'}, R), matchObj({'kind': 'hold', 'weight': 50, 'reps': 10}));
    });

    test("continues another routine's progression when its plan is the same one (a copied routine)", () {
      final B = {'d': '2026-04-01', 'routineIds': ['b'], 'entries': [{'id': LIFT, 'rid': 'b', 'planned': {'sets': 2, 'reps': 10, 'weight': 60}, 'target': {'sets': 2, 'reps': 10, 'weight': 60}, 'sets': [{'w': 60, 'r': 10, 'done': true}, {'w': 60, 'r': 10, 'done': true}]}]};
      expect(nextPrescription({'unit': 'kg', 'workouts': [B]}, {'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 60, 'prog': 'linear'}, {'id': 'copy', 'ex': []}),
          matchObj({'kind': 'up', 'weight': 62.5}));
    });

    test('leaves history saved before plans were stamped to progress as it always did', () {
      final S = {'unit': 'kg', 'workouts': [{'d': '2026-04-01', 'routineIds': ['r'], 'entries': [{'id': LIFT, 'target': {'sets': 2, 'reps': 15, 'weight': 40}, 'sets': [{'w': 40, 'r': 15, 'done': true}, {'w': 40, 'r': 15, 'done': true}]}]}]};
      expect(nextPrescription(S, {'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 40, 'prog': 'linear'}, R), matchObj({'kind': 'up', 'weight': 42.5}));
    });

    test("aims an Epley deload at the plan's set count even for history saved before plans were stamped", () {
      final miss = {'d': '2026-04-01', 'routineIds': ['r'], 'entries': [{'id': LIFT, 'target': {'sets': 3, 'reps': 8, 'weight': 60}, 'sets': [for (final r in [6, 6, 6]) {'w': 60, 'r': r, 'done': true}]}]};
      final p = nextPrescription({'unit': 'kg', 'workouts': [miss, miss, miss]}, {'id': LIFT, 'sets': 2, 'reps': 8, 'weight': 60, 'prog': 'linear'}, R);
      expect(p['kind'], 'deload');
      expect(p['sets'], 2);
    });
  });

  group('per-entry noProg (combine routines)', () {
    String PRESS() => jsFind(EXDB, (e) => e['bp'] != 'cardio' && e['id'] != LIFT && !_HEAVY_BP.contains(e['bp']))['id'] as String;
    JMap tgt(num w) => {'sets': 3, 'reps': 5, 'weight': w};
    JMap entry(String id, num w, List<num> reps, [JMap extra = const {}]) =>
        {'id': id, 'target': tgt(w), 'sets': [for (final r in reps) {'w': w, 'r': r, 'done': true}], ...extra};

    test('skips a noProg entry for that exercise only, in a mixed combined session', () {
      final S = {
        'unit': 'kg',
        'workouts': [
          {'d': '2026-02-01', 'routineIds': ['strength', 'rehab'], 'entries': [entry(LIFT, 60, [5, 5, 5]), entry(PRESS(), 40, [5, 5, 5], {'noProg': true})]},
        ],
      };
      expect(sessionsFor(S, LIFT), hasLength(1));
      expect(sessionsFor(S, PRESS()), hasLength(0));
    });

    test('still advances the non-excluded exercise of a mixed combined session', () {
      final S = {
        'unit': 'kg',
        'workouts': [
          {'d': '2026-02-01', 'entries': [entry(LIFT, 60, [5, 5, 5]), entry(PRESS(), 40, [5, 5, 5], {'noProg': true})]},
        ],
      };
      expect(nextPrescription(S, {'id': LIFT, ...tgt(60), 'prog': 'linear'})['weight'], 62.5);
    });

    test('a noProg gap never becomes the deload / stall baseline', () {
      final S = {
        'unit': 'kg',
        'workouts': [
          {'d': '2026-02-01', 'entries': [entry(LIFT, 60, [5, 5, 5])]},
          {'d': '2026-02-03', 'entries': [entry(LIFT, 60, [5, 5, 5])]},
          {'d': '2026-02-05', 'entries': [entry(LIFT, 30, [8, 8, 8], {'noProg': true})]},
        ],
      };
      expect(sessionsFor(S, LIFT).map((s) => s['d']).toList(), ['2026-02-01', '2026-02-03']);
      expect(nextPrescription(S, {'id': LIFT, ...tgt(60), 'prog': 'linear'})['weight'], 62.5);
    });

    test('honours a legacy whole-workout excludeFromProgression flag (all entries skipped)', () {
      final S = {
        'unit': 'kg',
        'workouts': [
          {'d': '2026-02-01', 'entries': [entry(LIFT, 60, [5, 5, 5])]},
          {'d': '2026-02-08', 'excludeFromProgression': true, 'entries': [entry(LIFT, 30, [8, 8])]},
        ],
      };
      expect(sessionsFor(S, LIFT).map((s) => s['d']).toList(), ['2026-02-01']);
    });

    test('an exercise only ever logged noProg → sessionsFor [] → nextPrescription kind "first"', () {
      final S = {
        'unit': 'kg',
        'workouts': [
          {'d': '2026-02-01', 'entries': [entry(LIFT, 30, [8, 8, 8], {'noProg': true})]},
        ],
      };
      expect(sessionsFor(S, LIFT), hasLength(0));
      expect(nextPrescription(S, {'id': LIFT, ...tgt(50), 'prog': 'linear'})['kind'], 'first');
    });

    test('entryExcluded truth table', () {
      expect(entryExcluded({}, {}), isFalse);
      expect(entryExcluded({'excludeFromProgression': true}, {}), isTrue);
      expect(entryExcluded({}, {'noProg': true}), isTrue);
      expect(entryExcluded({'excludeFromProgression': true}, {'noProg': true}), isTrue);
    });

    test('stallCount is not reset by a noProg gap at the same weight', () {
      JMap miss(String d) => {'d': d, 'entries': [entry(LIFT, 60, [4, 4, 4])]};
      final S = {
        'unit': 'kg',
        'workouts': [
          {'d': '2026-02-01', 'entries': [entry(LIFT, 60, [5, 5, 5])]},
          miss('2026-02-03'),
          {'d': '2026-02-04', 'entries': [entry(LIFT, 60, [3, 3, 3], {'noProg': true})]},
          miss('2026-02-05'),
          miss('2026-02-07'),
        ],
      };
      final sessions = sessionsFor(S, LIFT);
      expect(sessions.map((s) => s['d']).toList(), ['2026-02-01', '2026-02-03', '2026-02-05', '2026-02-07']);
      expect(stallCount(sessions), 3);
      expect(nextPrescription(S, {'id': LIFT, ...tgt(60), 'prog': 'linear'})['kind'], 'deload');
    });
  });

  group('history logged before targets were recorded', () {
    JMap legacy(List<List<num>> rows) => {
          'unit': 'kg',
          'workouts': [
            for (var i = 0; i < rows.length; i++)
              {
                'd': '2026-03-${'${i + 1}'.padLeft(2, '0')}',
                'entries': [
                  {'id': LIFT, 'sets': [for (final r in rows[i].skip(1)) {'w': rows[i][0], 'r': r, 'done': true}]},
                ],
              },
          ],
        };
    JMap cfg() => {'id': LIFT, 'sets': 3, 'reps': 5, 'weight': 60, 'prog': 'linear'};

    test('judges a targetless session against the current plan instead of calling it a miss', () {
      final p = nextPrescription(legacy([[60, 5, 5, 5]]), cfg());
      expect(p['kind'], 'up');
      expect(p['weight'], 62.5);
    });

    test('does not manufacture a stall out of a long clean history', () {
      final p = nextPrescription(legacy(List.generate(11, (_) => [60, 5, 5, 5])), cfg());
      expect(p['kind'], 'up');
    });

    test('still spots a genuine miss in old data', () {
      expect(nextPrescription(legacy([[60, 5, 5, 2]]), cfg())['kind'], 'hold');
    });

    test('matches the weight hint the app showed before this engine existed', () {
      expect(nextPrescription(legacy([[60, 5, 6, 5]]), cfg())['weight'], 62.5);
      expect(nextPrescription(legacy([[60, 5, 4, 5]]), cfg())['kind'], 'hold');
    });
  });

  group('applyPrescription', () {
    List<dynamic> sets() => [{'w': 60, 'r': 5, 'done': true}, {'w': 60, 'r': 5, 'done': false}];

    test('rewrites only what the policy decided, and only unlogged sets', () {
      final out = applyPrescription(sets(), {'kind': 'up', 'weight': 62.5});
      expect(out[0], jeq({'w': 60, 'r': 5, 'done': true}));
      expect(out[1], jeq({'w': 62.5, 'r': 5, 'done': false}));
    });

    test('sets reps too when the policy has an opinion about them', () {
      expect(applyPrescription(sets(), {'kind': 'up', 'weight': 42.5, 'reps': 8})[1], jeq({'w': 42.5, 'r': 8, 'done': false}));
    });

    test('re-ramps an open warm-up toward the new weight but never under the bar', () {
      final sets = [{'w': 25, 'r': 10, 'done': false, 'phase': 'warmup', 'warmup': true}, {'w': 50, 'r': 10, 'done': false}];
      expect(applyPrescription(sets, {'kind': 'up', 'weight': 55}, 5, 45).map((r) => r['w']).toList(), jeq([45, 55]));
      expect(applyPrescription(sets, {'kind': 'up', 'weight': 55}, 5).map((r) => r['w']).toList(), jeq([25, 55]));
    });

    test('touches nothing for "off" or a first session', () {
      final s = sets();
      expect(applyPrescription(s, {'kind': 'off'}), same(s));
      expect(applyPrescription(s, {'kind': 'first'}), same(s));
      expect(applyPrescription(s, null), same(s));
    });

    test('adjusts a timed set without inventing a weight', () {
      final timed = [{'sec': 45, 'w': 0, 'done': false}];
      expect(applyPrescription(timed, {'kind': 'up', 'sec': 50}), jeq([{'sec': 50, 'w': 0, 'done': false}]));
    });

    test('grows the list when the policy added a set (issue #33)', () {
      final three = [{'w': 0, 'r': 10, 'done': false}, {'w': 0, 'r': 10, 'done': false}, {'w': 0, 'r': 10, 'done': false}];
      final out = applyPrescription(three, {'kind': 'up', 'weight': 0, 'reps': 10, 'sets': 4});
      expect(out, hasLength(4));
      expect(out[3], jeq({'w': 0, 'r': 10, 'done': false}));
    });

    test('never shrinks a session that has already logged sets', () {
      expect(applyPrescription(sets(), {'kind': 'up', 'weight': 60, 'sets': 1}), hasLength(2));
    });
  });

  group('warm-up rows in session reads (round 3)', () {
    test('readSession ignores warm-up rows for reps, count, low and ok', () {
      final s = readSession({'id': LIFT, 'target': {'sets': 2, 'reps': 5, 'mode': 'reps'}, 'sets': [
        {'w': 20, 'r': 8, 'done': true, 'warmup': true},
        {'w': 60, 'r': 5, 'done': true},
        {'w': 60, 'r': 6, 'done': true},
      ]});
      expect(s['count'], 2);
      expect(s['low'], 5);
      expect(s['reps'], jeq([5, 6]));
      expect(s['ok'], isTrue);
    });

    test('readSession keeps an undone warm-up out of held/ok in time mode', () {
      final s = readSession({'id': LIFT, 'target': {'sets': 2, 'sec': 45, 'mode': 'time'}, 'sets': [
        {'sec': 45, 'done': true, 'warmup': true},
        {'sec': 45, 'done': true},
        {'sec': 30, 'done': true},
      ]});
      expect(s['held'], jeq([45, 30]));
      expect(s['ok'], isFalse);
    });

    test('uses phase as authoritative and falls back to the legacy warm-up flag', () {
      final s = readSession({'id': LIFT, 'target': {'sets': 1, 'reps': 5}, 'sets': [
        {'phase': 'warmup', 'w': 120, 'r': 20, 'done': true},
        {'phase': 'work', 'warmup': true, 'w': 60, 'r': 5, 'done': true},
      ]});
      expect(s['count'], 1);
      expect(s['weight'], 60);
      expect(s['low'], 5);
      expect(s['ok'], isTrue);
    });
  });

  group('applyPrescription never touches warm-up rows (round 3)', () {
    List<dynamic> sets() => [
          {'w': 20, 'r': 8, 'done': true, 'warmup': true},
          {'w': 60, 'r': 5, 'done': true},
          {'w': 60, 'r': 5, 'done': false},
        ];

    test('leaves a done warm-up exactly as logged', () {
      final out = applyPrescription(sets(), {'kind': 'up', 'weight': 62.5, 'reps': 5});
      expect(out[0], jeq({'w': 20, 'r': 8, 'done': true, 'warmup': true}));
      expect(out[1], jeq({'w': 60, 'r': 5, 'done': true}));
      expect(out[2], jeq({'w': 62.5, 'r': 5, 'done': false}));
    });

    test('grows the work rows, not the warm-up rows, when the policy adds sets', () {
      final out = applyPrescription(sets(), {'kind': 'up', 'weight': 62.5, 'reps': 5, 'sets': 4});
      expect(out.where((s) => !truthy(s['warmup'])), hasLength(4));
      expect(out.where((s) => truthy(s['warmup'])), hasLength(1));
      expect(out[0], jeq({'w': 20, 'r': 8, 'done': true, 'warmup': true}));
    });

    test('an open warm-up follows the reps or the hold the policy settled on, never a done one', () {
      final reps = applyPrescription([
        {'w': 20, 'r': 8, 'done': true, 'warmup': true},
        {'w': 0, 'r': 10, 'done': false, 'phase': 'warmup'},
        {'w': 0, 'r': 10, 'done': false},
      ], {'kind': 'up', 'weight': 0, 'reps': 12});
      expect(reps.map((s) => s['r']).toList(), jeq([8, 12, 12]));
      final held = applyPrescription([{'sec': 30, 'w': 0, 'done': false, 'phase': 'warmup'}, {'sec': 30, 'w': 0, 'done': false}], {'kind': 'up', 'sec': 35});
      expect(held.map((s) => s['sec']).toList(), jeq([35, 35]));
    });

    test('an all-warm-up entry terminates and stays untouched', () {
      final sets = [
        {'w': 20, 'r': 8, 'done': true, 'warmup': true},
        {'w': 25, 'r': 6, 'done': true, 'warmup': true},
      ];
      final out = applyPrescription(sets, {'kind': 'up', 'weight': 62.5, 'reps': 5, 'sets': 4});
      expect(out, jeq(sets));
    });
  });

  group('drop-sets and rest-pause sets in progression', () {
    test('readSession judges a drop-set row on its own main weight/reps, ignoring the drops', () {
      final withDrops = readSession({'id': LIFT, 'target': {'sets': 1, 'reps': 5}, 'sets': [
        {'type': 'dropset', 'w': 60, 'r': 5, 'done': true, 'drops': [{'w': 40, 'r': 8}, {'w': 20, 'r': 10}]},
      ]});
      final plain = readSession({'id': LIFT, 'target': {'sets': 1, 'reps': 5}, 'sets': [{'w': 60, 'r': 5, 'done': true}]});
      expect(withDrops, jeq(plain));
    });

    test('readSession judges a rest-pause row on its activation weight/reps, ignoring the bursts', () {
      final withBursts = readSession({'id': LIFT, 'target': {'sets': 1, 'reps': 8}, 'sets': [
        {'type': 'restpause', 'w': 60, 'r': 8, 'done': true, 'clusters': [{'r': 4, 'restSec': 15}, {'r': 3, 'restSec': 15}]},
      ]});
      final plain = readSession({'id': LIFT, 'target': {'sets': 1, 'reps': 8}, 'sets': [{'w': 60, 'r': 8, 'done': true}]});
      expect(withBursts, jeq(plain));
    });

    test("applyPrescription still rewrites a drop-set/rest-pause row's own weight, leaving its drops/clusters untouched", () {
      final sets = [{'type': 'dropset', 'w': 60, 'r': 5, 'done': false, 'drops': [{'w': 40, 'r': 8}]}];
      final out = applyPrescription(sets, {'kind': 'up', 'weight': 62.5});
      expect(out[0], jeq({'type': 'dropset', 'w': 62.5, 'r': 5, 'done': false, 'drops': [{'w': 40, 'r': 8}]}));
    });

    test("a newly grown row keeps the seed's planned type but not its already-logged drops/clusters", () {
      final sets = [{'type': 'dropset', 'w': 0, 'r': 10, 'done': false, 'drops': [{'w': 0, 'r': 12}]}];
      final out = applyPrescription(sets, {'kind': 'up', 'weight': 0, 'reps': 10, 'sets': 2});
      expect(out, hasLength(2));
      expect(out[1], jeq({'type': 'dropset', 'w': 0, 'r': 10, 'done': false}));
    });
  });

  group('a weight off the increment grid keeps its offset when it goes up (issue #175)', () {
    test('adds the step instead of snapping the sum to the grid', () {
      final lin = {'id': LIFT, 'sets': 3, 'reps': 5, 'weight': 397, 'prog': 'linear', 'inc': 10};
      final p = nextPrescription(hist(LIFT, [[397, 5, 5, 5]], {'sets': 3, 'reps': 5, 'weight': 397}), lin);
      expect(p['kind'], 'up');
      expect(p['weight'], 407);
      final dbl = {'id': LIFT, 'sets': 3, 'reps': 12, 'repsMin': 8, 'weight': 397, 'prog': 'double', 'inc': 10};
      final d = nextPrescription(hist(LIFT, [[397, 12, 12, 12]], {'sets': 3, 'reps': 12, 'weight': 397}), dbl);
      expect(d['kind'], 'up');
      expect(d['weight'], 407);
    });
    test('still snaps from a weight that sits on the grid', () {
      final p = nextPrescription(hist(LIFT, [[60, 5, 5, 5]]), {'id': LIFT, 'sets': 3, 'reps': 5, 'weight': 60, 'prog': 'linear', 'inc': 2.5});
      expect(p['weight'], 62.5);
    });
  });
}
