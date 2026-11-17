// Port of frontend/src/lib/units.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/plates.dart';
import 'package:klora_app/engine/units.dart';

import '_exdb.dart';
import '_helpers.dart';

void main() {
  setUpAll(loadTestExerciseDb);

  group('convertWeight', () {
    test('rounds lb to a half and kg to a quarter', () {
      expect(convertWeight(60, 'kg', 'lb'), 132.5);
      expect(convertWeight(135, 'lb', 'kg'), 61.25);
      expect(convertWeight(2.5, 'kg', 'lb'), 5.5);
    });
    test('leaves the value alone for the same unit, nothing, or garbage', () {
      expect(convertWeight(60, 'kg', 'kg'), 60);
      expect(convertWeight(null, 'kg', 'lb'), isNull);
      expect(convertWeight('', 'kg', 'lb'), '');
      expect(convertWeight('abc', 'kg', 'lb'), 'abc');
    });
    test('round-trips plate-loadable numbers', () {
      for (final kg in [20, 42.5, 60, 100, 142.5]) {
        expect(convertWeight(convertWeight(kg, 'kg', 'lb'), 'lb', 'kg'), kg);
      }
    });
  });

  group('convertStateUnit', () {
    JMap mk() => clone({
          'unit': 'kg', 'targetW': 80, 'bodyweight': [{'d': '2026-01-01', 'w': 82.4, 't': 1}],
          'exWeights': {'0025': {'w': 80, 'd': '2026-01-01'}, 'legacy': 100}, 'barWeights': {'0025': 15},
          'routines': [{'id': 'r', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 80, 'inc': 2.5, 'warmup': [{'weight': 40, 'reps': 8}]}, {'id': 'plank', 'mode': 'time', 'sec': 30, 'inc': 5}]}],
          'workouts': [{'id': 'w', 'entries': [{'id': '0025', 'topW': 80, 'target': {'weight': 80}, 'planned': {'sets': 3, 'reps': 5, 'weight': 80}, 'sets': [{'w': 80, 'r': 5, 'done': true, 'drops': [{'w': 60, 'r': 5}]}]}]}],
          'active': {'id': 'a', 'entries': [{'id': '0025', 'sets': [{'w': 82.5, 'r': 5, 'done': false}]}]},
          'workoutView': 'list',
        }) as JMap;
    final S = mk();

    test('converts every stored weight and keeps everything else', () {
      final out = convertStateUnit(S, 'lb');
      expect(out['unit'], 'lb');
      expect(out['targetW'], 176.4);
      expect(out['bodyweight'][0], jeq({'d': '2026-01-01', 'w': 181.7, 't': 1}));
      expect(out['exWeights']['0025']['w'], 176.5);
      expect(out['exWeights']['legacy'], 220.5);
      expect(out['barWeights']['0025'], 33);
      expect(out['routines'][0]['ex'][0], matchObj({'weight': 176.5, 'inc': 5.5, 'warmup': [{'weight': 88, 'reps': 8}]}));
      expect(out['routines'][0]['ex'][1], jeq({'id': 'plank', 'mode': 'time', 'sec': 30, 'inc': 5}));
      expect(out['workouts'][0]['entries'][0], matchObj({'topW': 176.5, 'target': {'weight': 176.5}, 'planned': {'sets': 3, 'reps': 5, 'weight': 176.5}}));
      expect(out['workouts'][0]['entries'][0]['sets'][0], matchObj({'w': 176.5, 'done': true, 'drops': [{'w': 132.5, 'r': 5}]}));
      expect(out['active']['entries'][0]['sets'][0]['w'], 182);
      expect(out['workoutView'], 'list');
      expect(S['unit'], 'kg');
      expect(S['workouts'][0]['entries'][0]['sets'][0]['w'], 80);
    });
    test('is a no-op for the unit already in use', () {
      expect(convertStateUnit(S, 'kg'), same(S));
    });
    test('converts a pyramid’s weight per set, leaving a set at 0 at 0 (#445)', () {
      final state = {...mk(), 'routines': [{'id': 'r', 'ex': [{'id': '0025', 'sets': 3, 'reps': 12, 'weight': 0, 'pyramid': [12, 10, 8], 'pyramidWeight': [60, 0, 80]}]}]};
      expect(convertStateUnit(state, 'lb')['routines'][0]['ex'][0]['pyramidWeight'], jeq([132.5, 0, 176.5]));
    });
    test("converts each workout's cached volume and session body weight, and the active session's (QA C11)", () {
      final drop = {'id': '0025', 'sets': [{'w': 80, 'r': 5, 'done': true, 'type': 'dropset', 'drops': [{'w': 60, 'r': 5}]}, {'w': 40, 'r': 8, 'done': true, 'phase': 'warmup'}]};
      final base = mk();
      final state = {
        ...base,
        'workouts': [{'id': 'w', 'vol': 700, 'bw': 82.4, 'entries': [drop]}, {'id': 'x', 'entries': []}],
        'active': {...base['active'] as Map<String, dynamic>, 'bw': 82.4},
      };
      final out = convertStateUnit(state, 'lb');
      expect(out['workouts'][0]['vol'], 1545);
      expect(workoutVolume(out['workouts'][0]), 1545);
      expect(out['workouts'][0]['bw'], 181.7);
      expect(out['active']['bw'], 181.7);
      expect((out['workouts'][1] as Map).containsKey('vol'), isFalse);
      expect((state['workouts'] as List)[0]['vol'], 700);
    });
    test('keeps body weight at 0.1 resolution and brings a kg → lb → kg round trip home (QA C15)', () {
      final ws = [78.6, 82.1, 82.2, 81.8, 81.4];
      final state = <String, dynamic>{
        'unit': 'kg', 'targetW': 77,
        'bodyweight': [for (var i = 0; i < ws.length; i++) {'d': '2026-01-0${i + 1}', 'w': ws[i], 't': i}],
        'workouts': [{'id': 'w', 'bw': 78.6, 'entries': []}], 'active': {'id': 'a', 'bw': 78.6, 'entries': []},
      };
      final lb = convertStateUnit(state, 'lb');
      expect((lb['bodyweight'] as List).map((b) => b['w']).toList(), jeq([173.3, 181, 181.2, 180.3, 179.5]));
      expect(lb['targetW'], 169.8);
      final back = convertStateUnit(lb, 'kg');
      expect((back['bodyweight'] as List).map((b) => b['w']).toList(), jeq([78.6, 82.1, 82.2, 81.8, 81.4]));
      expect(back['targetW'], 77);
      expect(back['workouts'][0]['bw'], 78.6);
      expect(back['active']['bw'], 78.6);
    });
  });

  group('convertStateUnit: bar weights', () {
    dynamic conv(Map<String, dynamic> barWeights, String from, String to) => convertStateUnit({'unit': from, 'barWeights': barWeights}, to)['barWeights'];

    test('an override equal to the old default drops out, so the new default applies (45 lb IS the 20 kg bar)', () {
      expect(conv({'0025': 45}, 'lb', 'kg'), jeq({}));
      expect(conv({'0025': 20}, 'kg', 'lb'), jeq({}));
      expect(conv({'1344': 25}, 'lb', 'kg'), jeq({}));
      expect(conv({'1344': 10}, 'kg', 'lb'), jeq({}));
    });
    test('an explicit 0 ("no bar") stays 0', () {
      expect(conv({'0025': 0}, 'lb', 'kg'), jeq({'0025': 0}));
      expect(conv({'0025': 0}, 'kg', 'lb'), jeq({'0025': 0}));
    });
    test('a custom bar converts like any weight, and drops out when it lands on the new default', () {
      expect(conv({'0025': 33}, 'lb', 'kg'), jeq({'0025': 15}));
      expect(conv({'0025': 15}, 'kg', 'lb'), jeq({'0025': 33}));
      expect(conv({'0025': 44}, 'lb', 'kg'), jeq({}));
      expect(conv({'1383': 100}, 'lb', 'kg'), jeq({'1383': 45.25}));
      expect(conv({'no-such-id': 45}, 'lb', 'kg'), jeq({'no-such-id': 20.5}));
    });
    test('junk in the map is dropped', () {
      expect(conv({'0025': '45', '1344': -1, '1383': null}, 'lb', 'kg'), jeq({}));
    });
  });

  group('convertStateUnit: plate inventories', () {
    final home = {'45': 1, '35': 1, '25': 1, '10': 2, '_ts': 50};
    final S = <String, dynamic>{'unit': 'lb', 'plates': {'lb': home}, 'loadKind': {'0025': {'kind': 'none', '_ts': 40}}, 'barWeights': {'1383': 100}};

    test('each unit keeps its own list; the kg side starts from the standard kg set', () {
      final kg = convertStateUnit(S, 'kg');
      expect(kg['plates'], jeq({'lb': home}));
      expect(kg['loadKind'], jeq(S['loadKind']));
      expect(inventoryFor(kg), jeq(inventoryFor({'unit': 'kg'})));
      expect(kg['barWeights'], jeq({'1383': 45.25}));
      final back = convertStateUnit(kg, 'lb');
      expect(back['plates'], jeq({'lb': home}));
      expect(inventoryFor(back), jeq([{'w': 45, 'n': 1}, {'w': 35, 'n': 1}, {'w': 25, 'n': 1}, {'w': 10, 'n': 2}]));
    });

    test('a kg list counted after the switch is the one the kg rows use, and the lb list survives it', () {
      final kg = convertStateUnit(S, 'kg');
      kg['plates'] = withPlatePairs(kg, 20, 1, 60);
      expect(inventoryFor(kg).firstWhere((p) => p['w'] == 20)['n'], 1);
      final back = convertStateUnit(kg, 'lb');
      expect(back['plates']['lb'], jeq(home));
      expect(back['plates']['kg'], matchObj({'20': 1, '_ts': 60}));
    });
  });
}
