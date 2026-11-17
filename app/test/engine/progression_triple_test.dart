// Port of frontend/src/lib/progression.triple.test.js — triple progression (issue #179): reps,
// then sets, then load.
// skipped: 'a routine copied from a session does not take the day’s per-set aims as its plan' —
// routineFromSession is session-routines.js, not part of this port.
// ignore_for_file: non_constant_identifier_names, constant_identifier_names
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/plan_share.dart';
import 'package:klora_app/engine/progression.dart';
import 'package:klora_app/engine/session_start.dart';
import 'package:klora_app/engine/workout_model.dart';

import '_exdb.dart';
import '_helpers.dart';

const _HEAVY_BP = ['upper legs', 'lower legs', 'back', 'hips', 'glutes'];
const _BW_EQ = ['body weight', 'band', 'resistance band'];
String get LIFT => jsFind(EXDB, (e) => e['bp'] != 'cardio' && !_HEAVY_BP.contains(e['bp']) && !_BW_EQ.contains(e['eq']) && !isAssisted(e['id']))['id'] as String;
JMap get cfg => {'id': LIFT, 'sets': 3, 'setsMax': 5, 'reps': 12, 'repsMin': 8, 'weight': 60, 'inc': 2.5, 'mode': 'reps', 'prog': 'triple'};
JMap get routine => {'id': 'r', 'name': 'A', 'ex': [cfg]};
List<dynamic> work(List<dynamic> rows) => rows.where((s) => !isWarmupRow(s)).toList();
JMap without(JMap m, String key) => {...m}..remove(key);

// One session the way the app runs it: built from the routine, every set lifted with
// `lift(aim, k)` reps (all of them as asked when none is given), then saved.
var day = 0;
({JMap st, JMap entry}) train(JMap st, [num Function(num aim, int k)? lift]) {
  lift ??= (aim, _) => aim;
  final entry = buildSessionEntries(st, routine)[0] as JMap;
  var k = -1;
  final done = [
    for (final s in entry['sets'] as List)
      if (isWarmupRow(s)) {...s as Map<String, dynamic>, 'done': true} else {...s as Map<String, dynamic>, 'r': lift(s['r'] as num, ++k), 'done': true},
  ];
  day++;
  final w = {'d': '2026-01-${'$day'.padLeft(2, '0')}', 'routineId': 'r', 'entries': [{...entry, 'rid': 'r', 'sets': done}]};
  return (st: {...st, 'workouts': [...st['workouts'] as List, w]}, entry: entry);
}

List<dynamic> aims(JMap entry) => work(entry['sets'] as List).map((s) => s['r']).toList();
JMap fresh() {
  day = 0;
  return {'unit': 'kg', 'workouts': [], 'exWeights': {}, 'routines': [routine]};
}

void main() {
  setUpAll(loadTestExerciseDb);

  group('triple progression is a policy like the others', () {
    test('is offered for rep work with a name, an explanation and the usual deload', () {
      expect(POLICIES_FOR['reps'], contains('triple'));
      expect(POLICIES_FOR['time'], isNot(contains('triple')));
      expect(POLICY_NAME['triple'], 'Triple progression');
      expect(POLICY_DESC['triple'], contains('set'));
      expect(DELOAD_AFTER['triple'], 3);
    });

    test('reads its set range off sets and setsMax, never below the base sets', () {
      expect(tripleSetsOf({'sets': 3, 'setsMax': 5}), jeq({'setsMin': 3, 'setsMax': 5}));
      expect(tripleSetsOf({'sets': 3}), jeq({'setsMin': 3, 'setsMax': 3}));
      expect(tripleSetsOf({'sets': 4, 'setsMax': 2}), jeq({'setsMin': 4, 'setsMax': 4}));
      expect(tripleSetsOf({'sets': 3, 'setsMax': 99})['setsMax'], 10);
    });

    test('stamps setsMax as part of the plan, so raising it starts the plan again', () {
      expect(plannedOf(cfg), matchObj({'sets': 3, 'reps': 12, 'repsMin': 8, 'setsMax': 5}));
      expect(planChanged(plannedOf(cfg), {...cfg, 'setsMax': 6}), isTrue);
      expect(planChanged(plannedOf(cfg), cfg), isFalse);
      expect(plannedOf({...without(cfg, 'setsMax'), 'prog': 'double'}).containsKey('setsMax'), isFalse);
    });
  });

  group('a full cycle: reps → sets → load', () {
    test('climbs the base sets together, adds one set at a time, then raises the weight', () {
      var st = fresh();
      final line = <String>[];
      for (var i = 0; i < 26; i++) {
        final r = train(st);
        line.add('${jsString(work(r.entry['sets'] as List)[0]['w'])}:${jsJoin(aims(r.entry))}');
        st = r.st;
      }
      expect(line.sublist(0, 5), ['60:8,8,8', '60:9,9,9', '60:10,10,10', '60:11,11,11', '60:12,12,12']);
      expect(line.sublist(5, 10), ['60:12,12,12,8', '60:12,12,12,9', '60:12,12,12,10', '60:12,12,12,11', '60:12,12,12,12']);
      expect(line.sublist(10, 15), ['60:12,12,12,12,8', '60:12,12,12,12,9', '60:12,12,12,12,10', '60:12,12,12,12,11', '60:12,12,12,12,12']);
      expect(line[15], '62.5:8,8,8');
      expect(line.sublist(16, 20), ['62.5:9,9,9', '62.5:10,10,10', '62.5:11,11,11', '62.5:12,12,12']);
    });

    test('opens the first session at the base sets and the bottom of the range', () {
      final entry = buildSessionEntries(fresh(), routine)[0] as JMap;
      expect(entry['plan'], matchObj({'kind': 'first', 'sets': 3, 'reps': 8, 'rowReps': [8, 8, 8]}));
      expect(aims(entry), jeq([8, 8, 8]));
      expect(entry['target']['rowReps'], jeq([8, 8, 8]));
      expect(work(entry['sets'] as List).every((s) => s['w'] == 60), isTrue);
    });

    test('counts reps beyond the aim: a set that already reached the top adds the next set', () {
      var st = fresh();
      st = train(st, (_, _) => 12).st;
      final p = nextPrescription(st, cfg, routine);
      expect(p, matchObj({'kind': 'up', 'sets': 4, 'rowReps': [12, 12, 12, 8], 'weight': 60}));
    });

    test('without a set ceiling above the base sets it is double progression with per-set aims', () {
      final flat = without(cfg, 'setsMax');
      final r = {...routine, 'ex': [flat]};
      JMap st = {'unit': 'kg', 'workouts': [], 'exWeights': {}, 'routines': [r]};
      final entry = buildSessionEntries(st, r)[0] as JMap;
      st = {
        ...st,
        'workouts': [
          ...st['workouts'] as List,
          {'d': '2026-02-0${(st['workouts'] as List).length + 1}', 'routineId': 'r', 'entries': [
            {...entry, 'rid': 'r', 'sets': [for (final s in entry['sets'] as List) {...s as Map<String, dynamic>, 'r': 12, 'done': true}]},
          ]},
        ],
      };
      expect(nextPrescription(st, flat, r), matchObj({'kind': 'up', 'weight': 62.5, 'rowReps': [8, 8, 8]}));
    });
  });

  group('misses, stalls and deloads', () {
    JMap atFourthSet() {
      var st = fresh();
      for (var i = 0; i < 7; i++) {
        st = train(st).st;
      }
      return st;
    }

    test('holds the same sets and reps after a miss, without cutting the added set', () {
      var st = atFourthSet();
      expect(aims(train(st).entry), jeq([12, 12, 12, 10]));
      st = train(st, (aim, k) => k == 3 ? aim - 3 : aim).st;
      final p = nextPrescription(st, cfg, routine);
      expect(p, matchObj({'kind': 'hold', 'weight': 60, 'sets': 4, 'rowReps': [12, 12, 12, 10]}));
      expect((p['why'] as List)[0], 'Missed reps last time. Same sets and reps again ({0} of {1} to go).');
    });

    test('more reps on the moving set is progress, so it does not count toward a deload', () {
      var st = atFourthSet();
      st = train(st, (aim, k) => k == 3 ? 7 : aim).st;
      st = train(st, (aim, k) => k == 3 ? 8 : aim).st;
      st = train(st, (aim, k) => k == 3 ? 9 : aim).st;
      final sessions = sessionsFor(st, LIFT, cfg, 'r');
      expect(stallCount(sessions, 'triple'), 0);
      final p = nextPrescription(st, cfg, routine);
      expect(p['kind'], 'hold');
      expect(p['rowReps'], jeq([12, 12, 12, 10]));
      expect((p['why'] as List)[0], 'Short of the target, but more reps than before. Same sets and reps again.');
    });

    test('three real stalls deload with Epley and start the cycle again at the base sets', () {
      var st = atFourthSet();
      for (var i = 0; i < 3; i++) {
        st = train(st, (aim, k) => k == 3 ? 7 : aim).st;
      }
      expect(stallCount(sessionsFor(st, LIFT, cfg, 'r'), 'triple'), 3);
      final p = nextPrescription(st, cfg, routine);
      expect(p['kind'], 'deload');
      expect(p['rowReps'], jeq([8, 8, 8]));
      expect(p['sets'], 3);
      expect(p['weight'], lessThan(60));
      expect((p['weight'] as num) % 2.5, 0);
      expect(p['weight'], 57.5);
      final entry = buildSessionEntries(st, routine)[0] as JMap;
      expect(aims(entry), jeq([8, 8, 8]));
      expect(work(entry['sets'] as List).every((s) => s['w'] == 57.5), isTrue);
    });

    test('a deloaded session that went well climbs again from there', () {
      var st = atFourthSet();
      for (var i = 0; i < 3; i++) {
        st = train(st, (aim, k) => k == 3 ? 7 : aim).st;
      }
      st = train(st).st;
      expect(nextPrescription(st, cfg, routine), matchObj({'kind': 'hold', 'weight': 57.5, 'rowReps': [9, 9, 9]}));
    });
  });

  group('triple progression keeps the rules every policy follows', () {
    test('an edited plan starts again at the base sets', () {
      var st = fresh();
      for (var i = 0; i < 7; i++) {
        st = train(st).st;
      }
      final edited = {...cfg, 'setsMax': 4};
      final p = nextPrescription(st, edited, {...routine, 'ex': [edited]});
      expect((p['why'] as List)[0], 'Plan changed, so starting from your new target.');
      expect(p['sets'], 3);
      expect(p['rowReps'], hasLength(3));
    });

    test('a session judged against its own per-set aims, not the top of the range', () {
      final entry = {'id': LIFT, 'target': {...cfg, 'sets': 4, 'reps': 12, 'rowReps': [12, 12, 12, 9]}, 'sets': [for (final r in [12, 12, 12, 9]) {'w': 60, 'r': r, 'done': true}]};
      expect(readSession(entry, cfg)['ok'], isTrue);
      expect(readSession({...entry, 'sets': [for (final r in [12, 12, 12, 8]) {'w': 60, 'r': r, 'done': true}]}, cfg)['ok'], isFalse);
      expect(readSession({'id': LIFT, 'sets': [for (final r in [12, 12, 12, 9]) {'w': 60, 'r': r, 'done': true}]}, {...cfg, 'reps': 12, 'rowReps': [12, 12, 12, 9]})['ok'], isFalse);
    });

    test('a session in progress keeps its logged rows when the aims are applied', () {
      final rows = [{'w': 60, 'r': 10, 'done': true}, {'w': 60, 'r': 8, 'done': false}, {'w': 60, 'r': 8, 'done': false}];
      final out = applyPrescription(rows, {'kind': 'hold', 'weight': 60, 'reps': 12, 'sets': 4, 'rowReps': [12, 12, 12, 8]}, 2.5);
      expect(out.map((s) => s['r']).toList(), jeq([10, 12, 12, 8]));
      expect(out, hasLength(4));
    });

    test('splits the aims across the sides of a unilateral set', () {
      final rows = [makeSideSet({'w': 20, 'r': 16}), makeSideSet({'w': 20, 'r': 16})];
      final out = applyPrescription(rows, {'kind': 'hold', 'weight': 20, 'reps': 20, 'sets': 3, 'rowReps': [20, 20, 16]}, 2.5);
      expect(out.map((s) => [s['sides']['L']['r'], s['sides']['R']['r']]).toList(), jeq([[10, 10], [10, 10], [8, 8]]));
    });

    test('an assistance machine takes less help as its raise', () {
      final c = {...cfg, 'assisted': true, 'sets': 1, 'setsMax': 1, 'reps': 10, 'repsMin': 8, 'weight': 40, 'inc': 5};
      final r = {...routine, 'ex': [c]};
      final st = {'unit': 'kg', 'exWeights': {}, 'routines': [r], 'workouts': [
        {'d': '2026-03-01', 'routineId': 'r', 'entries': [
          {'id': c['id'], 'rid': 'r', 'planned': plannedOf(c), 'target': {...c, 'sets': 1, 'reps': 10, 'rowReps': [10]}, 'sets': [{'w': 40, 'r': 10, 'done': true}]},
        ]},
      ]};
      expect(nextPrescription(st, c, r), matchObj({'kind': 'up', 'weight': 35, 'rowReps': [8]}));
    });

    test('leaves linear and double progression exactly as they were', () {
      final st = {'unit': 'kg', 'exWeights': {}, 'routines': [], 'workouts': [
        {'d': '2026-03-01', 'entries': [{'id': LIFT, 'target': {'sets': 3, 'reps': 12, 'repsMin': 8}, 'sets': [for (final r in [10, 10, 10]) {'w': 60, 'r': r, 'done': true}]}]},
      ]};
      final dbl = nextPrescription(st, {...without(cfg, 'setsMax'), 'prog': 'double'}, null);
      expect(dbl, matchObj({'kind': 'hold', 'weight': 60, 'reps': 11}));
      expect(dbl.containsKey('rowReps'), isFalse);
      final lin = nextPrescription(st, {...without(cfg, 'setsMax'), 'prog': 'linear'}, null);
      expect(lin.containsKey('rowReps'), isFalse);
    });
  });

  group('triple progression in the plan around it', () {
    test('reads its set range on the routine line', () {
      expect(setsRepsOf(cfg), '3–5 × 8–12');
      expect(exLine(cfg, 'kg'), '3–5 × 8–12 · 60 kg');
      expect(setsRepsOf(without(cfg, 'setsMax')), '3 × 8–12');
    });

    test('travels with a shared plan', () {
      final S = {'unit': 'kg', 'week': {}, 'customEx': [], 'routines': [routine]};
      final ex = (parsePlan(jsonEncode(buildPlanBundle(S, 'Plan')))['routines'] as List)[0]['ex'][0];
      expect(ex, matchObj({'prog': 'triple', 'sets': 3, 'setsMax': 5, 'reps': 12, 'repsMin': 8}));
    });
  });
}
