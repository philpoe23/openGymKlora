// Port of frontend/src/lib/queue.test.js.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/queue.dart';

import '_helpers.dart';

final routines = <dynamic>[
  {'id': 'd1', 'name': 'US W1 D1'},
  {'id': 'd2', 'name': 'US W1 D2'},
  {'id': 'd3', 'name': 'US W1 D3'},
  {'id': 'own', 'name': 'Core'},
];
int parseLocal(String s) => DateTime.parse(s).millisecondsSinceEpoch;
final SINCE = parseLocal('2026-09-07T08:00:00');
const TODAY = '2026-09-09';

Map<String, dynamic> baseQueue() =>
    <String, dynamic>{'ids': ['d1', 'd2', 'd3'], 'since': SINCE, 'startsOn': '2026-09-07', 'label': 'US W1'};

Map<String, dynamic> S([Map<String, dynamic> over = const {}]) => <String, dynamic>{
      'routines': routines,
      'workouts': <dynamic>[],
      'queue': baseQueue(),
      ...over,
    };

Map<String, dynamic> w([Map<String, dynamic> over = const {}]) => <String, dynamic>{
      'id': 'w',
      'd': '2026-09-08',
      'start': SINCE + 3600000,
      'routineIds': <dynamic>[],
      'routineId': null,
      'name': '',
      ...over,
    };

void main() {
  group('DONE RULE', () {
    test('a finished workout on the routine, started at or after the apply, marks it done', () {
      expect(queueDone(S({'workouts': [w({'routineIds': ['d1'], 'start': SINCE, 'name': 'US W1 D1'})]})), jeq(['d1']));
      expect(queueRemaining(S({'workouts': [w({'routineIds': ['d1'], 'start': SINCE})]})), jeq(['d2', 'd3']));
    });

    test("a workout from before the apply is last week's, unless its name says otherwise", () {
      final old = w({'routineIds': ['d1'], 'start': SINCE - 1, 'name': 'Push'});
      expect(queueDone(S({'workouts': [old]})), jeq([]));
      final adopted = w({'routineIds': ['d1'], 'start': SINCE - 86400000, 'name': 'US W1 D1 + Core'});
      expect(queueDone(S({'workouts': [adopted]})), jeq(['d1']));
    });

    test("a past week's workout that carries this week's name does not count — the name clause is bounded to the week", () {
      final lastMonth = w({'routineIds': ['d2'], 'start': SINCE - 8 * 86400000, 'd': '2026-08-30', 'name': 'US W1 D2'});
      expect(queueDone(S({'workouts': [lastMonth]})), jeq([]));
      final backfilled = w({'routineIds': ['d2'], 'start': SINCE - 86400000, 'd': '2026-09-07', 'name': 'US W1 D2'});
      expect(queueDone(S({'workouts': [backfilled]})), jeq(['d2']));
    });

    test('the routine id has to be on the workout — a name alone is not enough', () {
      expect(queueDone(S({'workouts': [w({'routineIds': ['x'], 'name': 'US W1 D1'})]})), jeq([]));
      expect(queueDone(S({'workouts': [w({'routineIds': [], 'name': 'US W1 D1'})]})), jeq([]));
    });

    test('reads the legacy scalar routineId on a workout from before routineIds existed', () {
      expect(queueDone(S({'workouts': [w({'routineIds': null, 'routineId': 'd2'})]})), jeq(['d2']));
      expect(queueDone(S({'workouts': [w({'routineIds': [], 'routineId': 'd2'})]})), jeq([]));
    });

    test('a merged session counts for every routine in it', () {
      expect(queueDone(S({'workouts': [w({'routineIds': ['d1', 'd3']})]})), jeq(['d1', 'd3']));
      expect(queueRemaining(S({'workouts': [w({'routineIds': ['d1', 'd3']})]})), jeq(['d2']));
    });

    test('a workout with no start (imported history) counts only through its name', () {
      expect(queueDone(S({'workouts': [w({'routineIds': ['d1'], 'start': null, 'name': 'Push'})]})), jeq([]));
      expect(queueDone(S({'workouts': [w({'routineIds': ['d1'], 'start': null, 'name': 'US W1 D1'})]})), jeq(['d1']));
    });

    test('the session in progress never counts — only finished workouts do', () {
      final s = S({'active': {'id': 'a', 'routineIds': ['d1'], 'start': SINCE + 1, 'name': 'US W1 D1'}});
      expect(queueDone(s), jeq([]));
      expect(queueRemaining(s), jeq(['d1', 'd2', 'd3']));
    });

    test('without a queue nothing is done, nothing remains, and there is no view', () {
      final s = S({'queue': null, 'workouts': [w({'routineIds': ['d1']})]});
      expect(queueDone(s), jeq([]));
      expect(queueRemaining(s), jeq([]));
      expect(queueNext(s, TODAY, TODAY), isNull);
      expect(queueView(s, TODAY), isNull);
    });

    test('a queue of the wrong shape reads as no queue instead of throwing', () {
      for (final queue in <dynamic>[<String, dynamic>{}, {'ids': 'd1'}, 'd1', 7]) {
        expect(queueRemaining(S({'queue': queue})), jeq([]));
        expect(queueNext(S({'queue': queue}), TODAY, TODAY), isNull);
        expect(queueView(S({'queue': queue}), TODAY), isNull);
      }
    });
  });

  group('queueNext', () {
    test('answers on today once the week is active, and on no other day', () {
      expect(queueNext(S(), TODAY, TODAY), 'd1');
      expect(queueNext(S(), '2026-09-08', TODAY), isNull);
      expect(queueNext(S(), '2026-09-10', TODAY), isNull);
    });

    test('moves on to the next undone session in slot order', () {
      expect(queueNext(S({'workouts': [w({'routineIds': ['d1']})]}), TODAY, TODAY), 'd2');
      expect(queueNext(S({'workouts': [w({'routineIds': ['d2']})]}), TODAY, TODAY), 'd1');
    });

    test('while the week waits on a future startsOn, the session sits on that day, not on today', () {
      final s = S({'queue': {...baseQueue(), 'startsOn': '2026-09-14'}});
      expect(queueNext(s, TODAY, TODAY), isNull);
      expect(queueNext(s, '2026-09-14', TODAY), 'd1');
      expect(queueNext(s, '2026-09-15', TODAY), isNull);
    });

    test('is null once the week is complete', () {
      final s = S({'workouts': [w({'routineIds': ['d1', 'd2', 'd3']})]});
      expect(queueNext(s, TODAY, TODAY), isNull);
    });
  });

  group('pins — a session given a day (S.dayPlan[iso] = queue routine id)', () {
    const FRI = '2026-09-11';
    test('a session pinned to another day is skipped by the floating rule until that day', () {
      expect(queueNext(S({'dayPlan': {FRI: 'd1'}}), TODAY, TODAY), 'd2');
      expect(queueNext(S({'dayPlan': {TODAY: 'd3'}}), TODAY, TODAY), 'd3');
      expect(queueNext(S({'dayPlan': {FRI: 'd1', '2026-09-12': 'd2', '2026-09-13': 'd3'}}), TODAY, TODAY), isNull);
    });

    test('a pin on a past day is stale, and a pin on a done session is fulfilled: both let the session float', () {
      expect(queueNext(S({'dayPlan': {'2026-09-08': 'd1'}}), TODAY, TODAY), 'd1');
      final done = S({'dayPlan': {FRI: 'd1'}, 'workouts': [w({'routineIds': ['d1']})]});
      expect(queueNext(done, TODAY, TODAY), 'd2');
      expect(pinState(done, 'd1'), 'done');
    });

    test('pinState: open for a session still to do, done once logged, null for anything else', () {
      expect(pinState(S(), 'd2'), 'open');
      expect(pinState(S({'workouts': [w({'routineIds': ['d2']})]}), 'd2'), 'done');
      expect(pinState(S(), 'own'), isNull);
      expect(pinState(S(), 'rest'), isNull);
      expect(pinState(S(), null), isNull);
      expect(pinState(S({'queue': null}), 'd1'), isNull);
      expect(pinState(S({'routines': routines.where((r) => r['id'] != 'd1').toList()}), 'd1'), isNull);
    });

    test('a pin dated between today and a future startsOn is honoured on its day, and skipped on the start day', () {
      final s = S({'queue': {...baseQueue(), 'startsOn': '2026-09-14'}, 'dayPlan': {'2026-09-12': 'd1'}});
      expect(queueNext(s, '2026-09-14', TODAY), 'd2');
      expect(queueNext(s, TODAY, TODAY), isNull);
      expect(pinState(s, 'd1'), 'open');
    });

    test('queueView lights the floating session and shows a pinned one with its day', () {
      final v = queueView(S({'dayPlan': {FRI: 'd1', '2026-09-13': 'd1'}}), TODAY)!;
      expect(v['items'], jeq([
        {'id': 'd1', 'name': 'US W1 D1', 'state': 'pinned', 'on': FRI},
        {'id': 'd2', 'name': 'US W1 D2', 'state': 'next'},
        {'id': 'd3', 'name': 'US W1 D3', 'state': 'later'},
      ]));
      final today = queueView(S({'dayPlan': {TODAY: 'd3'}}), TODAY)!;
      expect((today['items'] as List).map((i) => i['state']).toList(), jeq(['later', 'later', 'next']));
      final all = queueView(S({'dayPlan': {FRI: 'd1', '2026-09-12': 'd2', '2026-09-13': 'd3'}}), TODAY)!;
      expect((all['items'] as List).map((i) => i['state']).toList(), jeq(['pinned', 'pinned', 'pinned']));
      expect((all['items'] as List).map((i) => i['on']).toList(), jeq([FRI, '2026-09-12', '2026-09-13']));
      final done = queueView(S({'dayPlan': {FRI: 'd1'}, 'workouts': [w({'routineIds': ['d1']})]}), TODAY)!;
      expect((done['items'] as List)[0], jeq({'id': 'd1', 'name': 'US W1 D1', 'state': 'done'}));
    });

    test('pins never change the tally', () {
      expect(weekTally(S({'dayPlan': {FRI: 'd1'}}), TODAY), jeq({'done': 0, 'planned': 3}));
      expect(queueRemaining(S({'dayPlan': {FRI: 'd1'}})), jeq(['d1', 'd2', 'd3']));
    });
  });

  group('queueView', () {
    test('lists the sessions in slot order with one lit as next', () {
      final v = queueView(S({'workouts': [w({'routineIds': ['d1']})]}), TODAY)!;
      expect(v['label'], 'US W1');
      expect(v['items'], jeq([
        {'id': 'd1', 'name': 'US W1 D1', 'state': 'done'},
        {'id': 'd2', 'name': 'US W1 D2', 'state': 'next'},
        {'id': 'd3', 'name': 'US W1 D3', 'state': 'later'},
      ]));
      expect(v['remaining'], jeq(['d2', 'd3']));
      expect(v, matchObj({'complete': false, 'startsOn': '2026-09-07', 'waiting': false}));
    });

    test('says the week is waiting before startsOn, and still names the next session', () {
      final v = queueView(S({'queue': {...baseQueue(), 'startsOn': '2026-09-14'}}), TODAY)!;
      expect(v['waiting'], true);
      expect(v['items'][0]['state'], 'next');
      expect(v['startsOn'], '2026-09-14');
    });

    test('a complete week has every chip done and nothing remaining', () {
      final v = queueView(S({'workouts': [w({'routineIds': ['d1', 'd2', 'd3']})]}), TODAY)!;
      expect((v['items'] as List).map((i) => i['state']).toList(), jeq(['done', 'done', 'done']));
      expect(v, matchObj({'remaining': [], 'complete': true}));
    });

    test('a session whose routine no longer exists is dropped from the week, not pinned as next forever', () {
      final v = queueView(S({'queue': {...baseQueue(), 'ids': ['gone', 'd1', 'd2']}}), TODAY)!;
      expect((v['items'] as List).map((i) => i['id']).toList(), jeq(['d1', 'd2']));
      expect(v['items'][0]['state'], 'next');
      expect(queueRemaining(S({'queue': {...baseQueue(), 'ids': ['gone', 'd1']}})), jeq(['d1']));
      expect(queueNext(S({'queue': {...baseQueue(), 'ids': ['gone', 'd1']}}), TODAY, TODAY), 'd1');
      expect(queueView(S({'queue': {...baseQueue(), 'ids': ['gone']}}), TODAY), isNull);
      expect(queueNext(S({'queue': {...baseQueue(), 'ids': ['gone']}}), TODAY, TODAY), isNull);
    });

    test('a queue without a startsOn is active since the day of the apply, not silently dead', () {
      final noStart = S({'queue': {'ids': ['d1', 'd2'], 'since': SINCE, 'label': 'US W1'}});
      expect(queueNext(noStart, TODAY, TODAY), 'd1');
      expect(queueView(noStart, TODAY), matchObj({'waiting': false, 'startsOn': '2026-09-07'}));
      final nullStart = S({'queue': {'ids': ['d1'], 'since': SINCE, 'startsOn': null, 'label': 'US W1'}});
      expect(queueNext(nullStart, TODAY, TODAY), 'd1');
    });
  });

  group('weekTally — the streak card fraction', () {
    Map<String, dynamic> own(String d, [Map<String, dynamic> over = const {}]) => w({
          'id': 'own-$d',
          'd': d,
          'start': parseLocal('${d}T18:00:00'),
          'routineIds': ['own'],
          'name': 'Core',
          ...over,
        });

    test("without a queue: this calendar week's workouts over the weekdays with a plan, as before", () {
      final s = S({'queue': null, 'week': {'1': ['own'], '3': ['own', 'd1'], '5': []}, 'workouts': [own('2026-09-07'), own('2026-09-05')]});
      expect(weekTally(s, TODAY), jeq({'done': 1, 'planned': 2}));
      expect(weekTally(S({'queue': null}), TODAY), jeq({'done': 0, 'planned': 0}));
    });

    test('the own half of a merged session stays done after its routine is deleted; only the plan forgets it', () {
      final noOwn = routines.where((r) => r['id'] != 'own').toList();
      final merged = w({'routineIds': ['d1', 'own'], 'name': 'US W1 D1 + Core'});
      expect(weekTally(S({'routines': noOwn, 'workouts': [merged]}), TODAY), jeq({'done': 2, 'planned': 3}));
      expect(weekTally(S({'routines': noOwn, 'week': {'3': ['own']}, 'workouts': [merged]}), TODAY), jeq({'done': 2, 'planned': 3}));
      final split = [
        w({'id': 'a', 'routineIds': ['d1'], 'name': 'US W1 D1'}),
        w({'id': 'b', 'start': SINCE + 7200000, 'routineIds': ['own'], 'name': 'Core'}),
      ];
      expect(weekTally(S({'routines': noOwn, 'workouts': split}), TODAY), jeq({'done': 2, 'planned': 3}));
    });

    test('a weekday pointing only at a deleted routine is not a planned day — the strip shows it as rest', () {
      expect(weekTally(S({'queue': null, 'week': {'3': ['gone']}}), TODAY), jeq({'done': 0, 'planned': 0}));
      expect(weekTally(S({'queue': null, 'week': {'3': ['gone', 'own'], '5': 'gone'}}), TODAY), jeq({'done': 0, 'planned': 1}));
      expect(weekTally(S({'week': {'3': ['gone']}}), TODAY), jeq({'done': 0, 'planned': 3}));
    });

    test("a coach week alone: the queue's sessions, done by the DONE RULE, whatever calendar week they fell in", () {
      expect(weekTally(S(), TODAY), jeq({'done': 0, 'planned': 3}));
      expect(weekTally(S({'workouts': [w({'routineIds': ['d1']})]}), TODAY), jeq({'done': 1, 'planned': 3}));
      final s = S({
        'queue': {...baseQueue(), 'since': SINCE - 7 * 86400000, 'startsOn': '2026-08-31'},
        'workouts': [w({'routineIds': ['d1'], 'd': '2026-09-04', 'start': SINCE - 5 * 86400000})],
      });
      expect(weekTally(s, TODAY), jeq({'done': 1, 'planned': 3}));
    });

    test('your own weekday rides along: one more planned, and its workout this week one more done', () {
      final s = S({'week': {'3': ['own']}, 'workouts': [w({'routineIds': ['d1']}), own('2026-09-09')]});
      expect(weekTally(s, TODAY), jeq({'done': 2, 'planned': 4}));
      expect(weekTally(S({'week': {'3': ['own']}, 'workouts': [own('2026-09-02')]}), TODAY), jeq({'done': 0, 'planned': 4}));
    });

    test("a weekday that holds only queue routines (the planner's old pointers) adds no day", () {
      expect(weekTally(S({'week': {'1': ['d1'], '3': ['d2'], '5': ['d3']}}), TODAY), jeq({'done': 0, 'planned': 3}));
      expect(weekTally(S({'week': {'1': ['d1', 'own']}}), TODAY), jeq({'done': 0, 'planned': 4}));
      expect(weekTally(S({'queue': {...baseQueue(), 'ids': ['d1', 'd2', 'gone']}, 'week': {'5': ['gone']}}), TODAY), jeq({'done': 0, 'planned': 2}));
    });

    test("a merged session counts for both sides — following the app's own daily proposal all week ends at 4 / 4", () {
      final merged = w({'routineIds': ['d1', 'own'], 'name': 'US W1 D1 + Core'});
      expect(weekTally(S({'week': {'3': ['own']}, 'workouts': [merged]}), TODAY), jeq({'done': 2, 'planned': 4}));
      final week = [
        w({'id': 'mon', 'd': '2026-09-07', 'start': SINCE + 3600000, 'routineIds': ['d1'], 'name': 'US W1 D1'}),
        w({'id': 'wed', 'd': '2026-09-09', 'start': SINCE + 2 * 86400000, 'routineIds': ['d2', 'own'], 'name': 'US W1 D2 + Core'}),
        w({'id': 'fri', 'd': '2026-09-11', 'start': SINCE + 4 * 86400000, 'routineIds': ['d3'], 'name': 'US W1 D3'}),
      ];
      expect(weekTally(S({'week': {'3': ['own']}, 'workouts': week}), '2026-09-13'), jeq({'done': 4, 'planned': 4}));
      expect(queueDone(S({'workouts': week})), jeq(['d1', 'd2', 'd3']));
    });

    test('every other workout is training on top: freestyle, a redo of a done session, a pre-apply coach-routine one', () {
      final redo = w({'id': 'w2', 'd': '2026-09-09', 'start': SINCE + 2 * 86400000, 'routineIds': ['d1'], 'name': 'US W1 D1'});
      expect(weekTally(S({'workouts': [w({'routineIds': ['d1']}), redo]}), TODAY), jeq({'done': 2, 'planned': 3}));
      expect(queueDone(S({'workouts': [w({'routineIds': ['d1']}), redo]})), jeq(['d1']));
      final long = {...baseQueue(), 'since': SINCE - 7 * 86400000, 'startsOn': '2026-08-31'};
      final sat = w({'id': 'sat', 'd': '2026-09-05', 'start': SINCE - 2 * 86400000, 'routineIds': ['d1'], 'name': 'US W1 D1'});
      expect(weekTally(S({'queue': long, 'workouts': [sat, redo]}), TODAY), jeq({'done': 2, 'planned': 3}));
      expect(weekTally(S({'queue': long, 'workouts': [redo, sat]}), TODAY), jeq({'done': 2, 'planned': 3}));
      final freestyle = w({'routineIds': [], 'name': 'Freestyle', 'd': '2026-09-08'});
      expect(weekTally(S({'workouts': [freestyle]}), TODAY), jeq({'done': 1, 'planned': 3}));
      final before = w({'routineIds': ['d1'], 'name': 'US W3 D1', 'd': '2026-09-07', 'start': SINCE - 3600000});
      expect(weekTally(S({'workouts': [before]}), TODAY), jeq({'done': 1, 'planned': 3}));
      expect(queueDone(S({'workouts': [before]})), jeq([]));
    });

    test("a queue waiting on a future startsOn is next week's plan: the card counts this calendar week alone", () {
      final days = ['2026-09-07', '2026-09-08', '2026-09-10'];
      final w1 = [
        for (var i = 0; i < days.length; i++)
          w({'id': 'w$i', 'd': days[i], 'start': parseLocal('${days[i]}T18:00:00'), 'routineIds': ['d${i + 1}'], 'name': 'US W1 D${i + 1}'}),
      ];
      final w2 = {'ids': ['d1', 'd2', 'd3', 'own'], 'since': parseLocal('2026-09-10T21:00:00'), 'startsOn': '2026-09-14', 'label': 'US W2'};
      expect(weekTally(S({'queue': w2, 'workouts': w1}), '2026-09-11'), jeq({'done': 3, 'planned': 0}));
      expect(weekTally(S({'queue': w2, 'week': {'5': ['own']}, 'workouts': w1}), '2026-09-11'), jeq({'done': 3, 'planned': 1}));
      expect(weekTally(S({'queue': w2, 'week': {'5': ['own']}, 'workouts': w1}), '2026-09-14'), jeq({'done': 0, 'planned': 4}));
    });

    test("follows the week-start setting: a Sunday workout is this week's for a Sunday start, last week's for Monday", () {
      final s = S({'queue': null, 'week': {'0': ['own']}, 'workouts': [own('2026-09-06')]});
      expect(weekTally({...s, 'weekStart': 0}, TODAY), jeq({'done': 1, 'planned': 1}));
      expect(weekTally({...s, 'weekStart': 1}, TODAY), jeq({'done': 0, 'planned': 1}));
    });
  });

  group('queueOf — the shared normalization', () {
    test('keeps the first occurrence of a repeated id and drops deleted ones', () {
      final st = S({'queue': {'ids': ['d1', 'd2', 'd1', 'gone'], 'since': SINCE, 'startsOn': '2026-09-07', 'label': 'US W1'}});
      expect(queueOf(st)!['ids'], jeq(['d1', 'd2']));
      expect(st['queue']['ids'], jeq(['d1', 'd2', 'd1', 'gone']));
    });

    test('a malformed, duplicate-only or all-deleted queue reads as no queue', () {
      expect(queueOf(S({'queue': null})), isNull);
      expect(queueOf(S({'queue': {'ids': 'nope'}})), isNull);
      expect(queueOf(S({'queue': {'ids': ['gone'], 'since': SINCE}})), isNull);
    });

    test('a repeated id is one chip, not two', () {
      final st = S({'queue': {'ids': ['d1', 'd1', 'd2'], 'since': SINCE, 'startsOn': '2026-09-07', 'label': 'US W1'}});
      expect((queueView(st, TODAY)!['items'] as List).map((i) => i['id']).toList(), jeq(['d1', 'd2']));
    });
  });
}
