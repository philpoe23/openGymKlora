// Port of frontend/src/lib/rep-range.js — the two bounds of double progression.

import 'dart:math' as math;

import 'js.dart';

/// `{ reps, repsMin }`: reps is the upper bound, repsMin the lower.
JMap normalizeRepRange(dynamic reps, dynamic repsMin, [dynamic stride = 1]) {
  final step = stride is num && stride.isFinite && stride == stride.truncate() && stride > 0 ? stride.toInt() : 1;
  final upper = _align(_positiveInt(reps, 10), step);
  final lower = _align(_positiveInt(repsMin, math.max(1, upper - 2)), step);
  return lower >= upper ? {'reps': lower + step, 'repsMin': lower} : {'reps': upper, 'repsMin': lower};
}

int _align(int value, int stride) => math.max(stride, (value / stride).ceil() * stride);

int _positiveInt(dynamic value, int fallback) {
  final n = toNum(value);
  return n.isFinite && n > 0 ? math.max(1, mathRound(n).toInt()) : fallback;
}
