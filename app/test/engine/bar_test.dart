// Port of frontend/src/lib/bar.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/bar.dart';
import 'package:klora_app/engine/exercises.dart';

import '_exdb.dart';

void main() {
  setUpAll(loadTestExerciseDb);
  String idOf(String eq) => EXDB.firstWhere((e) => e['eq'] == eq)['id'] as String;

  group('bar equipment', () {
    test('covers the five bar types and the 228 v1.3 catalogue exercises they carry', () {
      expect(BAR_EQ.toList()..sort(), ['barbell', 'ez barbell', 'olympic barbell', 'smith machine', 'trap bar']);
      final legacy = <String>{for (final id in (testV13Ids())) id.toString()};
      expect(EXDB.where((e) => legacy.contains(e['id']) && BAR_EQ.contains(e['eq'])).length, 228);
      for (final eq in BAR_EQ) {
        expect(EXDB.any((e) => e['eq'] == eq), isTrue, reason: eq);
      }
    });

    test('usesBar answers for ids and exercise objects alike', () {
      for (final eq in BAR_EQ) {
        expect(usesBar(idOf(eq)), isTrue, reason: eq);
        expect(usesBar({'eq': eq}), isTrue, reason: eq);
      }
      expect(usesBar({'eq': 'dumbbell'}), isFalse);
      expect(usesBar({'eq': 'body weight'}), isFalse);
      expect(usesBar('no-such-id'), isFalse);
      expect(usesBar(null), isFalse);
    });
  });

  group('per-unit defaults', () {
    test('every bar type has a default in both units', () {
      for (final eq in BAR_EQ) {
        expect(DEFAULT_BAR_KG[eq], greaterThan(0), reason: eq);
        expect(DEFAULT_BAR_LB[eq], greaterThan(0), reason: eq);
      }
      expect(defaultBarWeight('ez barbell', 'kg'), 10);
      expect(defaultBarWeight('ez barbell', 'lb'), 25);
      expect(defaultBarWeight('olympic barbell', 'kg'), 20);
      expect(defaultBarWeight('barbell', 'lb'), 45);
      expect(defaultBarWeight('dumbbell', 'kg'), isNull);
    });
  });

  group('barWeightFor', () {
    late String barbell, ez;
    setUpAll(() {
      barbell = idOf('barbell');
      ez = idOf('ez barbell');
    });

    test('falls back to the equipment default in the profile unit', () {
      expect(barWeightFor({'unit': 'kg', 'barWeights': {}}, barbell), 20);
      expect(barWeightFor({'unit': 'lb', 'barWeights': {}}, barbell), 45);
      expect(barWeightFor({'unit': 'kg'}, ez), 10);
    });

    test('an explicit override wins over the default', () {
      final S = {'unit': 'kg', 'barWeights': {ez: 7.5}};
      expect(barWeightFor(S, ez), 7.5);
      expect(hasBarOverride(S, ez), isTrue);
      expect(barWeightFor(S, barbell), 20);
      expect(hasBarOverride(S, barbell), isFalse);
    });

    test('a deleted override falls back to the default, but a stored 0 is "no bar"', () {
      final S = {'unit': 'kg', 'barWeights': <String, dynamic>{ez: 12.5}};
      (S['barWeights'] as Map).remove(ez);
      expect(barWeightFor(S, ez), 10);
      expect(barWeightFor({'unit': 'kg', 'barWeights': {ez: 0}}, ez), 0);
      expect(hasBarOverride({'unit': 'kg', 'barWeights': {ez: 0}}, ez), isTrue);
    });

    test('is null for anything without a bar', () {
      final dumbbell = EXDB.firstWhere((e) => e['eq'] == 'dumbbell');
      expect(barWeightFor({'unit': 'kg', 'barWeights': {}}, dumbbell['id']), isNull);
      expect(barWeightFor({'unit': 'kg', 'barWeights': {}}, 'no-such-id'), isNull);
    });
  });

  group('plateSplit', () {
    test('splits what is beyond the bar evenly per side', () {
      expect(plateSplit(62.5, 20), 21.25);
      expect(plateSplit(100, 20), 40);
      expect(plateSplit(30, 10), 10);
    });

    test('rounds to 2 decimals', () {
      expect(plateSplit(65.55, 20), 22.78);
      expect(plateSplit(21.2, 20), 0.6);
    });

    test('is null when there is nothing sensible to show', () {
      expect(plateSplit(20, 20), isNull);
      expect(plateSplit(15, 20), isNull);
      expect(plateSplit(0, 20), isNull);
      expect(plateSplit(null, 20), isNull);
      expect(plateSplit(100, null), isNull);
      expect(plateSplit(null, null), isNull);
    });
  });
}
