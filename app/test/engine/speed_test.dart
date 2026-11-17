// Port of frontend/src/lib/speed.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/format.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/speed.dart';

import '_exdb.dart';

const bike = '2138'; // stationary bike, cardio

void main() {
  setUpAll(loadTestExerciseDb);
  tearDown(() => setWeightDecimals(1));

  group('speedUnitOf', () {
    test('follows the weight unit until the profile chooses', () {
      expect(speedUnitOf({'unit': 'kg'}), 'kmh');
      expect(speedUnitOf({'unit': 'lb'}), 'mph');
      expect(speedUnitOf({}), 'kmh');
      expect(speedUnitOf(null), 'kmh');
      expect(speedUnitOf({'unit': 'lb', 'speedUnit': null}), 'mph');
    });
    test('keeps a choice either way round', () {
      expect(speedUnitOf({'unit': 'kg', 'speedUnit': 'mph'}), 'mph');
      expect(speedUnitOf({'unit': 'lb', 'speedUnit': 'kmh'}), 'kmh');
      expect(speedUnitOf({'unit': 'lb', 'speedUnit': 'knots'}), 'mph');
    });
    test('labels the numbers', () {
      expect(speedLabel('kmh'), 'km/h');
      expect(speedLabel('mph'), 'mph');
      expect(speedLabel(null), 'km/h');
    });
  });

  group('toSpeed / fromSpeed', () {
    test('uses the exact mile', () {
      expect(KMH_PER_MPH, 1.609344);
      expect(toSpeed(1.609344, 'mph'), 1);
      expect(toSpeed(8, 'mph'), 4.97);
      expect(fromSpeed(6, 'mph'), 9.66);
      expect(fromSpeed(10, 'mph'), 16.09);
    });

    test('is the identity in km/h, so a km/h profile stores exactly what it always did', () {
      for (final v in [0, 8, 9.656064, 10.25, 12.3456]) {
        expect(toSpeed(v, 'kmh'), v);
        expect(fromSpeed(v, 'kmh'), v);
        expect(toSpeed(v, null), v);
      }
    });

    test('reads back every mph speed typed with up to two decimals exactly as typed', () {
      final off = [];
      for (var i = 0; i <= 4000; i++) {
        final typed = i / 100;
        final back = toSpeed(fromSpeed(typed, 'mph'), 'mph');
        if (back != typed) off.add([typed, back]);
      }
      expect(off, isEmpty);
    });

    test('stores km/h to the hundredth, not the full float', () {
      expect(fromSpeed(6.2, 'mph'), 9.98);
      expect(str(fromSpeed(3.3, 'mph')), '5.31');
    });

    test('passes an empty field through untouched', () {
      for (final v in [null, '']) {
        expect(toSpeed(v, 'mph'), v);
        expect(fromSpeed(v, 'mph'), v);
      }
    });
  });

  group('speed in labels', () {
    test('formats a stored km/h speed in the unit on screen', () {
      expect(fmtSpeed(8, 'kmh'), '8 km/h');
      expect(fmtSpeed(8, 'mph'), '5 mph');
      setWeightDecimals(2);
      expect(fmtSpeed(8, 'mph'), '4.97 mph');
    });

    test('reads a logged cardio set and a planned cardio slot in mph', () {
      final set = {'min': 30, 'speed': 9.66, 'done': true};
      final target = {'id': bike, 'sets': 1, 'min': 30, 'speed': 9.66};
      expect(setLabel(bike, set, target, 'mph'), '30 min @ 6 mph');
      expect(setLabel(bike, set, target), '30 min @ 9.7 km/h');
      // A set saved by an older build, with no target: read from its own fields.
      expect(setLabel(bike, set, null, 'mph'), '30 min @ 6 mph');
      expect(exLine({'id': bike, 'sets': 2, 'min': 20, 'speed': 16.09}, 'lb', 'mph'), '2 × 20 min @ 10 mph');
      expect(exLine({'id': bike, 'sets': 2, 'min': 20, 'speed': 16.09}, 'kg'), '2 × 20 min @ 16.1 km/h');
    });
    // skipped: "prints a plan in the profile's speed unit" — planPrintHTML is plan-share.js
    // (Task 6) and HTML.
  });
}
