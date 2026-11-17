// Port of frontend/src/lib/history.move-entry.test.js.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/history.dart';

import '_helpers.dart';

// #377: the routine editor's arrows move one exercise. Inside a superset it passes the next
// member; at the edge it leaves the superset where it stands; a single exercise still jumps a
// whole superset and never joins it.
Map<String, dynamic> e(String id, [String? sg, Map<String, dynamic> extra = const {}]) =>
    <String, dynamic>{'id': id, 'sets': 3, 'reps': 8, 'sg': ?sg, ...extra};
List<String> ids(List<dynamic>? list) =>
    list!.map((x) => '${x['id']}${x['sg'] != null ? ':${x['sg']}' : ''}').toList();

void main() {
  group('moveRoutineEntry', () {
    test('swaps with the next member inside a superset, configurations untouched', () {
      final a = e('a', 'g', {'w': 40, 'note': 'pause'});
      final b = e('b', 'g');
      final c = e('c', 'g');
      final d = e('d');
      final items = <dynamic>[a, b, c, d];
      final down = moveRoutineEntry(items, 0, 1);
      expect(ids(down), ['b:g', 'a:g', 'c:g', 'd']);
      expect(down![1], same(a));
      final up = moveRoutineEntry(items, 2, -1);
      expect(ids(up), ['a:g', 'c:g', 'b:g', 'd']);
      expect(ids(items), ['a:g', 'b:g', 'c:g', 'd']);
    });

    test('leaves the superset at its top edge, where it stands', () {
      final items = <dynamic>[e('x'), e('a', 'g'), e('b', 'g'), e('c', 'g')];
      final out = moveRoutineEntry(items, 1, -1);
      expect(ids(out), ['x', 'a', 'b:g', 'c:g']);
      expect(out![1], jeq(e('a')));
      expect(items[1]['sg'], 'g');
    });

    test('leaves the superset at its bottom edge, where it stands', () {
      final items = <dynamic>[e('a', 'g'), e('b', 'g'), e('c', 'g'), e('y')];
      expect(ids(moveRoutineEntry(items, 2, 1)), ['a:g', 'b:g', 'c', 'y']);
    });

    test('a superset of two dissolves when one leaves', () {
      final items = <dynamic>[e('a', 'g'), e('b', 'g'), e('c')];
      expect(ids(moveRoutineEntry(items, 1, 1)), ['a', 'b', 'c']);
      expect(ids(moveRoutineEntry(items, 0, -1)), ['a', 'b', 'c']);
    });

    test('a member at the very top or bottom of the list can still leave', () {
      final items = <dynamic>[e('a', 'g'), e('b', 'g'), e('c', 'g')];
      expect(ids(moveRoutineEntry(items, 0, -1)), ['a', 'b:g', 'c:g']);
      expect(ids(moveRoutineEntry(items, 2, 1)), ['a:g', 'b:g', 'c']);
    });

    test('a single exercise jumps a whole superset and does not join it', () {
      final items = <dynamic>[e('x'), e('a', 'g'), e('b', 'g'), e('y')];
      expect(ids(moveRoutineEntry(items, 0, 1)), ['a:g', 'b:g', 'x', 'y']);
      expect(ids(moveRoutineEntry(items, 3, -1)), ['x', 'y', 'a:g', 'b:g']);
      expect(moveRoutineEntry(items, 0, 1), jeq(moveSupersetUnit(items, 0, 1)));
    });

    test('a press that does nothing returns null and changes nothing', () {
      final items = <dynamic>[e('x', 'lone'), e('a'), e('b')];
      final before = jsonEncode(items);
      expect(moveRoutineEntry(items, 0, -1), isNull);
      expect(moveRoutineEntry(items, 2, 1), isNull);
      expect(moveRoutineEntry(items, 5, 1), isNull);
      expect(moveRoutineEntry(items, 1, 2), isNull);
      expect(moveRoutineEntry(null, 0, 1), isNull);
      expect(jsonEncode(items), before);
    });
  });
}
