// Port of frontend/src/lib/progression.extra-sets.test.js — issue #233: a set logged on top of
// the plan is extra work, not part of the prescription.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/progression.dart';

import '_exdb.dart';

JMap set(num w, num r, [bool done = true]) => {'w': w, 'r': r, 'done': done};
JMap entry(JMap? target, List<dynamic> sets) => {'id': '0025', 'target': target, 'sets': sets};
const plan = {'mode': 'reps', 'sets': 3, 'reps': 8, 'weight': 60};

void main() {
  setUpAll(loadTestExerciseDb);

  group('extra sets stay out of the progression read', () {
    test('ignores a heavier bonus set when reading the weight', () {
      final done = readSession(entry(plan, [set(60, 8), set(60, 8), set(60, 8), set(80, 8)]));
      expect(done['weight'], 60);
      expect(done['ok'], isTrue);
    });

    test('does not call the session missed because a bonus set fell short', () {
      final done = readSession(entry(plan, [set(60, 8), set(60, 8), set(60, 8), set(80, 3)]));
      expect(done['ok'], isTrue);
      expect(done['low'], 8);
      expect(done['count'], 3);
      expect(done['amrap'], 8);
    });

    test('still reports a short session as short, and still reads every planned set', () {
      final short = readSession(entry(plan, [set(60, 8), set(60, 5), set(60, 8)]));
      expect(short['ok'], isFalse);
      expect(short['low'], 5);
      final missing = readSession(entry(plan, [set(60, 8), set(60, 8)]));
      expect(missing['ok'], isFalse);
    });

    test('reads everything when the plan names no set count (freestyle)', () {
      final free = readSession(entry({'mode': 'reps', 'reps': 8}, [set(60, 8), set(80, 8)]));
      expect(free['weight'], 80);
      expect(free['count'], 2);
    });

    test('leaves warm-ups out before counting, so a warm-up does not eat a planned slot', () {
      final warm = readSession(entry(plan, [{'w': 20, 'r': 10, 'done': true, 'phase': 'warmup'}, set(60, 8), set(60, 8), set(60, 8), set(90, 8)]));
      expect(warm['weight'], 60);
      expect(warm['ok'], isTrue);
    });

    test('applies the same rule to a timed hold', () {
      const timed = {'mode': 'time', 'sets': 2, 'sec': 30, 'weight': 0};
      final held = readSession(entry(timed, [{'sec': 30, 'done': true}, {'sec': 30, 'done': true}, {'sec': 12, 'done': true}]));
      expect(held['ok'], isTrue);
      expect(held['best'], 30);
    });
  });

  group('a session with no plan of its own is read whole', () {
    JMap ramp() => {'id': '0025', 'sets': [set(40, 5), set(50, 5), set(60, 5), set(70, 5), set(80, 5)]};

    test("grades an imported session on all of its sets, not on today's set count", () {
      final s = readSession(ramp(), plan);
      expect(s['weight'], 80);
      expect(s['count'], 5);
      expect(readSession({...ramp(), 'target': {...plan, 'reps': 5}}, plan)['weight'], 60);
    });

    test('so the first prescription after an import starts from the top set, not the third', () {
      final cfg = {'id': '0025', 'mode': 'reps', 'sets': 3, 'reps': 5, 'weight': 60, 'prog': 'linear'};
      final S = {'unit': 'kg', 'workouts': [{'id': 'hevy-1', 'd': '2026-09-01', 'entries': [ramp()]}]};
      final p = nextPrescription(S, cfg);
      expect(p['kind'], 'up');
      expect(p['weight'], 82.5);
    });
  });
}
