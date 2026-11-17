// Port of frontend/src/lib/session-start.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/progression.dart';
import 'package:klora_app/engine/session_start.dart';
import 'package:klora_app/engine/workout_model.dart';

import '_exdb.dart';
import '_helpers.dart';

List<dynamic> _work(dynamic e) => (e['sets'] as List).where((s) => !isWarmupRow(s)).toList();
JMap _allDone(dynamic entry) => {
      ...entry as Map<String, dynamic>,
      'sets': [for (final s in entry['sets'] as List) {...s as Map<String, dynamic>, 'done': true}],
    };

void main() {
  setUpAll(loadTestExerciseDb);

  group('buildSessionEntries', () {
    final st = {'unit': 'kg', 'workouts': [], 'exWeights': {}, 'routines': []};

    test('ramps the warm-ups on the exercise’s own increment, not the unit default', () {
      final r = {'id': 'r', 'prog': 'off', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60, 'inc': 1.25, 'warmupSets': 2}]};
      final entries = buildSessionEntries(st, r);
      final warm = (entries[0]['sets'] as List).where(isWarmupRow).map((s) => s['w'] as num).toList();
      expect(warm, hasLength(2));
      for (final w in warm) {
        expect((mathRound(w / 1.25 * 1000) / 1000) % 1, 0);
      }
      expect(_work(entries[0]).every((s) => s['w'] == 60), isTrue);
    });

    test('keeps the unit default for timed exercises, whose inc is seconds', () {
      final r = {'id': 'r', 'prog': 'off', 'ex': [{'id': '0025', 'mode': 'time', 'sets': 2, 'sec': 30, 'inc': 10, 'weight': 0}]};
      final entries = buildSessionEntries(st, r);
      expect((entries[0]['sets'] as List).every((s) => s['sec'] == 30), isTrue);
    });

    test('persists the effective deload target so completing the opened rows reads as a hit', () {
      final cfg = {'id': '0025', 'sets': 3, 'reps': 8, 'weight': 60, 'prog': 'linear'};
      final st = {
        'unit': 'kg', 'exWeights': {}, 'routines': [],
        'workouts': [
          for (final n in [1, 2, 3])
            {
              'd': '2026-01-0$n', 'routineIds': ['r'],
              'entries': [{'id': cfg['id'], 'target': {'sets': 3, 'reps': 8, 'weight': 60}, 'sets': [for (final r in [6, 6, 6]) {'w': 60, 'r': r, 'done': true}]}],
            },
        ],
      };
      final r = {'id': 'r', 'prog': 'linear', 'ex': [cfg]};
      final entry = buildSessionEntries(st, r)[0];
      final work = _work(entry);
      expect(entry['plan']['kind'], 'deload');
      expect(entry['target'], matchObj({'reps': entry['plan']['reps'], 'weight': entry['plan']['weight']}));
      expect(readSession(_allDone(entry), cfg)['ok'], isTrue);
      expect(work.every((s) => s['r'] == entry['target']['reps'] && s['w'] == entry['target']['weight']), isTrue);
    });

    JMap history(List<num> reps, [JMap extra = const {}]) => {
          'unit': 'kg', 'exWeights': {}, 'routines': [],
          'workouts': [
            {'d': '2026-01-01', 'routineIds': ['r'], 'entries': [{'id': '0025', 'target': {'sets': 2, 'reps': 15, 'weight': 40}, 'sets': [for (final r in reps) {'w': 40, 'r': r, 'done': true}]}]},
          ],
          ...extra,
        };
    for (final c in [
      ['linear', 'up', [15, 15]],
      ['linear', 'hold', [15, 9]],
      ['greyskull', 'up', [15, 15]],
      ['greyskull', 'deload', [15, 9]],
    ]) {
      final prog = c[0] as String, kind = c[1] as String, reps = (c[2] as List).cast<num>();
      test("opens $prog $kind at the plan's reps, and completing the rows reads as a hit", () {
        final cfg = {'id': '0025', 'sets': 2, 'reps': 10, 'weight': 40, 'prog': prog};
        final entry = buildSessionEntries(history(reps), {'id': 'r', 'prog': prog, 'ex': [cfg]})[0];
        final work = _work(entry);
        expect(entry['plan']['kind'], kind);
        expect(entry['target']['reps'], 10);
        expect(work.map((s) => s['r']).toList(), jeq([10, 10]));
        expect(work.every((s) => s['r'] == entry['target']['reps'] && s['w'] == entry['target']['weight']), isTrue);
        expect(readSession(_allDone(entry), cfg)['ok'], isTrue);
      });
    }

    test("carries last session's reps instead when the profile starts from the last session", () {
      final cfg = {'id': '0025', 'sets': 2, 'reps': 10, 'weight': 40, 'prog': 'linear'};
      final entry = buildSessionEntries(history([15, 15], {'startFrom': 'last'}), {'id': 'r', 'prog': 'linear', 'ex': [cfg]})[0];
      expect((entry['sets'] as List).map((s) => [s['w'], s['r']]).toList(), jeq([[42.5, 15], [42.5, 15]]));
      expect(entry['target']['reps'], 10);
      expect(entry['carried'], isTrue);
      expect(buildSessionEntries(history([15, 15]), {'id': 'r', 'prog': 'linear', 'ex': [cfg]})[0]['carried'], isNull);
      expect(buildSessionEntries(history([10, 10], {'startFrom': 'last'}), {'id': 'r', 'prog': 'linear', 'ex': [cfg]})[0]['carried'], isNull);
    });

    test("warms up at the plan's reps, not at last session's", () {
      final cfg = {'id': '0025', 'sets': 2, 'reps': 10, 'weight': 40, 'warmupSets': 1};
      final entry = buildSessionEntries(history([15, 15]), {'id': 'r', 'prog': 'linear', 'ex': [cfg]})[0];
      expect((entry['sets'] as List).map((s) => [isWarmupRow(s) ? 'warm' : 'work', s['r']]).toList(), jeq([['warm', 10], ['work', 10], ['work', 10]]));
    });

    test("re-ramps a progressed barbell lift's warm-up from the bar, not from half the weight", () {
      final lb = {'unit': 'lb', 'exWeights': {}, 'routines': [], 'workouts': [{'d': '2026-01-01', 'routineIds': ['r'], 'entries': [{'id': '0025', 'target': {'sets': 2, 'reps': 10, 'weight': 50}, 'sets': [for (final r in [10, 10]) {'w': 50, 'r': r, 'done': true}]}]}]};
      final cfg = {'id': '0025', 'sets': 2, 'reps': 10, 'weight': 50, 'prog': 'linear', 'warmupSets': 1};
      final entry = buildSessionEntries(lb, {'id': 'r', 'prog': 'linear', 'ex': [cfg]})[0];
      expect(entry['plan']['weight'], 55);
      expect((entry['sets'] as List).map((s) => s['w']).toList(), jeq([45, 55, 55]));
      final noBar = buildSessionEntries({...lb, 'barWeights': {'0025': 0}}, {'id': 'r', 'prog': 'linear', 'ex': [cfg]})[0];
      expect((noBar['sets'] as List).map((s) => s['w']).toList(), jeq([25, 55, 55]));
    });

    test("splits the plan's reps evenly per side", () {
      final cfg = {'id': '0025', 'sets': 1, 'reps': 16, 'weight': 20, 'side': true, 'prog': 'linear'};
      JMap side(num w, num r) => {'w': w, 'r': r, 'done': true};
      final st = {
        'unit': 'kg', 'exWeights': {}, 'routines': [],
        'workouts': [
          {'d': '2026-01-01', 'routineIds': ['r'], 'entries': [{'id': '0025', 'target': {'sets': 1, 'reps': 10, 'weight': 20, 'side': true}, 'sets': [
            {'w': 22.5, 'r': 10, 'done': true, 'sides': {'L': side(22.5, 5), 'R': side(20, 5)}},
          ]}]},
        ],
      };
      final entry = buildSessionEntries(st, {'id': 'r', 'ex': [cfg]})[0];
      final row = entry['sets'][0];
      expect(entry['plan']['kind'], 'up');
      expect([row['sides']['L']['r'], row['sides']['R']['r']], jeq([8, 8]));
      expect(row['r'], entry['target']['reps']);
    });

    test('stamps what the routine asked for on every entry, apart from the target it progressed', () {
      final cfg = {'id': '0025', 'sets': 2, 'reps': 10, 'weight': 40, 'prog': 'linear'};
      final entry = buildSessionEntries(history([15, 15]), {'id': 'r', 'prog': 'linear', 'ex': [cfg]})[0];
      expect(entry['planned'], jeq({'sets': 2, 'reps': 10, 'weight': 40}));
      expect(entry['target']['weight'], 42.5);
    });

    test('opens an edited plan at its new numbers, and completing them reads as a hit', () {
      final st = history([15, 15]);
      (st['workouts'] as List)[0]['entries'][0]['planned'] = {'sets': 2, 'reps': 15, 'weight': 40};
      final cfg = {'id': '0025', 'sets': 3, 'reps': 10, 'weight': 40, 'prog': 'linear'};
      final entry = buildSessionEntries(st, {'id': 'r', 'prog': 'linear', 'ex': [cfg]})[0];
      final work = _work(entry);
      expect(entry['plan']['kind'], 'hold');
      expect(work.map((s) => [s['w'], s['r']]).toList(), jeq([[40, 10], [40, 10], [40, 10]]));
      expect(entry['target'], matchObj({'sets': 3, 'reps': 10, 'weight': 40}));
      expect(readSession(_allDone(entry), cfg)['ok'], isTrue);
    });

    test('returns a bare array — no { entries, excluded } wrapper', () {
      final r = {'id': 'r', 'prog': 'off', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60}]};
      final out = buildSessionEntries(st, r);
      expect(out, isA<List>());
      expect(out, hasLength(1));
    });

    test('stamps noProg + plan.kind "off" on every entry of an excluded routine, and neither on a normal one', () {
      final ex = [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60}, {'id': '0031', 'sets': 3, 'reps': 8, 'weight': 40}];
      final excluded = buildSessionEntries(st, {'id': 'rehab', 'excludeFromProgression': true, 'ex': ex});
      expect(excluded.every((e) => e['noProg'] == true), isTrue);
      expect(excluded.every((e) => e['plan']['kind'] == 'off'), isTrue);
      final normal = buildSessionEntries(st, {'id': 'r', 'prog': 'off', 'ex': ex});
      expect(normal.every((e) => e['noProg'] == null), isTrue);
    });

    test('does not stamp rid — that is the merge helper’s job', () {
      final r = {'id': 'r', 'prog': 'off', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60}]};
      expect(buildSessionEntries(st, r)[0]['rid'], isNull);
    });
  });

  group('plannedConfigOf', () {
    test("puts the plan's sets, reps and range back in place of today's", () {
      final entry = {
        'target': {'id': '0025', 'mode': 'reps', 'sets': 3, 'reps': 9, 'repsMin': 8, 'weight': 42.5, 'prog': 'double'},
        'planned': {'sets': 3, 'reps': 12, 'repsMin': 8, 'weight': 40},
      };
      expect(plannedConfigOf(entry), jeq({'id': '0025', 'mode': 'reps', 'sets': 3, 'reps': 12, 'repsMin': 8, 'weight': 42.5, 'prog': 'double'}));
    });

    test("drops a bottom the plan does not have, and takes a hold's seconds", () {
      expect(plannedConfigOf({'target': {'sets': 3, 'reps': 13, 'repsMin': 10, 'weight': 0}, 'planned': {'sets': 2, 'reps': 10, 'weight': 0}}),
          jeq({'sets': 2, 'reps': 10, 'weight': 0}));
      expect(plannedConfigOf({'target': {'mode': 'time', 'sets': 2, 'sec': 50, 'weight': 0}, 'planned': {'sets': 2, 'sec': 45, 'weight': 0}})['sec'], 45);
    });

    test('opens an entry built before plans were stamped at its target', () {
      final target = {'sets': 2, 'reps': 8, 'weight': 60};
      expect(plannedConfigOf({'target': target}), jeq(target));
      expect(plannedConfigOf({'target': target}), isNot(same(target)));
    });
  });

  group('builtOutOfProgression', () {
    final deload = {'id': 'd', 'excludeFromProgression': true};
    final main = {'id': 'm'};

    test('is an exercise of a routine kept out of progression', () {
      expect(builtOutOfProgression({'noProg': true, 'rid': 'd'}, deload), isTrue);
    });
    test('is not an exercise kept out by hand in a routine that counts', () {
      expect(builtOutOfProgression({'noProg': true, 'rid': 'm'}, main), isFalse);
    });
    test('is not an exercise with no routine, nor one that was never kept out', () {
      expect(builtOutOfProgression({'noProg': true}, null), isFalse);
      expect(builtOutOfProgression({'rid': 'd'}, deload), isFalse);
      expect(builtOutOfProgression(null, deload), isFalse);
    });
  });
}
