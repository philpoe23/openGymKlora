// Port of frontend/src/lib/backoff.js — back-off sets, one weight step lighter each.

import 'dart:math' as math;

import 'exercises.dart';
import 'js.dart';
import 'workout_model.dart';

num _round1(num v) => mathRound(v * 10) / 10;

bool isBackoff(dynamic cfg) {
  if (!truthy(cfg) || at(cfg, 'backoff') != true) return false;
  if (or(at(cfg, 'mode'), 'reps') != 'reps') return false;
  final p = at(cfg, 'pyramid');
  if (p is List && p.isNotEmpty) return false;
  return at(at(cfg, 'intensifier'), 'type') != 'restpause';
}

/// The weight of work set [k] (0 = the top set) below a top set of [top].
num backoffAt(dynamic top, num k, dynamic step) {
  final t = numOr(top, 0);
  final s = numOr(step, 0);
  if (!(t > 0) || !(s > 0) || !(k > 0)) return t;
  final raw = t - k * s;
  final onGrid = (t - mathRound(t / s) * s).abs() <= 0.1;
  final v = onGrid ? _round1(mathRound(raw / s) * s) : _round1(raw);
  return math.max(math.min(t, s), v);
}

num backoffStepOf(dynamic cfg, [dynamic unit]) {
  if (!isBackoff(cfg) || isAssisted(cfg)) return 0;
  return toNum(at(cfg, 'inc')) > 0 ? cfg['inc'] as num : defaultIncrement(at(cfg, 'id'), unit);
}

List<num> backoffWeights(dynamic top, num n, dynamic step) =>
    List.generate(math.max(0, n).toInt(), (k) => backoffAt(top, k, step));

/// Steps the open work rows of a fresh entry down from its first work row.
List<dynamic> applyBackoff(List<dynamic> rows, dynamic step) {
  if (!(toNum(step) > 0)) return rows;
  final first = jsFind(rows, (r) => !isWarmupRow(r));
  final top = first != null ? numOr(at(first, 'w'), 0) : 0;
  if (!(top > 0)) return rows;
  var k = -1;
  return rows.map<dynamic>((row) {
    if (isWarmupRow(row)) return row;
    k++;
    if (k == 0) return row;
    final w = backoffAt(top, k, step);
    if (isSideSet(row)) {
      dynamic side(dynamic s) => truthy(at(s, 'done')) ? s : {...asMap(s), 'w': w};
      return syncSideAggregate({
        ...asMap(row),
        'sides': {'L': side(row['sides']['L']), 'R': side(row['sides']['R'])},
      });
    }
    return truthy(at(row, 'done')) ? row : {...asMap(row), 'w': w};
  }).toList();
}
