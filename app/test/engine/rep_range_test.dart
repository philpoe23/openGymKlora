// Port of frontend/src/lib/rep-range.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/rep_range.dart';

import '_helpers.dart';

void main() {
  group('normalizeRepRange', () {
    test('keeps valid positive integer bounds unchanged', () {
      expect(normalizeRepRange(12, 8), jeq({'reps': 12, 'repsMin': 8}));
    });

    test('rounds bounds to positive integers', () {
      expect(normalizeRepRange(12.4, 7.6), jeq({'reps': 12, 'repsMin': 8}));
      expect(normalizeRepRange(0, -2), jeq({'reps': 10, 'repsMin': 8}));
    });

    test('raises the upper bound when the lower bound reaches it', () {
      expect(normalizeRepRange(8, 8), jeq({'reps': 9, 'repsMin': 8}));
    });

    test('raises the upper bound when the lower bound exceeds it', () {
      expect(normalizeRepRange(8, 12), jeq({'reps': 13, 'repsMin': 12}));
    });

    test('keeps the lower bound at least one below a lowered upper bound', () {
      expect(normalizeRepRange(6, 8), jeq({'reps': 9, 'repsMin': 8}));
    });

    test('supplies a usable default lower bound for a small upper bound', () {
      expect(normalizeRepRange(1, null), jeq({'reps': 2, 'repsMin': 1}));
    });

    test('aligns both bounds to an even stride', () {
      expect(normalizeRepRange(13, 7, 2), jeq({'reps': 14, 'repsMin': 8}));
    });

    test('keeps a valid gap when per-side bounds are invalid', () {
      expect(normalizeRepRange(8, 9, 2), jeq({'reps': 12, 'repsMin': 10}));
      expect(normalizeRepRange(0, -2, 2), jeq({'reps': 10, 'repsMin': 8}));
    });
  });
}
