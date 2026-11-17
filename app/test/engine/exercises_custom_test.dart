// Port of frontend/src/lib/exercises.custom.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';

import '_exdb.dart';
import '_helpers.dart';

void main() {
  setUpAll(loadTestExerciseDb);
  tearDown(() => registerCustom([]));

  group('isCustomEx', () {
    test('a registered custom exercise without the flag is still custom', () {
      final c = <String, dynamic>{'id': 'cx1', 'n': 'My row', 'bp': 'back'};
      expect(isCustomEx(c), isFalse);
      registerCustom([c]);
      expect(isCustomEx(c), isTrue);
      expect(isCustomEx({...c}), isTrue);
      expect(isCustomEx(EXIDX['cx1']), isTrue);
    });

    test('a flagged one is custom even before it is registered', () {
      expect(isCustomEx({'id': 'cnew', 'n': 'x', 'bp': 'back', 'custom': true}), isTrue);
    });

    test('a built-in is never custom, also when a custom shadows its id', () {
      final built = CATALOGUE[0];
      expect(isCustomEx(built), isFalse);
      final shadow = {'id': built['id'], 'n': 'Mine', 'bp': 'back'};
      registerCustom([shadow]);
      expect(isCustomEx(shadow), isTrue);
      expect(isCustomEx(built), isFalse);
      registerCustom([]);
      expect(EXIDX[built['id']], same(built));
    });

    test('nothing is not custom', () {
      expect(isCustomEx(null), isFalse);
      expect(isCustomEx('cx1'), isFalse);
    });
  });

  group('healCustomEx', () {
    test('puts the flag back on entries that lost it, keeping their stamp', () {
      final list = [
        {'id': 'a', 'n': 'A', 'bp': 'back', '_ts': 5},
        {'id': 'b', 'n': 'B', 'bp': 'chest', 'eq': 'custom', 'custom': true},
      ];
      final out = healCustomEx(list) as List;
      expect(out, isNot(same(list)));
      expect(out[0], jeq({'id': 'a', 'n': 'A', 'bp': 'back', '_ts': 5, 'custom': true, 'eq': ''}));
      expect(out[1], same(list[1]));
      expect(list[0]['custom'], isNull);
    });

    test('is idempotent and keeps identity when nothing is missing', () {
      final once = healCustomEx([{'id': 'a', 'n': 'A', 'bp': 'back', 'eq': 'cable'}]) as List;
      expect(once[0]['eq'], 'cable');
      expect(healCustomEx(once), same(once));
      final empty = [];
      expect(healCustomEx(empty), same(empty));
      expect(healCustomEx(null), isNull);
    });

    test('leaves junk entries alone', () {
      final list = [null, {'id': 'a', 'n': 'A', 'bp': 'back', 'custom': true}];
      expect(healCustomEx(list), same(list));
    });
  });
}
