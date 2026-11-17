// The logger's session operations (lib/ui/workout/session_ops.dart), without widgets: start,
// set edits, what a tick decides (rest, superset rotation, the end of the session) and finish.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/history.dart' show supersetUnits;
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/progression.dart' show weightIncrement;
import 'package:klora_app/engine/workout_model.dart' show WEIGHT_ORIGIN_MANUAL;
import 'package:klora_app/ui/workout/session_ops.dart';

import '../engine/_exdb.dart';

JMap state({List<dynamic>? routines, List<dynamic>? workouts}) => <String, dynamic>{
  'unit': 'kg',
  'restSec': 90,
  'exWeights': <String, dynamic>{},
  'workouts': workouts ?? <dynamic>[],
  'week': <String, dynamic>{},
  'dayPlan': <String, dynamic>{},
  'routines':
      routines ??
      [
        {
          'id': 'r1',
          'name': 'Push A',
          'ex': [
            {'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60},
            {'id': '0289', 'sets': 2, 'reps': 10, 'weight': 24, 'restSec': 120},
          ],
        },
      ],
};

JMap started(JMap s, [List<String> ids = const ['r1']]) {
  s['active'] = buildActive(s, ids, null, now: 1000000, today: '2026-11-13');
  return s;
}

List<dynamic> setsOf(JMap s, int idx) => asList((s['active']['entries'] as List)[idx]['sets']);

void main() {
  setUpAll(loadTestExerciseDb);

  test('a session from a routine: its entries, named after it, stamped with its routine', () {
    final s = started(state());
    final A = s['active'] as Map;
    expect(A['name'], 'Push A');
    expect(A['routineIds'], ['r1']);
    expect(A['cur'], 0);
    expect(A['start'], 1000000);
    expect(A['d'], '2026-11-13');
    expect(A['bw'], isNull);
    expect(A['workoutView'], 'cards');
    final entries = A['entries'] as List;
    expect(entries.map((e) => e['id']), ['0025', '0289']);
    expect(entries.every((e) => e['rid'] == 'r1'), isTrue);
    expect(setsOf(s, 0).map((r) => [r['w'], r['r'], r['done']]), [
      [60, 5, false],
      [60, 5, false],
      [60, 5, false],
    ]);
    // A freestyle start has no entries and says so.
    final f = buildActive(state(), const [], 72.5);
    expect(f['name'], 'Freestyle');
    expect(f['entries'], isEmpty);
    expect(f['bw'], 72.5);
  });

  test('a weight typed on a work set is yours, and carries to the sets after it', () {
    final s = started(state());
    final inc = weightIncrement(cfgOf((s['active']['entries'] as List)[0]), 'kg');
    final next = stepLoad(s, (s['active']['entries'] as List)[0], 60, 1);
    expect(next, 60 + inc);
    setField(s, 0, 0, 'w', next);
    expect(setsOf(s, 0).map((r) => r['w']), [next, next, next]);
    expect(setsOf(s, 0)[0]['weightOrigin'], WEIGHT_ORIGIN_MANUAL);
    // A set already ticked keeps what it lifted.
    setsOf(s, 0)[2]['done'] = true;
    setField(s, 0, 0, 'w', 70);
    expect(setsOf(s, 0).map((r) => r['w']), [70, 70, next]);
    // Reps never cascade.
    setField(s, 0, 1, 'r', 3);
    expect(setsOf(s, 0).map((r) => r['r']), [5, 3, 5]);
  });

  test('add, copy and remove sets; a live exercise always keeps one', () {
    final s = started(state());
    addSet(s, 1);
    expect(setsOf(s, 1).length, 3);
    expect(setsOf(s, 1).last, {'w': 24, 'r': 10, 'done': false});
    copySetAt(s, 1, 0);
    expect(setsOf(s, 1).length, 4);
    expect(removeSetAt(s, 1, 0), isTrue);
    expect(removeSetAt(s, 1, 0), isTrue);
    expect(removeSetAt(s, 1, 0), isTrue);
    expect(setsOf(s, 1).length, 1);
    expect(removeSetAt(s, 1, 0), isFalse);
    expect(setsOf(s, 1).length, 1);
  });

  test('a tick is stamped, and the rest it earns is the exercise’s own or the default', () {
    final s = started(state());
    final hw = <int, num>{};
    expect(tickSet(s, 0, 0, now: 5000), isTrue);
    expect(setsOf(s, 0)[0]['done'], isTrue);
    expect(setsOf(s, 0)[0]['at'], 5000);
    var out = afterTick(s['active'], 0, 0, checked: true, highWater: hw, defaultRestSec: 90, timerRunning: false);
    expect(out.restSec, 90);
    expect(out.workoutDone, isFalse);

    // The exercise with its own rest (120 s).
    tickSet(s, 1, 0);
    out = afterTick(s['active'], 1, 0, checked: true, highWater: hw, defaultRestSec: 90, timerRunning: false);
    expect(out.restSec, 120);

    // Unticking starts nothing.
    expect(tickSet(s, 1, 0), isFalse);
    out = afterTick(s['active'], 1, 0, checked: false, highWater: hw, defaultRestSec: 90, timerRunning: false);
    expect(out.restSec, isNull);
    // Ticking it again is not new progress: it only fills a gap in the rest.
    tickSet(s, 1, 0);
    out = afterTick(s['active'], 1, 0, checked: true, highWater: hw, defaultRestSec: 90, timerRunning: true);
    expect(out.restSec, isNull);
  });

  test('the last set of the session rests no more and says the workout is done', () {
    final s = started(state());
    final hw = <int, num>{};
    for (var i = 0; i < 3; i++) {
      tickSet(s, 0, i);
    }
    // The finished exercise has its top weight captured.
    expect((s['active']['entries'] as List)[0]['topW'], 60);
    tickSet(s, 1, 0);
    tickSet(s, 1, 1);
    final out = afterTick(s['active'], 1, 1, checked: true, highWater: hw, defaultRestSec: 90, timerRunning: false);
    expect(out.restSec, isNull);
    expect(out.workoutDone, isTrue);
  });

  test('a superset walks member to member and rests after the round', () {
    final s = started(
      state(
        routines: [
          {
            'id': 'r1',
            'name': 'Arms',
            'ex': [
              {'id': '0025', 'sets': 2, 'reps': 5, 'weight': 60, 'sg': 'a'},
              {'id': '0289', 'sets': 2, 'reps': 10, 'weight': 24, 'sg': 'a'},
            ],
          },
        ],
      ),
    );
    expect(supersetUnits(s['active']['entries']), [
      [0, 1],
    ]);
    final hw = <int, num>{};
    tickSet(s, 0, 0);
    var out = afterTick(s['active'], 0, 0, checked: true, highWater: hw, defaultRestSec: 90, timerRunning: false);
    expect(out.nextCur, 1);
    expect(out.restSec, isNull);
    tickSet(s, 1, 0);
    out = afterTick(s['active'], 1, 0, checked: true, highWater: hw, defaultRestSec: 90, timerRunning: false);
    expect(out.nextCur, 0);
    expect(out.restSec, 90);
  });

  test('Prev / Next move between units, and stop at either end', () {
    final s = started(state());
    expect(unitTarget(s['active'], -1), isNull);
    expect(unitTarget(s['active'], 1), 1);
    (s['active'] as Map)['cur'] = 1;
    expect(unitTarget(s['active'], 1), isNull);
  });

  test('add, swap and skip exercises in the live session', () {
    final s = started(state());
    final at0 = addExercise(s, '0043');
    expect(at0, 1);
    final entries = s['active']['entries'] as List;
    expect(entries.map((e) => e['id']), ['0025', '0043', '0289']);
    expect(entries[1]['rid'], 'r1');
    expect(s['active']['cur'], 1);

    // Nothing logged: replaced in place.
    expect(swapExercise(s, 1, '0047'), 1);
    expect((s['active']['entries'] as List).map((e) => e['id']), ['0025', '0047', '0289']);

    // Something logged: kept, the replacement goes after it.
    tickSet(s, 0, 0);
    expect(swapExercise(s, 0, '0289'), 1);
    expect((s['active']['entries'] as List).map((e) => e['id']), ['0025', '0289', '0047', '0289']);

    removeExercise(s, 1);
    expect((s['active']['entries'] as List).map((e) => e['id']), ['0025', '0047', '0289']);
    // The marker stays put: the exercise after the skipped one is next.
    expect(s['active']['cur'], 1);
    removeExercise(s, 2);
    removeExercise(s, 1);
    expect(s['active']['cur'], 0);
  });

  test('finish: the record, its volume and PRs, the kept best weight, and the session gone', () {
    final history = {
      'id': 'w0',
      'd': '2026-11-10',
      'start': 1,
      'end': 2,
      'routineIds': ['r1'],
      'routineId': 'r1',
      'name': 'Push A',
      'entries': [
        {
          'id': '0025',
          'rid': 'r1',
          'sets': [
            {'w': 50, 'r': 5, 'done': true},
            {'w': 50, 'r': 5, 'done': true},
          ],
        },
        {
          'id': '0289',
          'rid': 'r1',
          'sets': [
            {'w': 24, 'r': 8, 'done': true},
          ],
        },
      ],
    };
    final s = started(state(workouts: [history]));
    for (final r in setsOf(s, 0)) {
      (r as Map)
        ..['w'] = 70
        ..['done'] = true
        ..['at'] = 1000500;
    }
    // Same weight, more reps: an estimated-1RM record, not a weight PR.
    final db = setsOf(s, 1)[0] as Map;
    db
      ..['w'] = 24
      ..['r'] = 12
      ..['done'] = true
      ..['at'] = 1000600;

    final r = buildFinished(s, now: 2000000);
    expect(r.prs, ['0025']);
    expect(r.e1prs.map((p) => p['id']), ['0289']);
    expect(r.e1prs.first['prev'], greaterThan(0));
    expect(r.workout['vol'], 70 * 5 * 3 + 24 * 12);
    expect(r.workout['prs'], ['0025']);
    expect(r.workout['end'], 2000000);
    expect((r.workout['entries'] as List).length, 2);

    writeFinished(s, r.workout);
    expect(s['active'], isNull);
    expect((s['workouts'] as List).length, 2);
    expect((s['workouts'] as List).last, same(r.workout));
    expect(s['exWeights']['0025'], {'w': 70, 'd': '2026-11-13'});
    expect(checkInText(r.workout, 'kg'), 'Finished Push A — 4 sets, 1,338 kg');
  });

  test('finish refills a completed rotation pass this app manages', () {
    final s = started(state());
    s['rotation'] = {
      'id': 'rot',
      'sequence': ['r1'],
      'label': 'Loop',
    };
    s['queue'] = {
      'ids': ['r1'],
      'since': 0,
      'startsOn': '2026-11-01',
      'label': 'Loop',
      'rotationId': 'rot',
    };
    tickSet(s, 0, 0, now: 1000100);
    final r = buildFinished(s, now: 1000200);
    writeFinished(s, r.workout);
    expect(s['queue']['ids'], ['r1']);
    expect(s['queue']['startsOn'], '2026-11-14');
  });
}
