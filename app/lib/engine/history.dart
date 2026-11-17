// Port of frontend/src/lib/history.js — pure helpers over the state object S: how an exercise is
// logged (mode, bodyweight, per side), set labels, planned-set building (warm-ups, pyramids,
// intensifiers), routine/day resolution (incl. the coach queue), supersets, row editing helpers,
// volume and best-weight readers. Comments explaining the rules live in the JS source.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:math' as math;

import 'backoff.dart';
import 'bar.dart';
import 'dumbbells.dart';
import 'exercises.dart';
import 'format.dart';
import 'i18n_core.dart';
import 'incline.dart';
import 'js.dart';
import 'pyramid.dart';
import 'queue.dart';
import 'speed.dart';
import 'superset_meta.dart';
import 'workout_model.dart';

JMap _objectOf(dynamic value) => value is Map ? asMap(value) : <String, dynamic>{};

/// `Number(o.key)` where a missing key is undefined (NaN) and an explicit null is 0.
num _numU(dynamic o, String key) => o is Map && o.containsKey(key) ? toNum(o[key]) : double.nan;

/// `${o.key}` in a template literal: a missing key prints 'undefined'.
String _tpl(dynamic o, String key) => o is Map && o.containsKey(key) ? jsString(o[key]) : 'undefined';

/// JS `a > 0` for a value that may be anything.
bool _gt0(dynamic v) => v is num ? v > 0 : (v is String || v is bool ? toNum(v) > 0 : false);

/// `list[i] || list[list.length - 1]`.
dynamic _rowOr(List<dynamic> sets, int i) {
  final v = at(sets, i);
  return truthy(v) ? v : (sets.isEmpty ? null : sets.last);
}

List<dynamic> _workRowsForMode(dynamic entry, [String mode = 'reps']) {
  final source = _objectOf(entry);
  final target = _objectOf(or(source['target'], source));
  final expectedMode = normalizeMode(mode, 'reps');
  return (source['sets'] is List ? source['sets'] as List : <dynamic>[])
      .where((set) => phaseForSet(set) == 'work' && modeForSet(set, target) == expectedMode)
      .toList();
}

/// When a workout happened, as epoch ms: its own start, else noon on its day, else NaN.
num workoutAt(dynamic w) {
  final start = at(w, 'start');
  if (isFiniteNum(start)) return start as num;
  final day = at(w, 'd');
  if (day is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
    return isoNoon(day)?.millisecondsSinceEpoch ?? double.nan;
  }
  return double.nan;
}

/// How an exercise is logged: 'reps', 'time' or 'cardio' (explicit mode, else the body part).
String modeOf(dynamic cfg) {
  final m = truthy(cfg) ? at(cfg, 'mode') : null;
  if (m == 'reps' || m == 'time' || m == 'cardio') return m as String;
  return isCardio(truthy(cfg) ? at(cfg, 'id') : cfg) ? 'cardio' : 'reps';
}

bool isTimed(dynamic cfg) => modeOf(cfg) == 'time';

bool isBw(dynamic cfg) {
  if (truthy(cfg) && at(cfg, 'bodyweight') != null) return truthy(at(cfg, 'bodyweight'));
  return isBodyweightEq(truthy(cfg) ? at(cfg, 'id') : cfg);
}

bool isPerSide(dynamic cfg) => truthy(cfg) && truthy(at(cfg, 'side'));

num sideReps(dynamic reps) => numOr(reps, 0) / 2;

int repStep(dynamic cfg) => isPerSide(cfg) ? 2 : 1;

num setsFromRows(dynamic cfg, dynamic rows) {
  final n = math.max(0, numOr(rows, 0));
  return modeOf(cfg) == 'time' && isPerSide(cfg) ? (n / 2).ceil() : n;
}

/// mm:ss for a work duration.
String fmtSec(dynamic sec) {
  final n = math.max(0, mathRound(numOr(sec, 0))).toInt();
  return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
}

const Map<String, Map<String, dynamic>> EFFORT = {
  'rir': {'f': 'rir', 'hd': 'RIR', 'step': 0.5, 'min': 0, 'max': 10},
  'rpe': {'f': 'rpe', 'hd': 'RPE', 'step': 0.5, 'min': 6, 'max': 10},
};

/// One tap of an effort stepper; null means "nothing logged".
dynamic stepEffort(dynamic kind, dynamic cur, num dir) {
  final e = EFFORT[kind];
  if (e == null) return cur;
  final num min = e['min'], max = e['max'], step = e['step'];
  if (cur == null) return dir < 0 ? null : min;
  final n = mathRound((toNum(cur) + dir * step) * 100) / 100;
  if (dir < 0 && n < min) return null;
  return dir > 0 ? math.min(max, n) : math.max(min, n);
}

/// A typed effort is capped but not floored.
dynamic capEffort(dynamic kind, dynamic v) =>
    v == null || EFFORT[kind] == null ? v : math.min(EFFORT[kind]!['max'] as num, toNum(v));

/// Which scale a profile logs: 'rir', 'rpe' or 'none'.
String effortOf(dynamic S) {
  final e = truthy(S) ? at(S, 'effort') : null;
  return e == 'none' || EFFORT[e] != null ? e as String : (truthy(S) && truthy(at(S, 'showRir')) ? 'rir' : 'none');
}

String _effortTail(dynamic s) {
  final k = at(s, 'rir') != null ? 'rir' : at(s, 'rpe') != null ? 'rpe' : null;
  return k != null ? ' (${EFFORT[k]!['hd']} ${fmtNum(s[k])})' : '';
}

const Set<String> _EXPLICIT_MODES = {'reps', 'time', 'cardio'};

/// One-line summary of a logged set.
String setLabel(dynamic id, dynamic s, [dynamic cfg, dynamic speedUnit]) {
  final JMap c = truthy(cfg) ? {...asMap(cfg), 'id': at(cfg, 'id') ?? id} : {'id': id};
  var mode = modeOf(c);
  if (!truthy(cfg) && !_gt0(at(s, 'r'))) {
    if (_gt0(at(s, 'min')) || _gt0(at(s, 'speed'))) {
      mode = 'cardio';
    } else if (_gt0(at(s, 'sec'))) {
      mode = 'time';
    }
  }
  if (!_EXPLICIT_MODES.contains(at(cfg, 'mode')) &&
      mode != 'reps' &&
      _gt0(at(s, 'r')) &&
      !(_gt0(at(s, 'min')) || _gt0(at(s, 'speed')) || _gt0(at(s, 'sec')))) {
    mode = 'reps';
  }
  if (mode == 'cardio') {
    final grade = hasIncline(s) ? ' · ${t('{0}% incline', [fmtNum(toNum(s['incline']))])}' : '';
    return '${jsString(or(at(s, 'min'), 0))} min @ ${fmtSpeed(or(at(s, 'speed'), 0), speedUnit)}$grade';
  }
  final fail = isFailureSet(s) ? ' ${t('F')}' : '';
  if (mode == 'time') return fmtSec(at(s, 'sec')) + (_gt0(at(s, 'w')) ? ' · ${fmtNum(s['w'])}' : '') + fail;
  final bw = isBw(c);
  final meaning = !bw && bellsIn(c) == 2 ? dbLoadOf(c['dbLoad']) : null;
  String load(dynamic w, dynamic reps) {
    final r = jsString(reps);
    if (bw) return (_gt0(w) ? '+${fmtNum(w)} × ' : '') + r;
    if (meaning == 'each') return '${t('{0} each', [fmtNum(or(w, 0))])} × $r';
    if (meaning == 'total') return '${t('{0} total', [fmtNum(or(w, 0))])} × $r';
    return '${fmtNum(or(w, 0))}×$r';
  }

  final planned = at(c['intensifier'], 'type') == 'restpause';
  dynamic repsOf(dynamic side) {
    final reps = or(at(side, 'r'), 0);
    final repsN = toNum(reps);
    final bursts = clustersOf(side).map((b) => numOr(at(b, 'r'), 0)).where((r) => r > 0).toList();
    final sum = bursts.fold<num>(0, (a, b) => a + b);
    if (bursts.isEmpty || sum > repsN || (planned && sum != repsN)) return reps;
    return jsJoin(repsN > sum ? [repsN - sum, ...bursts] : bursts, '+');
  }

  String oneSide(dynamic side) {
    final drops = dropsOf(side).where((d) => numOr(at(d, 'r'), 0) > 0);
    return load(at(side, 'w'), repsOf(side)) +
        drops.map((d) => ' ↘ ${load(numOr(at(d, 'w'), 0), toNum(at(d, 'r')))}').join('');
  }

  if (isSideSet(s)) {
    final partial = s['sides']['L']['done'] != s['sides']['R']['done'];
    return ['L', 'R'].map((key) {
          final side = s['sides'][key];
          return '${t(key)} ${partial && !truthy(at(side, 'done')) ? '–' : oneSide(side) + _effortTail(side)}';
        }).join(' · ') +
        fail;
  }
  return oneSide(s) + fail + _effortTail(s);
}

/// Default config for a freshly added exercise.
JMap defaultConfig(dynamic id, [dynamic mode]) {
  final m = truthy(mode) ? mode : modeOf({'id': id});
  if (m == 'cardio') return {'sets': 1, 'min': 20, 'speed': 8};
  final JMap bw = isBodyweightEq(id) ? {'bodyweight': true} : {};
  if (m == 'time') return {'sets': 3, 'sec': 45, 'weight': 0, 'mode': 'time', ...bw};
  return {'sets': 3, 'reps': 10, 'weight': 0, 'mode': 'reps', ...bw};
}

bool _hasRange(dynamic cfg) {
  final lo = at(cfg, 'repsMin');
  return _gt0(lo) && at(cfg, 'reps') != null && toNum(lo) < toNum(at(cfg, 'reps'));
}

String _repsOfCfg(dynamic cfg, [String Function(dynamic v)? fmt]) {
  final f = fmt ?? (dynamic v) => v == null ? 'undefined' : jsString(v);
  return _hasRange(cfg) ? '${f(cfg['repsMin'])}–${f(cfg['reps'])}' : f(at(cfg, 'reps'));
}

/// "2 × 10", "3 × 8–12", "2 × 0:45": what a plan asks for per set, without its load.
String setsRepsOf(dynamic cfg) {
  final mode = modeOf(cfg);
  final n = or(at(cfg, 'sets'), 1);
  if (mode == 'cardio') return '${jsString(n)} × ${jsString(or(at(cfg, 'min'), 20))} min';
  if (mode == 'time') return '${jsString(n)} × ${fmtSec(or(at(cfg, 'sec'), 45))}';
  if (isPyramid(cfg)) return pyramidLabel(cfg['pyramid'] as List);
  final setsMax = at(cfg, 'setsMax');
  final sets = setsMax != null && toNum(setsMax) > toNum(n) ? '${jsString(n)}–${jsString(setsMax)}' : jsString(n);
  return '$sets × ${_repsOfCfg(cfg)}';
}

/// One-line summary of a planned exercise ("3 × 10 · 60 kg").
String exLine(dynamic cfg, dynamic unit, [dynamic speedUnit]) {
  final mode = modeOf(cfg);
  final n = or(at(cfg, 'sets'), 1);
  final weight = at(cfg, 'weight');
  final backoff = mode == 'reps' && _gt0(weight) ? backoffStepOf(cfg, unit) : 0;
  final u = jsString(unit);
  final load = !truthy(weight)
      ? ''
      : truthy(backoff)
          ? ' · ${isBw(cfg) ? '+' : ''}${backoffWeights(weight, toNum(n), backoff).map(fmtNum).join(' → ')} $u'
          : ' · ${isBw(cfg) ? '+' : ''}${fmtNum(weight)} $u';
  if (mode == 'cardio') {
    return '${jsString(n)} × ${jsString(or(at(cfg, 'min'), 20))} min @ ${fmtSpeed(or(at(cfg, 'speed'), 8), speedUnit)}';
  }
  if (mode == 'time') return '${setsRepsOf(cfg)}$load${isPerSide(cfg) ? ' · ${t('per side')}' : ''}';
  final split = isPerSide(cfg) ? ' · ${t('{0}/side', [_repsOfCfg(cfg, (v) => fmtNum(sideReps(v)))])}' : '';
  return '${setsRepsOf(cfg)}$load$split';
}

/// Drop superset ids that no longer have an adjacent partner (mutates [ex]).
void cleanupSg(dynamic ex) {
  final list = asList(ex);
  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    final sg = at(e, 'sg');
    if (truthy(sg) && !(at(at(list, i - 1), 'sg') == sg || at(at(list, i + 1), 'sg') == sg)) {
      (e as Map).remove('sg');
    }
  }
  syncSupersetMeta(list);
}

List<int> _contiguousSgGroup(List<dynamic> items, int idx) {
  final sg = at(at(items, idx), 'sg');
  if (!truthy(sg)) return [idx];
  var first = idx, last = idx;
  while (first > 0 && at(items[first - 1], 'sg') == sg) {
    first--;
  }
  while (last + 1 < items.length && at(items[last + 1], 'sg') == sg) {
    last++;
  }
  return [for (var i = first; i <= last; i++) i];
}

String _freshSg(List<dynamic> items, int first, int second) {
  final base = 'sg-${math.min(first, second)}-${math.max(first, second)}';
  var sg = base;
  var n = 2;
  while (items.any((e) => at(e, 'sg') == sg)) {
    sg = '$base-${n++}';
  }
  return sg;
}

/// Pair two adjacent entries, merging any contiguous groups on either side. Throws
/// [ArgumentError] (JS TypeError) for a non-list, [RangeError] for bad indexes.
List<dynamic> pairAdjacent(dynamic items, dynamic first, dynamic second, [dynamic groupId]) {
  if (items is! List) throw ArgumentError('Superset entries must be an array');
  if (first is! int || second is! int || !truthy(at(items, first)) || !truthy(at(items, second))) {
    throw RangeError('Superset entry indexes are invalid');
  }
  if ((first - second).abs() != 1) throw RangeError('Superset entries must be adjacent');
  final next = items.map<dynamic>((e) => <String, dynamic>{...asMap(e)}).toList();
  final left = math.min(first, second), right = math.max(first, second);
  final group = truthy(groupId)
      ? groupId
      : truthy(next[left]['sg'])
          ? next[left]['sg']
          : truthy(next[right]['sg'])
              ? next[right]['sg']
              : _freshSg(next, left, right);
  final members = <int>{..._contiguousSgGroup(next, left), ..._contiguousSgGroup(next, right)};
  for (final i in members) {
    next[i]['sg'] = group;
  }
  return next;
}

/// Remove one entry from its superset and clean ids left without an adjacent partner.
List<dynamic> unpairSuperset(dynamic items, dynamic idx) {
  if (items is! List) throw ArgumentError('Superset entries must be an array');
  if (idx is! int || !truthy(at(items, idx))) throw RangeError('Superset entry index is invalid');
  final next = items.map<dynamic>((e) => <String, dynamic>{...asMap(e)}).toList();
  (next[idx] as Map).remove('sg');
  for (var i = 0; i < next.length; i++) {
    final e = next[i];
    final sg = e['sg'];
    if (truthy(sg) && !(at(at(next, i - 1), 'sg') == sg || at(at(next, i + 1), 'sg') == sg)) e.remove('sg');
  }
  return next;
}

/// Is this completed entry excluded from progression / session read-back?
bool entryExcluded(dynamic w, dynamic entry) => at(w, 'excludeFromProgression') == true || at(entry, 'noProg') == true;

/// Which routine a saved entry was planned by (issue #216), or null.
dynamic entryRoutineId(dynamic w, dynamic en) {
  if (truthy(at(en, 'rid'))) return en['rid'];
  if (asList(or(at(w, 'entries'), const [])).any((e) => truthy(e) && truthy(at(e, 'rid')))) return null;
  final ids = at(w, 'routineIds') ?? <dynamic>[];
  final first = ids is List ? at(ids, 0) : ids;
  return first ?? at(w, 'routineId');
}

dynamic _entryIn(dynamic w, dynamic exId, dynamic rid) => jsFind(asList(or(at(w, 'entries'), const [])),
    (e) => truthy(e) && at(e, 'id') == exId && (!truthy(rid) || entryRoutineId(w, e) == rid));

/// The last counting session of an exercise: `{d, sets, target, rid?, planned?}`, or null.
JMap? lastEntryFor(dynamic S, dynamic exId, [dynamic rid]) {
  if (truthy(rid)) {
    final own = _lastEntryIn(S, exId, rid);
    if (own != null) return own;
  }
  return _lastEntryIn(S, exId, null);
}

JMap? _lastEntryIn(dynamic S, dynamic exId, dynamic rid) {
  final workouts = asList(or(at(S, 'workouts'), const []));
  for (var i = workouts.length - 1; i >= 0; i--) {
    final w = workouts[i];
    final en = _entryIn(w, exId, rid);
    if (en == null) continue;
    if (entryExcluded(w, en)) continue;
    final done = asList(at(en, 'sets')).where((s) => truthy(at(s, 'done')) && !isWarmupRow(s)).toList();
    if (done.isNotEmpty) {
      final slot = entryRoutineId(w, en);
      return <String, dynamic>{
        'd': at(w, 'd'),
        'sets': done,
        'target': truthy(at(en, 'target')) ? en['target'] : null,
        if (truthy(slot)) 'rid': slot,
        if (truthy(at(en, 'planned'))) 'planned': en['planned'],
      };
    }
  }
  return null;
}

/// How long any single note may get.
const int NOTE_MAX = 500;

/// The most recent session note the user pinned for this exercise: `{note, d}`, or null.
JMap? pinnedNoteFor(dynamic S, dynamic exId) {
  final workouts = asList(or(at(S, 'workouts'), const []));
  final editing = at(at(S, 'active'), 'editingWorkoutId');
  for (var i = workouts.length - 1; i >= 0; i--) {
    final w = workouts[i];
    if (editing != null && (at(w, 'id') != null ? w['id'] : '${_tpl(w, 'd')}|${_tpl(w, 'start')}') == editing) continue;
    final en = jsFind(asList(or(at(w, 'entries'), const [])), (e) => at(e, 'id') == exId);
    final note = jsString(or(at(en, 'note'), '')).trim();
    if (note.isNotEmpty && truthy(at(en, 'notePin'))) return {'note': note, 'd': at(w, 'd')};
  }
  return null;
}

/// The standing note for an exercise, or null.
String? exNoteFor(dynamic S, dynamic exId) {
  final v = jsString(or(at(or(at(S, 'exNotes'), const {}), exId is String ? exId : jsString(exId)), '')).trim();
  return v.isEmpty ? null : v;
}

/// A freestyle exercise starts with the last target the user actually trained.
JMap freestyleConfig(dynamic S, dynamic cfg) {
  final last = lastEntryFor(S, at(cfg, 'id'));
  if (last == null) return <String, dynamic>{...asMap(cfg)};
  final lastTarget = <String, dynamic>{..._objectOf(or(last['target'], const {}))}..remove('dbLoad');
  return <String, dynamic>{
    ...asMap(cfg),
    ...lastTarget,
    'id': at(cfg, 'id'),
    'sets': math.max(1, (last['sets'] as List).length),
  };
}

/// The best weight ever logged for an exercise (lowest on an assistance machine); 0 for none.
/// [as] compares dumbbell weights in that meaning (lib/dumbbells.js).
num bestWeightFor(dynamic S, dynamic exId, [dynamic as]) {
  final H = truthy(as) ? historyAs(S, exId, as) : S;
  num best = 0;
  for (final w in asList(at(H, 'workouts'))) {
    for (final e in asList(at(w, 'entries'))) {
      if (at(e, 'id') != exId) continue;
      final entryBest = bestWeightForEntry(e);
      if (entryBest > 0) best = best > 0 ? betterWeight(exId, best, entryBest) : entryBest;
    }
  }
  return best;
}

/// The routine ids planned for a date, in merge order (`[]` = rest). [today] defaults to now.
List<dynamic> effectiveRoutineIds(dynamic S, dynamic iso, [String? today]) {
  today ??= todayISO();
  final routines = asList(at(S, 'routines'));
  final ov = at(at(S, 'dayPlan'), jsString(iso));
  if (ov == 'rest') return [];
  final pin = pinState(S, ov);
  if (pin == null && truthy(ov) && routines.any((r) => at(r, 'id') == ov)) return [ov];
  final d = isoNoon(iso);
  final wdRaw = at(at(S, 'week'), d == null ? 'NaN' : '${jsDay(d)}');
  final wdList = truthy(wdRaw) ? (wdRaw is List ? wdRaw : [wdRaw]) : const [];
  final weekday = wdList.where((id) => routines.any((r) => at(r, 'id') == id)).toList();
  final q = pin == 'open' ? ov : queueNext(S, jsString(iso), today);
  final own = truthy(q) || queueLiveOn(S, jsString(iso), today)
      ? weekday.where((id) => !asList(at(at(S, 'queue'), 'ids')).contains(id)).toList()
      : weekday;
  return truthy(q) ? [q, ...own] : own;
}

/// The routines planned for a date (see [effectiveRoutineIds]).
List<dynamic> effectiveRoutines(dynamic S, dynamic iso, [String? today]) => effectiveRoutineIds(S, iso, today)
    .map((id) => jsFind(asList(at(S, 'routines')), (r) => at(r, 'id') == id))
    .where(truthy)
    .toList();

dynamic effectiveRoutineId(dynamic S, dynamic iso, [String? today]) => at(effectiveRoutineIds(S, iso, today), 0);
dynamic effectiveRoutine(dynamic S, dynamic iso, [String? today]) => at(effectiveRoutines(S, iso, today), 0);

/// The next day that has something to train after [iso]: `{iso, weekday, routines, routine}`.
JMap? nextTrainingDay(dynamic S, dynamic iso, [String? today]) {
  final base = isoNoon(iso);
  if (base == null) return null;
  for (var i = 1; i <= 7; i++) {
    final d = DateTime(base.year, base.month, base.day + i, 12);
    final nextIso = isoOf(d);
    final routines = effectiveRoutines(S, nextIso, today);
    if (routines.any((r) => asList(or(at(r, 'ex'), const [])).isNotEmpty)) {
      return {'iso': nextIso, 'weekday': jsDay(d), 'routines': routines, 'routine': routines[0]};
    }
  }
  return null;
}

/// The rows a planned exercise starts a session with: its work sets, preceded by
/// `cfg.warmupSets` warm-ups. [options]: preferLast, useTarget, planReps, rid, step.
List<dynamic> buildSets(dynamic S, dynamic cfg, [dynamic options]) {
  final opts = _objectOf(options);
  final rows = _buildWorkSets(S, cfg, opts);
  final warm = math.max(0, math.min(MAX_PLANNED_WARMUPS, numOr(mathRound(toNum(at(cfg, 'warmupSets'))), 0))).toInt();
  if (warm == 0) return rows;
  final mode = modeOf(cfg);
  var out = rows;
  final floor = barFloor(S, at(cfg, 'id'));
  for (var i = 0; i < warm; i++) {
    out = insertWarmupRow(out, mode, cfg, opts['step'] ?? 2.5, floor);
  }
  return out;
}

const int MAX_PLANNED_WARMUPS = 5;

/// The lightest warm-up a lift can have: its bar, 0 for anything without one.
num barFloor(dynamic S, dynamic exId) => toNum(or(barWeightFor(S, exId), 0));

List<dynamic> _buildWorkSets(dynamic S, dynamic cfg, JMap options) {
  final preferLast = truthy(options['preferLast']);
  final useTarget = truthy(options['useTarget']);
  final last = lastEntryFor(S, at(cfg, 'id'), options['rid']);
  final lastSets = last == null ? const <dynamic>[] : last['sets'] as List;
  final n = math.max(1, numOr(at(cfg, 'sets'), 1)).toInt();
  final mode = modeOf(cfg);
  final sets = <dynamic>[];
  dynamic prevAt(int i) => !useTarget && last != null ? _rowOr(lastSets, i) : null;
  final planReps = truthy(options['planReps']) && !preferLast && _gt0(at(cfg, 'reps'));

  if (mode == 'cardio') {
    for (var i = 0; i < n; i++) {
      final prev = prevAt(i);
      sets.add(<String, dynamic>{
        'min': truthy(prev) ? at(prev, 'min') : or(at(cfg, 'min'), 20),
        'speed': truthy(prev) ? at(prev, 'speed') : or(at(cfg, 'speed'), 8),
        ...inclineFrom(prev),
        'done': false,
      });
    }
    return sets;
  }
  if (mode == 'time') {
    final count = isPerSide(cfg) ? n * 2 : n;
    for (var i = 0; i < count; i++) {
      final prev = prevAt(i);
      final carried = truthy(prev) && _gt0(at(prev, 'sec')) ? prev : null;
      final row = <String, dynamic>{
        'sec': carried != null ? carried['sec'] : or(at(cfg, 'sec'), 45),
        'w': carried != null ? or(carried['w'], 0) : or(at(cfg, 'weight'), 0),
        'done': false,
      };
      if (isPerSide(cfg)) row['side'] = i % 2 == 0 ? 'L' : 'R';
      sets.add(row);
    }
    return sets;
  }
  final conf = at(or(at(S, 'exWeights'), const {}), jsString(at(cfg, 'id')));
  for (var i = 0; i < n; i++) {
    final prev = prevAt(i);
    final usable = truthy(prev) && _gt0(at(prev, 'r')) ? prev : null;
    final lastRegular = last != null ? _rowOr(lastSets, i) : null;
    final w = useTarget
        ? (_gt0(at(cfg, 'weight'))
            ? cfg['weight']
            : (truthy(lastRegular) && _gt0(at(lastRegular, 'r')) ? at(lastRegular, 'w') : at(cfg, 'weight')))
        : usable != null
            ? at(usable, 'w')
            : (truthy(conf) && _gt0(at(conf, 'w')) ? conf['w'] : at(cfg, 'weight'));
    final row = <String, dynamic>{'w': w, 'r': planReps || usable == null ? at(cfg, 'reps') : at(usable, 'r'), 'done': false};
    if (isPyramid(cfg)) {
      final target = pyramidTargetAt(cfg['pyramid'] as List, i);
      final seed = usable ?? (truthy(lastRegular) && _gt0(at(lastRegular, 'r')) ? lastRegular : null);
      if (target == PYRAMID_MAX) {
        row['r'] = seed != null ? at(seed, 'r') : 0;
        row['max'] = true;
      } else {
        row['r'] = target;
      }
      final planned = pyramidWeightAt(cfg, i);
      if (planned > 0 && !(preferLast && usable != null)) {
        row['w'] = planned;
      } else if (useTarget && seed != null) {
        row['w'] = at(seed, 'w');
      }
    }
    if (isPerSide(cfg)) {
      sets.add(usable != null && isSideSet(usable) ? _seedSideFromLast(row, usable, planReps) : makeSideSet(row));
    } else {
      sets.add(row);
    }
  }
  return sets;
}

JMap _seedSideFromLast(JMap row, dynamic prev, bool planReps) {
  final base = makeSideSet(row);
  if (!isSideSet(prev)) return base;
  JMap carry(dynamic s, String key) => {
        'w': numOr(at(s, 'w'), 0),
        'r': planReps ? base['sides'][key]['r'] : numOr(at(s, 'r'), 0),
        'done': false,
      };
  return syncSideAggregate(<String, dynamic>{
    ...base,
    'sides': <String, dynamic>{'L': carry(prev['sides']['L'], 'L'), 'R': carry(prev['sides']['R'], 'R')},
  });
}

/// Stamp every work row with the exercise's planned intensifier (and last-to-failure).
List<dynamic> applyIntensifierPlan(List<dynamic> sets, dynamic cfg, [dynamic grid]) =>
    applyFailurePlan(_shapeRows(sets, cfg, grid), cfg);

/// "Last set to failure": marks the last work row (both halves of a timed per-side pair).
List<dynamic> applyFailurePlan(List<dynamic> sets, dynamic cfg) {
  if (!truthy(cfg) || at(cfg, 'lastToFailure') != true || modeOf(cfg) == 'cardio') return sets;
  var last = -1;
  for (var i = 0; i < sets.length; i++) {
    if (!isWarmupRow(sets[i])) last = i;
  }
  final from = last > 0 && at(at(sets, last), 'side') == 'R' && at(at(sets, last - 1), 'side') == 'L' ? last - 1 : last;
  if (last < 0) return sets;
  return [
    for (var i = 0; i < sets.length; i++)
      i >= from && i <= last && !truthy(at(sets[i], 'done')) ? <String, dynamic>{...asMap(sets[i]), 'failure': true} : sets[i],
  ];
}

List<dynamic> _shapeRows(List<dynamic> sets, dynamic cfg, dynamic grid) {
  final intens = truthy(cfg) ? at(cfg, 'intensifier') : null;
  final kind = truthy(intens) ? at(intens, 'type') : null;
  if (kind != 'dropset' && kind != 'restpause') return sets;
  if (kind == 'dropset') {
    final count = math.max(1, numOr(mathRound(toNum(at(intens, 'count'))), 1)).toInt();
    final pct = at(intens, 'pct');
    JMap withDrops(dynamic row) {
      final drops = <dynamic>[];
      dynamic w = or(at(row, 'w'), 0);
      for (var k = 0; k < count; k++) {
        w = nextDropWeight(w, pct, grid);
        drops.add(<String, dynamic>{'w': w, 'r': at(row, 'r')});
      }
      return <String, dynamic>{...asMap(row), 'type': 'dropset', 'drops': drops};
    }

    return sets.map<dynamic>((s) {
      if (isWarmupRow(s)) return s;
      if (isSideSet(s)) {
        return syncSideAggregate(<String, dynamic>{
          ...asMap(s),
          'sides': <String, dynamic>{'L': withDrops(s['sides']['L']), 'R': withDrops(s['sides']['R'])},
        });
      }
      return withDrops(s);
    }).toList();
  }
  final restSec = math.max(5, numOr(at(intens, 'restSec'), 15));
  final totalReps = math.max(1, numOr(mathRound(toNum(at(intens, 'totalReps'))), 1));
  final firstWork = jsFind(sets, (s) => !isWarmupRow(s));
  final w = or(at(truthy(firstWork) ? firstWork : (truthy(at(sets, 0)) ? sets[0] : const {}), 'w'), 0);
  List<dynamic> clustersFor(num reps) =>
      splitBurstReps(reps).map((r) => <String, dynamic>{'r': r, 'restSec': restSec}).toList();
  final warmup = <String, dynamic>{
    'w': w,
    'r': math.max(1, numOr(mathRound(toNum(at(cfg, 'reps'))), 1)),
    'done': false,
    'phase': 'warmup',
  };
  final work = <String, dynamic>{'w': w, 'r': totalReps, 'done': false, 'type': 'restpause', 'clusters': clustersFor(totalReps)};
  if (isPerSide(cfg)) {
    final source = jsFind(sets, (s) => !isWarmupRow(s));
    JMap side(String key, num reps) => {
          'w': at(at(at(source, 'sides'), key), 'w') ?? w,
          'r': reps,
          'done': false,
          'type': 'restpause',
          'clusters': clustersFor(reps),
        };
    return [
      makeSideSet(warmup),
      syncSideAggregate(<String, dynamic>{
        ...work,
        'sides': <String, dynamic>{'L': side('L', (totalReps / 2).ceil()), 'R': side('R', (totalReps / 2).floor())},
      }),
    ];
  }
  return [warmup, work];
}

/// Volume of a workout: completed work sets (warm-ups left out), per side, with drops, × the
/// entry's dumbbell volume factor.
num workoutVolume(dynamic w) {
  num v = 0;
  for (final e in asList(at(w, 'entries'))) {
    final f = volumeFactor(e);
    for (final s in asList(at(e, 'sets'))) {
      if (!isWarmupRow(s)) v += completedVolumeOf(s) * f;
    }
  }
  return v;
}

num? _timestampOf(dynamic value) {
  if (value is num) return value.isFinite ? value : null;
  if (value is String && value.trim().isNotEmpty) {
    final n = toNum(value);
    return n.isFinite ? n : null;
  }
  return null;
}

/// A finished session's local calendar day ('YYYY-MM-DD'), or null.
String? workoutDay(dynamic w) {
  final day = jsString(or(at(w, 'd'), ''));
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
    final date = isoNoon(day);
    if (date != null && isoOf(date) == day) return day;
  }
  final start = _timestampOf(at(w, 'start'));
  if (start != null && start.abs() <= 8.64e15) return isoOf(DateTime.fromMillisecondsSinceEpoch(start.truncate()));
  return null;
}

/// Duration in ms from the session timestamps; 0 without both.
num workoutDuration(dynamic w) {
  final start = _timestampOf(at(w, 'start'));
  final end = _timestampOf(at(w, 'end'));
  return start != null && end != null ? math.max(0, end - start) : 0;
}

int setUnits(dynamic s) => isSideSet(s) ? 2 : 1;

int doneUnits(dynamic s) => isSideSet(s)
    ? (truthy(s['sides']['L']['done']) ? 1 : 0) + (truthy(s['sides']['R']['done']) ? 1 : 0)
    : (truthy(at(s, 'done')) ? 1 : 0);

int setUnitsTotal(dynamic entries) => asList(entries)
    .fold<int>(0, (n, e) => n + asList(or(at(e, 'sets'), const [])).fold<int>(0, (m, s) => m + setUnits(s)));

int setsDone(dynamic w) {
  var n = 0;
  for (final e in asList(at(w, 'entries'))) {
    for (final s in asList(at(e, 'sets'))) {
      n += doneUnits(s);
    }
  }
  return n;
}

int setsDoneActive(dynamic A) => truthy(A) ? setsDone(A) : 0;

dynamic lastBW(dynamic S) {
  final bw = asList(at(S, 'bodyweight'));
  return bw.isNotEmpty ? bw.last : null;
}

/// Group consecutive items sharing a superset id (sg) into "units" of indices.
List<List<int>> supersetUnits(dynamic items) {
  final list = asList(items);
  final units = <List<int>>[];
  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    final prev = at(list, i - 1);
    final sg = at(e, 'sg');
    if (i > 0 && truthy(sg) && truthy(prev) && truthy(at(prev, 'sg')) && sg == prev['sg']) {
      units.last.add(i);
    } else {
      units.add([i]);
    }
  }
  return units;
}

/// A saved session's entries in sections: one per routine (by `rid`), each with its superset units.
List<JMap> sessionSections(dynamic entries) {
  final list = asList(entries);
  final sections = <JMap>[];
  for (var i = 0; i < list.length; i++) {
    final rid = truthy(at(list[i], 'rid')) ? list[i]['rid'] : null;
    var section = jsFind(sections, (x) => x['rid'] == rid) as JMap?;
    if (section == null) {
      section = <String, dynamic>{'rid': rid, 'items': <int>[]};
      sections.add(section);
    }
    (section['items'] as List<int>).add(i);
  }
  return sections.map((s) {
    final items = s['items'] as List<int>;
    return <String, dynamic>{
      'rid': s['rid'],
      'items': items,
      'units': supersetUnits(items.map((i) => list[i]).toList()).map((unit) => unit.map((k) => items[k]).toList()).toList(),
    };
  }).toList();
}

/// Move the selected occurrence's whole display unit by one neighbouring unit, or null.
List<dynamic>? moveSupersetUnit(dynamic items, dynamic index, dynamic direction) {
  if (items is! List || (direction != -1 && direction != 1)) return null;
  final units = supersetUnits(items);
  final source = units.indexWhere((unit) => unit.contains(index));
  final target = source + (direction as int);
  if (source < 0 || target < 0 || target >= units.length) return null;
  final reordered = [...units];
  final selected = reordered[source];
  reordered[source] = reordered[target];
  reordered[target] = selected;
  return reordered.expand((u) => u).map((i) => items[i]).toList();
}

/// The routine editor's up/down arrows (#377); null when the press would do nothing.
List<dynamic>? moveRoutineEntry(dynamic items, dynamic index, dynamic direction) {
  if (items is! List || (direction != -1 && direction != 1)) return null;
  if (index is! int || index < 0 || index >= items.length) return null;
  final group = _contiguousSgGroup(items, index);
  if (group.length < 2) return moveSupersetUnit(items, index, direction);
  final next = items.toList();
  final other = index + (direction as int);
  if (group.contains(other)) {
    next[index] = items[other];
    next[other] = items[index];
    return next;
  }
  next[index] = <String, dynamic>{...asMap(items[index])}..remove('sg');
  final rest = group.where((i) => i != index).toList();
  if (rest.length == 1) next[rest[0]] = <String, dynamic>{...asMap(items[rest[0]])}..remove('sg');
  return next;
}

List<dynamic> unitOf(dynamic units, dynamic idx) =>
    (jsFind(asList(units), (u) => asList(u).contains(idx)) as List<dynamic>?) ?? [idx];

/// Consecutive weeks (back from this one) with at least one workout.
int streakWeeks(dynamic S, [DateTime? now]) {
  final workouts = asList(at(S, 'workouts'));
  if (workouts.isEmpty) return 0;
  final ws = weekStartOf(S);
  final weeks = workouts.map((w) => weekKey(at(w, 'd'), ws)).toSet();
  var streak = 0;
  var cur = now ?? DateTime.now();
  for (var i = 0; i < 520; i++) {
    final wk = weekKey(isoOf(cur), ws);
    if (weeks.contains(wk)) {
      streak++;
    } else if (i > 0) {
      break;
    }
    cur = DateTime(cur.year, cur.month, cur.day - 7, cur.hour, cur.minute, cur.second, cur.millisecond);
  }
  return streak;
}

/// Cascade an explicit work-set load edit through the later inherited work sets.
List<dynamic> cascadeWeight(List<dynamic> rows, int from, dynamic value, [dynamic side, num backoffStep = 0]) {
  final source = at(rows, from);
  if (!truthy(source) || isWarmupRow(source)) return rows.toList();
  final sides = isSideSet(source) ? (truthy(side) ? [side] : ['L', 'R']) : null;
  final next = rows.toList();
  final stepDown = backoffStep > 0 && value != null;
  var k = 0;
  JMap setWeight(dynamic row) {
    final out = <String, dynamic>{...asMap(row)};
    if (value == null) {
      out.remove('w');
    } else {
      out['w'] = stepDown ? backoffAt(value, k, backoffStep) : value;
    }
    return out;
  }

  dynamic setSideWeight(dynamic row, dynamic key) {
    final current = at(at(row, 'sides'), key);
    if (!truthy(current) || at(current, 'done') == true || at(current, 'weightOrigin') == WEIGHT_ORIGIN_MANUAL) return row;
    final nextSide = setWeight(current);
    return syncSideAggregate(<String, dynamic>{
      ...asMap(row),
      'sides': <String, dynamic>{...asMap(row['sides']), key as String: nextSide},
    });
  }

  for (var j = from + 1; j < next.length; j++) {
    final row = next[j];
    if (isWarmupRow(row)) continue;
    k++;
    if (sides != null) {
      if (!isSideSet(row)) continue;
      dynamic out = row;
      for (final key in sides) {
        out = setSideWeight(out, key);
      }
      next[j] = out;
    } else if (!isSideSet(row) && !truthy(at(row, 'done')) && at(row, 'weightOrigin') != WEIGHT_ORIGIN_MANUAL) {
      next[j] = setWeight(row);
    }
  }
  return next;
}

num _rungDown(num x, dynamic step) =>
    step is List ? ownedFloor(step.map(toNum).toList(), x) : (x / toNum(step)).floor() * toNum(step);

/// Recompute the open warm-ups so they ramp toward the weight the work rows actually carry.
List<dynamic> rerampWarmups(List<dynamic> rows, [dynamic step = 2.5, num floor = 0]) {
  final firstWork = rows.indexWhere((x) => !isWarmupRow(x));
  if (firstWork <= 0) return rows;
  final target = numOr(at(rows[firstWork], 'w'), 0);
  if (!(target > 0)) return rows;
  final out = rows.toList();
  num from = 0;
  for (var i = 0; i < firstWork; i++) {
    if (truthy(at(out[i], 'done'))) {
      from = numOr(at(out[i], 'w'), 0);
      continue;
    }
    final w = target > from ? math.min(target, math.max(math.max(0, floor), _rungDown(from + (target - from) / 2, step))) : target;
    out[i] = isSideSet(out[i])
        ? syncSideAggregate(<String, dynamic>{
            ...asMap(out[i]),
            'sides': <String, dynamic>{
              'L': <String, dynamic>{...asMap(out[i]['sides']['L']), 'w': w},
              'R': <String, dynamic>{...asMap(out[i]['sides']['R']), 'w': w},
            },
          })
        : <String, dynamic>{...asMap(out[i]), 'w': w};
    from = w;
  }
  return out;
}

/// Insert a warm-up row at the end of the warm-up block, ramping toward the working weight.
List<dynamic> insertWarmupRow(List<dynamic> rows, dynamic mode, dynamic target, [dynamic step = 2.5, num floor = 0]) {
  final firstWork = rows.indexWhere((x) => !isWarmupRow(x));
  final atIdx = firstWork == -1 ? rows.length : firstWork;
  final prev = atIdx > 0 ? rows[atIdx - 1] : null;
  final work = firstWork == -1 ? null : rows[firstWork];
  num rampTo(num to) {
    final from = prev != null ? numOr(at(prev, 'w'), 0) : 0;
    if (!(to > 0)) return 0;
    if (to <= from) return to;
    return math.min(to, math.max(math.max(0, floor), _rungDown(from + (to - from) / 2, step)));
  }

  final JMap warm;
  if (mode == 'cardio') {
    warm = {
      'min': prev != null ? at(prev, 'min') : (work != null ? at(work, 'min') : or(at(target, 'min'), 20)),
      'speed': prev != null ? at(prev, 'speed') : (work != null ? at(work, 'speed') : or(at(target, 'speed'), 8)),
      ...inclineFrom(prev ?? work),
      'done': false,
      'phase': 'warmup',
      'warmup': true,
    };
  } else if (mode == 'time') {
    warm = {
      'sec': prev != null ? at(prev, 'sec') : (work != null ? at(work, 'sec') : or(at(target, 'sec'), 45)),
      'w': rampTo(work != null ? numOr(at(work, 'w'), 0) : numOr(at(target, 'weight'), 0)),
      'done': false,
      'phase': 'warmup',
      'warmup': true,
    };
  } else {
    warm = {
      'w': rampTo(work != null ? numOr(at(work, 'w'), 0) : numOr(at(target, 'weight'), 0)),
      'r': work != null ? at(work, 'r') : (prev != null ? at(prev, 'r') : at(target, 'reps')),
      'done': false,
      'phase': 'warmup',
      'warmup': true,
    };
  }
  final warmRow = mode == 'reps' && isPerSide(target) ? makeSideSet(warm) : warm;
  return rows.toList()..insert(atIdx, warmRow);
}

/// Can this row become a warm-up? Only a plain straight work set.
bool canBeWarmup(dynamic row) =>
    truthy(row) && !isWarmupRow(row) && !isSideSet(row) && !isDropSet(row) && !isRestPauseSet(row);

/// "Make it a warm-up set": the row takes a warm-up's shape and moves to the end of the warm-ups.
List<dynamic> makeWarmupAt(List<dynamic> rows, int i) {
  final src = at(rows, i);
  if (!canBeWarmup(src)) return rows;
  final warm = <String, dynamic>{'w': or(at(src, 'w'), 0), 'r': at(src, 'r'), 'done': truthy(at(src, 'done')), 'phase': 'warmup', 'warmup': true};
  if (at(src, 'at') != null) warm['at'] = src['at'];
  return _placeRow(rows, i, warm);
}

/// "Count it as a working set": the warm-up becomes the first work set.
List<dynamic> makeWorkAt(List<dynamic> rows, int i) {
  final src = at(rows, i);
  if (!truthy(src) || !isWarmupRow(src)) return rows;
  final work = <String, dynamic>{...asMap(src)}
    ..remove('phase')
    ..remove('warmup');
  return _placeRow(rows, i, work);
}

List<dynamic> _placeRow(List<dynamic> rows, int i, dynamic row) {
  final next = [for (var j = 0; j < rows.length; j++) if (j != i) rows[j]];
  final firstWork = next.indexWhere((x) => !isWarmupRow(x));
  next.insert(firstWork == -1 ? next.length : firstWork, row);
  return next;
}

/// The rows one set takes up at [i]: `[start, count]` (a timed per-side L/R pair is one set).
List<int> setSpanAt(List<dynamic> rows, int i) {
  final row = at(rows, i);
  if (at(row, 'side') == 'L' && at(at(rows, i + 1), 'side') == 'R') return [i, 2];
  if (at(row, 'side') == 'R' && at(at(rows, i - 1), 'side') == 'L') return [i - 1, 2];
  return [i, 1];
}

const List<String> _NOT_COPIED = ['done', 'at', 'planSec', 'weightOrigin', 'type', 'drops', 'clusters'];

JMap _bare(dynamic src) {
  final out = <String, dynamic>{...asMap(src)};
  for (final k in _NOT_COPIED) {
    out.remove(k);
  }
  return out;
}

JMap _copyOfRow(dynamic src) {
  if (isSideSet(src)) {
    JMap side(dynamic sd) => {..._bare(sd), 'done': false};
    return syncSideAggregate(<String, dynamic>{
      ..._bare(src),
      'sides': <String, dynamic>{'L': side(src['sides']['L']), 'R': side(src['sides']['R'])},
      'done': false,
    });
  }
  return {..._bare(src), 'done': false};
}

/// The rows a copy of row [i] spans: `{start, end}` (a timed per-side pair copies as a pair).
JMap copySpanAt(List<dynamic> rows, int i) {
  dynamic work(dynamic r) => truthy(r) && !isWarmupRow(r) ? at(r, 'side') : null;
  final start = work(at(rows, i)) == 'R' && work(at(rows, i - 1)) == 'L' ? i - 1 : i;
  final end = work(at(rows, start)) == 'L' && work(at(rows, start + 1)) == 'R' ? start + 1 : start;
  return {'start': start, 'end': end};
}

/// "One more like this one": an unticked copy of row [i] (or its pair) right below it.
List<dynamic> copyRowAt(List<dynamic> rows, int i) {
  if (!truthy(at(rows, i))) return rows.toList();
  final span = copySpanAt(rows, i);
  final start = span['start'] as int, end = span['end'] as int;
  return rows.toList()..insertAll(end + 1, rows.sublist(start, end + 1).map(_copyOfRow));
}

/// Undo for a removed set: [row] back at index [i] (past the end lands it last).
List<dynamic> insertRowAt(List<dynamic> rows, dynamic i, dynamic row) {
  final next = rows.toList();
  final idx = i is int ? math.max(0, math.min(i, next.length)) : next.length;
  return next..insert(idx, row);
}

/// Remove the set at [i] (both halves of a per-side pair), never emptying the entry.
List<dynamic> removeRowAt(List<dynamic> rows, int i) {
  final span = setSpanAt(rows, i);
  if (rows.length <= span[1]) return rows.toList();
  return rows.toList()..removeRange(span[0], span[0] + span[1]);
}

/// "Remove set": the last set (a timed per-side exercise's last L/R pair).
List<dynamic> removeLastSet(List<dynamic> rows) => rows.isNotEmpty ? removeRowAt(rows, rows.length - 1) : rows.toList();

/// Completed non-warm-up sets across a workout's entries, per side.
int workSetsDone(dynamic w) => asList(or(at(w, 'entries'), const [])).fold<int>(
    0, (n, e) => n + asList(or(at(e, 'sets'), const [])).fold<int>(0, (m, s) => m + (isWarmupRow(s) ? 0 : doneUnits(s))));

const List<String> _METRIC_MODES = ['reps', 'time', 'cardio'];

List<dynamic> _completedRowsForMode(dynamic entry, String mode) =>
    _workRowsForMode(entry, mode).where((s) => hasCompletedWork(s) && !isWarmupRow(s)).toList();

/// The completed work rows an entry's metric reads (in [mode], else the entry's own).
List<dynamic> metricRowsForEntry(dynamic entry, [dynamic mode]) {
  final requested = mode is String ? mode.trim().toLowerCase() : '';
  final resolved = _METRIC_MODES.contains(requested) ? requested : metricModeForEntry(entry);
  return resolved != null ? _completedRowsForMode(entry, resolved) : <dynamic>[];
}

/// The authoritative metric for an entry; reps rows take precedence over timed/cardio rows.
String? metricModeForEntry(dynamic entry, [dynamic fallback]) {
  for (final mode in _METRIC_MODES) {
    if (_completedRowsForMode(entry, mode).isNotEmpty) return mode;
  }
  return modeForEntry(entry, fallback);
}

/// Every saved occurrence of an exercise in one workout, in stored order.
List<dynamic> entriesForExercise(dynamic workout, dynamic exId) {
  if (exId == null || exId == '') return [];
  return asList(or(at(workout, 'entries'), const [])).where((entry) => at(entry, 'id') == exId).toList();
}

/// Metric data `{entry, mode, rows}` for every occurrence in one workout.
List<JMap> metricEntriesForExercise(dynamic workout, dynamic exId) => entriesForExercise(workout, exId)
    .map((entry) {
      final mode = metricModeForEntry(entry);
      return <String, dynamic>{'entry': entry, 'mode': mode, 'rows': mode != null ? metricRowsForEntry(entry, mode) : <dynamic>[]};
    })
    .where((item) => (item['rows'] as List).isNotEmpty || (item['mode'] == 'reps' && bestWeightForEntry(item['entry']) > 0))
    .toList();

/// Total reps from one completed row, counting only completed limbs of a per-side row.
num completedRepsOf([dynamic set]) {
  if (isSideSet(set)) {
    return [set['sides']['L'], set['sides']['R']]
        .where((side) => at(side, 'done') == true)
        .fold<num>(0, (total, side) => total + math.max(0, numOr(at(side, 'r'), 0)));
  }
  return at(set, 'done') == true ? math.max(0, numOr(at(set, 'r'), 0)) : 0;
}

/// Best load from completed work rows (lowest on an assistance machine), with a guarded
/// reps-only legacy `topW` fallback.
num bestWeightForEntry([dynamic entry]) {
  final e = _objectOf(entry);
  final target = or(e['target'], e);
  final workRows = e['sets'] is List ? (e['sets'] as List).where((s) => phaseForSet(s) == 'work').toList() : <dynamic>[];
  final repsRows = metricRowsForEntry(e, 'reps');
  final completedRows = repsRows.isNotEmpty ? repsRows : workRows.where((set) => hasCompletedWork(set) && !isWarmupRow(set)).toList();
  final assisted = isAssisted(truthy(e['id']) ? {'id': e['id']} : e);
  num best = 0;
  var hasUsableWeight = false;
  for (final set in completedRows) {
    final completedSets = isSideSet(set) ? [set['sides']['L'], set['sides']['R']].where((side) => at(side, 'done') == true) : [set];
    for (final completedSet in completedSets) {
      final weight = _numU(completedSet, 'w');
      if (!weight.isFinite) continue;
      if (assisted && !(weight > 0)) continue;
      best = hasUsableWeight ? betterWeight(e['id'], best, weight) : weight;
      hasUsableWeight = true;
    }
  }
  if (hasUsableWeight) return best;

  final parentMode = modeForSet(<String, dynamic>{}, target);
  final hasNonRepsWorkRow = workRows.any((set) => modeForSet(set, target) != 'reps');
  final hasWarmupRow = e['sets'] is List && (e['sets'] as List).any(isWarmupRow);
  final topWeight = _numU(e, 'topW');
  if (parentMode == 'reps' &&
      !hasNonRepsWorkRow &&
      !hasWarmupRow &&
      topWeight.isFinite &&
      (best <= 0 || (assisted ? topWeight > 0 && topWeight < best : topWeight > best))) {
    best = topWeight;
  }
  return best;
}
