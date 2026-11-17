// Port of frontend/src/lib/workout-model.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/workout_model.dart';

import '_helpers.dart';

void main() {
  group('phaseForSet / isWarmupRow', () {
    test('reads both the explicit phase and the legacy boolean', () {
      expect(isWarmupRow({'phase': 'warmup'}), isTrue);
      expect(isWarmupRow({'warmup': true}), isTrue);
      expect(isWarmupRow({'phase': 'work'}), isFalse);
      expect(isWarmupRow({}), isFalse);
      expect(phaseForSet({'phase': 'Warm-Up'}), 'warmup');
    });
  });

  group('per-side load provenance', () {
    test('survives aggregate resync when the other side changes', () {
      final row = makeSideSet({'w': 20, 'r': 16});
      row['sides']['R']['weightOrigin'] = WEIGHT_ORIGIN_MANUAL;
      final next = setSideField(row, 'L', 'w', 15);
      expect(next['sides']['L']['w'], 15);
      expect(next['sides']['R']['w'], 20);
      expect(next['sides']['R']['weightOrigin'], WEIGHT_ORIGIN_MANUAL);
    });
  });

  group('setType / isDropSet / isRestPauseSet', () {
    test('defaults to straight for anything without a recognised type', () {
      expect(setType({}), 'straight');
      expect(setType({'type': 'nonsense'}), 'straight');
      expect(setType(null), 'straight');
      expect(isDropSet({}), isFalse);
      expect(isRestPauseSet({}), isFalse);
    });

    test('recognises drop-set and rest-pause rows', () {
      expect(setType({'type': 'dropset'}), 'dropset');
      expect(isDropSet({'type': 'dropset'}), isTrue);
      expect(setType({'type': 'restpause'}), 'restpause');
      expect(isRestPauseSet({'type': 'restpause'}), isTrue);
    });

    test('is a separate axis from warm-up — a row is not both at once by construction, but phase never leaks into type', () {
      expect(setType({'phase': 'warmup', 'type': 'dropset'}), 'dropset');
      expect(isWarmupRow({'phase': 'warmup', 'type': 'dropset'}), isTrue);
    });
  });

  group('dropsOf / clustersOf', () {
    test('only return rows for their own type', () {
      final drop = {'type': 'dropset', 'drops': [{'w': 80, 'r': 5}]};
      final burst = {'type': 'restpause', 'clusters': [{'r': 4, 'restSec': 15}]};
      expect(dropsOf(drop), jeq([{'w': 80, 'r': 5}]));
      expect(clustersOf(drop), jeq([]));
      expect(clustersOf(burst), jeq([{'r': 4, 'restSec': 15}]));
      expect(dropsOf(burst), jeq([]));
    });

    test('is defensive about missing/malformed arrays', () {
      expect(dropsOf({'type': 'dropset'}), jeq([]));
      expect(dropsOf({'type': 'dropset', 'drops': 'nope'}), jeq([]));
      expect(clustersOf(null), jeq([]));
    });
  });

  group('extraVolumeOf', () {
    test("sums weight x reps across a drop-set's own drops", () {
      final set = {'type': 'dropset', 'w': 100, 'r': 5, 'drops': [{'w': 80, 'r': 5}, {'w': 60, 'r': 6}]};
      expect(extraVolumeOf(set), 80 * 5 + 60 * 6);
    });

    test('is zero for rest-pause — its own r is already the total across every burst, so clusters are a breakdown, not extra volume', () {
      final set = {
        'type': 'restpause', 'w': 60, 'r': 20,
        'clusters': [{'r': 10, 'restSec': 15}, {'r': 5, 'restSec': 15}, {'r': 3, 'restSec': 15}, {'r': 1, 'restSec': 15}, {'r': 1, 'restSec': 15}],
      };
      expect(extraVolumeOf(set), 0);
    });

    test('is zero for a straight or warm-up set', () {
      expect(extraVolumeOf({'w': 100, 'r': 5}), 0);
      expect(extraVolumeOf({'phase': 'warmup', 'w': 20, 'r': 8}), 0);
    });

    test('sums both sides drops for a per-side drop-set (issue #60)', () {
      var s = addSideDrop(makeSideSet({'w': 20, 'r': 16}), 20);
      expect(extraVolumeOf(s), 16 * 8 * 2);
      s = setSideDropAt(s, 'R', 0, {'w': 10, 'r': 6});
      expect(extraVolumeOf(s), 16 * 8 + 10 * 6);
    });
  });

  group('addDrop / addCluster', () {
    test('appends a drop and stamps the row as a drop-set', () {
      final set = {'w': 100, 'r': 5, 'done': true};
      final next = addDrop(set, {'w': 80, 'r': 5});
      expect(next['type'], 'dropset');
      expect(next['drops'], jeq([{'w': 80, 'r': 5}]));
      expect(set.containsKey('drops'), isFalse);
      expect(addDrop(next, {'w': 60, 'r': 4})['drops'], jeq([{'w': 80, 'r': 5}, {'w': 60, 'r': 4}]));
    });

    test('appends a burst and stamps the row as a rest-pause set', () {
      final set = {'w': 60, 'r': 8, 'done': true};
      final next = addCluster(set, {'r': 4, 'restSec': 15});
      expect(next['type'], 'restpause');
      expect(next['clusters'], jeq([{'r': 4, 'restSec': 15}]));
    });
  });

  group('removeDropAt / removeClusterAt', () {
    test('removes one entry by index, leaving the rest in place', () {
      final set = {'type': 'dropset', 'w': 100, 'r': 5, 'drops': [{'w': 80, 'r': 5}, {'w': 60, 'r': 5}]};
      expect(removeDropAt(set, 0)['drops'], jeq([{'w': 60, 'r': 5}]));
    });

    test('removes one burst by index', () {
      final set = {'type': 'restpause', 'w': 60, 'r': 8, 'clusters': [{'r': 4, 'restSec': 15}, {'r': 3, 'restSec': 15}]};
      expect(removeClusterAt(set, 1)['clusters'], jeq([{'r': 4, 'restSec': 15}]));
    });

    test('reverts the row to a straight set once its last drop/burst is removed', () {
      final drop = {'type': 'dropset', 'w': 100, 'r': 5, 'drops': [{'w': 80, 'r': 5}]};
      expect(removeDropAt(drop, 0), jeq({'type': 'straight', 'w': 100, 'r': 5, 'drops': []}));
      expect(isDropSet(removeDropAt(drop, 0)), isFalse);

      final burst = {'type': 'restpause', 'w': 60, 'r': 8, 'clusters': [{'r': 4, 'restSec': 15}]};
      expect(removeClusterAt(burst, 0), jeq({'type': 'straight', 'w': 60, 'r': 8, 'clusters': []}));
      expect(isRestPauseSet(removeClusterAt(burst, 0)), isFalse);
    });
  });

  group('setDropAt / setClusterAt', () {
    test("patches one drop's fields, leaving the others untouched", () {
      final set = {'type': 'dropset', 'w': 100, 'r': 5, 'drops': [{'w': 80, 'r': 5}, {'w': 60, 'r': 5}]};
      expect(setDropAt(set, 0, {'w': 82.5})['drops'], jeq([{'w': 82.5, 'r': 5}, {'w': 60, 'r': 5}]));
      expect(setDropAt(set, 1, {'r': 6})['drops'], jeq([{'w': 80, 'r': 5}, {'w': 60, 'r': 6}]));
    });

    test("patches one burst's reps", () {
      final set = {'type': 'restpause', 'w': 60, 'r': 8, 'clusters': [{'r': 4, 'restSec': 15}]};
      expect(setClusterAt(set, 0, {'r': 5})['clusters'], jeq([{'r': 5, 'restSec': 15}]));
    });

    test('is a no-op for an index that does not exist', () {
      final set = {'type': 'dropset', 'w': 100, 'r': 5, 'drops': [{'w': 80, 'r': 5}]};
      expect(setDropAt(set, 3, {'w': 1}), same(set));
    });
  });

  group('nextDropWeight / nextBurstReps', () {
    test('drops by the given percentage, rounded to the nearest .5', () {
      expect(nextDropWeight(100, 20), 80);
      expect(nextDropWeight(80, 20), 64);
      expect(nextDropWeight(61, 10), 55);
    });

    test('defaults to 20% and never goes negative', () {
      expect(nextDropWeight(100), 80);
      expect(nextDropWeight(0, 20), 0);
    });

    test("lands on the exercise's weight step when given one, and always below the weight it drops from", () {
      expect(nextDropWeight(60, 20, 2.5), 47.5);
      expect(nextDropWeight(100, 20, 5), 80);
      expect(nextDropWeight(80, 20, 5), 65);
      expect(nextDropWeight(5, 5, 2.5), 2.5);
      expect(nextDropWeight(2.5, 10, 2.5), 0);
    });

    test('takes a snapping function (the plates you own) as the grid', () {
      expect(nextDropWeight(100, 20, (num w) => (w / 10).floor() * 10), 80);
      expect(nextDropWeight(100, 25, (num w) => (w / 10).floor() * 10), 70);
    });

    test('roughly halves the previous rep count, floored at 1', () {
      expect(nextBurstReps(8), 4);
      expect(nextBurstReps(1), 1);
      expect(nextBurstReps(0), 1);
    });
  });

  group('splitBurstReps', () {
    test('splits a total into a descending, roughly-halving sequence that adds back up to it', () {
      expect(splitBurstReps(12), jeq([6, 3, 2, 1]));
      expect(splitBurstReps(6), jeq([3, 2, 1]));
      expect(splitBurstReps(1), jeq([1]));
    });

    test('every split sums exactly to the requested total', () {
      for (final total in [1, 2, 3, 5, 7, 10, 15, 20, 33]) {
        expect(splitBurstReps(total).fold<num>(0, (a, b) => a + b), total);
      }
    });

    test('is empty for zero or invalid input', () {
      expect(splitBurstReps(0), jeq([]));
      expect(splitBurstReps(-5), jeq([]));
      expect(splitBurstReps(null), jeq([]));
    });
  });

  group('modeForSet / modeForEntry stay reps-mode for drop-sets and rest-pause sets', () {
    test("infers reps mode from the row's own r field regardless of type", () {
      expect(modeForSet({'type': 'dropset', 'w': 100, 'r': 5}), 'reps');
      expect(modeForSet({'type': 'restpause', 'w': 60, 'r': 8}), 'reps');
    });

    test('an entry mixing straight and drop-set rows still reads as one reps-mode entry', () {
      final entry = {
        'sets': [
          {'w': 100, 'r': 5},
          {'type': 'dropset', 'w': 100, 'r': 5, 'drops': [{'w': 80, 'r': 5}]},
        ],
      };
      expect(modeForEntry(entry), 'reps');
    });
  });

  group('isSideSet', () {
    test('is true only for a row carrying both L and R sides', () {
      expect(isSideSet({'sides': {'L': {'w': 10, 'r': 8}, 'R': {'w': 10, 'r': 8}}}), isTrue);
      expect(isSideSet({'w': 10, 'r': 8}), isFalse);
      expect(isSideSet({'sides': {'L': {'w': 10, 'r': 8}}}), isFalse);
      expect(isSideSet(null), isFalse);
    });
  });

  group('makeSideSet', () {
    test('splits the row total evenly across two sides at the same weight, nothing done', () {
      final s = makeSideSet({'w': 15, 'r': 16, 'done': false});
      expect(isSideSet(s), isTrue);
      expect(s['sides']['L'], jeq({'w': 15, 'r': 8, 'done': false}));
      expect(s['sides']['R'], jeq({'w': 15, 'r': 8, 'done': false}));
      expect(s['r'], 16);
      expect(s['w'], 15);
      expect(s['done'], false);
    });

    test('drops any straight-set effort so the row carries a single source of truth', () {
      final s = makeSideSet({'w': 20, 'r': 10, 'rir': 2});
      expect(s.containsKey('rir'), isFalse);
      expect(s.containsKey('rpe'), isFalse);
    });
  });

  group('syncSideAggregate', () {
    test('recomputes r as the sum, w as the heavier side, done only when both sides are', () {
      final row = {'sides': {'L': {'w': 15, 'r': 8, 'done': true}, 'R': {'w': 17.5, 'r': 6, 'done': false}}};
      final s = syncSideAggregate(row);
      expect(s['r'], 14);
      expect(s['w'], 17.5);
      expect(s['done'], false);
      final bothDone = syncSideAggregate({'sides': {'L': {'w': 15, 'r': 8, 'done': true}, 'R': {'w': 15, 'r': 8, 'done': true}}});
      expect(bothDone['done'], true);
    });

    test('takes the harder side for the row effort — lower RIR, higher RPE', () {
      final rir = syncSideAggregate({'sides': {'L': {'w': 15, 'r': 8, 'rir': 3}, 'R': {'w': 15, 'r': 8, 'rir': 1}}});
      expect(rir['rir'], 1);
      expect(rir.containsKey('rpe'), isFalse);
      final rpe = syncSideAggregate({'sides': {'L': {'w': 15, 'r': 8, 'rpe': 7}, 'R': {'w': 15, 'r': 8, 'rpe': 9}}});
      expect(rpe['rpe'], 9);
      expect(rpe.containsKey('rir'), isFalse);
    });

    test('leaves a non-per-side row alone (returns a copy)', () {
      final s = syncSideAggregate({'w': 20, 'r': 10, 'done': true});
      expect(s, jeq({'w': 20, 'r': 10, 'done': true}));
      expect(isSideSet(s), isFalse);
    });
  });

  group('setSideField', () {
    test('patches one side and resyncs the aggregate', () {
      final base = makeSideSet({'w': 15, 'r': 16});
      final s = setSideField(base, 'R', 'w', 17.5);
      expect(s['sides']['R']['w'], 17.5);
      expect(s['sides']['L']['w'], 15);
      expect(s['w'], 17.5);
    });

    test('clears an effort field on null, mirroring how a straight row drops the key', () {
      var s = setSideField(makeSideSet({'w': 15, 'r': 16}), 'L', 'rir', 2);
      expect(s['sides']['L']['rir'], 2);
      expect(s['rir'], 2);
      s = setSideField(s, 'L', 'rir', null);
      expect((s['sides']['L'] as Map).containsKey('rir'), isFalse);
      expect(s.containsKey('rir'), isFalse);
    });

    test('ignores an unknown side without throwing', () {
      final base = makeSideSet({'w': 15, 'r': 16});
      expect(isSideSet(setSideField(base, 'X', 'w', 20)), isTrue);
    });
  });

  group('toggleSide', () {
    test('flips one side and marks the row done only once both sides are', () {
      var s = makeSideSet({'w': 15, 'r': 16});
      expect(s['done'], false);
      s = toggleSide(s, 'L');
      expect(s['sides']['L']['done'], true);
      expect(s['done'], false);
      s = toggleSide(s, 'R');
      expect(s['sides']['R']['done'], true);
      expect(s['done'], true);
      s = toggleSide(s, 'L');
      expect(s['done'], false);
    });
  });

  group('addSideDrop / removeSideDropAt / setSideDropAt', () {
    test('adds a drop to both sides, each seeded from its own side weight and reps', () {
      var s = makeSideSet({'w': 20, 'r': 16});
      s = setSideField(s, 'R', 'w', 18);
      s = addSideDrop(s, 20);
      expect(s['sides']['L']['drops'], jeq([{'w': 16, 'r': 8}]));
      expect(s['sides']['R']['drops'], jeq([{'w': 14.5, 'r': 8}]));
      expect(s['type'], 'dropset');
      expect(s.containsKey('drops'), isFalse);
    });

    test('edits one side drop independently, leaving the other side untouched', () {
      var s = addSideDrop(makeSideSet({'w': 20, 'r': 16}), 20);
      s = setSideDropAt(s, 'L', 0, {'w': 12});
      expect(s['sides']['L']['drops'][0]['w'], 12);
      expect(s['sides']['R']['drops'][0]['w'], 16);
    });

    test('removes a drop from both sides, reverting to straight when the last goes', () {
      var s = addSideDrop(makeSideSet({'w': 20, 'r': 16}), 20);
      s = removeSideDropAt(s, 0);
      expect(s['sides']['L']['drops'], jeq([]));
      expect(s['sides']['R']['drops'], jeq([]));
      expect(s.containsKey('type'), isFalse);
    });
  });

  group('addSideCluster / removeSideClusterAt / setSideClusterAt', () {
    test('adds a burst to both sides and grows each side reps by its own added burst', () {
      var s = makeSideSet({'w': 20, 'r': 16});
      s = addSideCluster(s, 15);
      expect(s['sides']['L']['clusters'], jeq([{'r': 4, 'restSec': 15}]));
      expect(s['sides']['L']['r'], 12);
      expect(s['sides']['R']['r'], 12);
      expect(s['r'], 24);
      expect(s['type'], 'restpause');
    });

    test('editing one side burst keeps that side reps in step and leaves the other alone', () {
      var s = addSideCluster(makeSideSet({'w': 20, 'r': 16}), 15);
      s = setSideClusterAt(s, 'L', 0, 6);
      expect(s['sides']['L']['clusters'][0]['r'], 6);
      expect(s['sides']['L']['r'], 14);
      expect(s['sides']['R']['r'], 12);
    });

    test('removing a burst subtracts its reps from that side', () {
      var s = addSideCluster(makeSideSet({'w': 20, 'r': 16}), 15);
      s = removeSideClusterAt(s, 0);
      expect(s['sides']['L']['clusters'], jeq([]));
      expect(s['sides']['L']['r'], 8);
      expect(s.containsKey('type'), isFalse);
    });
  });
}
