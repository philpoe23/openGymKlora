// Port of frontend/src/lib/speed.js — cardio speed, stored in km/h, shown in km/h or mph.
// ignore_for_file: constant_identifier_names

import 'format.dart';
import 'js.dart';

const double KMH_PER_MPH = 1.609344;

String speedUnitOf(dynamic S) {
  final su = at(S, 'speedUnit');
  if (su == 'mph' || su == 'kmh') return su as String;
  return at(S, 'unit') == 'lb' ? 'mph' : 'kmh';
}

String speedLabel(dynamic unit) => unit == 'mph' ? 'mph' : 'km/h';

dynamic toSpeed(dynamic kmh, dynamic unit) {
  if (unit != 'mph' || kmh == null || kmh == '' || !toNum(kmh).isFinite) return kmh;
  return mathRound(toNum(kmh) / KMH_PER_MPH * 100) / 100;
}

dynamic fromSpeed(dynamic value, dynamic unit) {
  if (unit != 'mph' || value == null || value == '' || !toNum(value).isFinite) return value;
  return mathRound(toNum(value) * KMH_PER_MPH * 100) / 100;
}

String fmtSpeed(dynamic kmh, dynamic unit) => '${fmtNum(toSpeed(numOr(kmh, 0), unit))} ${speedLabel(unit)}';
