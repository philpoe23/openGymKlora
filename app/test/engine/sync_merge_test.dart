// Port of frontend/src/lib/sync-merge.test.js, case for case.
//
// Not ported modules the JS test imports: import-csv.js (mergeImport) and workout-date.js
// (retimeWorkout). The three cases that use them build those helpers' output with the small
// test-local equivalents below (_retimeWorkout, _mergeImport), line-for-line from the JS, so no
// case is skipped.
// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/plates.dart';
import 'package:klora_app/engine/sync_merge.dart';
import 'package:klora_app/engine/units.dart';

import '_exdb.dart';
import '_helpers.dart';

JMap j(Object o) => clone(o) as JMap;
JMap workout(String id, [String d = '2026-09-01', num start = 1]) => j({'id': id, 'd': d, 'start': start, 'entries': []});
JMap routine(String id, [String? name]) => j({'id': id, 'name': name ?? id, 'ex': []});
JMap base([Map<String, dynamic> over = const {}]) => j({
      'unit': 'kg', 'restSec': 90, 'lang': 'en', 'week': {'1': ['r1']}, 'dayPlan': {},
      'workouts': [], 'routines': [], 'bodyweight': [], 'customEx': [], 'favEx': [], 'exWeights': {}, 'exNotes': {}, 'barWeights': {},
      'equipProfiles': [], 'gymCards': [], '_ts': 0, ...over,
    });
List<dynamic> ids(dynamic xs) => asList(xs).map((x) => x['id']).toList();
List<dynamic> sorted(List<dynamic> xs) => jsSort(List<dynamic>.of(xs), (a, b) => jsString(a).compareTo(jsString(b)));
dynamic byId(dynamic xs, Object id) => jsFind(asList(xs), (x) => x['id'] == id);
List<dynamic> L(dynamic v) => v as List<dynamic>;
JMap M(dynamic v) => v as JMap;

// workout-date.js retimeWorkout / backfillStart / legacySyncKey (not ported yet).
JMap _retimeWorkout(JMap w, String iso, String time) {
  final hm = time.split(':').map(int.parse).toList();
  final p = iso.split('-').map(int.parse).toList();
  final start = DateTime(p[0], p[1], p[2], hm[0], hm[1]).millisecondsSinceEpoch;
  final duration = (toNum(w['end'] ?? w['start']) - toNum(w['start'])).clamp(0, double.infinity);
  final moved = <String, dynamic>{...w, 'd': iso, 'start': start, 'end': start + duration};
  if (w['id'] == null) moved['id'] = '${w['d']}|${w['start']}';
  return moved;
}

// import-csv.js mergeImport (not ported yet), for parsed data with no custom exercises.
void _mergeImport(JMap S, JMap parsed) {
  if (parsed['kind'] == 'bodyweight') {
    final have = L(S['bodyweight']).map((b) => b['d']).toSet();
    final fresh = L(parsed['bodyweight']).where((b) => !have.contains(b['d'])).toList();
    S['bodyweight'] = jsSort([...L(S['bodyweight']), ...fresh], (a, b) => (a['d'] as String).compareTo(b['d']) < 0 ? -1 : 1);
    return;
  }
  final have = L(S['workouts']).map((w) => w['d']).toSet();
  final fresh = L(parsed['workouts']).where((w) => !have.contains(w['d'])).toList();
  S['workouts'] = jsSort([...L(S['workouts']), ...fresh], (a, b) => a['d'] == b['d']
      ? cmpNum(numOr(a['start'], 0) - numOr(b['start'], 0))
      : ((a['d'] as String).compareTo(b['d']) < 0 ? -1 : 1));
  for (final w in fresh) {
    for (final e in L(w['entries'])) {
      final mx = maxOf([0, ...L(e['sets']).map((s) => numOr(s['w'], 0)), numOr(e['topW'], 0)]);
      if (mx > 0) {
        final cur = S['exWeights'][e['id']];
        if (cur == null || (w['d'] as String).compareTo(cur['d']) >= 0) S['exWeights'][e['id']] = {'w': mx, 'd': w['d']};
      }
    }
  }
}

int _dateParse(String iso) => DateTime.parse('${iso}T00:00:00Z').millisecondsSinceEpoch;

void main() {
  setUpAll(loadTestExerciseDb);

  group('newerOf / unionById / mergeBodyweight', () {
    test('picks the later _ts, first argument on a tie or missing stamps', () {
      final a = j({'_ts': 5}), b = j({'_ts': 9});
      expect(newerOf(a, b), same(b));
      expect(newerOf(b, a), same(b));
      expect(newerOf({'_ts': 5}, {'_ts': 5}), jeq({'_ts': 5}));
      expect(newerOf({}, {}), jeq({}));
    });
    test('unions by id in the newer order, newer wins a shared id, dupes dropped', () {
      final out = unionById([routine('a', 'A2'), routine('b'), routine('b')], [routine('c'), routine('a', 'A1')]);
      expect(ids(out), ['a', 'b', 'c']);
      expect(out[0]['name'], 'A2');
      expect(unionById(null, null), jeq([]));
    });
    test('bodyweight: one entry per day, the later-edited one, sorted', () {
      final out = mergeBodyweight(j({'x': [{'d': '2026-09-02', 'w': 80, 't': 5}]})['x'],
          j({'x': [{'d': '2026-09-01', 'w': 81, 't': 1}, {'d': '2026-09-02', 'w': 79, 't': 9}]})['x']);
      expect(out, jeq([{'d': '2026-09-01', 'w': 81, 't': 1}, {'d': '2026-09-02', 'w': 79, 't': 9}]));
    });
  });

  group('mergeStates', () {
    JMap A() => base({
          '_ts': 200, 'restSec': 120, 'week': {'1': ['rA']},
          'workouts': [workout('w1'), workout('wA', '2026-09-03')],
          'routines': [routine('shared', 'from A'), routine('onlyA')],
          'bodyweight': [{'d': '2026-09-01', 'w': 80, 't': 10}],
          'customEx': [{'id': 'cA', 'name': 'A ex'}], 'favEx': ['x', 'y'],
          'exWeights': {'sq': {'w': 100}, 'bp': {'w': 60}}, 'exNotes': {'sq': 'A note'}, 'barWeights': {'sq': 20},
          'gymCards': [{'id': 'g1', 'value': '1'}], '_rev': 7,
        });
    JMap B() => base({
          '_ts': 100, 'restSec': 60, 'week': {'1': ['rB']},
          'workouts': [workout('w1'), workout('wB', '2026-09-02')],
          'routines': [routine('shared', 'from B'), routine('onlyB')],
          'bodyweight': [{'d': '2026-09-01', 'w': 79, 't': 20}, {'d': '2026-08-30', 'w': 82, 't': 1}],
          'customEx': [{'id': 'cB', 'name': 'B ex'}], 'favEx': ['y', 'z'],
          'exWeights': {'sq': {'w': 110}, 'dl': {'w': 140}}, 'exNotes': {'dl': 'B note'}, 'barWeights': {'dl': 15},
          'gymCards': [{'id': 'g2', 'value': '2'}], '_rev': 8,
        });

    test('no entity of either side disappears, ids stay unique', () {
      final m = mergeStates(A(), B());
      expect(sorted(ids(m['workouts'])), ['w1', 'wA', 'wB']);
      expect(sorted(ids(m['routines'])), ['onlyA', 'onlyB', 'shared']);
      expect(sorted(ids(m['customEx'])), ['cA', 'cB']);
      expect(sorted(ids(m['gymCards'])), ['g1', 'g2']);
      expect(L(m['bodyweight']).map((b) => b['d']).toList(), ['2026-08-30', '2026-09-01']);
      expect(m['favEx'], ['x', 'y', 'z']);
      expect(ids(m['workouts']).toSet().length, L(m['workouts']).length);
    });

    test('the newer copy decides settings, week, and a shared id; the other way round too', () {
      final m = mergeStates(A(), B());
      expect(m['restSec'], 120);
      expect(m['week'], jeq({'1': ['rA']}));
      expect(byId(m['routines'], 'shared')['name'], 'from A');
      final m2 = mergeStates(B(), {...A(), '_ts': 50});
      expect(m2['restSec'], 60);
      expect(m2['week'], jeq({'1': ['rB']}));
      expect(byId(m2['routines'], 'shared')['name'], 'from B');
    });

    test('bodyweight keeps the later-edited entry of a day, exWeights the larger weight, notes union', () {
      final m = mergeStates(A(), B());
      expect(jsFind(L(m['bodyweight']), (b) => b['d'] == '2026-09-01'), jeq({'d': '2026-09-01', 'w': 79, 't': 20}));
      expect(m['exWeights'], jeq({'sq': {'w': 110}, 'bp': {'w': 60}, 'dl': {'w': 140}}));
      expect(m['exNotes'], jeq({'sq': 'A note', 'dl': 'B note'}));
      expect(m['barWeights'], jeq({'sq': 20, 'dl': 15}));
    });

    group('a workout edited after it was logged', () {
      JMap set(num w, [String id = 'sq']) => j({'id': id, 'target': {'mode': 'reps'}, 'sets': [{'w': w, 'r': 5, 'done': true}]});
      JMap logged(List<dynamic> entries, [Map<String, dynamic> over = const {}]) => j({...workout('w1'), 'entries': entries, ...over});

      test('keeps the edit when the other copy is newer as a whole but still has the old version', () {
        final edited = base({'_ts': 100, 'workouts': [stampWorkout(logged([set(80)]), 100)]});
        final stale = base({'_ts': 200, 'workouts': [logged([set(100)])], 'bodyweight': [{'d': '2026-09-02', 'w': 80, 't': 200}]});
        for (final m in [mergeStates(edited, stale), mergeStates(stale, edited)]) {
          expect(L(m['workouts']), hasLength(1));
          expect(m['workouts'][0]['entries'][0]['sets'][0]['w'], 80);
          expect(L(m['bodyweight']), hasLength(1));
        }
      });

      test('keeps the later of two edits of the same workout, the newer copy\'s on a tie', () {
        final a = base({'_ts': 300, 'workouts': [stampWorkout(logged([set(80)]), 150)]});
        final b = base({'_ts': 100, 'workouts': [stampWorkout(logged([set(90)]), 250)]});
        expect(mergeStates(a, b)['workouts'][0]['entries'][0]['sets'][0]['w'], 90);
        expect(mergeStates(b, a)['workouts'][0]['entries'][0]['sets'][0]['w'], 90);
        final tie = base({'_ts': 100, 'workouts': [stampWorkout(logged([set(70)]), 250)]});
        expect(mergeStates(b, {...tie, '_ts': 50})['workouts'][0]['entries'][0]['sets'][0]['w'], 90);
      });

      test('a date move replaces the other copy by id too', () {
        final moved = _retimeWorkout(logged([set(80)]), '2026-08-20', '07:00');
        stampWorkout(moved, 100);
        final m = mergeStates(base({'_ts': 100, 'workouts': [moved]}), base({'_ts': 200, 'workouts': [logged([set(80)])]}));
        expect(L(m['workouts']), hasLength(1));
        expect(m['workouts'][0]['d'], '2026-08-20');
      });

      test('an edit of a workout the other copy deleted brings it back, edited', () {
        final edited = base({'_ts': 100, 'workouts': [stampWorkout(logged([set(80)]), 100)]});
        final deleted = base({'_ts': 200, 'workouts': []});
        expect(L(mergeStates(deleted, edited)['workouts']).map((w) => w['entries'][0]['sets'][0]['w']).toList(), [80]);
      });

      test('sign-in keeps the preferred side\'s version as it is', () {
        final server = base({'_ts': 100, 'workouts': [logged([set(100)])]});
        final device = base({'_ts': 50, 'workouts': [stampWorkout(logged([set(80)]), 300)]});
        expect(mergeStates(server, device, prefer: 'a')['workouts'][0]['entries'][0]['sets'][0]['w'], 100);
      });

      test('does not resurrect a kept load the edit took away, from either side', () {
        final edited = base({'_ts': 100, 'workouts': [stampWorkout(logged([set(80)]), 100)], 'exWeights': {'sq': {'w': 80, 'd': '2026-09-01'}}});
        final stale = base({'_ts': 200, 'workouts': [logged([set(1000)])], 'exWeights': {'sq': {'w': 1000, 'd': '2026-09-01'}}});
        expect(mergeStates(edited, stale)['exWeights']['sq'], jeq({'w': 80, 'd': '2026-09-01'}));
        expect(mergeStates(stale, edited)['exWeights']['sq'], jeq({'w': 80, 'd': '2026-09-01'}));
      });

      test('keeps a heavier set the other copy logged since, and its own kept load when that is better', () {
        final edited = base({'_ts': 100, 'workouts': [stampWorkout(logged([set(80)]), 100)], 'exWeights': {'sq': {'w': 85, 'd': '2026-08-01'}}});
        final other = base({'_ts': 200, 'workouts': [logged([set(1000)]), {...workout('w2', '2026-09-03'), 'entries': [set(90)]}], 'exWeights': {'sq': {'w': 1000, 'd': '2026-09-01'}}});
        expect(mergeStates(other, edited)['exWeights']['sq'], jeq({'w': 90, 'd': '2026-09-03'}));
        final noLater = base({'_ts': 200, 'workouts': [logged([set(1000)])], 'exWeights': {'sq': {'w': 1000, 'd': '2026-09-01'}}});
        expect(mergeStates(noLater, edited)['exWeights']['sq'], jeq({'w': 85, 'd': '2026-08-01'}));
      });

      test('keeps assisted-machine kept loads ordered by less help', () {
        final edited = base({'_ts': 100, 'workouts': [stampWorkout(logged([set(20, '0017')]), 100)], 'exWeights': {'0017': {'w': 20, 'd': '2026-09-01'}}});
        final stale = base({'_ts': 200, 'workouts': [logged([set(30, '0017')])], 'exWeights': {'0017': {'w': 30, 'd': '2026-09-01'}}});
        expect(mergeStates(stale, edited)['exWeights']['0017'], jeq({'w': 20, 'd': '2026-09-01'}));
      });

      test('leaves the kept loads alone when only the date, the length or the note changed', () {
        final moved = stampWorkout(logged([set(80)], {'note': 'moved'}), 100);
        final other = base({'_ts': 200, 'workouts': [logged([set(80)])], 'exWeights': {'sq': {'w': 120, 'd': '2026-08-01'}}});
        expect(mergeStates(other, base({'_ts': 100, 'workouts': [moved], 'exWeights': {}}))['exWeights']['sq'], jeq({'w': 120, 'd': '2026-08-01'}));
      });
    });

    test('is commutative on the union fields and idempotent', () {
      final ab = mergeStates(A(), B()), ba = mergeStates(B(), A());
      for (final f in ['workouts', 'routines', 'customEx', 'gymCards']) {
        expect(sorted(ids(ab[f])), sorted(ids(ba[f])));
      }
      expect(ab['bodyweight'], jeq(ba['bodyweight']));
      expect(sorted(L(ab['favEx'])), sorted(L(ba['favEx'])));
      expect(ab['exWeights'], jeq(ba['exWeights']));
      final again = mergeStates(A(), ab);
      expect(ids(again['workouts']), ids(ab['workouts']));
      expect(ids(again['routines']), ids(ab['routines']));
      expect(mergeStates(A(), A())['workouts'], jeq(A()['workouts']));
    });

    test('sorts workouts by day and start, takes the later _ts, drops _rev, does not touch inputs', () {
      final a = A(), b = B();
      final m = mergeStates(a, b);
      expect(L(m['workouts']).map((w) => w['d']).toList(), ['2026-09-01', '2026-09-02', '2026-09-03']);
      expect(m['_ts'], 200);
      expect(M(m).containsKey('_rev'), false);
      expect(a, jeq(A()));
      expect(b, jeq(B()));
      L(m['workouts'][0]['entries']).add('x');
      expect(a['workouts'][0]['entries'], jeq([]));
    });

    test('tolerates a missing side and missing lists', () {
      expect(mergeStates(A(), null), jeq(A()));
      expect(mergeStates(null, B()), jeq(B()));
      final sparse = j({'_ts': 5, 'workouts': null});
      final m = mergeStates(sparse, j({'_ts': 1, 'workouts': [workout('w')]}));
      expect(ids(m['workouts']), ['w']);
      expect(m['bodyweight'], jeq([]));
    });

    test('a workout without an id is kept once by day and start', () {
      final legacy = j({'d': '2026-09-01', 'start': 5, 'entries': []});
      final m = mergeStates(j({'_ts': 2, 'workouts': [legacy]}), j({'_ts': 1, 'workouts': [{...legacy}, {'d': '2026-09-01', 'start': 6, 'entries': []}]}));
      expect(L(m['workouts']), hasLength(2));
    });

    test('a legacy workout moved to another day replaces its untouched copy', () {
      final legacy = j({'d': '2026-09-01', 'start': 5, 'entries': [], 'prs': []});
      final moved = _retimeWorkout(legacy, '2026-08-20', '07:00');
      final m = mergeStates(j({'_ts': 2, 'workouts': [moved]}), j({'_ts': 1, 'workouts': [{...legacy}]}));
      expect(L(m['workouts']), hasLength(1));
      expect(m['workouts'][0]['d'], '2026-08-20');
    });

    test('a fresh id on the same edit would have duplicated it', () {
      final legacy = j({'d': '2026-09-01', 'start': 5, 'entries': [], 'prs': []});
      final renamed = {...legacy, 'id': 'brand-new', 'd': '2026-08-20'};
      final m = mergeStates(j({'_ts': 2, 'workouts': [renamed]}), j({'_ts': 1, 'workouts': [{...legacy}]}));
      expect(L(m['workouts']), hasLength(2));
    });

    test('the desktop setting and the phone workout both survive', () {
      final t0 = base({'_ts': 1000, 'workouts': [workout('w1')], 'restSec': 90});
      final server = {...t0, '_ts': 1001, 'workouts': [workout('w1'), workout('from-phone', '2026-09-05')], '_rev': 4};
      final desktop = {...t0, '_ts': 1002, 'restSec': 75};
      final m = mergeStates(desktop, server);
      expect(ids(m['workouts']), ['w1', 'from-phone']);
      expect(m['restSec'], 75);
      expect(m['_ts'], 1002);
    });
  });

  group('sign-in adoption helpers', () {
    final server = j({'_ts': 100, 'unit': 'lb', 'restSec': 60, 'workouts': [{'id': 'w1', 'd': '2026-09-01'}], 'bodyweight': [{'d': '2026-09-01', 'w': 80, 't': 1}], 'routines': [{'id': 'r1', 'name': 'A'}], 'week': {'1': ['r1']}});
    final local = j({'_ts': 900, 'unit': 'kg', 'restSec': 90, 'workouts': [{'id': 'w9', 'd': '2026-09-11'}], 'bodyweight': [{'d': '2026-09-11', 'w': 81, 't': 2}, {'d': '2026-09-01', 'w': 79, 't': 9}], 'routines': [{'id': 'rg', 'name': 'Guest'}], 'customEx': [{'id': 'c1', 'name': 'x'}], 'week': {'2': ['rg']}});
    test('localExtras counts what the device has that the server does not', () {
      expect(localExtras(local, server), jeq({'workouts': 1, 'bodyweight': 2, 'customEx': 1, 'routines': 1, 'setup': 1}));
      expect(localExtras(server, server), jeq({'workouts': 0, 'bodyweight': 0, 'customEx': 0}));
      expect(localExtras(null, server), jeq({'workouts': 0, 'bodyweight': 0, 'customEx': 0}));
    });
    test('mergeStates with prefer keeps the preferred side\'s settings and plan although the other is newer', () {
      final m = mergeStates(server, local, prefer: 'a');
      expect(m['unit'], 'lb');
      expect(m['restSec'], 60);
      expect(m['week'], jeq({'1': ['r1']}));
      expect(ids(m['workouts']), ['w1', 'w9']);
      expect(sorted(ids(m['routines'])), ['r1', 'rg']);
      expect(ids(m['customEx']), ['c1']);
      expect(jsFind(L(m['bodyweight']), (e) => e['d'] == '2026-09-01')['w'], 174.2);
      expect(mergeStates(server, local)['unit'], 'kg');
    });
  });

  group('routines keep the version edited last', () {
    JMap r(String id, num reps, [num? ts]) => j({'id': id, 'name': id, 'ex': [{'id': 'bench', 'sets': 3, 'reps': reps}], '_ts': ?ts});

    test('the older copy\'s routine wins when it was edited after the newer copy\'s', () {
      final phone = base({'_ts': 100, 'routines': [r('push', 15, 90), r('pull', 8, 10)]});
      final desk = base({'_ts': 200, 'restSec': 60, 'routines': [r('push', 10, 20), r('pull', 12, 150)]});
      final m = mergeStates(phone, desk);
      expect(m['restSec'], 60);
      expect(byId(m['routines'], 'push')['ex'][0]['reps'], 15);
      expect(byId(m['routines'], 'pull')['ex'][0]['reps'], 12);
      expect(ids(m['routines']), ['push', 'pull']);
      expect(mergeStates(desk, phone)['routines'], jeq(m['routines']));
    });

    test('a routine only the older copy has comes back next to its old neighbour, not at the end', () {
      final a = base({'_ts': 100, 'routines': [r('push', 5, 1), r('pull', 5, 90), r('leg', 5, 1), r('cond', 5, 1)]});
      final b = base({'_ts': 200, 'routines': [r('push', 5, 1), r('leg', 5, 1), r('leg2', 5, 150), r('cond', 5, 1)]});
      expect(ids(mergeStates(a, b)['routines']), ['push', 'pull', 'leg', 'leg2', 'cond']);
      final c = base({'_ts': 100, 'routines': [r('x', 5, 1), r('y', 5, 1), r('push', 5, 1)]});
      final d = base({'_ts': 200, 'routines': [r('push', 5, 1), r('leg', 5, 1)]});
      expect(ids(mergeStates(c, d)['routines']), ['x', 'y', 'push', 'leg']);
    });

    test('without stamps, or on a tie, the newer copy\'s version stays', () {
      final a = base({'_ts': 100, 'routines': [r('push', 15)]});
      final b = base({'_ts': 200, 'routines': [r('push', 10)]});
      expect(mergeStates(a, b)['routines'][0]['ex'][0]['reps'], 10);
      final c = base({'_ts': 100, 'routines': [r('push', 15, 50)]});
      final d = base({'_ts': 200, 'routines': [r('push', 10, 50)]});
      expect(mergeStates(c, d)['routines'][0]['ex'][0]['reps'], 10);
    });

    test('sign-in (prefer) keeps the preferred side\'s plan whatever the stamps say', () {
      final server = base({'_ts': 100, 'routines': [r('push', 10, 10)]});
      final device = base({'_ts': 200, 'routines': [r('push', 15, 90)]});
      expect(mergeStates(server, device, prefer: 'a')['routines'][0]['ex'][0]['reps'], 10);
    });

    test('stampRoutines stamps a new or edited routine and leaves the rest alone', () {
      final prev = [r('push', 10, 5), r('pull', 8, 6), r('legs', 5, 7)];
      final next = clone(prev) as List<dynamic>;
      next[0]['ex'][0]['reps'] = 12;
      next.add(r('core', 20));
      next.removeAt(2);
      stampRoutines(prev, next, 1000);
      expect(next.map((x) => x['_ts']).toList(), [1000, 6, 1000]);
      final again = clone(next) as List<dynamic>;
      again[1]['_ts'] = 99;
      stampRoutines(next, again, 2000);
      expect(again.map((x) => x['_ts']).toList(), [1000, 99, 1000]);
    });
  });

  group('balanceOverrides keep the choice made last', () {
    JMap pick(String? id, num ts) => j({'id': id, '_ts': ts});

    test('a role chosen on the older copy survives the newer copy\'s earlier choice', () {
      final phone = base({'_ts': 100, 'balanceOverrides': {'poliquin:dips': pick('0009', 90)}});
      final desk = base({'_ts': 200, 'restSec': 60, 'workouts': [workout('w2')], 'balanceOverrides': {'poliquin:dips': pick('0251', 20)}});
      for (final m in [mergeStates(phone, desk), mergeStates(desk, phone)]) {
        expect(m['restSec'], 60);
        expect(m['balanceOverrides']['poliquin:dips'], jeq(pick('0009', 90)));
      }
    });

    test('a clear is not undone by the other device\'s older choice, and a later choice beats a clear', () {
      final cleared = base({'_ts': 100, 'balanceOverrides': {'atg:pullups': pick(null, 80)}});
      final stale = base({'_ts': 300, 'balanceOverrides': {'atg:pullups': pick('0017', 40)}});
      expect(mergeStates(cleared, stale)['balanceOverrides']['atg:pullups'], jeq(pick(null, 80)));
      expect(mergeStates(stale, cleared)['balanceOverrides']['atg:pullups'], jeq(pick(null, 80)));
      final later = base({'_ts': 50, 'balanceOverrides': {'atg:pullups': pick('0652', 95)}});
      expect(mergeStates(cleared, later)['balanceOverrides']['atg:pullups'], jeq(pick('0652', 95)));
    });

    test('roles set on different devices are all kept; a tie or an unstamped entry goes to the newer copy', () {
      final a = base({'_ts': 100, 'balanceOverrides': {'poliquin:dips': pick('0009', 10), 'atg:nordicCurl': '0599'}});
      final b = base({'_ts': 200, 'balanceOverrides': {'poliquin:barbellCurl': pick('0031', 30), 'atg:nordicCurl': '3193'}});
      final m = mergeStates(a, b);
      expect(sorted(M(m['balanceOverrides']).keys.toList()), ['atg:nordicCurl', 'poliquin:barbellCurl', 'poliquin:dips']);
      expect(m['balanceOverrides']['atg:nordicCurl'], '3193');
      expect(mergeStampedMap({'k': pick('x', 5)}, {'k': pick('y', 5)})['k']['id'], 'x');
    });

    test('prefer keeps the preferred side\'s choice; one side without the map keeps the other\'s', () {
      final server = base({'_ts': 10, 'balanceOverrides': {'poliquin:dips': pick('0251', 5)}});
      final local = base({'_ts': 90, 'balanceOverrides': {'poliquin:dips': pick('0009', 80), 'atg:pullups': pick('0017', 80)}});
      final m = mergeStates(server, local, prefer: 'a');
      expect(m['balanceOverrides'], jeq({'poliquin:dips': pick('0251', 5), 'atg:pullups': pick('0017', 80)}));
      final bare = base({'_ts': 500});
      expect(mergeStates(bare, local)['balanceOverrides'], jeq(local['balanceOverrides']));
      expect(M(mergeStates(bare, base({'_ts': 1}))).containsKey('balanceOverrides'), false);
    });

    test('the merged map is a copy, not the input', () {
      final a = base({'_ts': 100, 'balanceOverrides': {'k': pick('x', 1)}});
      final m = mergeStates(a, base({'_ts': 50}));
      m['balanceOverrides']['k']['id'] = 'changed';
      expect(a['balanceOverrides']['k']['id'], 'x');
    });
  });

  group('plate loading keeps the choice made last', () {
    const SQUAT = '0043';

    test('a load kind picked on the older copy survives the newer copy\'s earlier pick', () {
      final phone = base({'_ts': 100, 'loadKind': withLoadKind({}, SQUAT, 'none', 90)});
      final desk = base({'_ts': 200, 'workouts': [workout('w2')], 'loadKind': withLoadKind({}, SQUAT, 'single', 20)});
      for (final m in [mergeStates(phone, desk), mergeStates(desk, phone)]) {
        expect(ids(m['workouts']), ['w2']);
        expect(loadKindFor(m, SQUAT), 'none');
      }
    });

    test('going back to the equipment\'s loading is not undone by an older pick, and a later pick beats it', () {
      final back = base({'_ts': 100, 'loadKind': withLoadKind({}, SQUAT, null, 80)});
      final stale = base({'_ts': 300, 'loadKind': withLoadKind({}, SQUAT, 'single', 40)});
      expect(loadKindFor(mergeStates(back, stale), SQUAT), 'pairs');
      expect(loadKindFor(mergeStates(stale, back), SQUAT), 'pairs');
      final later = base({'_ts': 50, 'loadKind': withLoadKind({}, SQUAT, 'single', 95)});
      expect(loadKindFor(mergeStates(back, later), SQUAT), 'single');
    });

    test('exercises set on different devices are all kept; a bare kind from the first builds loses to a stamped one', () {
      final a = base({'_ts': 100, 'loadKind': {...withLoadKind({}, 'a', 'single', 10), 'c': 'none'}});
      final b = base({'_ts': 200, 'loadKind': {...withLoadKind({}, 'b', 'none', 30), 'c': withLoadKind({}, 'c', 'single', 5)['c']}});
      final m = mergeStates(b, a);
      expect(sorted(M(m['loadKind']).keys.toList()), ['a', 'b', 'c']);
      expect(m['loadKind']['c'], jeq({'kind': 'single', '_ts': 5}));
    });

    test('a unit\'s plate list is kept whole as last counted; the other unit\'s comes along', () {
      final home = withPlatePairs({'unit': 'lb'}, 45, 1, 90);
      final phone = base({'_ts': 100, 'unit': 'lb', 'plates': home});
      final desk = base({'_ts': 200, 'unit': 'lb', 'workouts': [workout('w2')], 'plates': {...withPlatePairs({'unit': 'lb'}, 25, 2, 20), 'kg': {'20': 1, '_ts': 15}}});
      for (final m in [mergeStates(phone, desk), mergeStates(desk, phone)]) {
        expect(m['plates']['lb'], jeq(home['lb']));
        expect(jsFind(inventoryFor(m), (p) => p['w'] == 45)['n'], 1);
        expect(jsFind(inventoryFor(m), (p) => p['w'] == 25)['n'], 6);
        expect(m['plates']['kg'], jeq({'20': 1, '_ts': 15}));
      }
    });

    test('"Back to the standard set" wins against the other device\'s older list', () {
      final own = j({'unit': 'lb', 'plates': withPlatePairs({'unit': 'lb'}, 45, 1, 40)});
      final reset = base({'_ts': 100, 'unit': 'lb', 'plates': withStandardPlates(own, 80)});
      final stale = base({'_ts': 300, 'unit': 'lb', 'plates': own['plates']});
      for (final m in [mergeStates(reset, stale), mergeStates(stale, reset)]) {
        expect(inventoryFor(m), jeq(inventoryFor({'unit': 'lb'})));
      }
    });

    test('sign-in keeps the server\'s choices and adds what only the device has', () {
      final server = base({'_ts': 10, 'loadKind': withLoadKind({}, SQUAT, 'single', 5), 'plates': {'kg': {'20': 1, '_ts': 5}}});
      final local = base({'_ts': 90, 'loadKind': withLoadKind(withLoadKind({}, SQUAT, 'none', 80), 'b', 'single', 80), 'plates': {'kg': {'20': 4, '_ts': 80}, 'lb': {'45': 2, '_ts': 80}}});
      final m = mergeStates(server, local, prefer: 'a');
      expect(m['loadKind'], jeq({SQUAT: {'kind': 'single', '_ts': 5}, 'b': {'kind': 'single', '_ts': 80}}));
      expect(m['plates'], jeq({'kg': {'20': 1, '_ts': 5}, 'lb': {'45': 2, '_ts': 80}}));
      expect(M(mergeStates(base({'_ts': 500}), base({'_ts': 1}))).containsKey('plates'), false);
    });
  });

  group('custom exercises keep the version edited last', () {
    JMap photo(String hash) => j({'kind': 'image', 'hash': hash * 64, 'mime': 'image/webp', 'size': 10, 'width': 4, 'height': 3, 'at': 1});
    JMap cx([Map<String, dynamic> over = const {}]) => j({'id': 'c1', 'n': 'sandbag carry', 'bp': 'back', 'custom': true, ...over});

    test('a photo added on A survives a merge with B, which is newer as a whole', () {
      final A = base({'_ts': 100, 'customEx': [cx({'media': photo('a'), '_ts': 90})]});
      final B = base({'_ts': 200, 'customEx': [cx({'_ts': 10})], 'workouts': [workout('wB')]});
      final out = mergeStates(A, B);
      expect(out['customEx'][0]['media']['hash'], 'a' * 64);
      expect(ids(out['workouts']), ['wB']);
      expect(mergeStates(B, A)['customEx'][0]['media']['hash'], 'a' * 64);
    });

    test('on a tie, or without stamps, the newer copy\'s version stays', () {
      final A = base({'_ts': 100, 'customEx': [cx({'url': 'https://a.example/', '_ts': 7})]});
      final B = base({'_ts': 200, 'customEx': [cx({'url': 'https://b.example/', '_ts': 7})]});
      expect(mergeStates(A, B)['customEx'][0]['url'], 'https://b.example/');
      final C = base({'_ts': 100, 'customEx': [cx({'url': 'https://a.example/'})]});
      final D = base({'_ts': 200, 'customEx': [cx({'url': 'https://b.example/'})]});
      expect(mergeStates(C, D)['customEx'][0]['url'], 'https://b.example/');
    });

    test('sign-in (prefer) keeps the preferred side\'s version whatever the stamps say', () {
      final server = base({'_ts': 100, 'customEx': [cx({'_ts': 1})]});
      final device = base({'_ts': 50, 'customEx': [cx({'media': photo('d'), '_ts': 99})]});
      expect(mergeStates(server, device, prefer: 'a')['customEx'][0]['media'], isNull);
    });

    test('stampCustomEx stamps a new or edited exercise and leaves the rest alone', () {
      final prev = [cx({'_ts': 5}), cx({'id': 'c2', 'n': 'b', '_ts': 5})];
      final next = clone(prev) as List<dynamic>;
      next[0]['media'] = photo('e');
      next.add(cx({'id': 'c3', 'n': 'new'}));
      stampCustomEx(prev, next, 1000);
      expect(next.map((c) => c['_ts']).toList(), [1000, 5, 1000]);
      final again = clone(next) as List<dynamic>;
      again[1]['_ts'] = 6;
      stampCustomEx(next, again, 2000);
      expect(again.map((c) => c['_ts']).toList(), [1000, 6, 1000]);
    });
  });

  group('two copies in different units', () {
    JMap lifted(String id, num w) => j({'id': id, 'd': '2026-09-20', 'start': 1, 'end': 2, 'entries': [{'id': '0025', 'sets': [{'w': w, 'r': 5, 'done': true}]}]});
    final kg = base({'_ts': 300, 'workouts': [lifted('w1', 60), lifted('w-kg', 70)], 'bodyweight': [{'d': '2026-09-27', 'w': 81, 't': 300}], 'exWeights': {'0025': {'w': 55, 'd': '2026-09-20'}}});
    JMap lb() => {...convertStateUnit(base({'_ts': 200, 'workouts': [lifted('w1', 60)], 'exWeights': {'0025': {'w': 55, 'd': '2026-09-20'}}}), 'lb'), 'unitSet': {'at': 200, 'convert': true}};

    test('the unit chosen last stays, and the other copy is converted into it before anything is compared', () {
      for (final m in [mergeStates(kg, lb()), mergeStates(lb(), kg)]) {
        expect(m['unit'], 'lb');
        expect(m['unitSet'], jeq({'at': 200, 'convert': true}));
        expect(byId(m['workouts'], 'w-kg')['entries'][0]['sets'][0]['w'], convertWeight(70, 'kg', 'lb'));
        expect(byId(m['workouts'], 'w1')['entries'][0]['sets'][0]['w'], convertWeight(60, 'kg', 'lb'));
        expect(m['bodyweight'][0]['w'], convertBodyWeight(81, 'kg', 'lb'));
        expect(m['exWeights']['0025']['w'], convertWeight(55, 'kg', 'lb'));
      }
    });

    test('with no switch stamped on either side, the newer copy\'s unit stays', () {
      final old = {...convertStateUnit(base({'_ts': 100, 'workouts': [lifted('w1', 60)]}), 'lb')};
      final m = mergeStates(old, kg);
      expect(m['unit'], 'kg');
      expect(byId(m['workouts'], 'w1')['entries'][0]['sets'][0]['w'], 60);
    });

    test('a label-only switch relabels the other copy instead of converting it', () {
      final relabelled = {...base({'_ts': 200}), 'unit': 'lb', 'unitSet': {'at': 200, 'convert': false}};
      final m = mergeStates(kg, relabelled);
      expect(m['unit'], 'lb');
      expect(byId(m['workouts'], 'w-kg')['entries'][0]['sets'][0]['w'], 70);
      expect(m['bodyweight'][0]['w'], 81);
    });

    test('with prefer (sign-in), the preferred side\'s unit stays', () {
      final m = mergeStates(lb(), kg, prefer: 'a');
      expect(m['unit'], 'lb');
      expect(byId(m['workouts'], 'w-kg')['entries'][0]['sets'][0]['w'], convertWeight(70, 'kg', 'lb'));
    });
  });

  group('a reset holds against a copy that has not seen it', () {
    const R = 5000;
    final reset = base({'_ts': R, 'resetAt': R, 'restSec': 90});
    JMap w(String id, num end, [Map<String, dynamic> extra = const {}]) =>
        j({'id': id, 'd': '2026-09-01', 'start': end - 10, 'end': end, 'entries': [{'id': '0025', 'sets': [{'w': 100, 'r': 5, 'done': true}]}], ...extra});
    final stale = base({
      '_ts': 6000, 'restSec': 45,
      'workouts': [w('old', 1000), w('new', 5500), w('old-edited', 1000, {'_ts': 5600}), w('backfilled', 1000, {'_ts': 5700})],
      'routines': [{'id': 'r-old', 'name': 'old', 'ex': [], '_ts': 100}, {'id': 'r-new', 'name': 'new', 'ex': [], '_ts': 5800}, {'id': 'r-unstamped', 'name': 'x', 'ex': []}],
      'bodyweight': [{'d': '2026-08-01', 'w': 80, 't': 100}, {'d': '2026-09-27', 'w': 81, 't': 5900}],
      'customEx': [{'id': 'c-old', 'n': 'old', '_ts': 100}, {'id': 'c-new', 'n': 'new', '_ts': 5900}],
      'favEx': ['0025'], 'exNotes': {'0025': 'seat 4'}, 'gymCards': [{'id': 'g1', 'value': '123'}],
      'exWeights': {'0025': {'w': 140, 'd': '2026-08-01'}, '0100': {'w': 30, 'd': '2026-08-01'}},
      'loadKind': {'0025': {'kind': 'single', '_ts': 100}, '0100': {'kind': 'pairs', '_ts': 5900}},
    });

    test('without resetIds (a reset from before they were kept) keeps only what the other copy made after it, whichever copy is newer', () {
      for (final m in [mergeStates(reset, stale), mergeStates(stale, reset)]) {
        expect(sorted(ids(m['workouts'])), ['backfilled', 'new', 'old-edited']);
        expect(ids(m['routines']), ['r-new']);
        expect(L(m['bodyweight']).map((e) => e['d']).toList(), ['2026-09-27']);
        expect(ids(m['customEx']), ['c-new']);
        expect(m['favEx'] ?? [], jeq([]));
        expect(m['exNotes'] ?? {}, jeq({}));
        expect(m['gymCards'] ?? [], jeq([]));
        expect(M(m['loadKind']).keys.toList(), ['0100']);
        expect(m['exWeights'], jeq({'0025': {'w': 100, 'd': '2026-09-01'}}));
        expect(m['restSec'], 90);
        expect(m['resetAt'], R);
        expect(m['_ts'], 6000);
      }
    });

    test('two copies that both saw the reset merge as usual', () {
      final after = {...stale, 'resetAt': R};
      expect(ids(mergeStates(reset, after)['workouts']), hasLength(4));
    });

    test('a later reset wins over an earlier one', () {
      final later = base({'_ts': 9000, 'resetAt': 9000});
      expect(mergeStates({...stale, 'resetAt': R}, later)['workouts'], jeq([]));
    });

    test('not on sign-in: the device\'s own entries are not a copy of the account\'s history', () {
      final m = mergeStates(reset, stale, prefer: 'a');
      expect(ids(m['workouts']), hasLength(4));
    });

    test('sinceReset leaves the copy it reads alone', () {
      final before = jsonEncode(stale);
      sinceReset(stale, R);
      sinceReset(stale, R, resetIdsOf(stale));
      expect(jsonEncode(stale), before);
    });
  });

  group('a reset names what it wiped', () {
    final R = DateTime.now().millisecondsSinceEpoch;
    JMap w(String id, num end, [Map<String, dynamic> extra = const {}]) =>
        j({'id': id, 'd': '2026-09-01', 'start': end - 10, 'end': end, 'entries': [{'id': '0025', 'sets': [{'w': 100, 'r': 5, 'done': true}]}], ...extra});
    final before = base({
      '_ts': R - 1000,
      'workouts': [w('old', R - 5000)], 'routines': [{'id': 'r-old', 'name': 'old', 'ex': [], '_ts': R - 5000}],
      'bodyweight': [{'d': '2026-08-01', 'w': 80, 't': R - 5000}], 'customEx': [{'id': 'c-old', 'n': 'old', '_ts': R - 5000}],
      'favEx': ['0025'], 'exNotes': {'0025': 'seat 4'}, 'gymCards': [{'id': 'g1', 'value': '123'}],
      'loadKind': {'0025': {'kind': 'single', '_ts': R - 5000}},
    });
    final reset = base({'_ts': R, 'resetAt': R, 'resetIds': resetIdsOf(before)});

    test('drops exactly the wiped entries of a copy that has not seen the reset', () {
      final stale = j(before);
      stale['_ts'] = R + 10;
      for (final m in [mergeStates(reset, stale), mergeStates(stale, reset)]) {
        expect(m['workouts'], jeq([]));
        expect(m['routines'] ?? [], jeq([]));
        expect(m['bodyweight'], jeq([]));
        expect(m['customEx'] ?? [], jeq([]));
        expect(m['favEx'] ?? [], jeq([]));
        expect(m['exNotes'] ?? {}, jeq({}));
        expect(m['gymCards'] ?? [], jeq([]));
        expect(m['loadKind'] ?? {}, jeq({}));
        expect(m['exWeights'], jeq({}));
        expect(m['resetAt'], R);
      }
    });

    test('keeps a CSV import of old sessions and an old weigh-in history made on that device', () {
      final stale = j(before);
      _mergeImport(stale, j({'kind': 'workouts', 'customEx': [], 'workouts': [{...w('iw1', _dateParse('2024-03-01')), 'd': '2024-03-01'}]}));
      _mergeImport(stale, j({'kind': 'bodyweight', 'bodyweight': [{'d': '2024-03-01', 'w': 80, 't': _dateParse('2024-03-01')}]}));
      final m = mergeStates(stale, reset);
      expect(ids(m['workouts']), ['iw1']);
      expect(L(m['bodyweight']).map((e) => e['d']).toList(), ['2024-03-01']);
    });

    test('keeps a workout logged after the reset on a device whose clock runs behind', () {
      final stale = {...j(before), 'workouts': [...L(before['workouts']), w('after-but-skewed', R - 60000)]};
      expect(ids(mergeStates(stale, reset)['workouts']), ['after-but-skewed']);
    });

    test('keeps entries with no date or stamp at all', () {
      final stale = {...j(before), 'workouts': [j({'id': 'undated', 'entries': []})], 'routines': [j({'id': 'r-unstamped', 'name': 'x', 'ex': []})], 'customEx': [j({'id': 'c-unstamped', 'n': 'x'})]};
      final m = mergeStates(reset, stale);
      expect(ids(m['workouts']), ['undated']);
      expect(ids(m['routines']), ['r-unstamped']);
      expect(ids(m['customEx']), ['c-unstamped']);
    });

    test('the stamp only moves forward: kept by a backup merged over it (keepReset), and with a copy that carries none', () {
      final backup = base({'_ts': 5, 'workouts': [w('restored', 4)]});
      expect(M(mergeStates(backup, reset, prefer: 'a')).containsKey('resetAt'), false);
      final m = keepReset(reset, mergeStates(backup, reset, prefer: 'a'));
      expect(m['resetAt'], R);
      expect(m['resetIds'], jeq(reset['resetIds']));
      expect(ids(m['workouts']), ['restored']);
      final restored = {...backup, 'resetAt': R, 'resetIds': reset['resetIds'], '_ts': R + 5};
      final seen = base({'_ts': R + 1, 'resetAt': R, 'resetIds': reset['resetIds'], 'workouts': [w('gym-today', R + 1)]});
      expect(sorted(ids(mergeStates(seen, restored)['workouts'])), ['gym-today', 'restored']);
    });

    test('keepReset: a replace never takes the stamp back; the same reset\'s names are joined', () {
      final cur = j({'resetAt': R, 'resetIds': {'workouts': ['a']}});
      expect(keepReset(cur, j({'workouts': []})), matchObj({'resetAt': R, 'resetIds': {'workouts': ['a']}}));
      expect(keepReset(cur, j({'resetAt': R + 1, 'resetIds': {'workouts': ['b']}}))['resetIds'], jeq({'workouts': ['b']}));
      expect(keepReset(cur, j({'resetAt': R, 'resetIds': {'workouts': ['b']}}))['resetIds'], jeq({'workouts': ['a', 'b']}));
      expect(keepReset(j({}), j({'workouts': []})), jeq({'workouts': []}));
    });

    test('names are joined across copies and bounded', () {
      expect(mergeResetIds({'workouts': ['a', 'b']}, {'workouts': ['b', 'c'], 'routines': ['r']}), jeq({'workouts': ['a', 'b', 'c'], 'routines': ['r']}));
      final many = List<dynamic>.generate(RESET_ID_MAX + 5, (i) => 'w$i');
      final out = L(mergeResetIds({'workouts': many}, null)['workouts']);
      expect(out, hasLength(RESET_ID_MAX));
      expect(out.last, 'w${RESET_ID_MAX + 4}');
    });
  });

  group('localExtras and the weigh-ins of a day both copies have', () {
    final server = j({'unit': 'kg', 'workouts': [], 'bodyweight': [{'d': '2026-09-27', 'w': 80, 't': 100}]});
    test('counts a same-day weigh-in that differs and was entered later', () {
      expect(localExtras(j({'unit': 'kg', 'bodyweight': [{'d': '2026-09-27', 'w': 81.5, 't': 200}]}), server)['bodyweight'], 1);
    });
    test('not the same reading, nor one the server\'s later entry replaced', () {
      expect(localExtras(j({'unit': 'kg', 'bodyweight': [{'d': '2026-09-27', 'w': 80, 't': 200}]}), server)['bodyweight'], 0);
      expect(localExtras(j({'unit': 'kg', 'bodyweight': [{'d': '2026-09-27', 'w': 82, 't': 50}]}), server)['bodyweight'], 0);
    });
    test('compares in the server\'s unit', () {
      expect(localExtras(j({'unit': 'lb', 'bodyweight': [{'d': '2026-09-27', 'w': convertBodyWeight(80, 'kg', 'lb'), 't': 200}]}), server)['bodyweight'], 0);
    });
  });

  group('a removal holds against a copy that was offline', () {
    final W = j({'id': 'W', 'd': '2026-09-01', 'start': 100, 'end': 200, 'entries': [{'id': '0025', 'sets': [{'w': 150, 'r': 1, 'done': true}]}]});
    final both = base({
      '_ts': 300, 'workouts': [W, workout('keep')], 'routines': [{...routine('r1'), '_ts': 50}],
      'customEx': [{'id': 'c1', 'n': 'Sync me', '_ts': 50}], 'favEx': ['0025', 'c1'], 'gymCards': [{'id': 'g1', 'value': '1'}],
      'bodyweight': [{'d': '2026-09-02', 'w': 80, 't': 60}], 'exWeights': {'0025': {'w': 150, 'd': '2026-09-01'}},
    });
    JMap removedOnA() {
      final a = j(both);
      a['workouts'] = L(a['workouts']).where((w) => w['id'] != 'W').toList();
      a['routines'] = [];
      a['customEx'] = [];
      a['favEx'] = ['0025'];
      a['gymCards'] = [];
      a['bodyweight'] = [];
      a['exWeights'] = <String, dynamic>{};
      a['_ts'] = 1000;
      return stampDeletions(both, a, 1000);
    }

    JMap offlineB() {
      final b = j(both);
      b['bodyweight'] = [...L(b['bodyweight']), j({'d': '2026-09-05', 'w': 79, 't': 2000})];
      b['_ts'] = 2000;
      return b;
    }

    test('stamps what a change removed, and nothing when nothing was', () {
      final a = removedOnA();
      expect(a['deleted'], jeq({
        'workouts': {'W': 1000}, 'routines': {'r1': 1000}, 'customEx': {'c1': 1000},
        'bodyweight': {'2026-09-02': 1000}, 'gymCards': {'g1': 1000}, 'favEx': {'c1': 1000},
      }));
      expect(M(stampDeletions(both, j(both), 1000)).containsKey('deleted'), false);
    });

    test('stays removed, whichever copy is newer', () {
      for (final m in [mergeStates(removedOnA(), offlineB()), mergeStates(offlineB(), removedOnA())]) {
        expect(ids(m['workouts']), ['keep']);
        expect(m['routines'], jeq([]));
        expect(m['customEx'], jeq([]));
        expect(m['favEx'], ['0025']);
        expect(m['gymCards'], jeq([]));
        expect(L(m['bodyweight']).map((e) => e['d']).toList(), ['2026-09-05']);
        expect(M(m['exWeights']).containsKey('0025'), false);
        expect(m['deleted']['workouts'], jeq({'W': 1000}));
      }
    });

    test('an edit made after the removal keeps the entry', () {
      final b = offlineB();
      b['routines'] = [j({...routine('r1', 'edited'), '_ts': 1500})];
      b['workouts'] = L(b['workouts']).map((w) => w['id'] == 'W' ? j({...w, 'note': 'x', '_ts': 1500}) : w).toList();
      final m = mergeStates(removedOnA(), b);
      expect(ids(m['routines']), ['r1']);
      expect(ids(m['workouts']), contains('W'));
    });

    test('a favourite starred again after the removal comes back with it', () {
      final a = removedOnA();
      final again = j(a);
      again['favEx'] = <dynamic>['0025', 'c1'];
      stampDeletions(a, again, 1500);
      expect(again['deleted']['favEx'], jeq({'c1': -1500}));
      expect(sorted(L(mergeStates(again, offlineB())['favEx'])), ['0025', 'c1']);
      expect(mergeDeletions(a['deleted'], again['deleted'])!['favEx'], jeq({'c1': -1500}));
    });
  });

  group('added back means brought back by this change', () {
    JMap update(JMap S, num now, void Function(JMap) mut) {
      final n = j(S);
      mut(n);
      stampDeletions(S, n, now);
      stampEdits(S, n, now);
      n['_ts'] = now;
      return n;
    }

    test('an unrelated edit does not re-stamp an entry the copy only still holds, so a later delete sticks', () {
      final W = j({'id': 'w1', 'd': '2026-10-01', 'start': 1000, 'end': 2000, 'entries': [{'id': 'bench', 'sets': [{'w': 60, 'r': 5}]}]});
      final b0 = j({'unit': 'kg', 'workouts': [W], 'restSec': 90, '_ts': 2000});
      final phone1 = update(b0, 10000, (S) => S['workouts'] = []);
      final laptop1 = update(b0, 20000, (S) {
        stampWorkout(S['workouts'][0], 20000);
        S['workouts'][0]['entries'][0]['sets'][0]['w'] = 62.5;
      });
      final server = mergeStates(laptop1, phone1);
      expect(ids(server['workouts']), ['w1']);
      final phone2 = update(server, 30000, (S) => S['workouts'] = []);
      final laptop2 = update(server, 40000, (S) => S['restSec'] = 120);
      expect(laptop2['deleted']['workouts']['w1'], 10000);
      expect(mergeStates(laptop2, phone2)['workouts'], jeq([]));
    });
    test('a star set on a device that never saw an earlier unstar wins over it', () {
      final b0 = j({'unit': 'kg', 'favEx': [], '_ts': 1});
      var phone = update(b0, 10, (S) => S['favEx'] = ['bench']);
      phone = update(phone, 20, (S) => S['favEx'] = []);
      final tablet = update(b0, 30, (S) => S['favEx'] = ['bench']);
      expect(mergeStates(tablet, phone)['favEx'], ['bench']);
      expect(mergeStates(phone, tablet)['favEx'], ['bench']);
    });
  });

  group('a change is stamped after everything the copy it was made on carries (stampChange)', () {
    final T = DateTime.utc(2026, 10, 6, 12).millisecondsSinceEpoch;
    const DAY = 86400000;
    JMap change(JMap prev, num wall, void Function(JMap) mut) {
      final n = j(prev);
      mut(n);
      n['_ts'] = stampChange(prev, n, wall);
      return n;
    }

    test('a phone a day behind keeps the setting, rename and delete it made after the web change it saw', () {
      final b0 = j({'_ts': T - 3600000, 'restSec': 90, 'routines': [{'id': 'r1', 'name': 'Pull', 'ex': [], '_ts': T - 7200000}],
        'workouts': [{'id': 'w1', 'd': '2026-10-06', 'start': T - 7200000, 'end': T - 3600000, 'entries': []}]});
      final web = change(b0, T, (S) {
        S['restSec'] = 180;
        S['routines'][0]['name'] = 'Push A';
        S['workouts'][0]['note'] = 'x';
        stampWorkout(S['workouts'][0], T);
      });
      final phone = change(web, T + 60000 - DAY, (S) {
        S['restSec'] = 95;
        S['routines'][0]['name'] = 'Push B';
        S['workouts'] = [];
      });
      expect(phone['_ts'], greaterThan(web['_ts']));
      final web2 = change(web, T + 30000, (S) => S['theme'] = 'light');
      for (final m in [mergeStates(web2, phone), mergeStates(phone, web2)]) {
        expect(m['restSec'], 95);
        expect(m['routines'][0]['name'], 'Push B');
        expect(m['workouts'], jeq([]));
        expect(m['theme'], 'light');
      }
    });

    test('a delete is always stamped after the entry it removes', () {
      final b0 = j({'_ts': 10, 'workouts': [{'id': 'dupe', 'd': '2026-10-06', 'start': T - 100, 'end': T}], 'bodyweight': [{'d': '2026-10-06', 'w': 80, 't': T + 7200000}]});
      final n = change(b0, T - DAY, (S) {
        S['workouts'] = [];
        S['bodyweight'] = [];
      });
      expect(n['deleted']['workouts']['dupe'], greaterThan(T));
      expect(n['deleted']['bodyweight']['2026-10-06'], greaterThan(T + 7200000));
    });

    test('a weigh-in logged again after seeing a delete stamped by a clock that runs ahead is kept', () {
      const D = '2026-10-06';
      final b0 = j({'_ts': T - 500000, 'workouts': [], 'bodyweight': [{'d': D, 'w': 82, 't': T - 400000}]});
      final A = change(b0, T + 7200000, (S) => S['bodyweight'] = []);
      final B = change(A, T + 600000, (S) => S['bodyweight'] = [j({'d': D, 'w': 80.4, 't': T + 600000})]);
      final A2 = change(A, T + 7200000 + 5, (S) => S['restSec'] = 120);
      expect(L(mergeStates(A2, B)['bodyweight']).map((e) => e['w']).toList(), [80.4]);
    });

    test('highestStamp reads every kind of stamp', () {
      expect(highestStamp(j({'_ts': 1, 'edited': {'a': 5}, 'deleted': {'workouts': {'x': -9}}, 'routines': [{'_ts': 3, '_f': {'name': 12}}], 'plates': {'kg': {'_ts': 7}}})), 12);
      expect(highestStamp(null), 0);
    });
  });

  group('an entry edited on two devices keeps both edits, field by field', () {
    JMap change(JMap prev, num wall, void Function(JMap) mut) {
      final n = j(prev);
      mut(n);
      n['_ts'] = stampChange(prev, n, wall);
      return n;
    }

    final S0 = base({'_ts': 100,
      'workouts': [{'id': 'w1', 'd': '2026-09-30', 'start': 1, 'end': 2, 'entries': [{'id': 'bench', 'sets': [{'w': 100, 'r': 5}]}]}],
      'routines': [{'id': 'r1', 'name': 'Push', 'ex': [{'id': 'bench', 'sets': 3}], '_ts': 50}],
      'customEx': [{'id': 'c1', 'n': 'Landmine press', 'custom': true, '_ts': 50}],
      'equipProfiles': [{'id': 'eq1', 'name': 'Home', 'equipment': ['dumbbell']}],
      'gymCards': [{'id': 'g1', 'name': 'FitX', 'code': ''}]});

    test('a corrected set and a note, a plan change and a rename, a photo and a rename all survive', () {
      final A = change(S0, 1000, (S) {
        S['workouts'][0]['entries'][0]['sets'][0]['w'] = 110;
        stampWorkout(S['workouts'][0], 1000);
        S['routines'][0]['ex'][0]['sets'] = 5;
        S['customEx'][0]['media'] = {'hash': 'abc', 'kind': 'img'};
        L(S['equipProfiles'][0]['equipment']).add('barbell');
        S['gymCards'][0]['code'] = '4006381333931';
      });
      final B = change(S0, 2000, (S) {
        S['workouts'][0]['note'] = 'shoulder hurt';
        stampWorkout(S['workouts'][0], 2000);
        S['routines'][0]['name'] = 'Push heavy';
        S['customEx'][0]['n'] = 'Landmine press (1 arm)';
        S['gymCards'][0]['name'] = 'FitX Mitte';
        S['bodyweight'] = [j({'d': '2026-10-06', 'w': 80, 't': 2000})];
      });
      for (final m in [mergeStates(A, B), mergeStates(B, A)]) {
        expect(m['workouts'][0]['entries'][0]['sets'][0]['w'], 110);
        expect(m['workouts'][0]['note'], 'shoulder hurt');
        expect(m['routines'][0], matchObj({'name': 'Push heavy', 'ex': [{'id': 'bench', 'sets': 5}]}));
        expect(m['customEx'][0], matchObj({'n': 'Landmine press (1 arm)', 'media': {'hash': 'abc'}}));
        expect(m['equipProfiles'][0]['equipment'], ['dumbbell', 'barbell']);
        expect(m['gymCards'][0], matchObj({'name': 'FitX Mitte', 'code': '4006381333931'}));
      }
    });

    test('the same field edited on both: the later edit wins, a removal included', () {
      final A = change(S0, 1000, (S) {
        S['workouts'][0]['note'] = 'first';
        stampWorkout(S['workouts'][0], 1000);
      });
      final B = change(A, 2000, (S) {
        M(S['workouts'][0]).remove('note');
        stampWorkout(S['workouts'][0], 2000);
      });
      final A2 = change(A, 3000, (S) => S['bodyweight'] = [j({'d': '2026-10-06', 'w': 80, 't': 3000})]);
      expect(M(mergeStates(A2, B)['workouts'][0]).containsKey('note'), false);
      expect(M(mergeStates(B, A2)['workouts'][0]).containsKey('note'), false);
    });

    test('a card or profile edited after a delete elsewhere is kept, as other entries are', () {
      final del = change(S0, 1000, (S) => S['gymCards'] = []);
      final ed = change(S0, 2000, (S) => S['gymCards'][0]['code'] = '1');
      expect(ids(mergeStates(del, ed)['gymCards']), ['g1']);
    });
  });

  group('settings and plan days keep the change made last', () {
    JMap start() => base({'_ts': 100, 'week': {'1': ['r1']}, 'restSec': 90, 'sound': true, 'exNotes': {'0025': 'seat 4'}});
    JMap onB() {
      final b = start();
      final next = j(b);
      next['week']['3'] = ['upperB'];
      next['restSec'] = 120;
      M(next['exNotes']).remove('0025');
      next['_ts'] = 500;
      return stampEdits(b, next, 500);
    }

    JMap onA() {
      final a = start();
      final next = j(a);
      next['sound'] = false;
      next['bodyweight'] = [j({'d': '2026-09-05', 'w': 79, 't': 900})];
      next['_ts'] = 900;
      return stampEdits(a, next, 900);
    }

    test('stamps each changed setting and plan day on its own', () {
      expect(onB()['edited'], jeq({'week.3': 500, 'restSec': 500, 'exNotes.0025': 500}));
      expect(onA()['edited'], jeq({'sound': 900}));
    });

    test('takes each from the copy that changed it, whichever copy is newer', () {
      for (final m in [mergeStates(onA(), onB()), mergeStates(onB(), onA())]) {
        expect(m['week'], jeq({'1': ['r1'], '3': ['upperB']}));
        expect(m['restSec'], 120);
        expect(m['sound'], false);
        expect(m['exNotes'], jeq({}));
        expect(L(m['bodyweight']).map((e) => e['d']).toList(), ['2026-09-05']);
        expect(m['edited'], jeq({'week.3': 500, 'restSec': 500, 'exNotes.0025': 500, 'sound': 900}));
      }
    });

    test('a later change of the same day wins, a removal included', () {
      final a = onA();
      final next = j(a);
      next['week']['3'] = ['legs'];
      next['restSec'] = 60;
      stampEdits(a, next, 1000);
      expect(mergeStates(onB(), next)['week'], jeq({'1': ['r1'], '3': ['legs']}));
      expect(mergeStates(onB(), next)['restSec'], 60);
      final seen = mergeStates(onA(), onB());
      final cleared = j(seen);
      M(cleared['week']).remove('3');
      stampEdits(seen, cleared, 1000);
      for (final m in [mergeStates(onB(), cleared), mergeStates(cleared, onB())]) {
        expect(m['week'], jeq({'1': ['r1']}));
      }
    });

    test('a rotation refill on one device survives a setting saved later on the other', () {
      final s0 = base({'_ts': 100, 'queue': {'ids': ['a', 'b'], 'since': 1, 'startsOn': '2026-09-01', 'rotationId': 'r'}, 'rotation': {'id': 'r', 'sequence': ['a', 'b']}});
      final phone = j(s0);
      phone['queue'] = j({'ids': ['a', 'b'], 'since': 400, 'startsOn': '2026-09-06', 'rotationId': 'r'});
      phone['_ts'] = 400;
      stampEdits(s0, phone, 400);
      final desk = j(s0);
      desk['restSec'] = 45;
      desk['_ts'] = 800;
      stampEdits(s0, desk, 800);
      for (final m in [mergeStates(phone, desk), mergeStates(desk, phone)]) {
        expect(m['queue']['since'], 400);
        expect(m['restSec'], 45);
      }
    });

    test('unstamped copies still follow the newer one; sign-in keeps the preferred side', () {
      final m = mergeStates(base({'_ts': 1, 'restSec': 30}), base({'_ts': 2, 'restSec': 60}));
      expect(m['restSec'], 60);
      final signIn = mergeStates(base({'_ts': 1, 'restSec': 30}), onB(), prefer: 'a');
      expect(signIn['restSec'], 30);
    });
  });

  group('a reset leads the unit over a copy that switched before it', () {
    test('the reset copy is in kg, the stale lb copy is converted into it', () {
      const R = 5000;
      final reset = base({'_ts': R, 'resetAt': R, 'unit': 'kg', 'resetIds': {'bodyweight': ['2026-08-01|100']}});
      final stale = base({
        '_ts': 6000, 'unit': 'lb', 'unitSet': {'at': 100, 'convert': true}, 'restSec': 45,
        'bodyweight': [{'d': '2026-08-01', 'w': 176, 't': 100}, {'d': '2026-09-27', 'w': 220, 't': 5900}],
      });
      for (final m in [mergeStates(reset, stale), mergeStates(stale, reset)]) {
        expect(m['unit'], 'kg');
        expect(M(m).containsKey('unitSet'), false);
        expect(m['bodyweight'], jeq([{'d': '2026-09-27', 'w': convertBodyWeight(220, 'lb', 'kg'), 't': 5900}]));
        expect(m['restSec'], 90);
      }
    });
  });

  group('body measurements across devices (#82)', () {
    final b = {'unit': 'kg', '_ts': 100};
    test('keeps both devices\' check-ins, and of one day the one saved later', () {
      final phone = j({...b, '_ts': 300, 'measurements': [{'d': '2026-10-01', 't': 200, 'waist': 80}, {'d': '2026-10-03', 't': 300, 'waist': 79}]});
      final desk = j({...b, '_ts': 250, 'measurements': [{'d': '2026-10-01', 't': 250, 'waist': 81}, {'d': '2026-10-02', 't': 250, 'chest': 100}]});
      final out = mergeStates(phone, desk);
      expect(L(out['measurements']).map((e) => e['d']).toList(), ['2026-10-01', '2026-10-02', '2026-10-03']);
      expect(out['measurements'][0]['waist'], 81);
    });
    test('a check-in deleted on one device stays deleted', () {
      final prev = j({...b, 'measurements': [{'d': '2026-10-01', 't': 200, 'waist': 80}]});
      final next = stampDeletions(prev, j({...b, 'measurements': []}), 500);
      expect(next['deleted']['measurements']['2026-10-01'], 500);
      final out = mergeStates({...next, '_ts': 500}, {...prev, '_ts': 300});
      expect(out['measurements'] ?? [], jeq([]));
    });
    test('a check-in edited now wins over the other device\'s older copy of that day', () {
      final prev = j({...b, 'measurements': [{'d': '2026-10-01', 't': 200, 'waist': 80}]});
      final next = j({...b, 'measurements': [{'d': '2026-10-01', 't': 201, 'waist': 78}]});
      stampChange(prev, next, 1000);
      expect(next['measurements'][0]['t'], 1000);
    });
  });
}
