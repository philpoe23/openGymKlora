// Port of frontend/src/lib/onerm.js — estimated one-rep max (issues #18, #155): the formula
// suite, the weighted ensemble, per-entry best set, the per-exercise trend and record checks.
// Comments explaining the rules live in the JS source.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:math' as math;

import 'dumbbells.dart';
import 'exercises.dart';
import 'history.dart';
import 'js.dart';
import 'workout_model.dart';

const int REP_CAP = 12;
const int WEIGHTED_REP_CAP = 15;

typedef OneRmFormula = num Function(num w, num r);

final Map<String, OneRmFormula> FORMULAS = {
  'epley': (w, r) => w * (1 + r / 30),
  'brzycki': (w, r) => w * 36 / (37 - r),
  'lombardi': (w, r) => w * math.pow(r, 0.1),
  'oconner': (w, r) => w * (1 + r / 40),
  'mayhew': (w, r) => (w * 100) / (52.2 + 41.9 * math.exp(-0.055 * r)),
  'wathan': (w, r) => (w * 100) / (48.8 + 53.8 * math.exp(-0.075 * r)),
  'lander': (w, r) => (w * 100) / (101.3 - 2.67123 * r),
};
const String DEFAULT_FORMULA = 'epley';

const Map<String, String> FORMULA_NAMES = {
  'epley': 'Epley', 'brzycki': 'Brzycki', 'lombardi': 'Lombardi', 'oconner': 'O’Conner',
  'mayhew': 'Mayhew', 'wathan': 'Wathan', 'lander': 'Lander',
};

/// The formula a profile picked (`S.oneRmFormula`): 'weighted', one of [FORMULAS], else the default.
String formulaOf(dynamic S) {
  final f = at(S, 'oneRmFormula');
  return f == 'weighted' || (f is String && FORMULAS.containsKey(f)) ? f as String : DEFAULT_FORMULA;
}

const List<num> _RIR_PCT = [100, 95.5, 92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 71.7, 69.5, 67.5, 65.5, 63.6];

num _rirEstimate(num w, num effectiveReps) {
  final idx = math.min(math.max(mathRound(effectiveReps) - 1, 0), _RIR_PCT.length - 1);
  return (w * 100) / _RIR_PCT[idx.toInt()];
}

class _Wt {
  const _Wt(this.a, this.v);
  final num a;
  final num Function(num r) v;
}

final Map<String, _Wt> _WEIGHTS = {
  'epley': _Wt(0.95, (r) => r <= 6 ? 1 : math.max(0.4, 1 - (r - 6) * 0.12)),
  'brzycki': _Wt(1.10, (r) => r <= 8 ? 1 : math.max(0.3, 1 - (r - 8) * 0.18)),
  'lombardi': _Wt(0.85, (r) => r <= 5 ? 1 : math.max(0.4, 1 - (r - 5) * 0.10)),
  'oconner': _Wt(0.90, (r) => r <= 6 ? 1 : math.max(0.4, 1 - (r - 6) * 0.12)),
  'mayhew': _Wt(0.95, (r) => r <= 8 ? 1 : math.max(0.5, 1 - (r - 8) * 0.10)),
  'wathan': _Wt(0.90, (r) => r <= 7 ? 1 : math.max(0.4, 1 - (r - 7) * 0.12)),
  'lander': _Wt(0.85, (r) => r <= 7 ? 1 : math.max(0.35, 1 - (r - 7) * 0.15)),
  'rir': _Wt(1.00, (r) => r <= 10 ? 1 : math.max(0.4, 1 - (r - 10) * 0.15)),
};

num _ensembleCV(num w, num effectiveReps) {
  final vals = FORMULAS.values.map((f) => f(w, effectiveReps)).toList();
  final mean = vals.fold<num>(0, (a, b) => a + b) / vals.length;
  final variance = vals.fold<num>(0, (a, e) => a + math.pow(e - mean, 2)) / vals.length;
  return math.sqrt(variance) / mean;
}

/// Weighted average of all formula estimates and the RIR %1RM map, unrounded.
num weightedEstimate(num w, num effectiveReps) {
  num total = 0;
  num wsum = 0;
  for (final e in FORMULAS.entries) {
    final wt = _WEIGHTS[e.key]!.a * _WEIGHTS[e.key]!.v(effectiveReps);
    total += e.value(w, effectiveReps) * wt;
    wsum += wt;
  }
  final rirWt = _WEIGHTS['rir']!.a * _WEIGHTS['rir']!.v(effectiveReps);
  total += _rirEstimate(w, effectiveReps) * rirWt;
  wsum += rirWt;
  return total / wsum;
}

/// `Number(v)` where a missing value is undefined (NaN).
num _numU(dynamic v) => v == null ? double.nan : toNum(v);

/// Estimate a 1RM from one set (rounded to 0.1), or null when it cannot honestly answer.
num? estimate1RM(dynamic w, dynamic r, [dynamic formula = DEFAULT_FORMULA, dynamic rir]) {
  final weight = _numU(w);
  final reps = _numU(r);
  if (!weight.isFinite || !reps.isFinite) return null;
  if (weight <= 0 || reps < 1) return null;

  final validRir = rir != null && toNum(rir) >= 0;

  if (reps == 1 && (!validRir || toNum(rir) == 0)) return mathRound(weight * 10) / 10;

  if (formula == 'weighted') {
    final effectiveReps = validRir ? reps + toNum(rir) : reps;
    if (effectiveReps > WEIGHTED_REP_CAP) return null;
    final est = weightedEstimate(weight, effectiveReps);
    if (!est.isFinite || est <= 0) return null;
    return mathRound(est * 10) / 10;
  }

  if (reps > REP_CAP) return null;
  final fn = (formula is String ? FORMULAS[formula] : null) ?? FORMULAS[DEFAULT_FORMULA]!;
  final est = reps == 1 ? weight : fn(weight, mathRound(reps));
  if (!est.isFinite || est <= 0) return null;
  return mathRound(est * 10) / 10;
}

/// Best estimate out of one workout entry's completed sets: `{est, w, r}`, or null.
JMap? bestSetOf(dynamic entry, [String formula = DEFAULT_FORMULA]) {
  if (isAssisted(truthy(at(entry, 'id')) ? {'id': entry['id']} : entry)) return null;
  JMap? best;
  for (final s in metricRowsForEntry(entry, 'reps')) {
    final sets = isSideSet(s) ? [s['sides']['L'], s['sides']['R']].where((side) => at(side, 'done') == true) : [s];
    for (final set in sets) {
      final est = estimate1RM(at(set, 'w'), at(set, 'r'), formula, at(set, 'rir'));
      if (est != null && (best == null || est > (best['est'] as num))) {
        best = {'est': est, 'w': toNum(set['w']), 'r': mathRound(toNum(set['r']))};
      }
    }
  }
  return best;
}

JMap? _bestSetOfEntries(dynamic entries, [String formula = DEFAULT_FORMULA]) {
  JMap? best;
  for (final entry in asList(entries)) {
    final candidate = bestSetOf(entry, formula);
    if (candidate != null && (best == null || (candidate['est'] as num) > (best['est'] as num))) best = candidate;
  }
  return best;
}

/// One point per workout in which the exercise produced an estimate, chronological:
/// `{t, d, y, w, r}` (t = workoutAt, epoch ms or NaN; y = the estimate). [formula] defaults to
/// [formulaOf]; [as] to the exercise's current dumbbell meaning.
List<JMap> e1rmSeries(dynamic S, dynamic exId, [String? formula, dynamic as]) {
  formula ??= formulaOf(S);
  as ??= currentDbLoad(S, exId);
  if (isAssisted(exId)) return [];
  final pts = <JMap>[];
  for (final w in asList(or(at(S, 'workouts'), const []))) {
    final best = _bestSetOfEntries(entriesForExercise(workoutAs(w, exId, as), exId), formula);
    if (best != null) pts.add({'t': workoutAt(w), 'd': at(w, 'd'), 'y': best['est'], 'w': best['w'], 'r': best['r']});
  }
  return pts;
}

/// All-time best estimate for an exercise: `{est, w, r, d, t}`, or null.
JMap? best1RM(dynamic S, dynamic exId, [String? formula, dynamic as]) {
  formula ??= formulaOf(S);
  JMap? best;
  for (final p in e1rmSeries(S, exId, formula, as ?? currentDbLoad(S, exId))) {
    if (best == null || (p['y'] as num) > (best['est'] as num)) best = {'est': p['y'], 'w': p['w'], 'r': p['r'], 'd': p['d'], 't': p['t']};
  }
  return best;
}

/// Did [entry] beat every estimate in [S] (which does not yet contain it)? `{est, w, r, prev}`
/// (prev 0 for a first estimate), or null.
JMap? is1RMRecord(dynamic S, dynamic exId, dynamic entry, [String? formula]) {
  formula ??= formulaOf(S);
  final now = bestSetOf(entry, formula);
  if (now == null) return null;
  final prev = best1RM(S, exId, formula, entryDbLoad(entry));
  return prev == null || (now['est'] as num) > (prev['est'] as num) ? {...now, 'prev': prev != null ? prev['est'] : 0} : null;
}

/// Confidence index (0–1) of a 1RM estimate.
num calculate1RMAccuracy(dynamic reps, [dynamic rir, String formula = 'weighted']) {
  final r = _numU(reps);
  if (!r.isFinite || r < 1) return 0;
  if (r == 1 && rir == 0) return 1;
  if (r > WEIGHTED_REP_CAP) return 0;

  final repFactor = r == 1 ? 1 : 1 - 0.5 * (r - 1) / (WEIGHTED_REP_CAP - 1);
  final rirVal = toNum(rir);
  final rirFactor = (rir != null && rirVal.isFinite && rirVal > 0) ? 0.92 : 1;

  num spreadFactor = 1;
  if (formula == 'weighted' && r >= 2) {
    final cv = _ensembleCV(100, r);
    spreadFactor = math.max(0.5, 1 - cv / 0.15 * 0.5);
  }
  return mathRound(repFactor * rirFactor * spreadFactor * 100) / 100;
}
