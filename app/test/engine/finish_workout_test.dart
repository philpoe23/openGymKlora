// Port of frontend/src/lib/finish-workout.test.js.
// ignore_for_file: constant_identifier_names
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/finish_workout.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/session_start.dart';
import 'package:klora_app/engine/workout_model.dart';

import '_exdb.dart';
import '_helpers.dart';

void main() {
  setUpAll(loadTestExerciseDb);

  group('completed workout boundary', () {
    test('builds the same legacy-shaped record doFinishWorkout stores and keeps it visible', () {
      final active = {
        'id': 'active-1', 'd': '2026-08-08', 'start': 1000, 'routineIds': ['routine-1'], 'name': 'Push', 'bw': 80,
        'entries': [{'id': '0025', 'sets': [{'done': true, 'w': 60, 'r': 8}], 'topW': 60, 'target': {'sets': 1, 'reps': 8}}],
      };
      final completed = buildCompletedWorkout(active, end: 2000, prs: []);
      expect(completed, jeq({
        'id': 'active-1', 'd': '2026-08-08', 'start': 1000, 'end': 2000,
        'routineIds': ['routine-1'], 'routineId': 'routine-1', 'name': 'Push', 'bw': 80,
        'entries': [{'id': '0025', 'sets': [{'done': true, 'w': 60, 'r': 8}], 'topW': 60, 'target': {'sets': 1, 'reps': 8}}],
        'prs': [],
      }));
    });

    test('never stores planSec: an unfinished row goes back to recording its plan', () {
      final active = {
        'id': 'a', 'd': '2026-09-18', 'start': 1000,
        'entries': [{
          'id': 'plank',
          'sets': [
            {'done': true, 'sec': 30, 'w': 0},
            {'done': false, 'sec': 3, 'planSec': 30, 'w': 0},
            {'done': true, 'sec': 28, 'planSec': 45, 'w': 0},
          ],
        }],
      };
      final sets = (buildCompletedWorkout(active, end: 2000)['entries'] as List)[0]['sets'];
      expect(sets, jeq([
        {'done': true, 'sec': 30, 'w': 0},
        {'done': false, 'sec': 30, 'w': 0},
        {'done': true, 'sec': 28, 'w': 0},
      ]));
      expect(jsonEncode(sets), isNot(contains('planSec')));
    });

    test('never stores weightOrigin, on a row or on either side, and keeps the plan stamps', () {
      final planned = {'sets': 3, 'reps': 5, 'weight': 100};
      var rows = <dynamic>[
        {'w': 100, 'r': 5, 'done': true},
        {'w': 100, 'r': 5, 'done': false},
        {'w': 100, 'r': 5, 'done': false},
      ];
      rows[2] = {...rows[2] as Map<String, dynamic>, 'w': 95, 'weightOrigin': WEIGHT_ORIGIN_MANUAL};
      rows[1] = {...rows[1] as Map<String, dynamic>, 'w': 105, 'weightOrigin': WEIGHT_ORIGIN_MANUAL};
      rows = cascadeWeight(rows, 1, 105);
      expect(rows[2], matchObj({'w': 95, 'weightOrigin': WEIGHT_ORIGIN_MANUAL}));
      rows = rows.map((row) => {...row as Map<String, dynamic>, 'done': true}).toList();
      var side = setSideField(makeSideSet({'w': 20, 'r': 16}), 'L', 'w', 22.5);
      side['sides']['L']['weightOrigin'] = WEIGHT_ORIGIN_MANUAL;
      side = toggleSide(toggleSide(side, 'L'), 'R');

      final active = {
        'id': 'a', 'd': '2026-09-18', 'start': 1000, 'routineIds': ['r'],
        'entries': [
          {'id': '0025', 'rid': 'r', 'target': {...planned}, 'planned': planned, 'sets': rows},
          {'id': 'lunge', 'rid': 'r', 'target': {'sets': 1, 'reps': 16, 'side': true}, 'sets': [side]},
        ],
      };
      final saved = buildCompletedWorkout(active, end: 2000);
      expect(jsonEncode(saved), isNot(contains('weightOrigin')));
      final savedEntries = saved['entries'] as List;
      expect((savedEntries[0]['sets'] as List).map((s) => s['w']).toList(), jeq([100, 105, 95]));
      expect(savedEntries[0]['planned'], jeq(planned));
      expect(savedEntries[1]['sets'][0]['sides'], matchObj({'L': {'w': 22.5, 'done': true}, 'R': {'w': 20, 'done': true}}));
      expect(((active['entries'] as List)[0]['sets'] as List)[2]['weightOrigin'], WEIGHT_ORIGIN_MANUAL);

      final st = {'unit': 'kg', 'exWeights': {}, 'routines': [{'id': 'r', 'ex': [{'id': '0025', ...planned}]}], 'workouts': [saved]};
      final next = buildSessionEntries(st, (st['routines'] as List)[0])[0];
      expect(jsonEncode(next['sets']), isNot(contains('weightOrigin')));
    });

    test('leaves the rows it has nothing to strip exactly as they are', () {
      final rows = [{'done': true, 'w': 60, 'r': 8}];
      final active = {'id': 'a', 'd': '2026-09-18', 'start': 1000, 'entries': [{'id': '0025', 'sets': rows}]};
      expect((buildCompletedWorkout(active, end: 2000)['entries'] as List)[0]['sets'][0], same(rows[0]));
    });

    test('mirrors routineIds → routineId, and tolerates a legacy scalar active.routineId', () {
      final base = {
        'id': 'w', 'd': '2026-08-08', 'start': 1,
        'entries': [{'id': '0025', 'sets': [{'done': true, 'w': 60, 'r': 8}], 'target': {'sets': 1, 'reps': 8}}],
      };
      final combined = buildCompletedWorkout({...base, 'routineIds': ['a', 'b']});
      expect(combined['routineIds'], ['a', 'b']);
      expect(combined['routineId'], 'a');

      final legacy = buildCompletedWorkout({...base, 'routineId': 'only'});
      expect(legacy['routineIds'], ['only']);
      expect(legacy['routineId'], 'only');

      final freestyle = buildCompletedWorkout(base);
      expect(freestyle['routineIds'], isEmpty);
      expect(freestyle['routineId'], isNull);
    });

    test('carries per-entry rid and noProg onto the saved entry, written only when set', () {
      final active = {
        'id': 'w', 'd': '2026-08-08', 'start': 1, 'routineIds': ['strength', 'rehab'],
        'entries': [
          {'id': '0025', 'rid': 'strength', 'sets': [{'done': true, 'w': 60, 'r': 8}], 'target': {'sets': 1, 'reps': 8}},
          {'id': '0031', 'rid': 'rehab', 'noProg': true, 'sets': [{'done': true, 'w': 10, 'r': 12}], 'target': {'sets': 1, 'reps': 12}},
        ],
      };
      final entries = buildCompletedWorkout(active)['entries'] as List;
      final a = entries[0] as Map, b = entries[1] as Map;
      expect(a['rid'], 'strength');
      expect(a.containsKey('noProg'), isFalse);
      expect(b['rid'], 'rehab');
      expect(b['noProg'], isTrue);
    });

    test('keeps the plan each entry was built from, next to the target the prescription moved', () {
      final active = {
        'id': 'w', 'd': '2026-08-08', 'start': 1, 'routineIds': ['strength'],
        'entries': [
          {'id': '0025', 'rid': 'strength', 'planned': {'sets': 2, 'reps': 10, 'weight': 60}, 'sets': [{'done': true, 'w': 62.5, 'r': 10}], 'target': {'sets': 2, 'reps': 10, 'weight': 62.5}},
          {'id': '0031', 'sets': [{'done': true, 'w': 10, 'r': 12}], 'target': {'sets': 1, 'reps': 12}},
        ],
      };
      final entries = buildCompletedWorkout(active)['entries'] as List;
      expect(entries[0]['planned'], jeq({'sets': 2, 'reps': 10, 'weight': 60}));
      expect((entries[1] as Map).containsKey('planned'), isFalse);
    });

    test('derives topW from the highest completed non-warm-up work set, not stale entry data', () {
      final entry = {
        'id': '0025', 'topW': 80, 'target': {'mode': 'reps', 'sets': 2, 'reps': 8},
        'sets': [
          {'phase': 'warmup', 'done': true, 'w': 120, 'r': 8},
          {'done': true, 'w': 75, 'r': 8},
          {'done': true, 'w': 85, 'r': 7},
          {'done': false, 'w': 100, 'r': 8},
        ],
      };
      final active = {'id': 'active-1', 'd': '2026-08-08', 'start': 1000, 'entries': [entry]};
      expect((buildCompletedWorkout(active)['entries'] as List)[0]['topW'], 85);
      expect((buildCompletedWorkout({...active, 'entries': [{...entry, 'topW': 120}]})['entries'] as List)[0]['topW'], 85);
    });

    test('keeps a legacy topW when old completed rows have no usable weight', () {
      final active = {
        'id': 'active-1', 'd': '2026-08-08', 'start': 1000,
        'entries': [{'id': '0025', 'topW': 60, 'sets': [{'done': true, 'r': 8}]}],
      };
      expect((buildCompletedWorkout(active)['entries'] as List)[0]['topW'], 60);
    });

    test('writes the legacy excludeFromProgression mirror iff every completed entry is noProg', () {
      JMap mk(List<dynamic> entries) => {'id': 'w', 'd': '2026-08-08', 'start': 1, 'routineIds': ['x'], 'entries': entries};
      JMap done([JMap extra = const {}]) => {'id': '0025', 'sets': [{'done': true, 'w': 30, 'r': 8}], 'target': {'sets': 1, 'reps': 8}, ...extra};

      expect(buildCompletedWorkout(mk([done({'noProg': true}), done({'id': '0031', 'noProg': true})]))['excludeFromProgression'], isTrue);
      expect(buildCompletedWorkout(mk([done({'noProg': true}), done({'id': '0031'})])).containsKey('excludeFromProgression'), isFalse);
      expect(buildCompletedWorkout(mk([done(), done({'id': '0031'})])).containsKey('excludeFromProgression'), isFalse);
    });

    test('persists a muscle snapshot only when the caller supplies one', () {
      final active = {
        'id': 'active-1', 'd': '2026-08-08', 'start': 1000,
        'entries': [
          {'id': 'catalogue', 'sets': [{'done': true}]},
          {'id': 'custom', 'sets': [{'done': true}]},
        ],
      };
      final completed = buildCompletedWorkout(active,
          end: 2000,
          snapshotFor: (entry) => entry['id'] == 'custom' ? {'n': 'Custom lift', 'muscleWeights': {'chest': 1}} : null);
      final entries = completed['entries'] as List;
      expect((entries[0] as Map).containsKey('muscleSnapshot'), isFalse);
      expect(entries[1]['muscleSnapshot'], jeq({'n': 'Custom lift', 'muscleWeights': {'chest': 1}}));
    });
  });

  group('session notes', () {
    JMap active(JMap entry) => {
          'id': 'w1', 'd': '2026-08-25', 'start': 1, 'routineId': 'r1', 'name': 'Push', 'bw': null,
          'entries': [{'id': '0025', 'sets': [{'w': 100, 'r': 5, 'done': true}], ...entry}],
        };

    test('keeps a per-exercise note and its pin', () {
      final w = buildCompletedWorkout(active({'note': '  narrower grip next time  ', 'notePin': true}));
      expect((w['entries'] as List)[0]['note'], 'narrower grip next time');
      expect((w['entries'] as List)[0]['notePin'], isTrue);
    });

    test('keeps an unpinned note without inventing a pin', () {
      final w = buildCompletedWorkout(active({'note': 'shoulder twinged'}));
      expect((w['entries'] as List)[0]['note'], 'shoulder twinged');
      expect(((w['entries'] as List)[0] as Map).containsKey('notePin'), isFalse);
    });

    test('writes no note fields at all when nothing was typed', () {
      final w = buildCompletedWorkout(active({'note': '   ', 'notePin': true}));
      expect(((w['entries'] as List)[0] as Map).containsKey('note'), isFalse);
      expect(((w['entries'] as List)[0] as Map).containsKey('notePin'), isFalse);
    });

    test('keeps a whole-session note on the workout', () {
      final a = active({});
      expect(buildCompletedWorkout({...a, 'note': 'slept badly'})['note'], 'slept badly');
      expect(buildCompletedWorkout(a).containsKey('note'), isFalse);
    });
  });

  group('superset groups', () {
    final done = {'w': 40, 'r': 10, 'done': true};
    final open = {'w': 40, 'r': 10, 'done': false};
    JMap active(List<dynamic> entries) => {'id': 'w', 'd': '2026-09-17', 'start': 1, 'routineIds': ['r1'], 'name': 'Arms', 'entries': entries};

    test('keeps the group on every member that was trained', () {
      final w = buildCompletedWorkout(active([
        {'id': 'a', 'sg': 'sg1', 'sets': [done], 'target': {}},
        {'id': 'b', 'sg': 'sg1', 'sets': [done], 'target': {}},
        {'id': 'c', 'sets': [done], 'target': {}},
      ]));
      expect((w['entries'] as List).map((e) => e['sg']).toList(), ['sg1', 'sg1', null]);
      expect(((w['entries'] as List)[2] as Map).containsKey('sg'), isFalse);
    });

    test('drops the tag of a member whose partner was never trained', () {
      final entries = [
        {'id': 'a', 'sg': 'sg1', 'sets': [done], 'target': {}},
        {'id': 'b', 'sg': 'sg1', 'sets': [open], 'target': {}},
        {'id': 'c', 'sets': [done], 'target': {}},
      ];
      final w = buildCompletedWorkout(active(entries));
      expect((w['entries'] as List).map((e) => e['id']).toList(), ['a', 'c']);
      expect(((w['entries'] as List)[0] as Map).containsKey('sg'), isFalse);
      expect(entries[0]['sg'], 'sg1');
    });
  });

  group('sessionEnd: a workout finished long after its last set', () {
    const MIN = 60 * 1000;
    const T0 = 1000000000000;
    JMap atMins(List<num> mins) => {'entries': [{'id': 'x', 'sets': [for (final m in mins) {'done': true, 'w': 50, 'r': 8, 'at': T0 + m * MIN}]}]};

    test('keeps the Finish tap when it comes right after the last set', () {
      expect(sessionEnd(atMins([0, 15, 30, 45]), T0 + 50 * MIN), T0 + 50 * MIN);
    });

    test('ends at the last set when Finish is tapped the next day', () {
      expect(sessionEnd(atMins([0, 15, 30, 45]), T0 + 30 * 60 * MIN), T0 + 45 * MIN);
    });

    test('does not let a set ticked after a long break stretch the session', () {
      expect(sessionEnd(atMins([0, 15, 30, 45, 24 * 60]), T0 + 24 * 60 * MIN + 1), T0 + 45 * MIN);
    });

    test('ignores unticked sets and sets from builds that did not stamp them', () {
      final active = {'entries': [{'id': 'x', 'sets': [
        {'done': true, 'w': 50, 'r': 8, 'at': T0},
        {'done': false, 'w': 50, 'r': 8, 'at': T0 + 30 * MIN},
        {'done': true, 'w': 50, 'r': 8},
      ]}]};
      expect(sessionEnd(active, T0 + 5 * 60 * MIN), T0);
      expect(sessionEnd({'entries': [{'id': 'x', 'sets': [{'done': true, 'w': 50, 'r': 8}]}]}, 42), 42);
    });

    test('does not cut a long cardio finisher or hold off as a forgotten break', () {
      final active = <String, dynamic>{'entries': [
        {'id': 'x', 'sets': [for (final m in [0, 20, 40]) {'done': true, 'w': 50, 'r': 8, 'at': T0 + m * MIN}]},
        {'id': 'run', 'sets': [<String, dynamic>{'done': true, 'min': 30, 'speed': 10, 'at': T0 + 72 * MIN}]},
      ]};
      expect(sessionEnd(active, T0 + 73 * MIN), T0 + 73 * MIN);
      active['entries'][1]['sets'][0]['at'] = T0 + 24 * 60 * MIN;
      expect(sessionEnd(active, T0 + 24 * 60 * MIN + 1), T0 + 40 * MIN);
      final hold = {'entries': [
        {'id': 'x', 'sets': [{'done': true, 'w': 50, 'r': 8, 'at': T0}]},
        {'id': 'plank', 'sets': [{'done': true, 'at': T0 + 30 * MIN, 'sides': {'L': {'sec': 330, 'done': true}, 'R': {'sec': 330, 'done': true}}}]},
      ]};
      expect(sessionEnd(hold, T0 + 31 * MIN), T0 + 31 * MIN);
    });

    test('does not cut a cardio row ticked when it started and finished more than the gap later', () {
      final active = {'entries': [
        {'id': 'x', 'sets': [for (final m in [0, 20]) {'done': true, 'w': 50, 'r': 8, 'at': T0 + m * MIN}]},
        {'id': 'run', 'sets': [{'done': true, 'min': 30, 'speed': 10, 'at': T0 + 25 * MIN}]},
      ]};
      expect(sessionEnd(active, T0 + 56 * MIN), T0 + 56 * MIN);
      expect(sessionEnd(active, T0 + 24 * 60 * MIN), T0 + 55 * MIN);
      final hold = {'entries': [{'id': 'plank', 'sets': [{'done': true, 'sec': 300, 'at': T0}]}]};
      expect(sessionEnd(hold, T0 + 25 * MIN), T0 + 25 * MIN);
    });

    test('counts a per-side set once one side is done', () {
      final active = {'entries': [{'id': 'x', 'sets': [{
        'w': 20, 'r': 8, 'done': false, 'at': T0,
        'sides': {'L': {'w': 20, 'r': 8, 'done': true}, 'R': {'w': 20, 'r': 8, 'done': false}},
      }]}]};
      expect(sessionEnd(active, T0 + FORGOTTEN_GAP_MS + 1), T0);
    });
  });
}
