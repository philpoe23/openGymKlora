// Port of frontend/src/lib/units.js — converting a profile between kg and lb.
// ignore_for_file: constant_identifier_names

import 'bar.dart';
import 'exercises.dart';
import 'history.dart';
import 'js.dart';
import 'workout_model.dart';

const double _LB_PER_KG = 2.2046226218;

/// lb to the nearest 0.5, kg to the nearest 0.25; the value itself for the same unit or junk.
dynamic convertWeight(dynamic value, dynamic from, dynamic to) {
  if (from == to || value == null || value == '' || !toNum(value).isFinite) return value;
  final v = toNum(value);
  if (to == 'lb') return mathRound(v * _LB_PER_KG * 2) / 2;
  return mathRound(v / _LB_PER_KG * 4) / 4;
}

/// Body weight keeps its 0.1 resolution.
dynamic convertBodyWeight(dynamic value, dynamic from, dynamic to) {
  if (from == to || value == null || value == '' || !toNum(value).isFinite) return value;
  final v = toNum(value);
  return mathRound((to == 'lb' ? v * _LB_PER_KG : v / _LB_PER_KG) * 10) / 10;
}

dynamic _convSet(dynamic set, dynamic from, dynamic to) {
  if (set is! Map) return set;
  final out = <String, dynamic>{...asMap(set)};
  if (isSideSet(set)) {
    return syncSideAggregate({
      ...asMap(set),
      'sides': {'L': _convSet(set['sides']['L'], from, to), 'R': _convSet(set['sides']['R'], from, to)},
    });
  }
  if (out['w'] != null) out['w'] = convertWeight(out['w'], from, to);
  if (out['drops'] is List) {
    out['drops'] = (out['drops'] as List).map((d) => {...asMap(d), 'w': convertWeight(at(d, 'w'), from, to)}).toList();
  }
  return out;
}

dynamic _convTarget(dynamic cfg, dynamic from, dynamic to) {
  if (cfg is! Map) return cfg;
  final out = <String, dynamic>{...asMap(cfg)};
  if (out['weight'] != null) out['weight'] = convertWeight(out['weight'], from, to);
  if (toNum(out['inc']) > 0 && (out['mode'] == null || out['mode'] == 'reps')) out['inc'] = convertWeight(out['inc'], from, to);
  if (out['warmup'] is List) {
    out['warmup'] = (out['warmup'] as List)
        .map((w) => truthy(w) && at(w, 'weight') != null ? {...asMap(w), 'weight': convertWeight(w['weight'], from, to)} : w)
        .toList();
  }
  if (out['pyramidWeight'] is List) {
    out['pyramidWeight'] = (out['pyramidWeight'] as List).map((w) => toNum(w) > 0 ? convertWeight(w, from, to) : w).toList();
  }
  return out;
}

JMap _convBarWeights(dynamic bw, dynamic from, dynamic to) {
  final out = <String, dynamic>{};
  final m = asMap(or(bw, const {}));
  for (final id in jsKeys(m)) {
    final v = m[id];
    if (v is! num || !v.isFinite || v < 0) continue;
    if (v == 0) {
      out[id] = 0;
      continue;
    }
    final eq = at(EXIDX[id], 'eq');
    if (truthy(eq) && v == defaultBarWeight(eq, from)) continue;
    final c = convertWeight(v, from, to);
    if (truthy(eq) && c == defaultBarWeight(eq, to)) continue;
    out[id] = c;
  }
  return out;
}

dynamic _convEntry(dynamic e, dynamic from, dynamic to) {
  if (e is! Map) return e;
  return <String, dynamic>{
    ...asMap(e),
    if (e['topW'] != null) 'topW': convertWeight(e['topW'], from, to),
    if (truthy(e['target'])) 'target': _convTarget(e['target'], from, to),
    if (truthy(e['planned'])) 'planned': _convTarget(e['planned'], from, to),
    if (e['sets'] is List) 'sets': (e['sets'] as List).map((s) => _convSet(s, from, to)).toList(),
  };
}

/// A new state with every weight expressed in [to], and `unit` set to it; [S] itself for the
/// unit already in use.
JMap convertStateUnit(JMap S, String to) {
  final from = or(S['unit'], 'kg');
  if (from == to) return S;
  dynamic c(dynamic v) => convertWeight(v, from, to);
  dynamic bw(dynamic v) => convertBodyWeight(v, from, to);
  JMap convSession(dynamic s) {
    final out = <String, dynamic>{
      ...asMap(s),
      'entries': asList(or(at(s, 'entries'), const [])).map((e) => _convEntry(e, from, to)).toList(),
    };
    if (out['bw'] != null) out['bw'] = bw(out['bw']);
    if (isFiniteNum(out['vol'])) {
      out['vol'] = workoutVolume({'entries': (out['entries'] as List).where((e) => at(e, 'sets') is List).toList()});
    }
    return out;
  }

  final out = <String, dynamic>{...S, 'unit': to};
  if (S['bodyweight'] is List) {
    out['bodyweight'] = (S['bodyweight'] as List).map((b) => {...asMap(b), 'w': bw(at(b, 'w'))}).toList();
  }
  if (S['targetW'] != null) out['targetW'] = bw(S['targetW']);
  if (truthy(S['exWeights'])) {
    final ew = asMap(S['exWeights']);
    out['exWeights'] = <String, dynamic>{
      for (final k in jsKeys(ew)) k: ew[k] is Map ? {...asMap(ew[k]), 'w': c(ew[k]['w'])} : c(ew[k]),
    };
  }
  if (truthy(S['barWeights'])) out['barWeights'] = _convBarWeights(S['barWeights'], from, to);
  if (S['routines'] is List) {
    out['routines'] = (S['routines'] as List)
        .map((r) => {
              ...asMap(r),
              'ex': asList(or(at(r, 'ex'), const [])).map((cfg) => _convTarget(cfg, from, to)).toList(),
            })
        .toList();
  }
  if (S['workouts'] is List) out['workouts'] = (S['workouts'] as List).map(convSession).toList();
  if (truthy(S['active'])) out['active'] = convSession(S['active']);
  return out;
}
