// Port of frontend/src/lib/exercises.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';

import '_exdb.dart';
import '_helpers.dart';

void main() {
  setUpAll(loadTestExerciseDb);

  group('normalizeStr', () {
    test('handles null, undefined and empty strings', () {
      expect(normalizeStr(null), '');
      expect(normalizeStr(''), '');
    });

    test('lowercases text and removes diacritics / accents', () {
      expect(normalizeStr('Elevação Lateral'), 'elevacao lateral');
      expect(normalizeStr('SUPINO INCLINADO COM HALTERES'), 'supino inclinado com halteres');
      expect(normalizeStr('Tríceps & Panturrilhas'), 'triceps & panturrilhas');
      expect(normalizeStr('Quadríceps / Glúteos'), 'quadriceps / gluteos');
    });
  });

  group('matchExercise', () {
    final benchPress = {
      'id': '0025', 'n': 'barbell bench press', 'bp': 'chest', 'tg': 'pectorals', 'eq': 'barbell',
      'sm': ['triceps', 'deltoids'], 'desc': 'Classic chest exercise using a barbell on a flat bench.',
    };
    final lateralRaise = {
      'id': '0283', 'n': 'dumbbell lateral raise', 'bp': 'shoulders', 'tg': 'delts', 'eq': 'dumbbell',
      'sm': ['traps'], 'desc': 'Shoulder isolation movement.',
    };

    test('returns true for empty or whitespace-only query', () {
      expect(matchExercise(benchPress, ''), isTrue);
      expect(matchExercise(benchPress, '   '), isTrue);
      expect(matchExercise(benchPress, null), isTrue);
    });

    test('matches exact and partial words in exercise name regardless of case', () {
      expect(matchExercise(benchPress, 'bench'), isTrue);
      expect(matchExercise(benchPress, 'BENCH'), isTrue);
      expect(matchExercise(benchPress, 'barbell'), isTrue);
      expect(matchExercise(benchPress, 'press'), isTrue);
      expect(matchExercise(benchPress, 'squat'), isFalse);
    });

    test('matches multiple tokens in ANY order (not just sequential)', () {
      expect(matchExercise(benchPress, 'bench barbell'), isTrue);
      expect(matchExercise(benchPress, 'press bench barbell'), isTrue);
      expect(matchExercise(benchPress, 'barbell press chest'), isTrue);
      expect(matchExercise(benchPress, 'bench squat'), isFalse);
    });

    test('matches target muscle, equipment, secondary muscles and description', () {
      expect(matchExercise(benchPress, 'pectorals'), isTrue);
      expect(matchExercise(benchPress, 'triceps barbell'), isTrue);
      expect(matchExercise(benchPress, 'flat bench'), isTrue);
      expect(matchExercise(lateralRaise, 'dumbbell shoulder'), isTrue);
    });

    test('matches accent-insensitively', () {
      final customEx = {
        'id': 'custom-1', 'n': 'Elevação de Panturrilha', 'bp': 'lower legs', 'tg': 'calves', 'eq': 'body weight',
        'desc': 'Exercício para panturrilhas em pé.',
      };
      expect(matchExercise(customEx, 'elevacao'), isTrue);
      expect(matchExercise(customEx, 'elevação'), isTrue);
      expect(matchExercise(customEx, 'panturrilha elevacao'), isTrue);
      expect(matchExercise(customEx, 'ELEVACAO PE'), isTrue);
    });

    // skipped: 'matches translated UI terms when a language is active', 'matches the localized
    // exercise name as well as the English one', 'rebuilds the cached haystack when the language
    // changes' — need a non-English locale / name pack (_setLangState), not in the English shim.
  });

  group('the exercise dataset', () {
    test('has no names garbled by a wrong text encoding', () {
      final garbled = EXDB.where((e) => RegExp('в°|Ã|Â|â€').hasMatch(e['n'] as String)).map((e) => '${e['id']} ${e['n']}').toList();
      expect(garbled, isEmpty);
      expect(EXDB.firstWhere((e) => e['id'] == '0739')['n'], 'sled 45° leg press');
    });

    test('finds the sled presses by their angle', () {
      final found = EXDB.where((e) => matchExercise(e, '45° leg press')).map((e) => e['id']).toList();
      expect(found, containsAll(['0739', '1464', '0740']));
    });
  });

  group('search: the everyday version first', () {
    test('"leg press" finds the 45° sled leg press before the Smith and one-leg versions', () {
      expect(searchExercises(EXDB, 'leg press')[0]['id'], '0739');
      expect(searchExercises(EXDB, 'smith leg press')[0]['id'], '0760');
    });
  });

  group('byCategory', () {
    final list = [
      {'id': 'a', 'cat': 'stretching'},
      {'id': 'b', 'cat': 'strength'},
      {'id': 'c'},
    ];
    test('offers the types present, in the fixed order, and narrows to the chosen one', () {
      expect(byCategory(list, ''), jeq({'opts': ['strength', 'stretching'], 'on': '', 'list': list}));
      expect(byCategory(list, 'stretching'), jeq({'opts': ['strength', 'stretching'], 'on': 'stretching', 'list': [list[0]]}));
    });
    test('ignores a type the list has none of instead of showing nothing', () {
      expect(byCategory(list, 'yoga'), jeq({'opts': ['strength', 'stretching'], 'on': '', 'list': list}));
    });
  });
}
