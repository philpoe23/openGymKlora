// Port of frontend/src/lib/incline.js — treadmill incline per cardio set.
// ignore_for_file: constant_identifier_names

import 'dart:math' as math;

import 'exercises.dart';
import 'js.dart';

const num INCLINE_MAX = 40;
const num INCLINE_STEP = 0.5;

/// A grade on the half percent between 0 and 40; nothing stays nothing (null).
num? clampIncline(dynamic v) {
  if (v == null || v == '') return null;
  final n = toNum(v);
  if (!n.isFinite) return null;
  return math.min(INCLINE_MAX, math.max(0, mathRound(n / INCLINE_STEP) * INCLINE_STEP));
}

final _hilly = RegExp(r'treadmill|\bwalk|\brun\b|running|\bjog|sprint|stepmill|stair|stepper|elliptical|cross ?trainer|\bhik(e|ing)|incline|trot|march', caseSensitive: false);
final _flat = RegExp(r'bike|bicycl|cycl|row(ing|er)?\b|rope|skat|swim|\bski\b|erg\b|jack|burpee|punch|shuffle|hop|jump|climber|crawl', caseSensitive: false);
const Set<String> _HILLY_EQ = {'elliptical machine', 'stepmill machine'};

bool inclineFits(dynamic ex) {
  if (ex is! Map) return false;
  final name = truthy(ex['n']) ? jsString(ex['n']) : '';
  if (_flat.hasMatch(name)) return false;
  if (_hilly.hasMatch(name) || _HILLY_EQ.contains((truthy(ex['eq']) ? jsString(ex['eq']) : '').toLowerCase())) return true;
  return isCustomEx(ex);
}

bool hasIncline(dynamic s) => toNum(at(s, 'incline')) > 0;

JMap inclineFrom(dynamic s) => hasIncline(s) ? {'incline': toNum(s['incline'])} : <String, dynamic>{};
