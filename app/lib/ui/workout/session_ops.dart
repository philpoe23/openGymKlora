// The running session's state changes, as plain functions over the state document `S` (the
// store's `update` hands them its working copy). Ports of what frontend/src/views/Workout.jsx
// (ActiveWorkout, ExerciseBlock) and sheets.jsx (beginWorkout, swapActiveWorkoutExercise,
// doFinishWorkout) do to `S.active`; the widgets only call these and draw the result.
//
// Not ported (no client-v1 path reaches them): editing a saved workout (`editingWorkoutId`),
// logging a past one (`backfill`), timed holds, effort (RIR/RPE) logging, drop/burst sub-rows,
// pairing/unpairing supersets, and the per-session progression opt-out.

import 'dart:math' as math;

import '../../engine/dumbbells.dart';
import '../../engine/exercises.dart';
import '../../engine/finish_workout.dart';
import '../../engine/format.dart';
import '../../engine/history.dart';
import '../../engine/js.dart';
import '../../engine/muscles.dart';
import '../../engine/onerm.dart';
import '../../engine/plates.dart';
import '../../engine/progression.dart';
import '../../engine/pyramid.dart';
import '../../engine/rotation.dart';
import '../../engine/session_merge.dart';
import '../../engine/session_start.dart';
import '../../engine/superset_flow.dart';
import '../../engine/workout_model.dart';

/* ------------------------------------------------------------------ reading */

List<dynamic> entriesOf(dynamic A) => asList(at(A, 'entries'));

/// The marked exercise, clamped into the session (`cur` of ActiveWorkout).
int curOf(dynamic A) {
  final n = entriesOf(A).length;
  final c = at(A, 'cur');
  return c is int ? math.min(math.max(c, 0), math.max(0, n - 1)) : 0;
}

/// An entry's settings with its id: what modeOf, isBw, weightIncrement… read.
JMap cfgOf(dynamic entry) => <String, dynamic>{...asMap(or(at(entry, 'target'), const <String, dynamic>{})), 'id': at(entry, 'id')};

/// 'reps' | 'time' | 'cardio'.
String entryMode(dynamic entry) => modeOf(cfgOf(entry));

bool entryFinished(dynamic entry) {
  final sets = asList(at(entry, 'sets'));
  return sets.isNotEmpty && sets.every((s) => truthy(at(s, 'done')));
}

/// The number a set row shows: counted per phase, a timed L/R pair as one set (setNumberAt).
int setNumberAt(List<dynamic> sets, int i) {
  final s = sets[i];
  final warm = isWarmupRow(s);
  final phaseNum = sets.take(i + 1).where((x) => isWarmupRow(x) == warm).length;
  return truthy(at(s, 'side')) ? (phaseNum / 2).ceil() : phaseNum;
}

/// The weight step of an entry: the bells you own when listed, else the exercise's increment.
num loadStepOf(dynamic S, dynamic entry) {
  final cfg = cfgOf(entry);
  return entryMode(entry) == 'reps' ? weightIncrement(cfg, at(S, 'unit')) : 2.5;
}

/// One tap of the weight stepper (`stepLoad` of ExerciseBlock).
num stepLoad(dynamic S, dynamic entry, dynamic value, num dir) {
  final cfg = cfgOf(entry);
  final owned = entryMode(entry) == 'reps' ? ownedWeightsFor(S, cfg) : null;
  if (owned != null) return stepOwned(owned, value, dir);
  return stepWeight(value, loadStepOf(S, entry), dir);
}

/// A non-weight stepper tap: `max(0, round((v + dir·step)·100)/100)`.
num stepPlain(dynamic value, num step, num dir) => math.max(0, mathRound((numOr(value, 0) + dir * step) * 100) / 100);

/// The plate line for row [i] (or null): shown on the first loaded row and wherever the stack
/// changes from the loaded row before it. `{text, short?, moves?}`.
JMap? plateLineFor(dynamic S, dynamic entry, int i) {
  if (entryMode(entry) != 'reps') return null;
  final cfg = cfgOf(entry);
  final kind = loadKindFor(S, cfg);
  if (kind == 'none') return null;
  final base = baseWeightFor(S, at(entry, 'id'));
  final inv = inventoryFor(S);
  final sets = asList(at(entry, 'sets'));
  final perSide = isPerSide(cfg);
  JMap? loadAt(int j) {
    final s = sets[j];
    var w = at(s, 'w');
    if (perSide && isSideSet(s)) {
      final l = numOr(at(s['sides']['L'], 'w'), 0), r = numOr(at(s['sides']['R'], 'w'), 0);
      if (l != 0 && r != 0 && l != r) return null;
      w = l != 0 ? l : r;
    }
    return rowLoad(kind, w, base, inv);
  }

  final load = loadAt(i);
  if (load == null) return null;
  JMap? prev;
  for (var j = i - 1; j >= 0; j--) {
    prev = loadAt(j);
    if (prev != null) break;
  }
  if (prev != null && sameLoad(prev, load)) return null;
  final stack = (load['plates'] as List).map(fmtPlate).join(' + ');
  final text = load['barOnly'] == true
      ? 'Bar only'
      : load['kind'] == 'pairs'
      ? '${stack.isEmpty ? '–' : stack} per side'
      : 'Load ${stack.isEmpty ? '–' : stack}';
  final missing = toNum(load['missing']);
  String? moves;
  if (prev != null) {
    final d = plateDelta(prev['plates'], load['plates']);
    final m = [...asList(d['strip']).map((w) => '−${fmtPlate(w)}'), ...asList(d['add']).map((w) => '+${fmtPlate(w)}')];
    if (m.isNotEmpty) moves = m.join(' ');
  }
  return {'text': text, if (missing > 0) 'short': '${fmtPlate(missing)} ${at(S, 'unit') == 'lb' ? 'lb' : 'kg'} short', 'moves': ?moves};
}

/* ------------------------------------------------------------------ start */

/// The new `S.active` (sheets.jsx beginWorkout): [routineIds] built and merged, named after its
/// routines ('Freestyle' for none), with the body weight [bw] when one was entered.
JMap buildActive(dynamic st, dynamic routineIds, dynamic bw, {int? now, String? today}) {
  final built = buildCombinedEntries(st, routineIds);
  final routines = asList(built['routines']);
  return <String, dynamic>{
    'id': uid(),
    'd': today ?? todayISO(),
    'start': now ?? DateTime.now().millisecondsSinceEpoch,
    'routineIds': built['routineIds'],
    'name': routines.isNotEmpty ? deriveSessionName(routines.map((r) => at(r, 'name')).toList()) : 'Freestyle',
    'bw': truthy(bw) ? bw : null,
    'cur': 0,
    'entries': built['entries'],
    'workoutView': or(at(st, 'workoutView'), 'cards'),
  };
}

/// Today's routines when they hold any exercise: what the Start pill starts.
List<dynamic> todaysRoutineIds(dynamic S, [String? today]) {
  final ids = effectiveRoutineIds(S, today ?? todayISO());
  final routines = asList(at(S, 'routines'));
  final withEx = ids.where((id) => asList(at(jsFind(routines, (r) => at(r, 'id') == id), 'ex')).isNotEmpty).toList();
  return withEx;
}

/* ------------------------------------------------------------------ set rows */

JMap _entry(JMap s, int idx) => asMap((s['active'] as Map)['entries'][idx]);

/// A typed or stepped value into row [i] (`setField` of ActiveWorkout): null clears the field; a
/// weight is marked as yours and cascades to the later inherited work sets.
void setField(JMap s, int idx, int i, String field, dynamic v) {
  final e = _entry(s, idx);
  final sets = asList(e['sets']);
  final row = asMap(sets[i]);
  sets[i] = row;
  if (v == null) {
    row.remove(field);
  } else {
    row[field] = v;
  }
  if (field == 'sec') row.remove('planSec');
  if (field == 'w') {
    row['weightOrigin'] = WEIGHT_ORIGIN_MANUAL;
    e['sets'] = cascadeWeight(sets, i, v, null, numOr(at(e['target'], 'backoffStep'), 0));
  }
}

/// One side of a unilateral row (`setSide` of ExerciseBlock).
void setSideValue(JMap s, int idx, int i, String side, String field, dynamic v) {
  final e = _entry(s, idx);
  final sets = asList(e['sets']);
  final row = setSideField(sets[i], side, field, v);
  if (field != 'w') {
    sets[i] = row;
    return;
  }
  asMap(row['sides'][side])['weightOrigin'] = WEIGHT_ORIGIN_MANUAL;
  sets[i] = row;
  e['sets'] = cascadeWeight(sets, i, v, side, numOr(at(e['target'], 'backoffStep'), 0));
}

/// "Add set" (`addSet` of ActiveWorkout): one more like the last.
void addSet(JMap s, int idx) {
  final e = _entry(s, idx);
  final sets = asList(e['sets']);
  e['sets'] = sets;
  final l = sets.isNotEmpty ? sets.last : null;
  final target = asMap(or(e['target'], const <String, dynamic>{}));
  final cfg = cfgOf(e);
  final m = modeOf(cfg);
  if (m == 'cardio') {
    sets.add(<String, dynamic>{
      'min': l != null ? at(l, 'min') : or(target['min'], 20),
      'speed': l != null ? at(l, 'speed') : or(target['speed'], 8),
      if (l != null && hasInclineRow(l)) 'incline': l['incline'],
      'done': false,
    });
  } else if (m == 'time') {
    final sec = l != null ? at(l, 'sec') : or(target['sec'], 45);
    final w = l != null ? or(at(l, 'w'), 0) : or(target['weight'], 0);
    if (isPerSide(cfg)) {
      sets.add(<String, dynamic>{'sec': sec, 'w': w, 'done': false, 'side': 'L'});
      sets.add(<String, dynamic>{'sec': sec, 'w': w, 'done': false, 'side': 'R'});
    } else {
      sets.add(<String, dynamic>{'sec': sec, 'w': w, 'done': false});
    }
  } else {
    final row = <String, dynamic>{
      'w': l != null ? at(l, 'w') : 0,
      'r': l != null ? at(l, 'r') : target['reps'],
      'done': false,
      if (l != null && truthy(at(l, 'max'))) 'max': true,
    };
    if (isPerSide(cfg)) {
      sets.add(
        l != null && isSideSet(l)
            ? makeSideSet({'w': at(l['sides']['L'], 'w'), 'r': numOr(at(l['sides']['L'], 'r'), 0) * 2})
            : makeSideSet(row),
      );
    } else {
      sets.add(row);
    }
  }
}

bool hasInclineRow(dynamic s) => toNum(at(s, 'incline')) > 0;

/// Remove set [i] (both halves of an L/R pair); a live session always keeps one set. False when
/// it would have emptied the exercise.
bool removeSetAt(JMap s, int idx, int i) {
  final e = _entry(s, idx);
  final sets = asList(e['sets']);
  final span = setSpanAt(sets, i);
  if (sets.length <= span[1]) return false;
  e['sets'] = removeRowAt(sets, i);
  return true;
}

/// "One more like this one": a copy of set [i] right below it.
void copySetAt(JMap s, int idx, int i) {
  final e = _entry(s, idx);
  e['sets'] = copyRowAt(asList(e['sets']), i);
}

/// "Add warm-up": a ramp row before the work sets.
void addWarmup(JMap s, int idx) {
  final e = _entry(s, idx);
  final cfg = cfgOf(e);
  final m = modeOf(cfg);
  final dynamic ramp = (m == 'reps' ? ownedWeightsFor(s, cfg) : null) ?? defaultIncrement(e['id'], s['unit']);
  e['sets'] = insertWarmupRow(asList(e['sets']), m, or(e['target'], const <String, dynamic>{}), ramp, barFloor(s, e['id']));
}

/* ------------------------------------------------------------------ tick */

/// Flips set [i] (or one [side] of it) done, the way `toggle` of ActiveWorkout does inside its
/// update: stamps when the work happened, drops a set-aside plan and, when the exercise is now
/// finished, captures its top weight. Returns whether the row (or side) is now done.
bool tickSet(JMap s, int idx, int i, {String? side, int? now}) {
  final e = _entry(s, idx);
  final sets = asList(e['sets']);
  JMap row;
  if (side != null) {
    row = toggleSide(sets[i], side);
  } else {
    row = asMap(sets[i]);
    row['done'] = !truthy(row['done']);
  }
  sets[i] = row;
  final checked = truthy(row['done']);
  final sideDone = side != null ? truthy(at(row['sides'][side], 'done')) : checked;
  if (sideDone) row['at'] = now ?? DateTime.now().millisecondsSinceEpoch;
  if (checked && row['planSec'] != null) row.remove('planSec');
  if (checked && sets.every((x) => truthy(at(x, 'done')))) {
    final best = bestWeightForEntry(e);
    e['topW'] = truthy(best) ? best : null;
  }
  return side != null ? sideDone : checked;
}

/// What the screen does after a set was ticked (the second half of `toggle`).
class TickOutcome {
  const TickOutcome({this.restSec, this.stopRest = false, this.nextCur, this.workoutDone = false, this.switchSides = false});

  /// Start a rest of this many seconds (null: leave the timer as it is).
  final num? restSec;

  /// Stop a running rest first (the unit this set belongs to is done).
  final bool stopRest;

  /// Move the marker to this entry (superset rotation).
  final int? nextCur;

  /// Every set of the session is ticked.
  final bool workoutDone;

  /// The rest is the short "switch sides" pause of a timed per-side hold.
  final bool switchSides;
}

/// The short pause between the two sides of one timed per-side set.
const int kSwitchSidesSec = 10;

/// Decides the rest and the navigation after set [i] of entry [idx] was ticked on [A] (the
/// session as it is now). [highWater] is this entry's completed-set high-water mark before the
/// tick (updated in place); [defaultRestSec] is `S.restSec`; [timerRunning] whether a rest is
/// still counting.
TickOutcome afterTick(
  dynamic A,
  int idx,
  int i, {
  required bool checked,
  required Map<int, num> highWater,
  required dynamic defaultRestSec,
  required bool timerRunning,
}) {
  final entries = entriesOf(A);
  if (!checked || idx >= entries.length) return const TickOutcome();
  final entry = entries[idx];
  final progress = setProgressHighWater(entry, highWater[idx] ?? 0);
  highWater[idx] = progress['highWater'] as num;

  final units = supersetUnits(entries);
  final unit = jsFind(units, (u) => (u as List).contains(idx)) as List<int>?;
  final unitDone = unit != null && unit.every((ui) => asList(at(entries[ui], 'sets')).every((x) => truthy(at(x, 'done'))));
  final nextUnit = unitDone ? nextUnfinishedUnit(entries, units, idx) : null;
  final workoutDone = unitDone && nextUnit == null;
  final restBeforeWarmup =
      nextUnit != null &&
      nextUnit.any((ui) => asList(at(entries[ui as int], 'sets')).any((set) => isWarmupRow(set) && !truthy(at(set, 'done'))));
  final setRest = {'idx': idx, 'sec': pyramidRestFor(at(entry, 'target'), asList(at(entry, 'sets')), i)};
  final restSec = restSecFor(entries, unit ?? [idx], defaultRestSec, setRest);
  final restAfter = toNum(warmupRestSecFor(entry, i, restSec));

  if (progress['isNew'] != true) {
    final again = !restBeforeWarmup && restOnRecheck(timerRunning: timerRunning, unitDone: unitDone, lastUnit: workoutDone);
    return TickOutcome(restSec: again ? restAfter : null, workoutDone: workoutDone);
  }

  // Between the two sides of one timed per-side hold: a short switch, the set's rest after both.
  final rows = asList(at(entry, 'sets'));
  dynamic sideOf(dynamic r) => r != null && !isWarmupRow(r) ? at(r, 'side') : null;
  final partner = sideOf(rows[i]) == 'L' && i + 1 < rows.length && sideOf(rows[i + 1]) == 'R'
      ? rows[i + 1]
      : sideOf(rows[i]) == 'R' && i > 0 && sideOf(rows[i - 1]) == 'L'
      ? rows[i - 1]
      : null;
  if (entryMode(entry) == 'time' && partner != null && !truthy(at(partner, 'done')) && restAfter > 0) {
    return TickOutcome(restSec: math.min(kSwitchSidesSec, restAfter), switchSides: true);
  }

  if (unit == null || unit.length <= 1) {
    final rest = !restBeforeWarmup && restAfterSet(unitDone: unitDone, lastUnit: workoutDone);
    return TickOutcome(restSec: rest ? restAfter : null, stopRest: unitDone, workoutDone: workoutDone);
  }

  final step = supersetFlowStep(entries, unit, idx);
  if (step == null) return TickOutcome(stopRest: unitDone, workoutDone: workoutDone);
  if (step['unitDone'] == true) {
    final rest = nextUnit != null && nextUnit.isNotEmpty && !restBeforeWarmup;
    return TickOutcome(restSec: rest ? restAfter : null, stopRest: unitDone, workoutDone: workoutDone);
  }
  final next = step['nextIdx'];
  return TickOutcome(restSec: step['roundDone'] == true ? restAfter : null, nextCur: next is int ? next : null, workoutDone: workoutDone);
}

/* ------------------------------------------------------------------ navigation */

/// The first entry of the unit [direction] away from the marked one, or null at either end.
int? unitTarget(dynamic A, int direction) {
  final entries = entriesOf(A);
  final c = at(A, 'cur');
  if (c is! int || c < 0 || c >= entries.length) return null;
  final units = supersetUnits(entries);
  final u = units.indexWhere((x) => x.contains(c));
  final t = u + direction;
  return u < 0 || t < 0 || t >= units.length ? null : units[t][0];
}

/* ------------------------------------------------------------------ exercises */

/// The rows and plan an exercise gets in this session (the add and swap flows): its routine's
/// prescription in a planned session, last time's loads in a freestyle one.
JMap _builtFor(JMap s, dynamic cfg, dynamic routine, {bool noProg = false}) {
  final full = <String, dynamic>{...asMap(cfg)};
  final id = full['id'];
  if (routine != null) return buildPlannedEntry(s, full, routine, noProg: noProg);
  final reps = modeOf(full) == 'reps';
  final dynamic step =
      (reps ? ownedWeightsFor(s, full) : null) ?? (reps ? weightIncrement(full, s['unit']) : defaultIncrement(id, s['unit']));
  return <String, dynamic>{
    'target': withMeaning(s, cfg, id),
    'plan': null,
    'sets': applyIntensifierPlan(
      buildSets(historyAs(s, id, dbLoadFor(s, full)), full, {'step': step, 'preferLast': true}),
      full,
      dropGrid(s, full),
    ),
  };
}

dynamic _routineOf(JMap s, dynamic rid) => truthy(rid) ? jsFind(asList(s['routines']), (r) => at(r, 'id') == rid) : null;

/// "Add exercise" (quick add): built the way the marked exercise's routine builds it (or from
/// last time, freestyle), placed after the marked unit, and marked.
int addExercise(JMap s, String exId) {
  final A = asMap(s['active']);
  final entries = asList(A['entries']);
  A['entries'] = entries;
  final cur = entries.isEmpty ? null : entries[curOf(A)];
  final rid = at(cur, 'rid');
  final routine = _routineOf(s, rid);
  final noProg = routine != null && builtOutOfProgression(cur, routine);
  final cfg = routine == null ? freestyleConfig(s, {'id': exId, ...defaultConfig(exId)}) : defaultConfig(exId);
  final built = _builtFor(s, {...cfg, 'id': exId}, routine, noProg: noProg);
  final at0 = insertionIndexAfterCurrentUnit(supersetUnits(entries), A['cur'], entries.length).toInt();
  entries.insert(at0, <String, dynamic>{'id': exId, ...built, if (truthy(rid)) 'rid': rid, if (noProg) 'noProg': true});
  A['cur'] = at0;
  return at0;
}

/// Does entry [idx] hold a ticked set (a swap then keeps it and inserts the replacement)?
bool hasLoggedSet(dynamic entry) => asList(at(entry, 'sets')).any((x) => at(x, 'done') == true);

/// "Swap exercise" (swapActiveWorkoutExercise + swapActiveExercise): replaced in place when
/// nothing is logged, else inserted after it (out of its superset). Returns the replacement's
/// index, or null when the entry is gone.
int? swapExercise(JMap s, int idx, String exId) {
  final A = asMap(s['active']);
  final entries = asList(A['entries']);
  if (idx < 0 || idx >= entries.length) return null;
  final current = asMap(entries[idx]);
  final routine = _routineOf(s, current['rid']);
  final built = _builtFor(
    s,
    {...defaultConfig(exId), 'id': exId},
    routine,
    noProg: routine != null && builtOutOfProgression(current, routine),
  );
  final replacement = <String, dynamic>{
    'id': exId,
    ...built,
    if (truthy(current['rid'])) 'rid': current['rid'],
    if (current['noProg'] == true) 'noProg': true,
  };
  if (!hasLoggedSet(current)) {
    final meta = <String, dynamic>{
      for (final e in current.entries)
        if (!const ['id', 'target', 'plan', 'planned', 'carried', 'sets', 'sg'].contains(e.key)) e.key: e.value,
    };
    entries[idx] = <String, dynamic>{...meta, ...replacement, if (truthy(current['sg'])) 'sg': current['sg']};
    A['cur'] = idx;
    return idx;
  }
  final unit = unitOf(supersetUnits(entries), idx);
  final insertAt = unit.length > 1 ? (unit.last as int) + 1 : idx + 1;
  entries.insert(insertAt, replacement);
  A['cur'] = insertAt;
  return insertAt;
}

/// "Skip exercise" (removeActiveExercise): out of today's session; the marker stays in range.
void removeExercise(JMap s, int idx) {
  final A = s['active'];
  if (A is! Map || A['entries'] is! List) return;
  final entries = A['entries'] as List;
  if (idx < 0 || idx >= entries.length) return;
  entries.removeAt(idx);
  cleanupSg(entries);
  final cur = A['cur'] is int ? A['cur'] as int : 0;
  var c = idx < cur ? cur - 1 : cur;
  if (c >= entries.length) c = math.max(0, entries.length - 1);
  A['cur'] = c;
}

/* ------------------------------------------------------------------ finish */

class FinishResult {
  const FinishResult(this.workout, this.prs, this.e1prs);
  final JMap workout;
  final List<dynamic> prs;
  final List<JMap> e1prs;
}

/// The PRs a finished session earned against [st] (the state before it is written): weight PRs
/// (ids) and estimated-1RM records `{id, est, w, r, prev}` for the rest.
(List<dynamic>, List<JMap>) prsOf(dynamic st, dynamic A) {
  final prs = <dynamic>[];
  final e1prs = <JMap>[];
  for (final e in entriesOf(A)) {
    final id = at(e, 'id');
    final loads = asList(
      at(e, 'sets'),
    ).where((x) => truthy(at(x, 'done')) && !isWarmupRow(x)).map((x) => at(x, 'w')).where((w) => w is num && w > 0).toList();
    final num mx = loads.isEmpty ? 0 : loads.skip(1).fold<num>(toNum(loads.first), (a, b) => betterWeight(id, a, b));
    if (beatsWeight(id, mx, bestWeightFor(st, id, entryDbLoad(e)))) prs.add(id);
    final rec = is1RMRecord(st, id, e);
    if (rec != null && !prs.contains(id)) e1prs.add({'id': id, ...rec});
  }
  return (prs, e1prs);
}

/// doFinishWorkout's record of the session: built, with its PRs and volume. Pure: [st] is not
/// changed; [writeFinished] writes it.
FinishResult buildFinished(dynamic st, {int? now}) {
  final A = at(st, 'active');
  final (prs, e1prs) = prsOf(st, A);
  final w = buildCompletedWorkout(
    A,
    end: sessionEnd(A, now),
    prs: prs,
    snapshotFor: (e) {
      final ex = EXIDX[jsString(at(e, 'id'))];
      return isCustomEx(ex) ? exerciseMuscleSnapshot(ex) : null;
    },
  );
  w['vol'] = workoutVolume(w);
  return FinishResult(w, prs, e1prs);
}

/// The live half of doFinishWorkout's update: kept best weights, the workout appended, the
/// session gone, and a completed rotation pass refilled.
void writeFinished(JMap s, JMap w) {
  final exWeights = asMap(or(s['exWeights'], <String, dynamic>{}));
  s['exWeights'] = exWeights;
  for (final e in asList(w['entries'])) {
    final id = jsString(at(e, 'id'));
    final mx = bestWeightForEntry(e);
    if (mx > 0 && beatsWeight(id, mx, numOr(at(exWeights[id], 'w'), 0))) exWeights[id] = <String, dynamic>{'w': mx, 'd': w['d']};
  }
  final workouts = asList(or(s['workouts'], <dynamic>[]));
  s['workouts'] = workouts;
  workouts.add(w);
  s['active'] = null;
  refillAfter(s, w);
}

/// The coach check-in a finished session offers: "Finished Push — 18 sets, 4,520 kg".
String checkInText(JMap w, dynamic unit) {
  final n = setsDone(w);
  return 'Finished ${jsString(or(w['name'], 'my workout'))} — $n ${n == 1 ? 'set' : 'sets'}, ${fmtVol(w['vol'], unit == 'lb' ? 'lb' : 'kg')}';
}
