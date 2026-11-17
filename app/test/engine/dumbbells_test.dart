// Port of frontend/src/lib/dumbbells.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/dumbbells.dart';
import 'package:klora_app/engine/exercises.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/onerm.dart';
import 'package:klora_app/engine/session_start.dart';

import '_exdb.dart';
import '_helpers.dart';

const bench = '0289';
const row = '0292';
const curl = '0294';
const kb = '0517';
const squat = '0043';

JMap set(num w, num r, [JMap extra = const {}]) => {'w': w, 'r': r, 'done': true, ...extra};
JMap entry(String id, List<dynamic> sets, [JMap target = const {}]) =>
    {'id': id, 'sets': sets, 'target': {'sets': sets.length, 'reps': 8, 'mode': 'reps', ...target}};
JMap workout(String d, List<dynamic> entries, [JMap extra = const {}]) =>
    {'id': 'w$d', 'd': d, 'start': DateTime.parse('${d}T10:00:00').millisecondsSinceEpoch, 'entries': entries, ...extra};
JMap state([List<dynamic> workouts = const [], JMap extra = const {}]) =>
    {'unit': 'kg', 'workouts': workouts, 'routines': [], 'exWeights': {}, ...extra};

void main() {
  setUpAll(loadTestExerciseDb);

  group('the exercises this file assumes', () {
    test('are what the tests below need', () {
      expect(EXIDX[bench]['eq'], 'dumbbell');
      expect(EXIDX[row]['eq'], 'dumbbell');
      expect(EXIDX[row]['n'], matches(RegExp('one arm')));
      expect(EXIDX[curl]['eq'], 'dumbbell');
      expect(EXIDX[kb]['eq'], 'kettlebell');
      expect(EXIDX[squat]['eq'], 'barbell');
    });
  });

  group('the setting', () {
    test('is offered for dumbbells and kettlebells only', () {
      expect(isBellEx(bench), isTrue);
      expect(isBellEx(kb), isTrue);
      expect(isBellEx(squat), isFalse);
    });

    test('reads as entered unless a routine slot or the exercise says otherwise', () {
      expect(dbLoadFor(state(), bench), 'as');
      final S = state([], {'dbLoad': withDbLoad({}, bench, 'each', 5)});
      expect(S['dbLoad'][bench], jeq({'mode': 'each', '_ts': 5}));
      expect(dbLoadFor(S, bench), 'each');
      expect(dbLoadFor(S, {'id': bench, 'dbLoad': 'total'}), 'total');
      expect(dbLoadFor(S, {'id': bench, 'dbLoad': 'as'}), 'as');
      expect(dbLoadOf('both'), isNull);
      expect(dbLoadFor({'dbLoad': {bench: {'mode': 'x'}}}, bench), 'as');
    });

    test('goes back to as entered as a stamped null, so it wins a sync', () {
      final map = withDbLoad(withDbLoad({}, bench, 'each', 1), bench, 'as', 2);
      expect(map[bench], jeq({'mode': null, '_ts': 2}));
      expect(dbLoadFor({'dbLoad': map}, bench), 'as');
    });

    test('knows one-arm work holds one bell', () {
      expect(isOneArm({'id': row}), isTrue);
      expect(isOneArm({'id': bench}), isFalse);
      expect(isOneArm({'id': curl, 'side': true}), isTrue);
      expect(bellsIn({'id': bench}), 2);
      expect(bellsIn({'id': row}), 1);
    });
  });

  group('volume', () {
    test('counts every set saved before the setting existed exactly as before', () {
      final w = workout('2026-10-01', [entry(bench, [set(20, 10), set(20, 8)])]);
      expect(entryDbLoad(w['entries'][0]), 'as');
      expect(workoutVolume(w), 360);
    });

    test('counts both bells for a per-bell entry, once for both-together', () {
      final each = workout('2026-10-01', [entry(bench, [set(20, 10)], {'dbLoad': 'each'})]);
      final total = workout('2026-10-01', [entry(bench, [set(40, 10)], {'dbLoad': 'total'})]);
      expect(volumeFactor(each['entries'][0]), 2);
      expect(workoutVolume(each), 400);
      expect(workoutVolume(total), 400);
    });

    test('counts a one-arm exercise once, per bell or not', () {
      final r = workout('2026-10-01', [entry(row, [set(30, 10)], {'dbLoad': 'each'})]);
      expect(workoutVolume(r), 300);
    });

    test('doubles the drops of a per-bell drop-set too, and leaves warm-ups out', () {
      final w = workout('2026-10-01', [
        entry(bench, [
          set(10, 10, {'phase': 'warmup', 'warmup': true}),
          set(20, 8, {'type': 'dropset', 'drops': [{'w': 16, 'r': 5}]}),
        ], {'dbLoad': 'each'}),
      ]);
      expect(workoutVolume(w), (20 * 8 + 16 * 5) * 2);
    });

    // skipped: 'reaches the exercise history sheet' — exercise-history.js, not in this port.
  });

  group('the set label', () {
    test('says what the number means when the exercise said', () {
      expect(setLabel(bench, set(20, 8), {'id': bench, 'mode': 'reps', 'dbLoad': 'each'}), '20 each × 8');
      expect(setLabel(bench, set(40, 8), {'id': bench, 'mode': 'reps', 'dbLoad': 'total'}), '40 total × 8');
    });

    test('reads as always as entered, and for one-arm work', () {
      expect(setLabel(bench, set(20, 8), {'id': bench, 'mode': 'reps'}), '20×8');
      expect(setLabel(row, set(30, 8), {'id': row, 'mode': 'reps', 'dbLoad': 'each'}), '30×8');
    });
  });

  group('like with like', () {
    test('converts only between the two explicit meanings', () {
      expect(meaningFactor('total', 'each', {'id': bench}), 0.5);
      expect(meaningFactor('each', 'total', {'id': bench}), 2);
      expect(meaningFactor('as', 'each', {'id': bench}), 1);
      expect(meaningFactor('each', 'as', {'id': bench}), 1);
      expect(meaningFactor('total', 'each', {'id': row}), 1);
    });

    test('reads an entry in another meaning as a copy, weights, sides and drops included', () {
      final e = entry(bench, [set(40, 8, {'type': 'dropset', 'drops': [{'w': 30, 'r': 4}]})], {'dbLoad': 'total'});
      e['topW'] = 40;
      final as = entryAs(e, 'each');
      expect(as, isNot(same(e)));
      expect(as['sets'][0]['w'], 20);
      expect(as['sets'][0]['drops'][0]['w'], 15);
      expect(as['topW'], 20);
      expect(as['target']['dbLoad'], 'each');
      expect(e['sets'][0]['w'], 40);
      expect(entryAs(e, 'total'), same(e));
    });

    test('leaves the state alone when nothing converts', () {
      final S = state([workout('2026-10-01', [entry(bench, [set(20, 8)])])]);
      expect(historyAs(S, bench, 'each'), same(S));
      expect(historyAs(S, bench, 'as'), same(S));
    });

    test("judges records in the session's meaning", () {
      final S = state([workout('2026-10-01', [entry(bench, [set(40, 8)], {'dbLoad': 'total'})])]);
      expect(bestWeightFor(S, bench), 40);
      expect(bestWeightFor(S, bench, 'each'), 20);
      final today = entry(bench, [set(22, 8)], {'dbLoad': 'each'});
      expect(is1RMRecord(S, bench, today), isNotNull);
      expect(best1RM(S, bench, 'epley', 'each')!['w'], 20);
    });
    // The exerciseHistory / bestSetFor assertions of this JS case are skipped: exercise-history.js
    // is not part of this port.
    test("draws one curve across a switch, in the exercise's current meaning", () {
      final S = state([
        workout('2026-10-01', [entry(bench, [set(40, 1)], {'dbLoad': 'total'})]),
        workout('2026-10-08', [entry(bench, [set(22, 1)], {'dbLoad': 'each'})]),
      ]);
      expect(currentDbLoad(S, bench), 'each');
      expect(e1rmSeries(S, bench).map((p) => p['y']).toList(), jeq([20, 22]));
    });

    test('never converts sets logged as entered', () {
      final S = state([
        workout('2026-10-01', [entry(bench, [set(40, 1)])]),
        workout('2026-10-08', [entry(bench, [set(22, 1)], {'dbLoad': 'each'})]),
      ]);
      expect(e1rmSeries(S, bench).map((p) => p['y']).toList(), jeq([40, 22]));
    });
  });

  group('a session', () {
    test('stamps the meaning it is logged in, and only when there is one', () {
      final plain = buildPlannedEntry(state(), {'id': bench, 'sets': 2, 'reps': 8, 'weight': 20, 'mode': 'reps'}, null);
      expect(plain['target']['dbLoad'], isNull);
      final S = state([], {'dbLoad': withDbLoad({}, bench, 'each', 1)});
      expect(buildPlannedEntry(S, {'id': bench, 'sets': 2, 'reps': 8, 'weight': 20, 'mode': 'reps'}, null)['target']['dbLoad'], 'each');
      expect(withMeaning(S, {'sets': 2}, bench), jeq({'sets': 2, 'dbLoad': 'each'}));
      expect(withMeaning(state(), {'sets': 2}, bench), jeq({'sets': 2}));
    });

    test("starts from last time read in today's meaning after a switch", () {
      final S = state([workout('2026-10-01', [entry(bench, [set(40, 8), set(40, 8)], {'dbLoad': 'total', 'reps': 8, 'sets': 2})])]);
      final built = buildPlannedEntry(S, {'id': bench, 'sets': 2, 'reps': 8, 'weight': 0, 'mode': 'reps', 'dbLoad': 'each', 'inc': 2}, null);
      expect((built['sets'] as List).map((s) => s['w']).toList(), jeq([22, 22]));
      expect(built['target']['dbLoad'], 'each');
    });

    test("keeps today's numbers for an exercise that never chose", () {
      final S = state([workout('2026-10-01', [entry(bench, [set(40, 8), set(40, 8)], {'reps': 8, 'sets': 2})])]);
      final built = buildPlannedEntry(S, {'id': bench, 'sets': 2, 'reps': 8, 'weight': 0, 'mode': 'reps', 'inc': 2}, null);
      expect((built['sets'] as List).map((s) => s['w']).toList(), jeq([42, 42]));
    });
    test("freestyle follows the exercise's setting now, not the stamp of last time", () {
      final S = state([workout('2026-10-01', [entry(bench, [set(20, 8)], {'dbLoad': 'each'})])]);
      expect(freestyleConfig(S, {'id': bench}).containsKey('dbLoad'), isFalse);
    });
  });

  // skipped: 'sync and sharing' (3 cases) — mergeStates / stampChange (sync-merge.js) and
  // buildPlanBundle / parsePlan (plan-share.js), Task 6.
}
