// Port of frontend/src/lib/supersetFlow.js — pure decisions for the active-workout superset flow:
// the next unfinished unit, where an added exercise goes, when a completed set starts a rest and
// how long that rest runs.

import 'dart:math' as math;

import 'js.dart';
import 'superset_meta.dart';
import 'workout_model.dart';

bool _hasWork(List<dynamic> entries, dynamic idx) {
  final sets = at(at(entries, idx is int ? idx : -1), 'sets');
  return sets is List && sets.any((set) => !truthy(at(set, 'done')));
}

/// The first unfinished navigation unit after the one holding [fromIdx], wrapping once; or null.
List<dynamic>? nextUnfinishedUnit(dynamic entries, dynamic units, dynamic fromIdx) {
  if (entries is! List || units is! List || units.isEmpty) return null;
  final current = units.indexWhere((unit) => asList(unit).contains(fromIdx));
  final ordered = current < 0 ? units : [...units.sublist(current + 1), ...units.sublist(0, current)];
  return jsFind(ordered, (unit) => asList(unit).any((idx) => _hasWork(entries, idx))) as List<dynamic>?;
}

/// Insert after the whole navigation unit holding [currentIndex]; else at the end.
num insertionIndexAfterCurrentUnit(dynamic units, dynamic currentIndex, dynamic entryCount) {
  final length = math.max(0, numOr(entryCount, 0));
  if (units is! List || units.isEmpty) return length;
  final unit = jsFind(units, (candidate) => asList(candidate).contains(currentIndex));
  if (unit is! List || unit.isEmpty) return length;
  return math.min(length, maxOf(unit.map(toNum)) + 1);
}

/// A completion is new progress only when it beats the high-water mark of completed sets.
JMap setProgressHighWater(dynamic entry, [num previous = 0]) {
  final sets = at(entry, 'sets');
  final done = sets is List ? sets.fold<num>(0, (count, set) => count + (truthy(at(set, 'done')) ? 1 : 0)) : 0;
  return <String, dynamic>{'isNew': done > previous, 'highWater': math.max(previous, done)};
}

/// Whether completing a set should start a rest timer: always, except the session's last set.
bool restAfterSet({dynamic unitDone, dynamic lastUnit}) => !truthy(unitDone) || !truthy(lastUnit);

/// Whether re-checking an already-completed set should start a rest: fill a gap, never disturb a
/// running one.
bool restOnRecheck({dynamic timerRunning, dynamic unitDone, dynamic lastUnit}) =>
    !truthy(timerRunning) && restAfterSet(unitDone: unitDone, lastUnit: lastUnit);

/// How long the rest after a completed set should run, in seconds. [unit] is the group's entry
/// indices; [setRest] is the ticked set's own rest `{idx, sec}` (a pyramid set).
num restSecFor(dynamic entries, dynamic unit, dynamic defaultRestSec, [dynamic setRest]) {
  final num fallback = toNum(defaultRestSec) > 0 ? toNum(defaultRestSec) : 0;
  final idxs = unit is List && unit.isNotEmpty ? unit : <dynamic>[];
  if (idxs.isEmpty) return fallback;
  if (idxs.length > 1) {
    final rest = toNum(supersetMeta(entries, idxs, onTarget: true)['rest']);
    if (rest > 0) return rest;
  }
  return idxs.fold<num>(0, (longest, idx) {
    final own = truthy(setRest) && at(setRest, 'idx') == idx && toNum(at(setRest, 'sec')) > 0
        ? at(setRest, 'sec')
        : at(at(at(entries, idx is int ? idx : -1), 'target'), 'restSec');
    return math.max(longest, toNum(own) > 0 ? toNum(own) : fallback);
  });
}

/// The rest a completed warm-up ramp set earns: the exercise's `warmupRestSec` between ramp sets,
/// [workRestSec] after the last one and after any work set.
dynamic warmupRestSecFor(dynamic entry, dynamic setIdx, dynamic workRestSec) {
  final sets = asList(at(entry, 'sets'));
  final i = toNum(setIdx);
  final set = i is int ? at(sets, i) : null;
  if (!truthy(set) || !isWarmupRow(set)) return workRestSec;
  final next = jsFind(sets.skip((i as int) + 1), (s) => !truthy(at(s, 'done')));
  if (!truthy(next) || !isWarmupRow(next)) return workRestSec;
  final own = toNum(at(at(entry, 'target'), 'warmupRestSec'));
  return own > 0 ? own : workRestSec;
}

/// Where a newly completed superset set goes next: `{unitDone, roundDone, nextIdx}`, or null for
/// a singleton or a member not in [unit].
JMap? supersetFlowStep(dynamic entries, dynamic unit, dynamic fromIdx) {
  if (entries is! List || unit is! List || unit.length <= 1) return null;
  final pos = unit.indexOf(fromIdx);
  if (pos < 0) return null;

  final unitDone = !unit.any((idx) => _hasWork(entries, idx));
  if (unitDone) return <String, dynamic>{'unitDone': true, 'roundDone': false, 'nextIdx': null};

  final wrapped = [...unit.sublist(pos + 1), ...unit.sublist(0, pos + 1)];
  final nextIdx = jsFind(wrapped, (idx) => _hasWork(entries, idx));
  final roundDone = !unit.sublist(pos + 1).any((idx) => _hasWork(entries, idx));
  return <String, dynamic>{'unitDone': false, 'roundDone': roundDone, 'nextIdx': nextIdx};
}
