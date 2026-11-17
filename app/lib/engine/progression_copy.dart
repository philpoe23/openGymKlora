// Port of frontend/src/lib/progression-copy.js — a presentation-only view of a progression
// result: the policy behind the number, next to the engine's own explanation.

import 'js.dart';
import 'progression.dart';

/// `{ policyLabel, why }` for a prescription with a visible outcome, else null.
JMap? progressionGuidance(dynamic plan) {
  if (!truthy(at(plan, 'why')) || plan['kind'] == 'off' || plan['policy'] == 'off') return null;
  final policyLabel = POLICY_NAME[plan['policy']];
  if (policyLabel == null) return null;
  return {'policyLabel': policyLabel, 'why': plan['why']};
}
