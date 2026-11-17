// Port of frontend/src/lib/pyramid.js — pyramid sets: one rep target per set, a number or 'max'.
// ignore_for_file: constant_identifier_names

import 'dart:math' as math;

import 'i18n_core.dart';
import 'js.dart';
import 'workout_model.dart';

const String PYRAMID_MAX = 'max';
const int MAX_PYRAMID_SETS = 10;

const List<List<Object>> PYRAMID_PRESETS = [
  [12, 10, 8, 6],
  [6, 8, 10, 12],
  [12, 10, 8, 10, 12],
  [12, 8, 6, PYRAMID_MAX, 12],
];

bool isPyramid(dynamic cfg) {
  if (!truthy(cfg)) return false;
  final p = at(cfg, 'pyramid');
  return p is List && p.isNotEmpty && or(at(cfg, 'mode'), 'reps') == 'reps';
}

/// Whole targets of at least one rep, 'max', at most MAX_PYRAMID_SETS; [stride] 2 rounds up to even.
List<dynamic> normalizePyramid(dynamic list, [num stride = 1]) {
  if (list is! List) return [];
  final out = <dynamic>[];
  for (final v in list) {
    if (v == PYRAMID_MAX) {
      out.add(PYRAMID_MAX);
    } else if (v != null && v != '' && toNum(v).isFinite) {
      final n = math.max(1, mathRound(toNum(v)));
      out.add((n / stride).ceil() * stride);
    }
  }
  return out.length > MAX_PYRAMID_SETS ? out.sublist(0, MAX_PYRAMID_SETS) : out;
}

List<dynamic> pyramidFromFlat(dynamic cfg) {
  final n = math.max(1, math.min(MAX_PYRAMID_SETS, numOr(mathRound(toNum(at(cfg, 'sets'))), 1))).toInt();
  return List<dynamic>.filled(n, or(at(cfg, 'reps'), 10));
}

JMap flatFromPyramid(List<dynamic> list) {
  final first = jsFind(list, (v) => v is num);
  return {'sets': list.length, 'reps': or(first, 10)};
}

/// "12 · 8 · 6 · Max · 12"
String pyramidLabel(List<dynamic> list) => list.map((v) => v == PYRAMID_MAX ? t('Max') : jsString(v)).join(' · ');

dynamic pyramidTargetAt(List<dynamic> list, int i) => i < list.length ? at(list, i) : at(list, list.length - 1);

List<num> normalizePyramidRest(dynamic rest, int length) {
  final src = asList(rest);
  final out = List<num>.generate(length, (i) => math.max(0, numOr(mathRound(toNum(at(src, i))), 0)));
  return out.any((v) => v > 0) ? out : [];
}

List<num> normalizePyramidWeight(dynamic weights, int length) {
  final src = asList(weights);
  final out = List<num>.generate(length, (i) {
    final v = at(src, i);
    final w = v == null && i >= src.length ? double.nan : toNum(v);
    return w.isFinite && w > 0 ? mathRound(w * 100) / 100 : 0;
  });
  return out.any((v) => v > 0) ? out : [];
}

num pyramidWeightAt(dynamic cfg, int i) {
  final pw = at(cfg, 'pyramidWeight');
  if (!isPyramid(cfg) || pw is! List || pw.isEmpty) return 0;
  return math.max(0, numOr(pyramidTargetAt(pw, i), 0));
}

num pyramidRestFor(dynamic target, dynamic rows, int i) {
  final pr = at(target, 'pyramidRest');
  if (!isPyramid(target) || pr is! List || pr.isEmpty) return 0;
  final row = at(rows, i);
  if (!truthy(row) || isWarmupRow(row)) return 0;
  final k = (rows as List).take(i).where((r) => !isWarmupRow(r)).length;
  return math.max(0, numOr(pyramidTargetAt(pr, k), 0));
}

List<JMap> _maxSetsOf(dynamic workouts, dynamic exId) {
  final out = <JMap>[];
  for (final w in asList(workouts)) {
    for (final en in asList(at(w, 'entries'))) {
      if (at(en, 'id') != exId) continue;
      for (final s in asList(at(en, 'sets'))) {
        if (truthy(at(s, 'max')) && truthy(at(s, 'done')) && toNum(at(s, 'r')) > 0 && !isWarmupRow(s)) {
          out.add({'w': numOr(s['w'], 0), 'r': s['r'], 'd': at(w, 'd'), 't': at(w, 'start')});
        }
      }
    }
  }
  return out;
}

/// The Max set a set at [w] is up against: most reps at [w] or heavier; ties heavier, then first.
JMap? maxRecordAt(dynamic workouts, dynamic exId, dynamic w) {
  JMap? best;
  for (final s in _maxSetsOf(workouts, exId)) {
    if ((s['w'] as num) < numOr(w, 0)) continue;
    if (best == null || toNum(s['r']) > toNum(best['r']) || (toNum(s['r']) == toNum(best['r']) && (s['w'] as num) > (best['w'] as num))) best = s;
  }
  return best;
}

/// Most reps in a Max set, per workout: [{ t, y, d, w }].
List<JMap> maxRepsSeries(dynamic workouts, dynamic exId) {
  final byWorkout = <String, JMap>{};
  for (final s in _maxSetsOf(workouts, exId)) {
    final key = '${jsString(s['t'])}|${jsString(s['d'])}';
    final cur = byWorkout[key];
    if (cur == null || toNum(s['r']) > toNum(cur['y'])) byWorkout[key] = {'t': s['t'], 'y': s['r'], 'd': s['d'], 'w': s['w']};
  }
  return byWorkout.values.toList();
}
