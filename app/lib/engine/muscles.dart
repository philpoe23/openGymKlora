// Port of frontend/src/lib/muscles.js — which muscles an exercise trains, and how hard.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:math' as math;

import 'exercises.dart';
import 'format.dart';
import 'history.dart';
import 'js.dart';
import 'queue.dart';
import 'workout_model.dart';

const List<String> MUSCLES = [
  'trapezius', 'deltoids', 'chest', 'upper-back', 'serratus',
  'biceps', 'triceps', 'forearm',
  'abs', 'obliques', 'lower-back',
  'gluteal', 'quadriceps', 'hamstring', 'adductors', 'hip-flexors',
  'calves', 'tibialis',
];

/// A picked list in the map's own order; unknown names keep their place at the end.
List<dynamic> inMuscleOrder(dynamic list) {
  int pos(dynamic m) {
    final i = MUSCLES.indexOf(m is String ? m : '');
    return i < 0 ? MUSCLES.length : i;
  }

  return jsSort([...asList(list)], (a, b) => pos(a) - pos(b));
}

const List<String> INERT = ['head', 'hair', 'neck', 'hands', 'feet', 'knees', 'ankles'];

const Map<String, String> MUSCLE_NAME = {
  'trapezius': 'Traps', 'deltoids': 'Shoulders', 'chest': 'Chest', 'upper-back': 'Upper back',
  'serratus': 'Serratus', 'biceps': 'Biceps', 'triceps': 'Triceps', 'forearm': 'Forearms',
  'abs': 'Abs', 'obliques': 'Obliques', 'lower-back': 'Lower back', 'gluteal': 'Glutes',
  'quadriceps': 'Quads', 'hamstring': 'Hamstrings', 'adductors': 'Adductors',
  'hip-flexors': 'Hip flexors', 'calves': 'Calves', 'tibialis': 'Shins', 'cardiovascular system': 'cardiovascular system',
};

const Map<String, String?> _ALIAS = {
  'abs': 'abs', 'pectorals': 'chest', 'biceps': 'biceps', 'glutes': 'gluteal', 'delts': 'deltoids',
  'triceps': 'triceps', 'upper back': 'upper-back', 'lats': 'upper-back', 'calves': 'calves',
  'quads': 'quadriceps', 'forearms': 'forearm', 'hamstrings': 'hamstring', 'spine': 'lower-back',
  'traps': 'trapezius', 'adductors': 'adductors', 'serratus anterior': 'serratus',
  'abductors': 'gluteal', 'levator scapulae': 'trapezius', 'cardiovascular system': 'cardiovascular system',
  'shoulders': 'deltoids', 'deltoids': 'deltoids', 'rear deltoids': 'deltoids',
  'rotator cuff': 'deltoids', 'quadriceps': 'quadriceps', 'core': 'abs', 'abdominals': 'abs',
  'lower abs': 'abs', 'chest': 'chest', 'upper chest': 'chest', 'hip flexors': 'hip-flexors',
  'obliques': 'obliques', 'lower back': 'lower-back', 'rhomboids': 'upper-back',
  'trapezius': 'trapezius', 'back': 'upper-back', 'latissimus dorsi': 'upper-back',
  'brachialis': 'biceps', 'soleus': 'calves', 'shins': 'tibialis', 'wrists': 'forearm',
  'wrist flexors': 'forearm', 'wrist extensors': 'forearm', 'grip muscles': 'forearm',
  'groin': 'adductors', 'inner thighs': 'adductors',
  'ankles': null, 'feet': null, 'hands': null, 'ankle stabilizers': null,
  'sternocleidomastoid': null,
};

const Map<String, Map<String, num>> _BY_BODYPART = {
  'chest': {'chest': 1},
  'back': {'upper-back': 0.75, 'lower-back': 0.25},
  'shoulders': {'deltoids': 1},
  'upper arms': {'biceps': 0.5, 'triceps': 0.5},
  'lower arms': {'forearm': 1},
  'waist': {'abs': 0.7, 'obliques': 0.3},
  'upper legs': {'quadriceps': 0.4, 'hamstring': 0.35, 'gluteal': 0.25},
  'lower legs': {'calves': 0.8, 'tibialis': 0.2},
  'neck': {'trapezius': 1},
  'full body': {'chest': 0.2, 'upper-back': 0.2, 'gluteal': 0.2, 'quadriceps': 0.2, 'hamstring': 0.1, 'abs': 0.1},
  'cardio': {},
};

const num _SECONDARY = 0.4;

List<dynamic> _arrayOf(dynamic value) => value is List ? value : (value == null || value == '' ? const [] : [value]);

dynamic _firstPresent(dynamic object, List<String> keys) {
  if (object is! Map) return null;
  for (final key in keys) {
    if (object.containsKey(key)) return object[key];
  }
  return null;
}

dynamic _metadataOf(dynamic ex) {
  if (ex is! Map) return ex;
  const directKeys = [
    'muscleGroups', 'muscles', 'targetMuscles', 'muscleWeights',
    'primaries', 'primaryMuscles', 'primary', 'secondaries', 'secondaryMuscles', 'secondary',
  ];
  final hasDirect = directKeys.any(ex.containsKey) || [ex['tg'], ex['mg'], ..._arrayOf(ex['sm'])].any((v) => v != null && v != '');
  return !hasDirect && ex['muscleSnapshot'] is Map ? ex['muscleSnapshot'] : ex;
}

({List<dynamic> primary, List<dynamic> secondary})? _explicitPartsOf(dynamic ex) {
  if (ex is! Map) return null;
  final primary = _firstPresent(ex, ['primaries', 'primaryMuscles', 'primary']);
  final secondary = _firstPresent(ex, ['secondaries', 'secondaryMuscles', 'secondary']);
  if (primary != null || secondary != null) return (primary: _arrayOf(primary), secondary: _arrayOf(secondary));
  return null;
}

List<dynamic>? _explicitGroupsOf(dynamic ex) {
  if (ex is! Map) return null;
  for (final k in ['muscleGroups', 'muscles', 'targetMuscles']) {
    if (ex.containsKey(k)) {
      final groups = _arrayOf(ex[k]);
      return groups.isNotEmpty ? groups : null;
    }
  }
  return null;
}

String? _canonicalMuscle(dynamic value) {
  final name = (truthy(value) ? jsString(value) : '').toLowerCase().trim();
  if (MUSCLES.contains(name)) return name;
  return _ALIAS[name];
}

List<String> _canonicalUnique(Iterable<dynamic>? values) {
  final out = <String>[];
  for (final value in values ?? const []) {
    final slug = _canonicalMuscle(value);
    if (slug != null && !out.contains(slug)) out.add(slug);
  }
  return out;
}

bool _anyCanonical(Iterable<dynamic> xs) => xs.any((v) => _canonicalMuscle(v) != null);

/// True only when the catalogue explicitly supplied muscle groups.
bool hasExplicitMuscleMetadata(dynamic entry) {
  final ex = _metadataOf(entry);
  if (ex is! Map) return false;
  final parts = _explicitPartsOf(ex);
  if (parts != null && _anyCanonical([...parts.primary, ...parts.secondary])) return true;
  final groups = _explicitGroupsOf(ex);
  if (groups != null && _anyCanonical(groups)) return true;
  return _anyCanonical([ex['tg'], ex['mg'], ..._arrayOf(smOf(ex))]);
}

/// Canonical unique muscle groups.
List<String> muscleGroupsOf(dynamic entry) {
  final ex = _metadataOf(entry);
  final parts = _explicitPartsOf(ex);
  final explicit = _explicitGroupsOf(ex);
  final useParts = parts != null && _anyCanonical([...parts.primary, ...parts.secondary]);
  final source = useParts ? [...parts.primary, ...parts.secondary] : (explicit ?? [at(ex, 'tg'), at(ex, 'mg'), ..._arrayOf(smOf(ex))]);
  final out = _canonicalUnique(source);
  if (out.isEmpty && !useParts) out.addAll(_canonicalUnique((_BY_BODYPART[at(ex, 'bp')] ?? const {}).keys));
  return out;
}

List<String> normalizeMuscleGroups(dynamic entry) => muscleGroupsOf(entry);

bool matchesMuscleGroups(dynamic ex, dynamic requested) {
  final wanted = _arrayOf(requested).map(_canonicalMuscle).whereType<String>().toList();
  if (wanted.isEmpty) return true;
  final groups = muscleGroupsOf(ex).toSet();
  return wanted.any(groups.contains);
}

/// Complete muscle-weight metadata, including explicit zero-credit associations.
Map<String, num> muscleWeightsOf(dynamic ex) {
  if (!truthy(ex)) return {};
  final sourceEx = _metadataOf(ex);
  if (!identical(sourceEx, ex)) return muscleWeightsOf(sourceEx);
  final mw = at(ex, 'muscleWeights');
  if (mw is Map) {
    final snapshot = <String, num>{};
    for (final slug in MUSCLES) {
      if (!mw.containsKey(slug)) continue;
      final weight = toNum(mw[slug]);
      if (weight.isFinite && weight >= 0 && weight <= 1) snapshot[slug] = weight;
    }
    if (snapshot.isNotEmpty) return snapshot;
  }
  final out = <String, num>{};
  void add(dynamic name, num w) {
    final slug = _canonicalMuscle(name);
    if (slug != null) out[slug] = math.max(out[slug] ?? 0, w);
  }

  final parts = _explicitPartsOf(ex);
  final explicit = _explicitGroupsOf(ex);
  final useParts = parts != null && _anyCanonical([...parts.primary, ...parts.secondary]);
  if (useParts) {
    for (final m in parts.primary) {
      add(m, 1);
    }
    for (final m in parts.secondary) {
      add(m, _SECONDARY);
    }
  } else if (explicit != null) {
    for (final m in explicit) {
      add(m, 1);
    }
  } else {
    add(at(ex, 'tg'), 1);
    add(at(ex, 'mg'), _SECONDARY);
    for (final m in _arrayOf(smOf(ex))) {
      add(m, _SECONDARY);
    }
  }
  if (out.isEmpty) out.addAll(_BY_BODYPART[at(ex, 'bp')] ?? const {});
  return out;
}

/// Muscles one exercise trains: positive effective stimulus only.
Map<String, num> musclesOf(dynamic ex) => Map.fromEntries(muscleWeightsOf(ex).entries.where((e) => e.value > 0));

/// Display and weighted muscle metadata for a completed history entry.
JMap exerciseMuscleSnapshot(dynamic ex) {
  if (ex is! Map) return {};
  final out = <String, dynamic>{};
  if (ex['n'] != null) out['n'] = ex['n'];
  if (ex['bp'] != null) out['bp'] = ex['bp'];
  final weights = muscleWeightsOf(ex);
  if (weights.isNotEmpty) out['muscleWeights'] = {...weights};
  final parts = _explicitPartsOf(ex);
  if (parts != null) {
    final primaries = _canonicalUnique(parts.primary);
    final secondaries = _canonicalUnique(parts.secondary).where((s) => !primaries.contains(s)).toList();
    if (primaries.isNotEmpty) out['primaries'] = primaries;
    if (secondaries.isNotEmpty) out['secondaries'] = secondaries;
  }
  if (hasExplicitMuscleMetadata(ex)) out['muscleGroups'] = [...muscleGroupsOf(ex)];
  return out;
}

/// Training load per muscle, in effective sets. [items] is [{ id, sets, ex? }].
Map<String, num> loadOf(List<dynamic> items) {
  final load = <String, num>{};
  for (final item in items) {
    final id = at(item, 'id');
    final sets = at(item, 'sets');
    if (!truthy(sets)) continue;
    final historical = or(at(item, 'ex'), at(item, 'exercise'));
    final source = truthy(at(historical, 'muscleWeights')) ? historical : or(or(exById(id), historical), item);
    final m = musclesOf(source);
    for (final e in m.entries) {
      load[e.key] = (load[e.key] ?? 0) + e.value * toNum(sets);
    }
  }
  return load;
}

int _workCount(dynamic e, [bool Function(dynamic)? pick]) =>
    asList(or(at(e, 'sets'), const [])).where((s) => truthy(at(s, 'done')) && !isWarmupRow(s) && (pick == null || pick(s))).length;

/// Load for finished workouts (ticked work sets only), optionally narrowed by [pick].
Map<String, num> loadOfWorkouts(dynamic workouts, [bool Function(dynamic)? pick]) => loadOf([
      for (final w in asList(or(workouts, const [])))
        for (final e in asList(or(at(w, 'entries'), const [])))
          {'id': at(e, 'id'), 'ex': or(at(e, 'exercise'), e), 'sets': _workCount(e, pick)},
    ]);

/// Workouts in one Muscle balance range (0 = all, 7 = this week, else trailing days).
List<dynamic> muscleBalanceWindow(dynamic workouts, num win, [num? now, String? today, int ws = MONDAY]) {
  final n = now ?? DateTime.now().millisecondsSinceEpoch;
  final day = today ?? todayISO();
  return asList(or(workouts, const [])).where((w) {
    if (win == 0) return true;
    if (win == 7) return weekKey(at(w, 'd'), ws) == weekKey(day, ws);
    return workoutAt(w) > n - win * 86400000;
  }).toList();
}

/// Load a routine would produce, from its planned set counts.
Map<String, num> loadOfRoutine(dynamic routine, [dynamic exercises = const {}]) => loadOf([
      for (final c in asList(or(at(routine, 'ex'), const [])))
        {'id': at(c, 'id'), 'ex': or(at(exercises, at(c, 'id') ?? ''), c), 'sets': or(at(c, 'sets'), 1)},
    ]);

/// Effective sets programmed by the live recurring week (and the floating week, once each).
Map<String, num> loadOfWeeklyPlan([dynamic S]) {
  final routines = <dynamic, dynamic>{for (final r in asList(at(S, 'routines'))) at(r, 'id'): r};
  final exercises = <String, dynamic>{for (final e in asList(at(S, 'customEx'))) jsString(at(e, 'id')): e};
  final q = queueOf(S);
  final queued = q != null ? asList(or(at(at(S, 'queue'), 'ids'), const [])).toSet() : <dynamic>{};
  final week = asMap(or(at(S, 'week'), const {}));
  final ids = [
    for (final k in jsKeys(week))
      for (final id in (truthy(week[k]) ? (week[k] is List ? week[k] as List : [week[k]]) : const []))
        if (!queued.contains(id)) id,
    if (q != null) ...q['ids'] as List,
  ];
  final load = <String, num>{};
  for (final id in ids) {
    final routine = routines[id];
    if (routine == null) continue;
    for (final e in loadOfRoutine(routine, exercises).entries) {
      load[e.key] = (load[e.key] ?? 0) + e.value;
    }
  }
  return load;
}

/// Load for a workout still in progress.
Map<String, num> loadOfActive(dynamic active) => loadOf([
      for (final e in asList(or(at(active, 'entries'), const []))) {'id': at(e, 'id'), 'ex': or(at(e, 'exercise'), e), 'sets': _workCount(e)},
    ]);

/// Shade buckets 0–4 per muscle: relative to the hardest-worked muscle, or by [thresholds]
/// ([{ at, level, exclusive? }], the last matching rule wins).
Map<String, int> levelsOf(Map<dynamic, dynamic> load, [List<dynamic>? thresholds]) {
  if (thresholds != null) {
    final lv = <String, int>{};
    for (final m in MUSCLES) {
      final value = toNum(or(load[m], 0));
      var level = 0;
      for (final rule in thresholds) {
        final a = toNum(at(rule, 'at'));
        final matches = truthy(at(rule, 'exclusive')) ? value > a : value >= a;
        if (matches) level = math.max(0, math.min(4, toNum(at(rule, 'level')))).toInt();
      }
      lv[m] = level;
    }
    return lv;
  }
  final max = maxOf([0, ...MUSCLES.map((m) => toNum(or(load[m], 0)))]);
  final lv = <String, int>{};
  for (final m in MUSCLES) {
    final v = toNum(or(load[m], 0));
    lv[m] = !truthy(v) ? 0 : (max <= 0 ? 0 : math.max(1, math.min(4, (v / max * 4).ceil())));
  }
  return lv;
}

/// Muscles sorted hardest-worked first; untrained ones last, in body order.
JMap rankOf(Map<dynamic, dynamic> load) {
  num l(String m) => toNum(or(load[m], 0));
  final worked = jsSort(MUSCLES.where((m) => l(m) > 0).toList(), (a, b) {
    final d = cmpNum(l(b) - l(a));
    return d != 0 ? d : MUSCLES.indexOf(a) - MUSCLES.indexOf(b);
  });
  final missed = MUSCLES.where((m) => !(toNum(load[m]) > 0)).toList();
  return {'worked': worked, 'missed': missed};
}
