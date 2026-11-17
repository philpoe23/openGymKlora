// Port of frontend/src/lib/incline.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/incline.dart';

import '_exdb.dart';
import '_helpers.dart';

const treadmill = '2259';
const inclineWalk = '3666';
const elliptical = '2192';
const stepmill = '2311';
const run = '0685';
const bike = '2138';
const rower = '1161';
const rope = '2612';
const jacks = '3094';

void main() {
  setUpAll(loadTestExerciseDb);

  group('clampIncline', () {
    test('keeps a grade on the half percent between 0 and 40', () {
      expect(clampIncline(5), 5);
      expect(clampIncline(7.3), 7.5);
      expect(clampIncline(7.2), 7);
      expect(clampIncline('12.5'), 12.5);
      expect(clampIncline(55), INCLINE_MAX);
      expect(clampIncline(-3), 0);
      expect(clampIncline(0), 0);
    });
    test('leaves nothing as nothing, so a cleared field drops the key', () {
      expect(clampIncline(null), isNull);
      expect(clampIncline(''), isNull);
      expect(clampIncline('steep'), isNull);
      expect(clampIncline(double.nan), isNull);
    });
  });

  group('inclineFits', () {
    test('offers the incline on treadmills, walking, running, stairs and ellipticals', () {
      for (final id in [treadmill, inclineWalk, elliptical, stepmill, run]) {
        expect(inclineFits(EXIDX[id]), isTrue, reason: EXIDX[id]['n']);
      }
    });
    test('not on a bike, a rower, a rope or jumping jacks', () {
      for (final id in [bike, rower, rope, jacks]) {
        expect(inclineFits(EXIDX[id]), isFalse, reason: EXIDX[id]['n']);
      }
    });
    test('on your own cardio exercise unless its name says it has no grade', () {
      expect(inclineFits({'id': 'c1', 'n': 'Laufband', 'bp': 'cardio', 'custom': true}), isTrue);
      expect(inclineFits({'id': 'c2', 'n': 'Hill walk', 'bp': 'cardio', 'custom': true}), isTrue);
      expect(inclineFits({'id': 'c3', 'n': 'Spin bike', 'bp': 'cardio', 'custom': true}), isFalse);
      expect(inclineFits({'id': 'c4', 'n': 'Concept2 rower', 'bp': 'cardio', 'custom': true}), isFalse);
      expect(inclineFits(null), isFalse);
    });
  });

  group('a set with an incline', () {
    test('reads with its grade, and a flat or older set reads exactly as before', () {
      expect(setLabel(treadmill, {'min': 30, 'speed': 5.5, 'incline': 12, 'done': true}), '30 min @ 5.5 km/h · 12% incline');
      expect(setLabel(treadmill, {'min': 30, 'speed': 5.5, 'incline': 7.5}), '30 min @ 5.5 km/h · 7.5% incline');
      expect(setLabel(treadmill, {'min': 30, 'speed': 5.5, 'incline': 0}), '30 min @ 5.5 km/h');
      expect(setLabel(treadmill, {'min': 30, 'speed': 5.5}), '30 min @ 5.5 km/h');
      expect(setLabel(treadmill, {'min': 30, 'speed': 16.09344, 'incline': 4}, null, 'mph'), '30 min @ 10 mph · 4% incline');
    });

    test('knows which sets carry one and what a new row takes over', () {
      expect(hasIncline({'incline': 3}), isTrue);
      expect(hasIncline({'incline': 0}), isFalse);
      expect(hasIncline({}), isFalse);
      expect(hasIncline(null), isFalse);
      expect(inclineFrom({'incline': 6}), jeq({'incline': 6}));
      expect(inclineFrom({'incline': 0}), jeq({}));
      expect(inclineFrom(null), jeq({}));
    });

    test('is prefilled from last time, and a session with no grade last time opens flat', () {
      final cfg = {'id': treadmill, 'sets': 2, 'min': 20, 'speed': 8};
      Map<String, dynamic> last(List<dynamic> sets) => {
            'exWeights': {},
            'workouts': [
              {'id': 'w1', 'd': '2026-10-01', 'start': 0, 'end': 1, 'entries': [
                {'id': treadmill, 'target': {'sets': 2, 'min': 20, 'speed': 8}, 'sets': sets},
              ]},
            ],
          };
      expect(buildSets(last([{'min': 25, 'speed': 5, 'incline': 10, 'done': true}, {'min': 10, 'speed': 6, 'done': true}]), cfg), jeq([
        {'min': 25, 'speed': 5, 'incline': 10, 'done': false},
        {'min': 10, 'speed': 6, 'done': false},
      ]));
      expect(buildSets(last([{'min': 25, 'speed': 5, 'done': true}]), cfg), jeq([
        {'min': 25, 'speed': 5, 'done': false},
        {'min': 25, 'speed': 5, 'done': false},
      ]));
      expect(buildSets({'exWeights': {}, 'workouts': []}, cfg), jeq([
        {'min': 20, 'speed': 8, 'done': false},
        {'min': 20, 'speed': 8, 'done': false},
      ]));
    });

    test('comes along on a warm-up added in front of it and on a copied row', () {
      final rows = insertWarmupRow([{'min': 20, 'speed': 5, 'incline': 8, 'done': false}], 'cardio', {'min': 20, 'speed': 5});
      expect(rows[0], matchObj({'min': 20, 'speed': 5, 'incline': 8, 'phase': 'warmup'}));
      expect(copyRowAt([{'min': 20, 'speed': 5, 'incline': 8, 'done': true}], 0)[1], jeq({'min': 20, 'speed': 5, 'incline': 8, 'done': false}));
    });
    // skipped: 'is in the workout copied as text' — workout-text.js, not in this port.
    // skipped: 'is in the finish summary…' — finish-compare.js, not in this port.
  });

  // skipped: the 'importing an incline' group — parseWorkoutCSV (import-csv.js) is not ported.
}
