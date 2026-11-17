// Port of frontend/src/lib/history.copy-row.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/workout_model.dart';

import '_helpers.dart';

void main() {
  // Swipe on sets (v1.3.11): swipe right copies a set, swipe left removes one with an Undo.
  group('copyRowAt', () {
    test('puts an unticked copy of a work set right below it, keeping weight, reps and effort', () {
      final rows = <dynamic>[
        {'w': 60, 'r': 8, 'done': true, 'rir': 2, 'at': 123, 'weightOrigin': 'manual'},
        {'w': 60, 'r': 8, 'done': false},
      ];
      final out = copyRowAt(rows, 0);
      expect(out, hasLength(3));
      expect(out[1], jeq({'w': 60, 'r': 8, 'rir': 2, 'done': false}));
      expect(out[0], same(rows[0]));
      expect(rows, hasLength(2));
    });

    test('keeps a warm-up a warm-up, so a ladder grows by copying', () {
      final rows = <dynamic>[
        {'w': 40, 'r': 10, 'done': true, 'phase': 'warmup', 'warmup': true},
        {'w': 80, 'r': 5, 'done': false},
      ];
      final out = copyRowAt(rows, 0);
      expect(out[1], jeq({'w': 40, 'r': 10, 'done': false, 'phase': 'warmup', 'warmup': true}));
      expect(out[2], jeq({'w': 80, 'r': 5, 'done': false}));
    });

    test('drops drop sets and bursts on the copy', () {
      final rows = <dynamic>[
        {'w': 100, 'r': 6, 'done': true, 'type': 'dropset', 'drops': [{'w': 80, 'r': 5}]},
      ];
      expect(copyRowAt(rows, 0)[1], jeq({'w': 100, 'r': 6, 'done': false}));
      final rp = <dynamic>[
        {'w': 50, 'r': 14, 'done': false, 'type': 'restpause', 'clusters': [{'r': 4, 'restSec': 15}]},
      ];
      expect(copyRowAt(rp, 0)[1], jeq({'w': 50, 'r': 14, 'done': false}));
    });

    test('copies a timed hold with its time and a pyramid Max with its flag, but not the set-aside plan', () {
      expect(copyRowAt([{'sec': 38, 'w': 0, 'done': true, 'planSec': 45}], 0)[1], jeq({'sec': 38, 'w': 0, 'done': false}));
      expect(copyRowAt([{'w': 60, 'r': 12, 'done': false, 'max': true}], 0)[1], jeq({'w': 60, 'r': 12, 'done': false, 'max': true}));
    });

    test('copies a per-side set with both sides unticked and their own values', () {
      var row = makeSideSet({'w': 16, 'r': 20});
      row = setSideField(row, 'L', 'r', 11);
      row = setSideField(row, 'R', 'w', 18);
      row = toggleSide(row, 'L');
      row = {
        ...row,
        'sides': {
          ...row['sides'] as Map<String, dynamic>,
          'L': {...row['sides']['L'] as Map<String, dynamic>, 'type': 'dropset', 'drops': [{'w': 10, 'r': 6}]},
        },
      };
      final out = copyRowAt([row], 0);
      final c = out[1];
      expect(isSideSet(c), isTrue);
      expect(c['sides']['L'], jeq({'w': 16, 'r': 11, 'done': false}));
      expect(c['sides']['R'], jeq({'w': 18, 'r': 10, 'done': false}));
      expect(c['done'], false);
      expect(c['r'], 21);
      expect(c['w'], 18);
      expect((c as Map).containsKey('type'), isFalse);
    });

    test('copies a timed per-side hold as its L/R pair, after the pair', () {
      final rows = <dynamic>[
        {'sec': 30, 'w': 0, 'side': 'L', 'done': true},
        {'sec': 30, 'w': 0, 'side': 'R', 'done': false},
        {'sec': 30, 'w': 0, 'side': 'L', 'done': false},
        {'sec': 30, 'w': 0, 'side': 'R', 'done': false},
      ];
      for (final i in [0, 1]) {
        final out = copyRowAt(rows, i);
        expect(out.map((r) => r['side']).toList(), jeq(['L', 'R', 'L', 'R', 'L', 'R']));
        expect(out[2], jeq({'sec': 30, 'w': 0, 'side': 'L', 'done': false}));
        expect(copySpanAt(rows, i), jeq({'start': 0, 'end': 1}));
      }
    });

    test('leaves the rows alone for an index that is not there', () {
      final rows = <dynamic>[{'w': 1, 'r': 1, 'done': false}];
      expect(copyRowAt(rows, 4), jeq(rows));
    });
  });

  group('insertRowAt (undo of a removed set)', () {
    test('puts the exact row back where it was, tick and sub-rows included', () {
      final rows = <dynamic>[
        {'w': 60, 'r': 8, 'done': true},
        {'w': 60, 'r': 8, 'done': true, 'type': 'dropset', 'drops': [{'w': 50, 'r': 6}]},
        {'w': 60, 'r': 8, 'done': false},
      ];
      final removed = rows[1];
      final after = removeRowAt(rows, 1);
      expect(after, hasLength(2));
      final back = insertRowAt(after, 1, removed);
      expect(back, jeq(rows));
      expect(back[1], same(removed));
    });

    test('lands it last when the entry lost rows in the meantime', () {
      expect(insertRowAt([{'w': 1}], 5, {'w': 2}), jeq([{'w': 1}, {'w': 2}]));
      expect(insertRowAt([{'w': 1}], null, {'w': 2}), jeq([{'w': 1}, {'w': 2}]));
      expect(insertRowAt([{'w': 1}], -3, {'w': 2}), jeq([{'w': 2}, {'w': 1}]));
    });

    test('never lets removeRowAt take the last row', () {
      final rows = <dynamic>[{'w': 1, 'r': 1, 'done': false}];
      expect(removeRowAt(rows, 0), jeq(rows));
    });
  });
}
