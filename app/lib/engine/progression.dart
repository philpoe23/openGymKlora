// Port of frontend/src/lib/progression.js — automatic progression (issue #17): reading a finished
// session, counting stalls, and the next prescription under each policy (linear, Greyskull LP,
// double, triple, time), plus applying a prescription to freshly built rows. Everything is a pure
// function of the workout history. Comments explaining the rules live in the JS source.
//
// Prescriptions are `Map<String, dynamic>`; a field the JS leaves `undefined` is simply absent
// here (never stored as null), so `p['weight'] == null` reads exactly like `p.weight == null`.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:convert';
import 'dart:math' as math;

import 'backoff.dart';
import 'dumbbells.dart';
import 'exercises.dart';
import 'history.dart';
import 'js.dart';
import 'pyramid.dart';
import 'rep_range.dart';
import 'workout_model.dart';

export 'exercises.dart' show defaultIncrement;

const List<String> POLICIES = ['off', 'linear', 'greyskull', 'double', 'triple', 'time'];

const Map<String, List<String>> POLICIES_FOR = {
  'reps': ['off', 'linear', 'greyskull', 'double', 'triple'],
  'time': ['off', 'time'],
  'cardio': ['off'],
};

const Map<String, String> POLICY_NAME = {
  'off': 'No automatic progression',
  'linear': 'Linear progression',
  'greyskull': 'Greyskull LP',
  'double': 'Double progression',
  'triple': 'Triple progression',
  'time': 'Add time',
};
const Map<String, String> POLICY_DESC = {
  'off': 'Targets stay where you set them.',
  'linear': 'Hit every rep in every set and the weight goes up. Repeated misses trigger a deload.',
  'greyskull': 'Two straight sets plus a final set taken to failure. Beat the target on that set and the weight goes up (twice as much if you double the reps). One failure resets 10 %.',
  'double': 'Work up through a rep range at the same weight. Reach the top of the range in every set and the weight goes up, reps back to the bottom.',
  'triple': 'Reps climb to the top of the range, then a set is added, up to your most sets. All of them at the top and the weight goes up, back to your first sets and reps.',
  'time': 'Hold every set for the full duration and the target goes up.',
};

const double DELOAD_FACTOR = 0.9;
const Map<String, int> DELOAD_AFTER = {'linear': 3, 'greyskull': 1, 'double': 3, 'triple': 3, 'time': 3};
const double DELOAD_FACTOR_MIN = 0.5;
const double DELOAD_FACTOR_MAX = 0.95;

// ---- JS-semantics helpers local to this port -----------------------------------------------------

/// JS `v > 0` for any value (undefined/null/objects compare false).
bool _gt0(dynamic v) => toNum(v) > 0;

/// `Number(v)` where a missing value is `undefined` (NaN), not null (0).
num _numU(dynamic v) => v == null ? double.nan : toNum(v);

/// `Math.ceil` / `Math.floor` that pass NaN and ±Infinity through instead of throwing.
num _ceil(num x) => x.isFinite ? x.ceil() : x;
num _floor(num x) => x.isFinite ? x.floor() : x;

/// `a ?? b` where a missing key reads as undefined.
dynamic _nn(dynamic a, dynamic b) => a ?? b;

/// Adds [key] only when [value] is not undefined/null, the way a JS object literal holding
/// `key: undefined` reads back (and drops out of JSON).
void _put(JMap m, String key, dynamic value) {
  if (value != null) m[key] = value;
}

/// A JS-style numeric comparator chain (`a - b || c - d || …`): the first truthy difference.
int _chain(List<num> diffs) {
  for (final d in diffs) {
    if (truthy(d)) return d < 0 ? -1 : 1;
  }
  return 0;
}

num _round1(num v) => mathRound(v * 10) / 10;

// ---- deload factor, Epley -----------------------------------------------------------------------

bool isValidDeloadFactor(dynamic value) {
  final factor = toNum(value);
  return factor.isFinite && factor >= DELOAD_FACTOR_MIN && factor <= DELOAD_FACTOR_MAX;
}

num deloadFactorOf(dynamic cfg) => isValidDeloadFactor(at(cfg, 'deloadFactor')) ? toNum(cfg['deloadFactor']) : DELOAD_FACTOR;

num? epley1RM(dynamic weight, dynamic reps) {
  final w = _numU(weight);
  final r = _numU(reps);
  if (!w.isFinite || !r.isFinite || w <= 0 || r < 1) return null;
  final result = w * (1 + r / 30);
  return result.isFinite && result > 0 ? _round1(result) : null;
}

num? deloadTarget1RM(dynamic weight, dynamic reps, [dynamic factor = DELOAD_FACTOR, bool perSide = false]) {
  final base = epley1RM(weight, perSide ? _numU(reps) / 2 : reps);
  final f = isValidDeloadFactor(factor) ? toNum(factor) : DELOAD_FACTOR;
  return base == null ? null : _round1(base * f);
}

/// The load step for reps-mode weight controls and progression.
num weightIncrement(dynamic cfg, [dynamic unit]) =>
    truthy(cfg) && _gt0(at(cfg, 'inc')) ? toNum(cfg['inc']) : defaultIncrement(at(cfg, 'id'), unit);

const int DEFAULT_SEC_INCREMENT = 5;
const int MAX_BW_SETS = 6;

/// The policy in force for one exercise: its own override, else the routine's, else the mode's default.
String policyFor(dynamic cfg, [dynamic routine, String? mode]) {
  if (isPyramid(cfg)) return 'off';
  final m = (mode != null && mode.isNotEmpty) ? mode : modeOf(truthy(cfg) ? cfg : const <String, dynamic>{});
  final allowed = POLICIES_FOR[m] ?? const ['off'];
  final dynamic pick = (truthy(cfg) && truthy(at(cfg, 'prog')))
      ? cfg['prog']
      : (truthy(routine) && truthy(at(routine, 'prog')))
          ? routine['prog']
          : (m == 'reps' ? 'linear' : 'off');
  return pick is String && allowed.contains(pick) ? pick : 'off';
}

/// Snap to a loadable multiple of the step.
num snapWeight(num v, dynamic step) {
  if (!_gt0(step)) return _round1(v);
  final s = toNum(step);
  return _round1(mathRound(v / s) * s);
}

/// Add [step] the way a stepper tap does (issue #175): snapped to the [inc] grid only from a
/// weight already on it.
num addStep(dynamic w, num step, dynamic inc) {
  final v = numOr(w, 0);
  final i = toNum(inc);
  final onGrid = i > 0 && (v - mathRound(v / i) * i).abs() <= 0.1;
  final next = v + step;
  return math.max(0, onGrid ? snapWeight(next, i) : _round1(next));
}

num stepWeight(dynamic value, num step, num direction) {
  final v = numOr(value, 0);
  return addStep(v, direction * step, step);
}

/// Back off by a factor, landing on something you can actually load.
num deloadTo(num cur, num step, [num factor = DELOAD_FACTOR]) {
  var next = snapWeight(cur * factor, step);
  if (next >= cur) next = snapWeight(cur - step, step);
  return math.max(step, next);
}

List<num> _positiveGridAround(num ideal, num step, num maxWeight, bool strictLower) {
  if (!(ideal > 0) || !(step > 0) || !(maxWeight > 0)) return <num>[];
  final low = _floor(ideal / step) * step;
  final high = _ceil(ideal / step) * step;
  final values = <num>[];
  for (final v in [low, high].map((v) => snapWeight(v, step))) {
    if (!values.contains(v)) values.add(v);
  }
  return jsSort(
      values.where((v) => v > 0 && v <= maxWeight + 1e-9 && (!strictLower || v < maxWeight - 1e-9)).toList(),
      (a, b) => cmpNum(a - b));
}

/// Pick a bounded load/reps pair for an Epley target (hard constraints, then closest estimated
/// 1RM, fewer rep changes, greater load). [owned]: the sorted loads the lifter can load.
JMap? selectDeloadCandidate({
  dynamic currentWeight,
  dynamic targetWeight,
  dynamic targetReps,
  dynamic step,
  dynamic factor = DELOAD_FACTOR,
  dynamic reps,
  dynamic repsMin,
  bool perSide = false,
  List<num>? owned,
}) {
  final current = _numU(currentWeight);
  final baseWeight = _numU(targetWeight);
  final baseReps = _numU(targetReps);
  final stride = perSide ? 2 : 1;
  final c = _ceil(baseReps / stride) * stride;
  final num upper = c.isNaN ? double.nan : math.max(stride, c);
  final range = repsMin == null ? null : normalizeRepRange(reps, repsMin, stride);
  final num top = range != null
      ? math.min(range['reps'] as num, upper.isNaN ? double.nan : math.max(range['repsMin'] as num, upper))
      : upper;
  final num bottom = range != null ? range['repsMin'] as num : top;
  final repValues = <num>[];
  for (var r = top; r >= bottom; r -= stride) {
    repValues.add(r);
  }
  final target1RM = deloadTarget1RM(baseWeight, upper, factor, perSide);
  final stepN = toNum(step);
  if (!(current > 0) || target1RM == null || repValues.isEmpty || !(stepN > 0)) return null;

  final candidates = <JMap>[];
  for (final candidateReps in repValues) {
    final ideal = target1RM / (1 + (perSide ? candidateReps / 2 : candidateReps) / 30);
    final allowCurrent = repsMin != null && candidateReps < upper;
    final grid = owned != null
        ? ownedAround(ideal, owned, current, !allowCurrent)
        : _positiveGridAround(ideal, stepN, current, !allowCurrent);
    if (allowCurrent && !grid.contains(current)) grid.add(current);
    for (final candidateWeight in grid) {
      final epley = epley1RM(candidateWeight, perSide ? candidateReps / 2 : candidateReps);
      candidates.add({
        'weight': candidateWeight,
        'reps': candidateReps,
        'epley': epley,
        'error': ((epley ?? 0) - target1RM).abs(),
        'repChange': (candidateReps - upper).abs(),
        'fallback': false,
      });
    }
  }

  if (candidates.isEmpty) {
    for (final candidateReps in repValues) {
      final epley = epley1RM(current, perSide ? candidateReps / 2 : candidateReps);
      candidates.add({
        'weight': current,
        'reps': candidateReps,
        'epley': epley,
        'error': ((epley ?? 0) - target1RM).abs(),
        'repChange': (candidateReps - upper).abs(),
        'fallback': true,
      });
    }
  }
  if (candidates.isEmpty) return null;
  jsSort<JMap>(
      candidates,
      (a, b) => _chain([
            (a['error'] as num) - (b['error'] as num),
            (a['repChange'] as num) - (b['repChange'] as num),
            (b['weight'] as num) - (a['weight'] as num),
            (b['reps'] as num) - (a['reps'] as num),
          ]));
  return {
    ...candidates[0],
    'target1RM': target1RM,
    'factor': deloadFactorOf({'deloadFactor': factor}),
    'upper': upper,
    'bottom': bottom,
  };
}

/// What a routine's exercise asks for (issue #275), as stamped on every session entry.
JMap plannedOf(dynamic cfg) {
  final c = truthy(cfg) ? asMap(cfg) : <String, dynamic>{};
  final mode = modeOf(c);
  final out = <String, dynamic>{'sets': math.max(1, toNum(or(c['sets'], 1)))};
  if (mode == 'reps' && _gt0(c['reps'])) out['reps'] = c['reps'];
  if (mode == 'reps' && _gt0(c['repsMin'])) out['repsMin'] = c['repsMin'];
  if (mode == 'time' && _gt0(c['sec'])) out['sec'] = c['sec'];
  if (mode == 'reps' && _gt0(c['setsMax'])) out['setsMax'] = c['setsMax'];
  if (c['weight'] != null) out['weight'] = c['weight'];
  return out;
}

bool _climbsReps(dynamic cfg) => isBw(cfg) || !isLoadedEq(at(cfg, 'id')) || isAssisted(cfg);

const List<String> _PLAN_KEYS = ['sets', 'reps', 'repsMin', 'sec', 'setsMax'];
bool _samePlan(dynamic a, dynamic b) => _PLAN_KEYS.every((k) => at(a, k) == at(b, k));

/// Did the routine's sets or reps change since the session that stamped [planned]?
bool planChanged(dynamic planned, dynamic cfg) => truthy(planned) && !_samePlan(planned, plannedOf(cfg));

num _loadOf(dynamic entry, List<dynamic> sets) {
  final done = sets.where((s) => truthy(at(s, 'done'))).map((s) => toNum(or(at(s, 'w'), 0))).toList();
  if (!isAssisted(truthy(entry) && truthy(at(entry, 'id')) ? {'id': entry['id']} : entry)) return maxOf([0, ...done]);
  final loaded = done.where((w) => w > 0).toList();
  return loaded.isNotEmpty ? minOf(loaded) : 0;
}

/// `list.slice(0, end)` with JS coercion of [end].
List<dynamic> _slice(List<dynamic> list, num end) {
  if (end.isNaN) return <dynamic>[];
  final e = end.isInfinite ? (end > 0 ? list.length : 0) : end.truncate();
  return list.sublist(0, e < 0 ? math.max(0, list.length + e) : math.min(e, list.length));
}

/// Reduce one finished workout entry to what a policy needs to judge it. An entry without its
/// own target is judged against [fallback], the exercise's current plan.
JMap readSession(dynamic entry, [dynamic fallback]) {
  final ownTarget = truthy(entry) ? at(entry, 'target') : null;
  final dynamic target = or(or(ownTarget, fallback), <String, dynamic>{});
  final mode = modeOf({...asMap(target), 'id': truthy(entry) ? at(entry, 'id') : entry});
  final logged = asList(truthy(entry) ? or(at(entry, 'sets'), const []) : const []).where((s) => !isWarmupRow(s)).toList();
  final rowRepsRaw = at(target, 'rowReps');
  final List<num>? rowGoals = mode == 'reps' && truthy(entry) && truthy(ownTarget) && rowRepsRaw is List && rowRepsRaw.isNotEmpty
      ? rowRepsRaw.map((r) => math.max<num>(0, numOr(r, 0))).toList()
      : null;
  final num plannedRows = rowGoals != null ? rowGoals.length : toNum(or(at(target, 'sets'), logged.length));
  final planned = mode == 'time' && isPerSide(target) ? plannedRows * 2 : plannedRows;
  final enough = logged.length >= planned;
  final sets = truthy(entry) && truthy(ownTarget) ? _slice(logged, planned.isNaN ? double.nan : math.max(1, planned)) : logged;

  if (mode == 'time') {
    final goal = toNum(or(at(target, 'sec'), 0));
    final held = sets.map((s) => truthy(at(s, 'done')) ? toNum(or(at(s, 'sec'), 0)) : 0).toList();
    return {
      'mode': mode, 'target': target, 'goal': goal, 'held': held,
      'weight': _loadOf(entry, sets),
      'best': maxOf([0, ...held]),
      'ok': goal > 0 && enough && held.isNotEmpty && held.every((h) => h >= goal),
    };
  }
  final num goal = rowGoals != null ? maxOf(rowGoals) : toNum(or(at(target, 'reps'), 0));
  final num step = truthy(entry) && truthy(ownTarget) ? numOr(at(ownTarget, 'backoffStep'), 0) : 0;
  final num top = step > 0 && sets.isNotEmpty ? numOr(at(sets[0], 'w'), 0) : 0;
  bool heavyEnough(dynamic s, int k) => !(top > 0) || k == 0 || numOr(at(s, 'w'), 0) >= backoffAt(top, k, step) - 0.05;
  final reps = <num>[
    for (var k = 0; k < sets.length; k++) truthy(at(sets[k], 'done')) && heavyEnough(sets[k], k) ? toNum(or(at(sets[k], 'r'), 0)) : 0,
  ];
  var ok = goal > 0 && enough && reps.isNotEmpty;
  if (ok) {
    for (var k = 0; k < reps.length; k++) {
      final need = rowGoals != null ? (k < rowGoals.length ? rowGoals[k] : goal) : goal;
      if (!(reps[k] >= need)) {
        ok = false;
        break;
      }
    }
  }
  return {
    'mode': mode, 'target': target, 'goal': goal, 'reps': reps,
    'weight': _loadOf(entry, sets),
    'count': reps.length,
    'low': reps.isNotEmpty ? minOf(reps) : 0,
    'amrap': reps.isNotEmpty ? reps.last : 0,
    'ok': ok,
  };
}

/// Every past session for one exercise, oldest first. With a routine id, that routine's own
/// sessions (issue #216), or the exercise's whole history when it has none.
List<JMap> sessionsFor(dynamic S, dynamic exId, [dynamic fallback, dynamic rid]) {
  if (truthy(rid)) {
    final own = _sessionsIn(S, exId, fallback, rid);
    if (own.isNotEmpty) return own;
  }
  return _sessionsIn(S, exId, fallback, null);
}

List<JMap> _sessionsIn(dynamic S, dynamic exId, dynamic fallback, dynamic rid) {
  final out = <JMap>[];
  for (final w in asList(or(at(S, 'workouts'), const []))) {
    final entry = jsFind(asList(or(at(w, 'entries'), const [])),
        (e) => truthy(e) && at(e, 'id') == exId && (!truthy(rid) || entryRoutineId(w, e) == rid));
    if (entry == null) continue;
    if (entryExcluded(w, entry)) continue;
    if (!asList(at(entry, 'sets')).any((s) => truthy(at(s, 'done')) && !isWarmupRow(s))) continue;
    final slot = entryRoutineId(w, entry);
    out.add({
      'd': at(w, 'd'),
      if (truthy(slot)) 'rid': slot,
      if (truthy(at(entry, 'planned'))) 'planned': entry['planned'],
      ...readSession(entry, fallback),
    });
  }
  return out;
}

// ---- triple progression (issue #179) -----------------------------------------------------------

const int MAX_TRIPLE_SETS = 10;

/// `{ setsMin, setsMax }`: the base sets and the set ceiling of a triple-progression cycle.
JMap tripleSetsOf(dynamic cfg) {
  final num setsMin = math.max(1, numOr(mathRound(_numU(at(cfg, 'sets'))), 1));
  final num setsMax = math.max(setsMin, math.min(MAX_TRIPLE_SETS, numOr(mathRound(_numU(at(cfg, 'setsMax'))), setsMin)));
  return {'setsMin': setsMin, 'setsMax': setsMax};
}

List<num> _tripleRowsOf(dynamic session, num setsMin, num setsMax, JMap range) {
  final own = at(at(session, 'target'), 'rowReps');
  if (own is List && own.isNotEmpty) return own.map((r) => math.max<num>(0, numOr(r, 0))).toList();
  final n = math.min(setsMax, math.max(setsMin, numOr(at(at(session, 'target'), 'sets'), setsMin)));
  final reps = math.min(range['reps'] as num,
      math.max(range['repsMin'] as num, toNum(or(or(at(at(session, 'target'), 'reps'), at(session, 'goal')), range['repsMin']))));
  return List<num>.filled(n.toInt(), reps);
}

num _tripleActive(dynamic session) {
  final rows = at(at(session, 'target'), 'rowReps');
  final reps = asList(or(at(session, 'reps'), const []));
  if (rows is! List || rows.isEmpty) return numOr(at(session, 'low'), 0);
  num repAt(int k) => numOr(at(reps, k), 0);
  if (rows.every((r) => r == rows[0])) return minOf([for (var k = 0; k < rows.length; k++) repAt(k)]);
  return repAt(rows.length - 1);
}

bool _sameRows(dynamic a, dynamic b) =>
    jsonEncode(jsonNorm(or(at(at(a, 'target'), 'rowReps'), null))) == jsonEncode(jsonNorm(or(at(at(b, 'target'), 'rowReps'), null)));

/// How many sessions in a row ended in a miss, counting back from the most recent.
int stallCount(List<dynamic> sessions, [String? policy]) {
  var n = 0;
  for (var i = sessions.length - 1; i >= 0; i--) {
    final s = sessions[i];
    if (truthy(at(s, 'ok'))) break;
    if (i < sessions.length - 1 && at(s, 'weight') != at(sessions[i + 1], 'weight')) break;
    if (i < sessions.length - 1 &&
        truthy(at(s, 'planned')) &&
        truthy(at(sessions[i + 1], 'planned')) &&
        !_samePlan(s['planned'], sessions[i + 1]['planned'])) {
      break;
    }
    if (policy == 'double') {
      final run = <num>[];
      for (var j = i - 1; j >= 0 && at(sessions[j], 'weight') == at(s, 'weight'); j--) {
        run.add(toNum(at(sessions[j], 'low')));
      }
      if (run.isNotEmpty && toNum(at(s, 'low')) > maxOf(run)) break;
    }
    if (policy == 'triple') {
      final run = <num>[];
      for (var j = i - 1; j >= 0 && at(sessions[j], 'weight') == at(s, 'weight') && _sameRows(sessions[j], s); j--) {
        run.add(_tripleActive(sessions[j]));
      }
      if (run.isNotEmpty && _tripleActive(s) > maxOf(run)) break;
    }
    n++;
  }
  return n;
}

/// The next prescription for one exercise: `{policy, kind, weight?, reps?, sec?, sets?, rowReps?,
/// why}` — kind one of first | up | hold | deload | off, `why` a template + args. A field the
/// policy has no opinion on is absent.
JMap nextPrescription(dynamic S, dynamic cfg, [dynamic routine]) {
  final mode = modeOf(cfg);
  final policy = policyFor(cfg, routine, mode);
  final unit = or(at(S, 'unit'), 'kg');
  final num inc = mode == 'time' ? (_gt0(at(cfg, 'inc')) ? toNum(cfg['inc']) : DEFAULT_SEC_INCREMENT) : weightIncrement(cfg, unit);
  if (policy == 'off') return {'policy': policy, 'kind': 'off'};
  final assisted = isAssisted(cfg);
  final owned = mode == 'reps' && !assisted ? ownedWeightsFor(S, cfg) : null;
  num harder(num weight, num step) => assisted
      ? math.max(0, addStep(weight, -step, inc))
      : owned != null
          ? (ownedUp(owned, weight, step > inc ? 2 : 1) ?? weight)
          : addStep(weight, step, inc);
  num easier(num weight) => assisted ? addStep(weight, inc, inc) : owned != null ? ownedDeload(owned, weight, DELOAD_FACTOR) : deloadTo(weight, inc);
  bool topped(num weight) => owned != null && ownedUp(owned, weight) == null;
  JMap toppedOut(num weight, [JMap extra = const {}]) => {
        'policy': policy, 'kind': 'hold', 'weight': weight, ...extra,
        'why': ['You’ve outgrown the rack: {0} {1} is your heaviest dumbbell, so the weight stays.', weight, unit],
      };

  final sessions = sessionsFor(S, at(cfg, 'id'), cfg, at(routine, 'id')).where((s) => s['mode'] == mode).toList();
  final JMap? last = sessions.isEmpty ? null : sessions.last;
  final triple = policy == 'triple' && mode == 'reps';
  final range3 = triple ? normalizeRepRange(or(at(cfg, 'reps'), 10), at(cfg, 'repsMin'), repStep(cfg)) : null;
  final sets3 = triple ? tripleSetsOf(cfg) : null;
  List<num> startRows(num reps) => List<num>.filled((sets3!['setsMin'] as num).toInt(), reps);
  if (last == null) {
    if (triple) {
      return {
        'policy': policy, 'kind': 'first', 'reps': range3!['repsMin'], 'sets': sets3!['setsMin'],
        'rowReps': startRows(range3['repsMin'] as num), 'why': ['Nothing logged yet, so this session sets the baseline.'],
      };
    }
    return {'policy': policy, 'kind': 'first', 'why': ['Nothing logged yet, so this session sets the baseline.']};
  }

  final num lastWeight = toNum(last['weight']);
  final num lastLow = toNum(or(last['low'], 0));
  final dynamic lastGoal = last['goal'];
  final cfgWeight = at(cfg, 'weight');

  // Start again from the plan (issue #275).
  final borrowed = truthy(at(routine, 'id')) && last['rid'] != routine['id'];
  if (truthy(last['planned']) ? planChanged(last['planned'], cfg) : borrowed) {
    final why = borrowed ? ['First time in this routine, so starting from its own target.'] : ['Plan changed, so starting from your new target.'];
    final JMap? setW = _gt0(cfgWeight) && truthy(last['planned']) && at(last['planned'], 'weight') != cfgWeight ? {'weight': cfgWeight} : null;
    if (mode == 'time') {
      final out = <String, dynamic>{'policy': policy, 'kind': 'hold', ...?setW};
      _put(out, 'sec', or(or(at(cfg, 'sec'), lastGoal), null));
      out['why'] = why;
      return out;
    }
    if (setW == null && lastWeight <= 0 && _climbsReps(cfg)) {
      final out = <String, dynamic>{'policy': policy, 'kind': 'hold', 'weight': 0};
      _put(out, 'reps', or(at(cfg, 'reps'), null));
      out['why'] = why;
      return out;
    }
    final JMap held = setW ?? (lastWeight > 0 ? {'weight': lastWeight} : _gt0(cfgWeight) ? {'weight': cfgWeight} : <String, dynamic>{});
    if (triple) {
      final num aim = setW != null
          ? range3!['repsMin'] as num
          : math.min(range3!['reps'] as num, math.max(range3['repsMin'] as num, lastLow + repStep(cfg)));
      return {'policy': policy, 'kind': 'hold', ...held, 'reps': aim, 'sets': sets3!['setsMin'], 'rowReps': startRows(aim), 'why': why};
    }
    if (policy == 'double') {
      final range = normalizeRepRange(or(or(at(cfg, 'reps'), lastGoal), 10), at(cfg, 'repsMin'), repStep(cfg));
      final num aim = setW != null
          ? range['repsMin'] as num
          : math.min(range['reps'] as num, math.max(range['repsMin'] as num, lastLow + repStep(cfg)));
      return {'policy': policy, 'kind': 'hold', ...held, 'reps': aim, 'why': why};
    }
    final out = <String, dynamic>{'policy': policy, 'kind': 'hold', ...held};
    _put(out, 'reps', or(at(cfg, 'reps'), null));
    out['why'] = why;
    return out;
  }

  final stalls = stallCount(sessions, policy);
  final deloadAt = DELOAD_AFTER[policy] ?? 3;
  final lastOk = truthy(last['ok']);

  if (mode == 'time') {
    final num goalOrCfg = toNum(or(or(lastGoal, at(cfg, 'sec')), 0));
    if (lastOk) {
      final sec = goalOrCfg + inc;
      return {'policy': policy, 'kind': 'up', 'sec': sec, 'why': ['Held every set for the full time. Target goes up by {0}s.', inc]};
    }
    if (stalls >= deloadAt) {
      final sec = deloadTo(goalOrCfg, 5);
      return {'policy': policy, 'kind': 'deload', 'sec': sec, 'why': ['Short {0} sessions in a row. Back off to {1}s and build up again.', stalls, sec]};
    }
    final out = <String, dynamic>{'policy': policy, 'kind': 'hold'};
    _put(out, 'sec', or(lastGoal, at(cfg, 'sec')));
    out['why'] = ['Came up short last time. Same target again.'];
    return out;
  }

  final w = lastWeight;
  // Bodyweight work progresses in reps, then sets (issue #33).
  if (w <= 0 && _climbsReps(cfg)) {
    final num goal = toNum(or(or(lastGoal, at(cfg, 'reps')), 0));
    final num planSets = math.max(1, toNum(or(at(cfg, 'sets'), 1)));
    final lastTarget = last['target'];
    final num reached = truthy(last['planned'])
        ? math.max(planSets, toNum(or(truthy(lastTarget) ? at(lastTarget, 'sets') : lastTarget, 0)))
        : planSets;
    final JMap keep = reached > planSets ? {'sets': reached} : <String, dynamic>{};
    if (!lastOk || goal <= 0) {
      final out = <String, dynamic>{'policy': policy, 'kind': 'hold', 'weight': 0};
      _put(out, 'reps', truthy(goal) ? goal : null);
      return {...out, ...keep, 'why': ['Bodyweight: same target again until every set is clean.']};
    }
    final num top = _gt0(at(cfg, 'repsMax')) ? toNum(cfg['repsMax']) : 0;
    if (top > 0 && goal >= top) {
      final sets = reached + 1;
      final num bottom = math.max(1, math.min(toNum(or(at(cfg, 'reps'), top)), top));
      if (sets <= MAX_BW_SETS) {
        return {'policy': policy, 'kind': 'up', 'weight': 0, 'reps': bottom, 'sets': sets, 'why': ['{0} reps in every set! Add a set and go back to {1}.', goal, bottom]};
      }
      return {'policy': policy, 'kind': 'hold', 'weight': 0, 'reps': goal, ...keep, 'why': ['{0} sets of {1}. Time to add weight or try a harder variation.', sets - 1, goal]};
    }
    final next = goal + repStep(cfg);
    return {'policy': policy, 'kind': 'up', 'weight': 0, 'reps': next, ...keep, 'why': ['Bodyweight: every rep last time, so go for {0} this time.', next]};
  }
  // A loaded lift logged at 0 had its weight never typed in.
  if (w <= 0) {
    return {
      'policy': policy, 'kind': 'hold', if (_gt0(cfgWeight)) 'weight': cfgWeight,
      'why': ['No weight logged last time. Enter what you lift and progression takes it from there.'],
    };
  }

  JMap? epleyDeload() {
    if (assisted) return null;
    if (mode != 'reps' || (policy != 'linear' && policy != 'double')) return null;
    final previous = truthy(last['target']) ? asMap(last['target']) : <String, dynamic>{};
    final target = <String, dynamic>{
      ...asMap(cfg),
      ...previous,
      'weight': _nn(previous['weight'], at(cfg, 'weight')),
      'reps': _nn(previous['reps'], at(cfg, 'reps')),
      'repsMin': _nn(previous['repsMin'], at(cfg, 'repsMin')),
      'sets': _nn(at(cfg, 'sets'), previous['sets']),
      'bodyweight': _nn(previous['bodyweight'], at(cfg, 'bodyweight')),
      'side': _nn(previous['side'], at(cfg, 'side')),
      'intensifier': _nn(previous['intensifier'], at(cfg, 'intensifier')),
    };
    if (isBw(target) || at(target['intensifier'], 'type') == 'restpause') return null;
    final candidate = selectDeloadCandidate(
      currentWeight: w,
      targetWeight: target['weight'],
      targetReps: target['reps'],
      step: inc,
      factor: deloadFactorOf(cfg),
      reps: target['reps'],
      repsMin: policy == 'double' ? target['repsMin'] : null,
      perSide: isPerSide(target),
      owned: owned,
    );
    if (candidate == null) return null;
    final held = (candidate['weight'] as num) >= w;
    final out = <String, dynamic>{'policy': policy, 'kind': 'deload', 'weight': candidate['weight'], 'reps': candidate['reps']};
    _put(out, 'sets', target['sets']);
    out['target1RM'] = candidate['target1RM'];
    out['deloadFactor'] = candidate['factor'];
    out['why'] = held
        ? ['Stuck for {0} sessions. Hold {1} {2} and use {3} reps.', stalls, candidate['weight'], unit, candidate['reps']]
        : ['Stuck for {0} sessions. Epley deload to {1} {2} for {3} reps.', stalls, candidate['weight'], unit, candidate['reps']];
    return out;
  }

  if (triple) {
    final num top = range3!['reps'] as num;
    final num bottom = range3['repsMin'] as num;
    final num setsMin = sets3!['setsMin'] as num;
    final num setsMax = sets3['setsMax'] as num;
    final step = repStep(cfg);
    final rows = _tripleRowsOf(last, setsMin, setsMax, range3);
    JMap out(String kind, num weight, List<num> next, List<dynamic> why) =>
        {'policy': policy, 'kind': kind, 'weight': weight, 'reps': next[0], 'sets': next.length, 'rowReps': next, 'why': why};
    if (stalls >= deloadAt) {
      num? dw;
      if (!assisted) {
        final perSide = isPerSide(cfg);
        final target1RM = deloadTarget1RM(w, maxOf(rows), deloadFactorOf(cfg), perSide);
        final num? ideal = target1RM == null ? null : target1RM / (1 + (perSide ? bottom / 2 : bottom) / 30);
        final grid = ideal == null ? <num>[] : _positiveGridAround(ideal, inc, w, true);
        if (grid.isNotEmpty) dw = grid.reduce((a, b) => (b - ideal!).abs() < (a - ideal).abs() ? b : a);
      }
      dw ??= easier(w);
      return out('deload', dw, startRows(bottom), assisted
          ? ['Stuck for {0} sessions. Back to {1} {2} of help, start again at {3} sets of {4}.', stalls, dw, unit, setsMin, bottom]
          : ['Stuck for {0} sessions. Deload to {1} {2} and start again at {3} sets of {4}.', stalls, dw, unit, setsMin, bottom]);
    }
    if (!lastOk) {
      return out('hold', w, rows, stalls == 0
          ? ['Short of the target, but more reps than before. Same sets and reps again.']
          : ['Missed reps last time. Same sets and reps again ({0} of {1} to go).', deloadAt - stalls, deloadAt]);
    }
    final lastReps = asList(last['reps']);
    final got = [for (var k = 0; k < rows.length; k++) math.min(top, math.max(rows[k], numOr(at(lastReps, k), 0)))];
    num climb(num v) => math.min(top, math.max(bottom, v + step));
    final n = got.length;
    final baseLow = minOf(got.sublist(0, math.min(n, setsMin.toInt())));
    if (n <= setsMin && baseLow < top) {
      final aim = climb(baseLow);
      return out('hold', w, List<num>.filled(math.max(n, setsMin.toInt()), aim), ['Same weight, aim for {0} reps in every set.', aim]);
    }
    final active = got[n - 1];
    if (n > setsMin && active < top) {
      final aim = climb(active);
      return out('hold', w, [...got.sublist(0, n - 1).map((_) => top), aim], ['Same weight, aim for {0} reps on the last set.', aim]);
    }
    if (n < setsMax) return out('up', w, [...got.map((_) => top), bottom], ['{0} reps in every set! Add a set at {1} reps.', top, bottom]);
    return out('up', harder(w, inc), startRows(bottom), assisted
        ? ['Top of the range on all {0} sets. {1} {2} less help, back to {3} sets of {4}.', n, inc, unit, setsMin, bottom]
        : ['Top of the range on all {0} sets. {1} {2} more, back to {3} sets of {4}.', n, inc, unit, setsMin, bottom]);
  }

  if (policy == 'double') {
    final range = normalizeRepRange(or(or(at(cfg, 'reps'), lastGoal), 10), at(cfg, 'repsMin'), repStep(cfg));
    final num top = range['reps'] as num;
    final num bottom = range['repsMin'] as num;
    if (lastOk && lastLow >= top) {
      if (topped(w)) return toppedOut(w, {'reps': top});
      final up = harder(w, inc);
      final by = owned != null ? mathRound((up - w) * 100) / 100 : inc;
      return {
        'policy': policy, 'kind': 'up', 'weight': up, 'reps': bottom,
        'why': assisted
            ? ['Top of the rep range in every set. {0} {1} less help, back to {2} reps.', inc, unit, bottom]
            : ['Top of the rep range in every set. {0} {1} more, back to {2} reps.', by, unit, bottom],
      };
    }
    if (stalls >= deloadAt) {
      final selected = epleyDeload();
      if (selected != null) return selected;
      final dw = easier(w);
      return {
        'policy': policy, 'kind': 'deload', 'weight': dw, 'reps': bottom,
        'why': assisted
            ? ['Stuck for {0} sessions. Back to {1} {2} of help, then build up again.', stalls, dw, unit]
            : ['Stuck for {0} sessions. Deload to {1} {2}.', stalls, dw, unit],
      };
    }
    final aim = math.min(top, math.max(bottom, lastLow + repStep(cfg)));
    return {'policy': policy, 'kind': 'hold', 'weight': w, 'reps': aim, 'why': ['Same weight, aim for {0} reps this time.', aim]};
  }

  // linear + greyskull
  if (lastOk) {
    final num amrap = toNum(or(last['amrap'], 0));
    final dbl = policy == 'greyskull' && _gt0(lastGoal) && amrap >= toNum(lastGoal) * 2;
    if (topped(w)) return toppedOut(w);
    final up = harder(w, dbl ? inc * 2 : inc);
    final step = owned != null ? mathRound((up - w) * 100) / 100 : dbl ? inc * 2 : inc;
    return {
      'policy': policy, 'kind': 'up', 'weight': up,
      'why': dbl
          ? ['Last set hit {0} reps, twice the target! Take a double jump of {1} {2}.', last['amrap'], step, unit]
          : assisted
              ? ['Every rep last time. {0} {1} less help.', step, unit]
              : ['Every rep last time. {0} {1} more.', step, unit],
    };
  }
  if (stalls >= deloadAt) {
    final selected = epleyDeload();
    if (selected != null) return selected;
    final dw = easier(w);
    return {
      'policy': policy, 'kind': 'deload', 'weight': dw,
      'why': assisted
          ? ['Missed reps. {0} {1} of help while you build back up.', dw, unit]
          : stalls > 1
              ? ['Missed reps {0} sessions running. Reset to {1} {2} and work back up.', stalls, dw, unit]
              : ['Missed reps. Reset to {0} {1} and work back up.', dw, unit],
    };
  }
  return {'policy': policy, 'kind': 'hold', 'weight': w, 'why': ['Missed reps last time. Same weight again ({0} of {1} to go).', deloadAt - stalls, deloadAt]};
}

/// Apply a prescription to freshly built sets: only the fields the policy decided, only on sets
/// not logged yet. [floor] is the lift's bar, which re-ramped warm-ups never go under. Returns
/// [sets] itself when there is nothing to apply.
List<dynamic> applyPrescription(List<dynamic> sets, dynamic p, [dynamic step = 2.5, num floor = 0]) {
  if (!truthy(p) || at(p, 'kind') == 'off' || (at(p, 'kind') == 'first' && !truthy(at(p, 'rowReps')))) return sets;
  final pw = at(p, 'weight'), pr = at(p, 'reps'), ps = at(p, 'sec');
  final out = sets.map<dynamic>((s) {
    if (truthy(at(s, 'done'))) return s;
    if (isWarmupRow(s)) {
      if (pr != null && at(s, 'r') != null) return <String, dynamic>{...asMap(s), 'r': pr};
      if (ps != null && at(s, 'sec') != null) return <String, dynamic>{...asMap(s), 'sec': ps};
      return s;
    }
    if (isSideSet(s)) {
      final sides = <String, dynamic>{
        for (final side in ['L', 'R'])
          side: truthy(at(s['sides'][side], 'done'))
              ? s['sides'][side]
              : <String, dynamic>{
                  ...asMap(s['sides'][side]),
                  'w': ?pw,
                  if (pr != null) 'r': toNum(pr) / 2,
                },
      };
      return syncSideAggregate(<String, dynamic>{...asMap(s), 'sides': sides});
    }
    final o = <String, dynamic>{...asMap(s)};
    if (pw != null) o['w'] = pw;
    if (pr != null) o['r'] = pr;
    if (ps != null) o['sec'] = ps;
    return o;
  }).toList();
  final workRows = out.where((s) => !isWarmupRow(s)).toList();
  if (toNum(at(p, 'sets')) > workRows.length) {
    if (workRows.isEmpty) return rerampWarmups(out, step, floor);
    final seed = workRows.last;
    final plainSeed = <String, dynamic>{...asMap(seed)}
      ..remove('drops')
      ..remove('clusters');
    final want = toNum(p['sets']);
    while (out.where((s) => !isWarmupRow(s)).length < want) {
      out.add(isSideSet(seed)
          ? makeSideSet({'w': pw ?? at(seed, 'w'), 'r': pr ?? at(seed, 'r')})
          : <String, dynamic>{...plainSeed, 'done': false});
    }
  }
  final rowReps = at(p, 'rowReps');
  if (rowReps is List) {
    var k = -1;
    for (var i = 0; i < out.length; i++) {
      if (isWarmupRow(out[i])) continue;
      k++;
      final r = at(rowReps, k);
      if (truthy(at(out[i], 'done')) || !_gt0(r)) continue;
      final row = out[i];
      out[i] = isSideSet(row)
          ? syncSideAggregate(<String, dynamic>{
              ...asMap(row),
              'sides': <String, dynamic>{
                for (final side in ['L', 'R'])
                  side: truthy(at(row['sides'][side], 'done'))
                      ? row['sides'][side]
                      : <String, dynamic>{...asMap(row['sides'][side]), 'r': toNum(r) / 2},
              },
            })
          : <String, dynamic>{...asMap(row), 'r': r};
    }
  }
  return rerampWarmups(out, step, floor);
}
