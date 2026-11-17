// Port of frontend/src/lib/onerm.test.js.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/onerm.dart';

import '_exdb.dart';
import '_helpers.dart';

num _max(Iterable<num> xs) => xs.reduce(math.max);
num _min(Iterable<num> xs) => xs.reduce(math.min);
num _round1(num x) => mathRound(x * 10) / 10;

/// best1RM / e1rmSeries points without `t` (NaN for a workout with no date or start, which
/// never equals itself), for comparing two such results.
dynamic _noT(dynamic p) => p == null ? null : ({...p as Map<String, dynamic>}..remove('t'));

void main() {
  setUpAll(loadTestExerciseDb);

  group('estimate1RM', () {
    test('returns the load unchanged for a single rep', () {
      expect(estimate1RM(100, 1), 100);
      expect(estimate1RM(62.5, 1), 62.5);
    });

    test('matches Epley by hand across the usual rep ranges', () {
      expect(estimate1RM(100, 5), 116.7);
      expect(estimate1RM(100, 10), 133.3);
      expect(estimate1RM(80, 8), 101.3);
      expect(estimate1RM(60, 3), 66);
    });

    test('rounds to one decimal', () {
      expect(estimate1RM(101.25, 7), 124.9);
      final x = estimate1RM(100, 3)! * 10;
      expect(x == x.roundToDouble(), isTrue);
    });

    test('refuses reps beyond the cap rather than guessing', () {
      expect(estimate1RM(100, REP_CAP), isNotNull);
      expect(estimate1RM(100, REP_CAP + 1), isNull);
      expect(estimate1RM(60, 30), isNull);
    });

    test('rejects invalid, zero and negative input', () {
      expect(estimate1RM(0, 5), isNull);
      expect(estimate1RM(-100, 5), isNull);
      expect(estimate1RM(100, 0), isNull);
      expect(estimate1RM(100, -3), isNull);
      expect(estimate1RM(null, 5), isNull);
      expect(estimate1RM(100, null), isNull);
      expect(estimate1RM(double.nan, 5), isNull);
      expect(estimate1RM(double.infinity, 5), isNull);
      expect(estimate1RM('', ''), isNull);
    });

    test('accepts numeric strings, the shape number inputs arrive in', () {
      expect(estimate1RM('100', '5'), 116.7);
    });

    test('offers the other documented formulas and agrees with them at low reps', () {
      expect(estimate1RM(100, 5, 'brzycki'), 112.5);
      expect(estimate1RM(100, 5, 'lombardi'), 117.5);
      expect(FORMULAS.keys, contains('epley'));
    });

    test('keeps the formulas within a few percent up to 8 reps, and diverges most at the cap', () {
      num spread(int r) => _max(FORMULAS.keys.map((f) => estimate1RM(100, r, f)!)) - _min(FORMULAS.keys.map((f) => estimate1RM(100, r, f)!));
      expect(spread(1), 0);
      for (var r = 2; r <= 8; r++) {
        expect(spread(r), lessThan(10));
      }
      final upTo = [for (var r = 1; r < REP_CAP; r++) spread(r)];
      expect(spread(REP_CAP), greaterThan(_max(upTo)));
    });

    test('falls back to the default for an unknown formula name', () {
      expect(estimate1RM(100, 5, 'nope'), estimate1RM(100, 5));
    });
  });

  group('new formulas (oconner, mayhew, wathan, lander)', () {
    test("O'Conner matches hand calculation at r=5", () {
      expect(estimate1RM(100, 5, 'oconner'), 112.5);
    });
    test('Mayhew matches hand calculation at r=5', () {
      expect(estimate1RM(100, 5, 'mayhew'), _round1((100 * 100) / (52.2 + 41.9 * math.exp(-0.055 * 5))));
    });
    test('Wathan matches hand calculation at r=5', () {
      expect(estimate1RM(100, 5, 'wathan'), _round1((100 * 100) / (48.8 + 53.8 * math.exp(-0.075 * 5))));
    });
    test('Lander matches hand calculation at r=5', () {
      expect(estimate1RM(100, 5, 'lander'), _round1((100 * 100) / (101.3 - 2.67123 * 5)));
    });
    test('all seven formulas are present in FORMULAS', () {
      expect(FORMULAS.keys, containsAll(['epley', 'brzycki', 'lombardi', 'oconner', 'mayhew', 'wathan', 'lander']));
    });
  });

  group('weighted formula', () {
    test('returns a finite estimate between the min and max of individual formulas', () {
      final est = estimate1RM(100, 5, 'weighted')!;
      final vals = FORMULAS.keys.map((f) => estimate1RM(100, 5, f)!);
      expect(est, greaterThan(_min(vals) - 0.1));
      expect(est, lessThan(_max(vals) + 0.1));
    });
    test('returns exactly w for a single rep', () {
      expect(estimate1RM(100, 1, 'weighted'), 100);
    });
    test('returns null when effective reps exceed WEIGHTED_REP_CAP', () {
      expect(estimate1RM(100, WEIGHTED_REP_CAP, 'weighted'), isNotNull);
      expect(estimate1RM(100, WEIGHTED_REP_CAP + 1, 'weighted'), isNull);
    });
    test('accepts reps above REP_CAP but within WEIGHTED_REP_CAP', () {
      expect(estimate1RM(100, 13, 'weighted'), isNotNull);
      expect(estimate1RM(100, 13, 'epley'), isNull);
    });
    test('rounds to one decimal', () {
      final x = estimate1RM(100, 8, 'weighted')! * 10;
      expect((x - x.round()).abs() < 1e-9, isTrue);
    });
  });

  group('RIR handling', () {
    test('exactly 1 rep with RIR 0 returns the weight unchanged', () {
      expect(estimate1RM(100, 1, 'weighted', 0), 100);
      expect(estimate1RM(80, 1, 'epley', 0), 80);
    });
    test('weighted with RIR computes effective reps for the formula ensemble', () {
      expect(estimate1RM(100, 5, 'weighted', 2)!, greaterThan(estimate1RM(100, 5, 'weighted')!));
    });
    test('RIR map estimate alone (e.g. RIR 2, 5 reps) ≈ weight / 0.892', () {
      final est = estimate1RM(100, 5, 'weighted', 2)!;
      expect(est, greaterThan(110));
      expect(est, lessThan(140));
    });
    test('returns null when effective reps exceed WEIGHTED_REP_CAP', () {
      expect(estimate1RM(100, 13, 'weighted', 3), isNull);
    });
    test('ignores negative or non-numeric RIR', () {
      expect(estimate1RM(100, 5, 'weighted', -1), estimate1RM(100, 5, 'weighted'));
      expect(estimate1RM(100, 5, 'weighted', 'abc'), estimate1RM(100, 5, 'weighted'));
    });
    test('individual formulas ignore the RIR parameter', () {
      expect(estimate1RM(100, 5, 'epley', 2), estimate1RM(100, 5, 'epley'));
    });
  });

  group('calculate1RMAccuracy', () {
    test('returns 1 for a single rep to failure', () {
      expect(calculate1RMAccuracy(1, 0), 1);
    });
    test('returns 0 for reps beyond WEIGHTED_REP_CAP', () {
      expect(calculate1RMAccuracy(WEIGHTED_REP_CAP + 1), 0);
    });
    test('returns 0 for non-positive or non-finite input', () {
      expect(calculate1RMAccuracy(0), 0);
      expect(calculate1RMAccuracy(-1), 0);
      expect(calculate1RMAccuracy(double.nan), 0);
    });
    test('decreases accuracy as reps increase', () {
      final a3 = calculate1RMAccuracy(3), a8 = calculate1RMAccuracy(8), a13 = calculate1RMAccuracy(13);
      expect(a3, greaterThan(a8));
      expect(a8, greaterThan(a13));
    });
    test('penalises RIR presence by ~8%', () {
      final noRir = calculate1RMAccuracy(5);
      final withRir = calculate1RMAccuracy(5, 2);
      expect(withRir, closeTo(noRir * 0.92, 0.05)); // toBeCloseTo(x, 1)
    });
    test('RIR 0 does not penalise (to failure)', () {
      expect(calculate1RMAccuracy(5, 0), calculate1RMAccuracy(5));
    });
    test('returns a value between 0 and 1', () {
      for (var r = 1; r <= WEIGHTED_REP_CAP; r++) {
        final acc = calculate1RMAccuracy(r);
        expect(acc, greaterThanOrEqualTo(0));
        expect(acc, lessThanOrEqualTo(1));
      }
    });
    test('spread factor applies only to the weighted formula', () {
      expect(calculate1RMAccuracy(8, null, 'weighted'), lessThanOrEqualTo(calculate1RMAccuracy(8, null, 'epley')));
    });
  });

  group('bestSetOf', () {
    test('picks the highest estimate, not the heaviest set', () {
      final entry = {'id': 'x', 'sets': [
        {'w': 100, 'r': 5, 'done': true},
        {'w': 110, 'r': 3, 'done': true},
        {'w': 120, 'r': 1, 'done': true},
      ]};
      expect(bestSetOf(entry), jeq({'est': 121, 'w': 110, 'r': 3}));
    });
    test('ignores sets that were never checked off', () {
      expect(bestSetOf({'id': 'x', 'sets': [{'w': 100, 'r': 5, 'done': true}, {'w': 200, 'r': 5, 'done': false}]})!['w'], 100);
    });
    test('ignores topW, which carries no rep count', () {
      expect(bestSetOf({'id': 'x', 'topW': 200, 'sets': [{'w': 100, 'r': 5, 'done': true}]})!['est'], 116.7);
    });
    test('returns null for cardio and timed entries', () {
      expect(bestSetOf({'id': 'c', 'sets': [{'min': 20, 'speed': 9, 'done': true}]}), isNull);
      expect(bestSetOf({'id': 'p', 'sets': [{'sec': 60, 'w': 0, 'done': true}]}), isNull);
      expect(bestSetOf({'id': 'p', 'sets': [{'sec': 60, 'w': 20, 'done': true}]}), isNull);
    });
    test('survives a missing or empty entry', () {
      expect(bestSetOf(null), isNull);
      expect(bestSetOf({'sets': []}), isNull);
    });
  });

  final S = {
    'workouts': [
      {'d': '2026-01-01', 'start': 1, 'entries': [{'id': 'bench', 'sets': [{'w': 80, 'r': 5, 'done': true}]}]},
      {'d': '2026-01-08', 'start': 2, 'entries': [{'id': 'squat', 'sets': [{'w': 100, 'r': 5, 'done': true}]}]},
      {'d': '2026-01-15', 'start': 3, 'entries': [{'id': 'bench', 'sets': [{'w': 90, 'r': 5, 'done': true}, {'w': 90, 'r': 3, 'done': false}]}]},
      {'d': '2026-01-22', 'start': 4, 'entries': [{'id': 'bench', 'sets': [{'w': 85, 'r': 5, 'done': true}]}]},
      {'d': '2026-01-29', 'start': 5, 'entries': [{'id': 'run', 'sets': [{'min': 30, 'speed': 10, 'done': true}]}]},
    ],
  };

  group('e1rmSeries / best1RM', () {
    test('yields one chronological point per workout that produced an estimate', () {
      final pts = e1rmSeries(S, 'bench');
      expect(pts.map((p) => p['d']).toList(), ['2026-01-01', '2026-01-15', '2026-01-22']);
      expect(pts.map((p) => p['y']).toList(), jeq([93.3, 105, 99.2]));
    });
    test('reports the all-time best with the set behind it', () {
      expect(best1RM(S, 'bench'), jeq({'est': 105, 'w': 90, 'r': 5, 'd': '2026-01-15', 't': 3}));
    });
    test('has nothing to say about cardio or an unknown exercise', () {
      expect(e1rmSeries(S, 'run'), isEmpty);
      expect(best1RM(S, 'run'), isNull);
      expect(best1RM(S, 'nope'), isNull);
      expect(best1RM({'workouts': []}, 'bench'), isNull);
      expect(best1RM({}, 'bench'), isNull);
    });
    test('takes the strongest duplicate occurrence once per dated workout', () {
      final workouts = [{'d': '2026-02-01', 'start': 1, 'entries': [
        {'id': 'bench', 'sets': [{'w': 60, 'r': 5, 'done': true}]},
        {'id': 'bench', 'sets': [{'w': 100, 'r': 5, 'done': true}]},
      ]}];
      expect(e1rmSeries({'workouts': workouts}, 'bench'), jeq([{'t': 1, 'd': '2026-02-01', 'y': 116.7, 'w': 100, 'r': 5}]));
      expect(best1RM({'workouts': workouts}, 'bench'), matchObj({'est': 116.7, 'w': 100, 'r': 5, 'd': '2026-02-01'}));
    });
    test('estimates each completed per-side limb and leaves timed/cardio rows out', () {
      final sides = {'id': 'bench', 'target': {'mode': 'reps', 'side': true}, 'sets': [{'w': 100, 'r': 10, 'done': false,
        'sides': {'L': {'w': 100, 'r': 5, 'done': true}, 'R': {'w': 90, 'r': 5, 'done': false}}}]};
      expect(bestSetOf(sides), jeq({'est': 116.7, 'w': 100, 'r': 5}));
      expect(e1rmSeries({'workouts': [{'start': 1, 'd': '2026-02-01', 'entries': [sides]}]}, 'bench'),
          jeq([{'t': 1, 'd': '2026-02-01', 'y': 116.7, 'w': 100, 'r': 5}]));
      expect(e1rmSeries({'workouts': [{'start': 1, 'd': '2026-02-01', 'entries': [
        {'id': 'hold', 'target': {'mode': 'time'}, 'sets': [{'sec': 60, 'w': 200, 'r': 5, 'done': true}]},
        {'id': 'run', 'target': {'mode': 'cardio'}, 'sets': [{'min': 20, 'speed': 9, 'r': 5, 'done': true}]},
      ]}]}, 'hold'), isEmpty);
    });
  });

  group('is1RMRecord', () {
    test('flags a session that beats every previous estimate', () {
      expect(is1RMRecord(S, 'bench', {'id': 'bench', 'sets': [{'w': 95, 'r': 5, 'done': true}]}), jeq({'est': 110.8, 'w': 95, 'r': 5, 'prev': 105}));
    });
    test('stays quiet when the session does not beat the record', () {
      expect(is1RMRecord(S, 'bench', {'id': 'bench', 'sets': [{'w': 90, 'r': 5, 'done': true}]}), isNull);
      expect(is1RMRecord(S, 'bench', {'id': 'bench', 'sets': [{'w': 80, 'r': 5, 'done': true}]}), isNull);
    });
    test('counts the first ever estimate as a record', () {
      final rec = is1RMRecord(S, 'deadlift', {'id': 'deadlift', 'sets': [{'w': 140, 'r': 3, 'done': true}]})!;
      expect(rec['prev'], 0);
      expect(rec['est'], 154);
    });
    test('says nothing for a timed or unfinished entry', () {
      expect(is1RMRecord(S, 'plank', {'id': 'plank', 'sets': [{'sec': 90, 'done': true}]}), isNull);
      expect(is1RMRecord(S, 'bench', {'id': 'bench', 'sets': [{'w': 200, 'r': 5, 'done': false}]}), isNull);
    });
  });

  group('drop-sets, rest-pause sets and 1RM', () {
    test('estimates only from the main/activation weight×reps, ignoring lighter drops', () {
      final entry = {'id': 'x', 'sets': [
        {'type': 'dropset', 'w': 100, 'r': 5, 'done': true, 'drops': [{'w': 80, 'r': 5}, {'w': 60, 'r': 5}]},
      ]};
      expect(bestSetOf(entry), jeq(bestSetOf({'id': 'x', 'sets': [{'w': 100, 'r': 5, 'done': true}]})));
    });
    test("estimates only from the row's own w/r, ignoring rest-pause bursts", () {
      final entry = {'id': 'x', 'sets': [
        {'type': 'restpause', 'w': 60, 'r': 8, 'done': true, 'clusters': [{'r': 4, 'restSec': 15}, {'r': 3, 'restSec': 15}]},
      ]};
      expect(bestSetOf(entry), jeq(bestSetOf({'id': 'x', 'sets': [{'w': 60, 'r': 8, 'done': true}]})));
    });
    test('refuses to estimate a planned rest-pause row once its total reps exceed REP_CAP, same as any other high-rep set', () {
      final entry = {'id': 'x', 'sets': [
        {'type': 'restpause', 'w': 60, 'r': 20, 'done': true, 'clusters': [{'r': 10, 'restSec': 15}, {'r': 5, 'restSec': 15}, {'r': 3, 'restSec': 15}, {'r': 1, 'restSec': 15}, {'r': 1, 'restSec': 15}]},
      ]};
      expect(bestSetOf(entry), isNull);
    });
  });

  group('warm-up sets and 1RM', () {
    final ENTRY = {'id': 'warm-test', 'sets': [
      {'w': 20, 'r': 8, 'done': true, 'warmup': true},
      {'w': 80, 'r': 5, 'done': true},
    ]};
    test('does not let a ticked-off warm-up set set or raise the estimated 1RM', () {
      final working = {'id': 'warm-test', 'sets': [{'w': 80, 'r': 5, 'done': true}]};
      expect(bestSetOf(ENTRY), jeq(bestSetOf(working)));
      // `t` is NaN for these undated workouts on both sides (toEqual treats NaN as equal).
      expect(_noT(best1RM({'workouts': [{'entries': [ENTRY]}]}, 'warm-test')),
          jeq(_noT(best1RM({'workouts': [{'entries': [working]}]}, 'warm-test'))));
      expect((best1RM({'workouts': [{'entries': [ENTRY]}]}, 'warm-test')!['t'] as num).isNaN, isTrue);
    });
  });

  group('the formula a profile picked (Settings, Discord request)', () {
    final S = {'workouts': [{'d': '2026-10-01', 'entries': [{'id': 'x', 'sets': [{'w': 100, 'r': 8, 'done': true}]}]}]};
    test('reads the default when nothing or something unknown is stored', () {
      expect(formulaOf({}), 'epley');
      expect(formulaOf({'oneRmFormula': 'toString'}), 'epley');
      expect(formulaOf({'oneRmFormula': 'brzycki'}), 'brzycki');
      expect(formulaOf({'oneRmFormula': 'weighted'}), 'weighted');
    });
    test('the stored formula drives best1RM without every caller passing it', () {
      expect(best1RM(S, 'x')!['est'], estimate1RM(100, 8, 'epley'));
      expect(best1RM({...S, 'oneRmFormula': 'brzycki'}, 'x')!['est'], estimate1RM(100, 8, 'brzycki'));
      expect(best1RM({...S, 'oneRmFormula': 'brzycki'}, 'x')!['est'], lessThan(best1RM(S, 'x')!['est'] as num));
    });
  });
}
