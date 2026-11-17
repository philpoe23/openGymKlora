// Port of frontend/src/lib/plates.test.js. JS object keys are strings, so plate sizes appear as
// '45', '2.5' in the Dart maps.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';
import 'package:klora_app/engine/plates.dart';

import '_exdb.dart';
import '_helpers.dart';

final home = <String, dynamic>{
  'unit': 'lb',
  'plates': {'lb': {'45': 1, '35': 1, '25': 1, '15': 1, '10': 1, '5': 1, '2.5': 1}},
};

void main() {
  setUpAll(loadTestExerciseDb);
  String idOf(String eq) => EXDB.firstWhere((e) => e['eq'] == eq)['id'] as String;
  late List<dynamic> homeInv;
  setUpAll(() => homeInv = inventoryFor(home));

  group('inventoryFor', () {
    test('a profile without plates of its own gets the standard set for its unit, plenty of each', () {
      final lb = inventoryFor({'unit': 'lb'});
      expect(lb.map((p) => p['w']).toList(), jeq([45, 35, 25, 10, 5, 2.5]));
      expect(lb.every((p) => p['n'] == DEFAULT_PAIRS), isTrue);
      final kg = inventoryFor({'unit': 'kg'});
      expect(kg.map((p) => p['w']).toList(), jeq([25, 20, 15, 10, 5, 2.5, 1.25]));
      expect(inventoryFor({}).map((p) => p['w']).toList(), jeq(kg.map((p) => p['w']).toList()));
    });

    test('the editor lists every size, the inventory only what you have', () {
      expect(PLATE_SIZES['lb'], contains(15));
      expect(homeInv.map((p) => p['w']).toList(), jeq([45, 35, 25, 15, 10, 5, 2.5]));
      expect(homeInv.every((p) => p['n'] == 1), isTrue);
      expect(pairsOf(home, 45), 1);
      expect(pairsOf(home, 1.25), 0);
      expect(pairsOf({'unit': 'lb'}, 45), DEFAULT_PAIRS);
    });

    test("zero and junk counts drop out; the other unit's inventory is ignored", () {
      final S = {'unit': 'kg', 'plates': {'kg': {'20': 2, '10': 0, '5': 'x', '2.5': 1.9}, 'lb': {'45': 9}}};
      expect(inventoryFor(S), jeq([{'w': 20, 'n': 2}, {'w': 2.5, 'n': 1}]));
    });

    test("a list's stamp is not a plate, and a stamped list with no sizes is the standard set", () {
      expect(inventoryFor({'unit': 'lb', 'plates': {'lb': {'45': 1, '_ts': 1700}}}), jeq([{'w': 45, 'n': 1}]));
      expect(ownsPlates({'unit': 'lb', 'plates': {'lb': {'45': 1, '_ts': 1700}}}), isTrue);
      final reset = {'unit': 'lb', 'plates': {'lb': {'_ts': 1800}}};
      expect(ownsPlates(reset), isFalse);
      expect(inventoryFor(reset), jeq(inventoryFor({'unit': 'lb'})));
      final none = {'unit': 'lb', 'plates': {'lb': {'45': 0, '25': 0, '_ts': 1900}}};
      expect(ownsPlates(none), isTrue);
      expect(inventoryFor(none), jeq([]));
      expect(ownsPlates({'unit': 'kg', 'plates': {'lb': {'45': 1}}}), isFalse);
    });
  });

  group('stored choices carry the time they were made', () {
    test('the first count copies the standard set in; later ones change one size; both stamped', () {
      final first = withPlatePairs({'unit': 'lb', 'plates': {}}, 45, 1, 100);
      expect(first, jeq({'lb': {'45': 1, '35': 6, '25': 6, '10': 6, '5': 6, '2.5': 6, '_ts': 100}}));
      final next = withPlatePairs({'unit': 'lb', 'plates': {...first, 'kg': {'20': 2, '_ts': 50}}}, 15, 2.6, 200);
      expect(next['lb'], jeq({'45': 1, '35': 6, '25': 6, '15': 3, '10': 6, '5': 6, '2.5': 6, '_ts': 200}));
      expect(next['kg'], jeq({'20': 2, '_ts': 50}));
      expect(withPlatePairs({'unit': 'lb', 'plates': first}, 45, -3, 300)['lb']['45'], 0);
    });

    test('back to the standard set is a stamped list with no sizes, for this unit only', () {
      final S = {'unit': 'kg', 'plates': {'kg': {'20': 1, '_ts': 100}, 'lb': {'45': 1, '_ts': 90}}};
      expect(withStandardPlates(S, 200), jeq({'kg': {'_ts': 200}, 'lb': {'45': 1, '_ts': 90}}));
      expect(withStandardPlates({'unit': 'kg'}, 200), jeq({'kg': {'_ts': 200}}));
    });

    test("a load kind is stored with its time; null is the equipment's own, stamped too", () {
      expect(withLoadKind(null, 'a', 'single', 100), jeq({'a': {'kind': 'single', '_ts': 100}}));
      expect(withLoadKind({'a': {'kind': 'single', '_ts': 100}}, 'a', null, 200), jeq({'a': {'kind': null, '_ts': 200}}));
      expect(withLoadKind({}, 'a', 'weird', 100), jeq({'a': {'kind': null, '_ts': 100}}));
      expect(loadKindOf({'kind': 'none', '_ts': 1}), 'none');
      expect(loadKindOf({'kind': null, '_ts': 1}), isNull);
      expect(loadKindOf('pairs'), 'pairs');
      expect(loadKindOf('weird'), isNull);
      expect(loadKindOf(null), isNull);
    });
  });

  group('plateStack', () {
    test('heaviest first when that lands exactly — the way a bar is loaded', () {
      expect(plateStack(50, homeInv), jeq({'plates': [45, 5], 'missing': 0}));
      expect(plateStack(60, inventoryFor({'unit': 'lb'})), jeq({'plates': [45, 10, 5], 'missing': 0}));
      expect(plateStack(115, inventoryFor({'unit': 'lb'})), jeq({'plates': [45, 45, 25], 'missing': 0}));
      expect(plateStack(21.25, inventoryFor({'unit': 'kg'})), jeq({'plates': [20, 1.25], 'missing': 0}));
    });

    test("the coach ramp on Monday's squat, one pair of each", () {
      expect(plateStack(12.5, homeInv)['plates'], jeq([10, 2.5]));
      expect(plateStack(27.5, homeInv)['plates'], jeq([25, 2.5]));
      expect(plateStack(37.5, homeInv)['plates'], jeq([35, 2.5]));
      expect(plateStack(50, homeInv)['plates'], jeq([45, 5]));
      expect(plateStack(137.5, homeInv), jeq({'plates': [45, 35, 25, 15, 10, 5, 2.5], 'missing': 0}));
    });

    test('when greedy misses, the fewest plates that hit the weight exactly', () {
      expect(plateStack(50, [{'w': 35, 'n': 1}, {'w': 25, 'n': 2}]), jeq({'plates': [25, 25], 'missing': 0}));
      expect(plateStack(100, homeInv), jeq({'plates': [45, 35, 15, 5], 'missing': 0}));
    });

    test('what cannot be loaded says how much is missing, from the closest load below', () {
      expect(plateStack(140, homeInv), jeq({'plates': [45, 35, 25, 15, 10, 5, 2.5], 'missing': 2.5}));
      expect(plateStack(12.5, [{'w': 10, 'n': 1}, {'w': 5, 'n': 1}]), jeq({'plates': [10], 'missing': 2.5}));
      expect(plateStack(1, homeInv), jeq({'plates': [], 'missing': 1}));
    });

    test('nothing to load is an empty stack; an empty inventory misses everything', () {
      expect(plateStack(0, homeInv), jeq({'plates': [], 'missing': 0}));
      expect(plateStack(null, homeInv), jeq({'plates': [], 'missing': 0}));
      expect(plateStack(30, []), jeq({'plates': [], 'missing': 30}));
    });

    test('beyond everything you own: every plate on, the rest missing, without a search', () {
      expect(plateStack(200, homeInv), jeq({'plates': [45, 35, 25, 15, 10, 5, 2.5], 'missing': 62.5}));
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        expect(plateStack(999999.75, homeInv)['missing'], 999999.75 - 137.5);
      }
      expect(sw.elapsedMilliseconds, lessThan(200));
    });
  });

  group('plateDelta', () {
    test('what comes off and what goes on between two stacks', () {
      expect(plateDelta([10, 2.5], [25, 2.5]), jeq({'strip': [10], 'add': [25]}));
      expect(plateDelta([45, 5], [45, 5]), jeq({'strip': [], 'add': []}));
      expect(plateDelta([], [45, 35]), jeq({'strip': [], 'add': [45, 35]}));
      expect(plateDelta([45, 45, 10], [45, 25, 5])['strip'], jeq([45, 10]));
      expect(plateDelta([45, 45, 10], [45, 25, 5])['add'], jeq([25, 5]));
    });
  });

  group('loadKindFor', () {
    test('bars split per side, added weight and sleds are one stack, the rest is not plate-loaded', () {
      expect(loadKindFor({}, idOf('barbell')), 'pairs');
      expect(loadKindFor({}, idOf('smith machine')), 'pairs');
      expect(loadKindFor({}, idOf('body weight')), 'single');
      expect(loadKindFor({}, idOf('weighted')), 'single');
      expect(loadKindFor({}, idOf('sled machine')), 'single');
      expect(loadKindFor({}, idOf('dumbbell')), 'none');
      expect(loadKindFor({}, 'no-such-id'), 'none');
      expect(loadKindFor({}, idOf('band')), 'none');
      expect(loadKindFor({}, idOf('resistance band')), 'none');
      expect(loadKindFor({}, {'id': idOf('band'), 'bodyweight': true}), 'none');
    });

    test('a routine flagging an exercise as body-weight follows the flag', () {
      expect(loadKindFor({}, {'id': idOf('dumbbell'), 'bodyweight': true}), 'single');
      expect(loadKindFor({}, {'id': idOf('body weight'), 'bodyweight': false}), 'none');
    });

    test("the user's own choice wins; junk does not", () {
      final db = idOf('dumbbell'), barbell = idOf('barbell');
      expect(loadKindFor({'loadKind': {db: 'single'}}, db), 'single');
      expect(loadKindFor({'loadKind': {barbell: 'none'}}, barbell), 'none');
      expect(loadKindFor({'loadKind': {barbell: 'weird'}}, barbell), 'pairs');
    });

    test("a stamped choice reads like a bare one; a stamped null is the equipment's own", () {
      final db = idOf('dumbbell'), barbell = idOf('barbell'), bw = idOf('body weight');
      expect(loadKindFor({'loadKind': {db: {'kind': 'single', '_ts': 5}}}, db), 'single');
      expect(loadKindFor({'loadKind': {barbell: {'kind': 'none', '_ts': 5}}}, barbell), 'none');
      expect(loadKindFor({'loadKind': {barbell: {'kind': null, '_ts': 5}}}, barbell), 'pairs');
      expect(loadKindFor({'loadKind': {bw: {'kind': null, '_ts': 5}}}, {'id': bw, 'bodyweight': false}), 'none');
    });
  });

  group('baseWeightFor', () {
    test('the bar for bar exercises, 0 for "no bar", the override or 0 for anything else', () {
      final barbell = idOf('barbell'), sled = idOf('sled machine');
      expect(baseWeightFor({'unit': 'lb'}, barbell), 45);
      expect(baseWeightFor({'unit': 'lb', 'barWeights': {barbell: 0}}, barbell), 0);
      expect(baseWeightFor({'unit': 'lb', 'barWeights': {barbell: 35}}, barbell), 35);
      expect(baseWeightFor({'unit': 'lb'}, sled), 0);
      expect(baseWeightFor({'unit': 'lb', 'barWeights': {sled: 100}}, sled), 100);
      expect(baseWeightFor({'unit': 'lb'}, 'no-such-id'), 0);
    });
  });

  group('rowLoad', () {
    test('a bar row: per side beyond the bar, as plates', () {
      expect(rowLoad('pairs', 145, 45, homeInv), jeq({'kind': 'pairs', 'barOnly': false, 'perSide': 50, 'plates': [45, 5], 'missing': 0}));
      expect(rowLoad('pairs', 70, 45, homeInv)!['plates'], jeq([10, 2.5]));
    });

    test('at or below the bar is "bar only"; no weight is nothing', () {
      expect(rowLoad('pairs', 45, 45, homeInv), matchObj({'barOnly': true, 'plates': []}));
      expect(rowLoad('pairs', 40, 45, homeInv), matchObj({'barOnly': true}));
      expect(rowLoad('pairs', 0, 45, homeInv), isNull);
      expect(rowLoad('pairs', null, 45, homeInv), isNull);
    });

    test('no bar (issue #138): the whole total is plates', () {
      expect(rowLoad('pairs', 90, 0, homeInv), matchObj({'perSide': 45, 'plates': [45]}));
    });

    test('a single stack takes all of it beyond the base: a belt, a sled', () {
      expect(rowLoad('single', 25, 0, homeInv), jeq({'kind': 'single', 'barOnly': false, 'perSide': 25, 'plates': [25], 'missing': 0}));
      expect(rowLoad('single', 190, 100, homeInv)!['plates'], jeq([45, 45]));
    });

    test('a single stack counts both plates of each pair you own (QA 1.3.11)', () {
      final inv = inventoryFor({'unit': 'kg', 'plates': {'kg': {'20': 1, '10': 1, '_ts': 1}}});
      expect(rowLoad('single', 150, 0, inv), matchObj({'plates': [20, 20, 10, 10], 'missing': 90}));
      expect(rowLoad('single', 40, 0, inv), matchObj({'plates': [20, 20], 'missing': 0}));
      expect(rowLoad('pairs', 80, 20, inv), matchObj({'perSide': 30, 'plates': [20, 10], 'missing': 0}));
    });

    test('kind none never loads', () {
      expect(rowLoad('none', 100, 20, homeInv), isNull);
      expect(rowLoad(null, 100, 20, homeInv), isNull);
    });

    test('sameLoad compares stacks, so a run of equal weights shows its plates once', () {
      final a = rowLoad('pairs', 145, 45, homeInv), b = rowLoad('pairs', 145, 45, homeInv), c = rowLoad('pairs', 120, 45, homeInv);
      expect(sameLoad(a, b), isTrue);
      expect(sameLoad(a, c), isFalse);
      expect(sameLoad(rowLoad('pairs', 45, 45, homeInv), rowLoad('pairs', 40, 45, homeInv)), isTrue);
      expect(sameLoad(a, null), isFalse);
      expect(sameLoad(rowLoad('pairs', 325, 45, homeInv), rowLoad('pairs', 330, 45, homeInv)), isFalse);
    });
  });

  group('dropGrid', () {
    test("without a plate inventory of your own: the exercise's weight step", () {
      expect(dropGrid({'unit': 'kg'}, {'id': idOf('dumbbell'), 'inc': 2}), 2);
      expect(dropGrid({'unit': 'kg'}, {'id': idOf('barbell'), 'inc': 1.25}), 1.25);
    });
    test('with your own plates on a bar: the heaviest load at or below the drop that they make', () {
      final S = {'unit': 'kg', 'plates': {'kg': {'10': 2, '5': 1, '_ts': 1}}};
      final snap = dropGrid(S, {'id': idOf('barbell')});
      expect(snap, isA<Function>());
      expect(snap(48), 40);
      expect(snap(64), 60);
      expect(snap(15), 20);
    });
    test('a single stack drops onto both plates of each pair', () {
      final sled = idOf('sled machine');
      final S = {'unit': 'kg', 'plates': {'kg': {'20': 1, '10': 1, '_ts': 1}}, 'barWeights': {sled: 0}};
      final snap = dropGrid(S, {'id': sled});
      expect(snap(55), 50);
      expect(snap(100), 60);
    });
    test('a dumbbell is not plate-loaded, so plates do not decide its drop', () {
      final S = {'unit': 'kg', 'plates': {'kg': {'10': 2, '_ts': 1}}};
      expect(dropGrid(S, {'id': idOf('dumbbell'), 'inc': 2}), 2);
    });
  });

  group('loads between quarter-unit boundaries', () {
    for (final weight in [0.1, 2.4, 2.6, 7.4, 8.1]) {
      test('never exceeds $weight and reports the actual deficit', () {
        final result = plateStack(weight, [{'w': 2.5, 'n': 3}]);
        final loaded = (result['plates'] as List).fold<num>(0, (sum, w) => sum + (w as num));
        expect(loaded, lessThanOrEqualTo(weight));
        expect(result['missing'], closeTo(weight - loaded, 0.005));
      });
    }

    test('drop sets snap to a load the counted plates can make', () {
      final S = {'unit': 'kg', 'plates': {'kg': {'5': 3}}};
      final snap = dropGrid(S, {'id': idOf('barbell')});
      expect(snap(48.74), 40);
    });
  });
}
