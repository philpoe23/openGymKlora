// Port of frontend/src/lib/session-merge.test.js.
// ignore_for_file: non_constant_identifier_names
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/finish_workout.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/session_merge.dart';
import 'package:klora_app/engine/session_start.dart';
import 'package:klora_app/engine/workout_model.dart';

import '_exdb.dart';
import '_helpers.dart';

final st = <String, dynamic>{
  'unit': 'kg', 'workouts': [], 'exWeights': {},
  'routines': [
    {'id': 'r1', 'name': 'Strength', 'prog': 'off', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60}, {'id': '0031', 'sets': 3, 'reps': 8, 'weight': 40}]},
    {'id': 'r2', 'name': 'Core', 'prog': 'off', 'ex': [{'id': '0047', 'sets': 3, 'reps': 12, 'weight': 0}]},
    {'id': 'rehab', 'name': 'Rehab', 'excludeFromProgression': true, 'ex': [{'id': '0050', 'sets': 2, 'reps': 15, 'weight': 5}]},
  ],
};

void main() {
  setUpAll(loadTestExerciseDb);

  group('buildCombinedEntries', () {
    test('concatenates each routine’s entries in list order, stamping rid on every one', () {
      final out = buildCombinedEntries(st, ['r1', 'r2']);
      expect((out['entries'] as List).map((e) => e['id']).toList(), ['0025', '0031', '0047']);
      expect((out['entries'] as List).map((e) => e['rid']).toList(), ['r1', 'r1', 'r2']);
      expect(out['routineIds'], ['r1', 'r2']);
    });

    test('de-dupes a repeated id (first wins) and drops an id with no matching routine', () {
      final out = buildCombinedEntries(st, ['r1', 'gone', 'r1', 'r2']);
      expect(out['routineIds'], ['r1', 'r2']);
      expect((out['entries'] as List).map((e) => e['rid']).toList(), ['r1', 'r1', 'r2']);
    });

    test('an empty / null list builds nothing', () {
      expect(buildCombinedEntries(st, []), matchObj({'entries': [], 'routineIds': [], 'routines': []}));
      expect(buildCombinedEntries(st, null), matchObj({'entries': [], 'routineIds': []}));
    });

    test('a single-element list matches the plain buildSessionEntries path (bar the rid stamp)', () {
      final combined = (buildCombinedEntries(st, ['r1'])['entries'] as List).map((e) => {...e as Map<String, dynamic>}..remove('rid')).toList();
      expect(combined, jeq(buildSessionEntries(st, (st['routines'] as List)[0])));
    });

    test('carries an excluded routine’s per-entry noProg through the merge', () {
      final entries = buildCombinedEntries(st, ['r1', 'rehab'])['entries'] as List;
      expect(jsFind(entries, (e) => e['id'] == '0050'), matchObj({'rid': 'rehab', 'noProg': true}));
      expect(jsFind(entries, (e) => e['id'] == '0025')['noProg'], isNull);
    });
  });

  group('the same exercise in two routines of one combined day', () {
    List<dynamic> work(dynamic e) => (e['sets'] as List).where((s) => !isWarmupRow(s)).toList();
    final A = {'id': 'A', 'name': 'Heavy', 'ex': [{'id': '0025', 'sets': 2, 'reps': 10, 'weight': 60}]};
    final B = {'id': 'B', 'name': 'Light', 'ex': [{'id': '0025', 'sets': 2, 'reps': 15, 'weight': 40}]};

    test('opens each routine from its own entry of the saved workout', () {
      final state = <String, dynamic>{'unit': 'kg', 'exWeights': {}, 'routines': [A, B], 'workouts': []};
      final built = buildCombinedEntries(state, ['A', 'B']);
      final active = {
        'id': 'w1', 'd': '2026-08-01', 'start': 1, 'routineIds': built['routineIds'], 'name': 'Heavy + Light',
        'entries': [
          for (final e in built['entries'] as List)
            {...e as Map<String, dynamic>, 'sets': [for (final s in e['sets'] as List) {...s as Map<String, dynamic>, 'done': true}]},
        ],
      };
      (state['workouts'] as List).add(buildCompletedWorkout(active, end: 2));

      final next = buildCombinedEntries(state, ['A', 'B'])['entries'] as List;
      expect(work(next[0]).map((s) => [s['w'], s['r']]).toList(), jeq([[62.5, 10], [62.5, 10]]));
      expect(work(next[1]).map((s) => [s['w'], s['r']]).toList(), jeq([[42.5, 15], [42.5, 15]]));
    });
  });

  group('deriveSessionName', () {
    test('is null for an empty list', () {
      expect(deriveSessionName([]), isNull);
    });
    test('joins 1–3 names with " + "', () {
      expect(deriveSessionName(['Rehab']), 'Rehab');
      expect(deriveSessionName(['Rehab', 'Core']), 'Rehab + Core');
      expect(deriveSessionName(['A', 'B', 'C']), 'A + B + C');
    });
    test('collapses 4+ to "A + B + N more"', () {
      expect(deriveSessionName(['A', 'B', 'C', 'D']), 'A + B + 2 more');
      expect(deriveSessionName(['A', 'B', 'C', 'D', 'E']), 'A + B + 3 more');
    });
  });
}
