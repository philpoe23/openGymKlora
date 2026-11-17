// Port of frontend/src/lib/workout-model.js — focused workout semantics shared by session, history
// and strength views: a row's phase (warm-up/work), type (straight/drop-set/rest-pause), the
// to-failure flag, per-side (unilateral) rows and the reps/time/cardio mode.
// ignore_for_file: constant_identifier_names

import 'dart:math' as math;

import 'js.dart';

const List<String> _MODES = ['reps', 'time', 'cardio'];

JMap _objectOf(dynamic value) => value is Map ? asMap(value) : <String, dynamic>{};

String _normalizedPhase(dynamic value, [String fallback = 'work']) {
  final token = value is String ? value.trim().toLowerCase() : '';
  if (token == 'warmup' || token == 'warm-up' || token == 'warm_up') return 'warmup';
  if (token == 'work') return 'work';
  return fallback == 'warmup' ? 'warmup' : 'work';
}

/// Resolve a row's phase. An explicit phase wins over the legacy warmup boolean.
String phaseForSet(dynamic set, [String fallback = 'work']) {
  final source = _objectOf(set);
  if (source['phase'] != null && source['phase'] != '') return _normalizedPhase(source['phase'], fallback);
  return source['warmup'] == true ? 'warmup' : _normalizedPhase(null, fallback);
}

bool isWarmupRow(dynamic set) => phaseForSet(set) == 'warmup';

/// 'straight' (default), 'dropset' or 'restpause'.
String setType(dynamic set) {
  final t = _objectOf(set)['type'];
  return t == 'dropset' || t == 'restpause' ? t as String : 'straight';
}

bool isDropSet(dynamic set) => setType(set) == 'dropset';
bool isRestPauseSet(dynamic set) => setType(set) == 'restpause';

/// A set taken to failure; a warm-up never is one.
bool isFailureSet(dynamic set) {
  final source = _objectOf(set);
  return source['failure'] == true && !isWarmupRow(source);
}

/// Flip a row's to-failure mark, dropping the key when it goes off so the row is what it was.
JMap toggleFailure(dynamic set) {
  final out = <String, dynamic>{..._objectOf(set)};
  if (out['failure'] == true) {
    out.remove('failure');
  } else {
    out['failure'] = true;
  }
  return out;
}

/// A drop-set's weight drops, oldest first; empty for anything else.
List<dynamic> dropsOf(dynamic set) {
  final source = _objectOf(set);
  return isDropSet(source) && source['drops'] is List ? source['drops'] as List : <dynamic>[];
}

/// A rest-pause set's short-rest bursts, oldest first; empty for anything else.
List<dynamic> clustersOf(dynamic set) {
  final source = _objectOf(set);
  return isRestPauseSet(source) && source['clusters'] is List ? source['clusters'] as List : <dynamic>[];
}

num _dropVol(dynamic side) =>
    dropsOf(side).fold<num>(0, (n, d) => n + numOr(at(d, 'w'), 0) * numOr(at(d, 'r'), 0));

/// Weight x reps from a drop-set's drops, on top of its own main set (rest-pause adds nothing:
/// its own `r` is already the total).
num extraVolumeOf(dynamic set) {
  final source = _objectOf(set);
  if (isSideSet(source)) {
    final sides = source['sides'] as Map;
    return 0 + _dropVol(sides['L']) + _dropVol(sides['R']);
  }
  return _dropVol(source);
}

/// Append a weight drop to a row, marking it a drop-set.
JMap addDrop(dynamic set, dynamic drop) {
  final o = _objectOf(set);
  final prev = o['drops'] is List ? o['drops'] as List : <dynamic>[];
  return <String, dynamic>{
    ...o,
    'type': 'dropset',
    'drops': <dynamic>[...prev, <String, dynamic>{'w': numOr(at(drop, 'w'), 0), 'r': numOr(at(drop, 'r'), 0)}],
  };
}

/// Append a short-rest burst to a row, marking it a rest-pause set.
JMap addCluster(dynamic set, dynamic cluster) {
  final o = _objectOf(set);
  final prev = o['clusters'] is List ? o['clusters'] as List : <dynamic>[];
  return <String, dynamic>{
    ...o,
    'type': 'restpause',
    'clusters': <dynamic>[
      ...prev,
      <String, dynamic>{'r': numOr(at(cluster, 'r'), 0), 'restSec': numOr(at(cluster, 'restSec'), 0)},
    ],
  };
}

List<dynamic> _listOr(dynamic v) => truthy(v) && v is List ? v : <dynamic>[];

/// Remove one drop by index. Clearing the last one reverts the row to a straight set.
JMap removeDropAt(dynamic set, int i) {
  final src = _listOr(_objectOf(set)['drops']);
  final drops = <dynamic>[for (var idx = 0; idx < src.length; idx++) if (idx != i) src[idx]];
  return drops.isNotEmpty
      ? <String, dynamic>{..._objectOf(set), 'drops': drops}
      : <String, dynamic>{..._objectOf(set), 'type': 'straight', 'drops': drops};
}

/// Remove one burst by index. Clearing the last one reverts the row to a straight set.
JMap removeClusterAt(dynamic set, int i) {
  final src = _listOr(_objectOf(set)['clusters']);
  final clusters = <dynamic>[for (var idx = 0; idx < src.length; idx++) if (idx != i) src[idx]];
  return clusters.isNotEmpty
      ? <String, dynamic>{..._objectOf(set), 'clusters': clusters}
      : <String, dynamic>{..._objectOf(set), 'type': 'straight', 'clusters': clusters};
}

/// Patch one drop's fields in place (weight/reps steppers edit an existing drop).
dynamic setDropAt(dynamic set, int i, dynamic patch) {
  final drops = <dynamic>[..._listOr(_objectOf(set)['drops'])];
  if (!truthy(at(drops, i))) return set;
  drops[i] = <String, dynamic>{...asMap(drops[i]), ...asMap(patch)};
  return <String, dynamic>{..._objectOf(set), 'drops': drops};
}

/// Patch one burst's fields in place (a reps stepper edits an existing burst).
dynamic setClusterAt(dynamic set, int i, dynamic patch) {
  final clusters = <dynamic>[..._listOr(_objectOf(set)['clusters'])];
  if (!truthy(at(clusters, i))) return set;
  clusters[i] = <String, dynamic>{...asMap(clusters[i]), ...asMap(patch)};
  return <String, dynamic>{..._objectOf(set), 'clusters': clusters};
}

/// Suggested weight for the next drop: [pct]% lighter, on a loadable weight. [grid] is the
/// exercise's weight step (a number) or a function snapping a weight onto owned plates.
num nextDropWeight(dynamic prevWeight, [dynamic pct = 20, dynamic grid]) {
  final p = math.min(90, math.max(1, numOr(pct, 20)));
  final prev = math.max(0, numOr(prevWeight, 0));
  final raw = prev * (1 - p / 100);
  num tidy(num w) => mathRound(w * 1000) / 1000;
  if (grid is Function) {
    final w = toNum(grid(raw));
    if (w.isFinite && w >= 0) return tidy(w);
  } else if (toNum(grid) > 0) {
    final step = toNum(grid);
    var w = mathRound(raw / step) * step;
    if (prev > 0 && w >= prev) w = prev - step;
    return tidy(math.max(0, w));
  }
  return mathRound(raw * 2) / 2;
}

/// Suggested reps for the next rest-pause burst: roughly half the previous rep count.
num nextBurstReps(dynamic prevReps) => math.max(1, mathRound(numOr(prevReps, 0) / 2));

/// Split a rest-pause total into a descending, roughly-halving sequence that adds back up to it.
List<num> splitBurstReps(dynamic total) {
  final bursts = <num>[];
  var remaining = math.max(0, mathRound(numOr(total, 0)));
  while (remaining > 0) {
    final burst = math.min(remaining, nextBurstReps(remaining));
    bursts.add(burst);
    remaining -= burst;
  }
  return bursts;
}

// --- one-sided (unilateral) sets (issue #60) ---------------------------------------------------

bool isSideSet(dynamic set) {
  final s = _objectOf(set);
  final sides = s['sides'];
  return sides is Map && truthy(sides['L']) && truthy(sides['R']);
}

const String WEIGHT_ORIGIN_MANUAL = 'manual';

/// Includes a completed limb even when its partner is still unchecked.
bool hasCompletedWork(dynamic set) => isSideSet(set)
    ? set['sides']['L']['done'] == true || set['sides']['R']['done'] == true
    : at(set, 'done') == true;

/// Actual completed load x reps; the scalar maximum weight is only a summary.
num completedVolumeOf(dynamic set) {
  if (isSideSet(set)) return completedVolumeOf(set['sides']['L']) + completedVolumeOf(set['sides']['R']);
  if (!truthy(at(set, 'done'))) return 0;
  return numOr(at(set, 'w'), 0) * numOr(at(set, 'r'), 0) + extraVolumeOf(set);
}

JMap _sideOf(dynamic value) {
  final v = _objectOf(value);
  final out = <String, dynamic>{'w': numOr(v['w'], 0), 'r': numOr(v['r'], 0), 'done': v['done'] == true};
  if (v['rir'] != null) out['rir'] = v['rir'];
  if (v['rpe'] != null) out['rpe'] = v['rpe'];
  if (v['weightOrigin'] == WEIGHT_ORIGIN_MANUAL) out['weightOrigin'] = WEIGHT_ORIGIN_MANUAL;
  if (v['type'] == 'dropset' || v['type'] == 'restpause') out['type'] = v['type'];
  if (v['drops'] is List) out['drops'] = v['drops'];
  if (v['clusters'] is List) out['clusters'] = v['clusters'];
  return out;
}

/// Build a per-side row from a plain row: each side half the reps at the same weight, not done.
JMap makeSideSet([dynamic row]) {
  final base = _objectOf(row);
  final half = mathRound(numOr(base['r'], 0) / 2);
  final w = numOr(base['w'], 0);
  JMap side() => <String, dynamic>{'w': w, 'r': half, 'done': false};
  final next = <String, dynamic>{...base, 'sides': <String, dynamic>{'L': side(), 'R': side()}};
  next.remove('rir');
  next.remove('rpe');
  return syncSideAggregate(next);
}

/// Recompute the row's scalar mirror from its two sides; a shallow copy for any other row.
JMap syncSideAggregate(dynamic row) {
  final base = _objectOf(row);
  if (!isSideSet(base)) return <String, dynamic>{...base};
  final L = _sideOf(base['sides']['L']);
  final R = _sideOf(base['sides']['R']);
  final out = <String, dynamic>{
    ...base,
    'sides': <String, dynamic>{'L': L, 'R': R},
    'r': (L['r'] as num) + (R['r'] as num),
    'w': math.max(L['w'] as num, R['w'] as num),
    'done': L['done'] == true && R['done'] == true,
  };
  out.remove('rir');
  out.remove('rpe');
  final rirs = [L['rir'], R['rir']].where((v) => v != null).toList();
  final rpes = [L['rpe'], R['rpe']].where((v) => v != null).toList();
  if (rirs.isNotEmpty) {
    out['rir'] = minOf(rirs.map(toNum));
  } else if (rpes.isNotEmpty) {
    out['rpe'] = maxOf(rpes.map(toNum));
  }
  out.remove('drops');
  out.remove('clusters');
  out.remove('type');
  final sideType = setType(L) != 'straight' ? setType(L) : setType(R);
  if (sideType != 'straight') out['type'] = sideType;
  return out;
}

/// Patch one field on one side ('L'|'R'), resyncing the aggregate. A null clears rir/rpe.
JMap setSideField(dynamic row, dynamic side, String field, dynamic value) {
  final base = _objectOf(row);
  if (!isSideSet(base) || (side != 'L' && side != 'R')) return <String, dynamic>{...base};
  final cur = <String, dynamic>{..._sideOf(base['sides'][side])};
  if (value == null && (field == 'rir' || field == 'rpe')) {
    cur.remove(field);
  } else {
    cur[field] = value;
  }
  return syncSideAggregate(<String, dynamic>{
    ...base,
    'sides': <String, dynamic>{...asMap(base['sides']), side as String: cur},
  });
}

/// Flip one side's done tick, resyncing the row's own done.
JMap toggleSide(dynamic row, dynamic side) {
  final base = _objectOf(row);
  if (!isSideSet(base) || (side != 'L' && side != 'R')) return <String, dynamic>{...base};
  final cur = <String, dynamic>{..._sideOf(base['sides'][side]), 'done': !(_sideOf(base['sides'][side])['done'] as bool)};
  return syncSideAggregate(<String, dynamic>{
    ...base,
    'sides': <String, dynamic>{...asMap(base['sides']), side as String: cur},
  });
}

// --- per-side intensifiers (drop-sets / rest-pause) --------------------------------------------

JMap _patchSide(dynamic row, dynamic side, dynamic Function(JMap sd) fn) {
  final base = _objectOf(row);
  if (!isSideSet(base) || (side != 'L' && side != 'R')) return <String, dynamic>{...base};
  return syncSideAggregate(<String, dynamic>{
    ...base,
    'sides': <String, dynamic>{...asMap(base['sides']), side as String: fn(_sideOf(base['sides'][side]))},
  });
}

JMap _patchBothSides(dynamic row, dynamic Function(JMap sd, String key) fn) {
  final base = _objectOf(row);
  if (!isSideSet(base)) return <String, dynamic>{...base};
  return syncSideAggregate(<String, dynamic>{
    ...base,
    'sides': <String, dynamic>{
      'L': fn(_sideOf(base['sides']['L']), 'L'),
      'R': fn(_sideOf(base['sides']['R']), 'R'),
    },
  });
}

/// Append a drop to both sides, each seeded from its own side's weight (pct lighter) and reps.
JMap addSideDrop(dynamic row, [dynamic pct, dynamic grid]) => _patchBothSides(row, (side, _) {
      final drops = dropsOf(side);
      final base = drops.isNotEmpty ? at(drops.last, 'w') : numOr(side['w'], 0);
      return addDrop(side, {'w': nextDropWeight(base, pct ?? 20, grid), 'r': side['r']});
    });

JMap removeSideDropAt(dynamic row, int i) => _patchBothSides(row, (side, _) => removeDropAt(side, i));

JMap setSideDropAt(dynamic row, dynamic side, int i, dynamic patch) =>
    _patchSide(row, side, (sd) => setDropAt(sd, i, patch));

/// Append a rest-pause burst to both sides; each side's own `r` grows by its added burst.
JMap addSideCluster(dynamic row, [dynamic restSec]) => _patchBothSides(row, (side, _) {
      final clusters = clustersOf(side);
      final base = clusters.isNotEmpty ? at(clusters.last, 'r') : numOr(side['r'], 0);
      final added = nextBurstReps(base);
      return <String, dynamic>{
        ...addCluster(side, {'r': added, 'restSec': restSec}),
        'r': numOr(side['r'], 0) + added,
      };
    });

JMap removeSideClusterAt(dynamic row, int i) => _patchBothSides(row, (side, _) {
      final removed = numOr(at(at(clustersOf(side), i), 'r'), 0);
      return <String, dynamic>{...removeClusterAt(side, i), 'r': math.max(0, numOr(side['r'], 0) - removed)};
    });

JMap setSideClusterAt(dynamic row, dynamic side, int i, dynamic r) => _patchSide(row, side, (sd) {
      final delta = numOr(r, 0) - numOr(at(at(clustersOf(sd), i), 'r'), 0);
      return <String, dynamic>{
        ...asMap(setClusterAt(sd, i, {'r': r})),
        'r': math.max(0, numOr(sd['r'], 0) + delta),
      };
    });

// --- mode --------------------------------------------------------------------------------------

String normalizeMode(dynamic value, [dynamic fallback = 'reps']) {
  final token = value is String ? value.trim().toLowerCase() : '';
  if (_MODES.contains(token)) return token;
  return _MODES.contains(fallback) ? fallback as String : 'reps';
}

String? _modeFromUnit(dynamic value) {
  final token = value is String ? value.trim().toLowerCase() : '';
  if (const ['rep', 'reps', 'repetition', 'repetitions'].contains(token)) return 'reps';
  if (const ['sec', 'secs', 'second', 'seconds'].contains(token)) return 'time';
  if (const ['min', 'mins', 'minute', 'minutes'].contains(token)) return 'cardio';
  return null;
}

String? _explicitMode(dynamic source) {
  final value = _objectOf(source)['mode'];
  final token = value is String ? value.trim().toLowerCase() : '';
  return _MODES.contains(token) ? token : _modeFromUnit(_objectOf(source)['unit']);
}

String? _inferredMode(dynamic source) {
  final value = _objectOf(source);
  final explicit = _explicitMode(value);
  if (explicit != null) return explicit;
  if (jsString(or(value['mode'], '')).trim().toLowerCase() == 'amrap') return 'reps';
  if (value['min'] != null || value['speed'] != null) return 'cardio';
  if (value['sec'] != null || value['seconds'] != null || value['durationSec'] != null) return 'time';
  if (value['r'] != null || value['reps'] != null || value['actualReps'] != null) return 'reps';
  return null;
}

/// Resolve one row's mode: explicit row, parent target, then legacy result fields.
String modeForSet(dynamic set, [dynamic target]) =>
    _explicitMode(set) ?? _inferredMode(target ?? const <String, dynamic>{}) ?? _inferredMode(set) ?? 'reps';

/// Resolve a single mode for an entry; mixed work-row modes intentionally return null.
String? modeForEntry(dynamic entry, [dynamic fallback]) {
  final source = _objectOf(entry);
  final target = _objectOf(or(source['target'], source));
  final sets = source['sets'] is List ? source['sets'] as List : <dynamic>[];
  final work = sets.where((set) => !isWarmupRow(set)).toList();
  final observed = work.isNotEmpty ? work : sets;
  final modes = observed.map((set) => modeForSet(set, target)).toSet().toList();
  if (modes.length > 1) return null;
  if (modes.length == 1) return modes[0];
  final targetMode = _inferredMode(target);
  if (targetMode != null) return targetMode;
  return fallback == null ? modeForSet(source, target) : normalizeMode(fallback);
}
