// Port of frontend/src/lib/superset-meta.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/superset_flow.dart';
import 'package:klora_app/engine/superset_meta.dart';

import '_helpers.dart';

void main() {
  group("a superset's name and rest between rounds (#292)", () {
    test('is written onto every member and read back from the group', () {
      final ex = <Map<String, dynamic>>[
        {'id': 'a', 'sg': 'g'},
        {'id': 'b', 'sg': 'g'},
        {'id': 'c'},
      ];
      setSupersetMeta(ex, 'g', name: '  Arms finisher ', rest: 75);
      expect(ex[0], matchObj({'sgName': 'Arms finisher', 'sgRest': 75}));
      expect(ex[1], matchObj({'sgName': 'Arms finisher', 'sgRest': 75}));
      expect(ex[2]['sgName'], isNull);
      expect(supersetMeta(ex, [0, 1]), jeq({'name': 'Arms finisher', 'rest': 75}));
      setSupersetMeta(ex, 'g', name: '', rest: 0);
      expect(ex[0].containsKey('sgName'), isFalse);
      expect(ex[0].containsKey('sgRest'), isFalse);
    });
    test("a new member takes the group's values, one that left drops them", () {
      final ex = <Map<String, dynamic>>[
        {'id': 'a', 'sg': 'g', 'sgName': 'Pair', 'sgRest': 60},
        {'id': 'b', 'sg': 'g'},
        {'id': 'c', 'sgName': 'Old', 'sgRest': 30},
      ];
      syncSupersetMeta(ex);
      expect(ex[1], matchObj({'sgName': 'Pair', 'sgRest': 60}));
      expect(ex[2]['sgName'], isNull);
    });
    test("the group's rest replaces the longest member rest after a round", () {
      final entries = [
        {'target': {'restSec': 120, 'sgRest': 45}},
        {'target': {'restSec': 90, 'sgRest': 45}},
      ];
      expect(restSecFor(entries, [0, 1], 90), 45);
      // On a single exercise a leftover value means nothing.
      expect(restSecFor(entries, [0], 90), 120);
      expect(restSecFor([{'target': {'restSec': 120}}, {'target': {}}], [0, 1], 90), 120);
    });
  });
}
