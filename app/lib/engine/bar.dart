// Port of frontend/src/lib/bar.js — per-exercise bar weight, in the profile unit.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'exercises.dart';
import 'js.dart';

const Set<String> BAR_EQ = {'barbell', 'olympic barbell', 'ez barbell', 'smith machine', 'trap bar'};

const Map<String, num> DEFAULT_BAR_KG = {'barbell': 20, 'olympic barbell': 20, 'ez barbell': 10, 'smith machine': 9, 'trap bar': 25};
const Map<String, num> DEFAULT_BAR_LB = {'barbell': 45, 'olympic barbell': 45, 'ez barbell': 25, 'smith machine': 20, 'trap bar': 55};

dynamic _exOf(dynamic exOrId) => exOrId is String ? EXIDX[exOrId] : exOrId;

bool usesBar(dynamic exOrId) => BAR_EQ.contains(at(_exOf(exOrId), 'eq'));

num? defaultBarWeight(dynamic eq, [dynamic unit]) => (unit == 'lb' ? DEFAULT_BAR_LB : DEFAULT_BAR_KG)[eq];

dynamic _own(dynamic S, dynamic exId) => at(or(at(S, 'barWeights'), const {}), exId ?? '');

/// A stored 0 is "no bar" (issue #138).
bool isNoBar(dynamic S, dynamic exId) {
  final own = _own(S, exId);
  return own is num && own == 0;
}

bool hasBarOverride(dynamic S, dynamic exId) {
  final own = _own(S, exId);
  return (own is num && own == 0) || (own != null && toNum(own) > 0);
}

/// Effective bar weight, in the profile unit; null for anything without a bar.
dynamic barWeightFor(dynamic S, dynamic exOrId) {
  final ex = _exOf(exOrId);
  if (!BAR_EQ.contains(at(ex, 'eq'))) return null;
  final own = _own(S, at(ex, 'id'));
  if (own is num && own == 0) return 0;
  if (own != null && toNum(own) > 0) return own;
  return defaultBarWeight(at(ex, 'eq'), at(S, 'unit'));
}

/// Plates per side: (total − bar) / 2 to 2 decimals, or null.
num? plateSplit(dynamic total, dynamic bar) {
  if (total == null || bar == null) return null;
  final t = toNum(total), b = toNum(bar);
  if (!(t > 0) || !(b >= 0) || t <= b) return null;
  return mathRound(((t - b) / 2) * 100) / 100;
}
