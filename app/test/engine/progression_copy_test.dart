// Port of frontend/src/lib/progression-copy.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/progression_copy.dart';

import '_helpers.dart';

void main() {
  group('policy-labelled progression guidance', () {
    test('keeps the calculated outcome and identifies the policy that produced it', () {
      final why = ['Every rep last time. {0} {1} more.', 2.5, 'kg'];
      expect(progressionGuidance({'policy': 'linear', 'kind': 'up', 'weight': 62.5, 'why': why}), jeq({'policyLabel': 'Linear progression', 'why': why}));
    });

    test('labels hold and deload outcomes without changing their calculated reasons', () {
      final hold = ['Missed reps last time. Same weight again ({0} of {1} to go).', 2, 3];
      final deload = ['Missed reps. Reset to {0} {1} and work back up.', 55, 'kg'];
      expect(progressionGuidance({'policy': 'double', 'kind': 'hold', 'why': hold}), jeq({'policyLabel': 'Double progression', 'why': hold}));
      expect(progressionGuidance({'policy': 'greyskull', 'kind': 'deload', 'why': deload}), jeq({'policyLabel': 'Greyskull LP', 'why': deload}));
    });

    test('labels a baseline outcome and omits policies with no visible outcome', () {
      final baseline = ['Nothing logged yet, so this session sets the baseline.'];
      expect(progressionGuidance({'policy': 'linear', 'kind': 'first', 'why': baseline}), jeq({'policyLabel': 'Linear progression', 'why': baseline}));
      expect(progressionGuidance({'policy': 'off', 'kind': 'off'}), isNull);
      expect(progressionGuidance({'policy': 'linear', 'kind': 'first'}), isNull);
      expect(progressionGuidance(null), isNull);
    });
  });
}
