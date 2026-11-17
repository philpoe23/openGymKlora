// Port of the refillAfter cases of frontend/src/lib/rotation.test.js ("refilling a completed
// managed pass"); the rest of rotation.js is not ported (the client never edits a rotation).
// ignore_for_file: constant_identifier_names, non_constant_identifier_names
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/queue.dart';
import 'package:klora_app/engine/rotation.dart';

final routines = <dynamic>[
  {'id': 'a', 'name': 'A'},
  {'id': 'b', 'name': 'B'},
  {'id': 'c', 'name': 'C'},
  {'id': 'own', 'name': 'Core'},
];
const TODAY = '2026-09-12';
final NOW = DateTime.parse('${TODAY}T10:00:00').millisecondsSinceEpoch;

Map<String, dynamic> S([Map<String, dynamic> over = const {}]) => <String, dynamic>{
  'routines': routines,
  'workouts': <dynamic>[],
  'week': <String, dynamic>{},
  'dayPlan': <String, dynamic>{},
  'queue': null,
  'rotation': null,
  ...over,
};

Map<String, dynamic> w(String id, String d, [int? start]) => <String, dynamic>{
  'id': 'w-$id$d',
  'd': d,
  'start': start ?? NOW - 1000,
  'routineIds': [id],
  'routineId': id,
  'name': (routines.firstWhere((r) => r['id'] == id) as Map)['name'],
  'entries': <dynamic>[],
};

Map<String, dynamic> pass(List<String> ids, [Map<String, dynamic> over = const {}]) => <String, dynamic>{
  'ids': ids,
  'since': NOW - 86400000,
  'startsOn': '2026-09-10',
  'label': 'Rotation',
  ...over,
};

Map<String, dynamic> managed(List<String> ids, List<dynamic> workouts) => S({
  'rotation': {
    'id': 'r1',
    'sequence': ['a', 'b', 'c'],
    'label': 'My split',
  },
  'queue': pass(ids, {'rotationId': 'r1'}),
  'workouts': workouts,
});

void main() {
  group('refilling a completed managed pass', () {
    test('completed in order refills in the same order, starting tomorrow', () {
      final last = w('c', TODAY);
      final s = managed(['a', 'b', 'c'], [w('a', '2026-09-10'), w('b', '2026-09-11'), last]);
      expect(refillAfter(s, last, TODAY, NOW), true);
      expect(s['queue'], {
        'ids': ['a', 'b', 'c'],
        'since': NOW,
        'startsOn': '2026-09-13',
        'label': 'My split',
        'rotationId': 'r1',
      });
    });

    test('the routine that closed the pass is the one the next pass ends with', () {
      final last = w('b', TODAY);
      final s = managed(['a', 'b', 'c'], [w('c', '2026-09-10'), w('a', '2026-09-11'), last]);
      expect(refillAfter(s, last, TODAY, NOW), true);
      expect(s['queue']['ids'], ['c', 'a', 'b']);
    });

    test('a merged session credits every matching item; the last one in slot order sets the next pass', () {
      final merged = <String, dynamic>{
        'id': 'm',
        'd': TODAY,
        'start': NOW - 1000,
        'routineIds': ['a', 'b'],
        'routineId': 'a',
        'name': 'A + B',
        'entries': <dynamic>[],
      };
      final s = managed(['c', 'a', 'b'], [w('c', '2026-09-10'), merged]);
      expect(refillAfter(s, merged, TODAY, NOW), true);
      expect(s['queue']['ids'], ['c', 'a', 'b']);
    });

    test('an incomplete pass is left alone', () {
      final last = w('a', TODAY);
      final s = managed(['a', 'b', 'c'], [last]);
      expect(refillAfter(s, last, TODAY, NOW), false);
      expect(s['queue']['since'], NOW - 86400000);
    });

    test('a queue without a matching rotationId is never rewritten', () {
      final last = w('b', TODAY);
      final s = S({
        'rotation': {
          'id': 'r1',
          'sequence': ['a', 'b'],
          'label': 'My split',
        },
        'queue': pass(['a', 'b'], {'label': 'US W1'}),
        'workouts': [w('a', '2026-09-11'), last],
      });
      expect(refillAfter(s, last, TODAY, NOW), false);
      expect((s['queue'] as Map).containsKey('rotationId'), false);
      expect(s['queue']['since'], NOW - 86400000);
    });

    test('a queue and a rotation both missing their ids never match by accident', () {
      final last = w('b', TODAY);
      final s = S({
        'rotation': {
          'sequence': ['a', 'b'],
          'label': 'My split',
        },
        'queue': pass(['a', 'b']),
        'workouts': [w('a', '2026-09-11'), last],
      });
      expect(refillAfter(s, last, TODAY, NOW), false);
    });

    test('a managed pass that no longer matches its rotation waits for the editor', () {
      final last = w('b', TODAY);
      final s = S({
        'rotation': {
          'id': 'r1',
          'sequence': ['a', 'b', 'c'],
          'label': 'My split',
        },
        'queue': pass(['a', 'b'], {'rotationId': 'r1'}),
        'workouts': [w('a', '2026-09-11'), last],
      });
      expect(refillAfter(s, last, TODAY, NOW), false);
    });

    test('there is no queue to refill without one', () {
      expect(refillAfter(S(), w('a', TODAY), TODAY, NOW), false);
    });

    test('a backfilled finish dated before other logged workouts still starts the new pass after the latest of them', () {
      final backfilled = w('c', '2026-09-08');
      final s = managed(['a', 'b', 'c'], [w('a', '2026-09-10'), w('b', '2026-09-11'), backfilled]);
      expect(refillAfter(s, backfilled, TODAY, NOW), true);
      expect(s['queue']['startsOn'], '2026-09-12');
    });

    test('sweeps every future pin the closing pass left behind, so a fulfilled one does not reopen on the next pass', () {
      final last = w('c', TODAY);
      final s = managed(['a', 'b', 'c'], [w('a', '2026-09-10'), w('b', '2026-09-11'), last]);
      s['dayPlan'] = <String, dynamic>{'2026-09-13': 'a', '2026-09-14': 'c', '2026-09-09': 'b'};
      expect(refillAfter(s, last, TODAY, NOW), true);
      expect(s['dayPlan'], {'2026-09-09': 'b'});
    });

    test("uses the rotation's own label, never the closing pass's", () {
      final last = w('c', TODAY);
      final s = S({
        'rotation': {
          'id': 'r1',
          'sequence': ['a', 'b', 'c'],
          'label': 'Rotation',
        },
        'queue': pass(['a', 'b', 'c'], {'rotationId': 'r1', 'label': 'US W1'}),
        'workouts': [w('a', '2026-09-10'), w('b', '2026-09-11'), last],
      });
      expect(refillAfter(s, last, TODAY, NOW), true);
      expect(s['queue']['label'], 'Rotation');
    });

    test('a workout logged with a clock ahead of now does not re-credit the new pass', () {
      final last = w('c', TODAY, NOW - 1000);
      final skewed = w('a', '2026-09-11', NOW + 5 * 60000);
      final s = managed(['a', 'b', 'c'], [skewed, w('b', '2026-09-11'), last]);
      expect(refillAfter(s, last, TODAY, NOW), true);
      expect(queueRemaining(s), ['a', 'b', 'c']);
      expect(queueView(s, TODAY)!['waiting'], true);
    });
  });

  test('rotationIds keeps the first occurrence of each routine that still exists', () {
    expect(
      rotationIds(
        S({
          'rotation': {
            'id': 'r1',
            'sequence': ['a', 'gone', 'b', 'a'],
          },
        }),
      ),
      ['a', 'b'],
    );
  });
}
