// Port of frontend/src/lib/plan-share.js — sharing a weekly plan as a small self-contained file:
// buildPlanBundle (every routine, the week schedule, the custom exercises they use), parsePlan
// (validate + normalise an imported file, converting loads into the reader's unit) and mergePlan
// (add the routines as new ones; optionally replace the week). Comments explaining the rules live
// in the JS source.
//
// Not ported: planPrintHTML / printPlan (and their private helpers scheme, intensifierLine,
// units, routineHTML, weekHTML) — the printable HTML page and the browser print dialog are
// DOM/web-only; the app has no print view.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:convert';
import 'dart:math' as math;

import 'backoff.dart';
import 'dumbbells.dart';
import 'exercises.dart';
import 'format.dart';
import 'history.dart';
import 'i18n_core.dart';
import 'js.dart';
import 'media_refs.dart';
import 'muscles.dart';
import 'progression.dart' show MAX_TRIPLE_SETS;
import 'pyramid.dart';
import 'units.dart';

const int PLAN_FMT = 1;
const List<int> WEEK_DAYS = [1, 2, 3, 4, 5, 6, 0];
const Set<String> _PLAN_UNITS = {'kg', 'lb'};

/// What parsePlan / buildPlanBundle / mergePlan throw for a file that is not a plan (the JS
/// `Error` with `code: 'not-plan'`, or a plain one for a bad unit). Its text is the message
/// itself, so a screen can show `'$e'` as it shows `e.message` on the web.
class PlanFormatException extends FormatException {
  const PlanFormatException(super.message, {this.code});

  /// 'not-plan' when the input is not a plan file at all; null for a contradictory unit.
  final String? code;

  @override
  String toString() => message;
}

String? _planUnit(dynamic value) => value == 'lbs' ? 'lb' : (_PLAN_UNITS.contains(value) ? value as String : null);

Never _unitError() => throw PlanFormatException(t('this isn’t an openGym plan file'));

String? _declaredPlanUnit(JMap data) {
  String? declared;
  for (final key in const ['unit', 'weightUnit']) {
    if (data[key] == null) continue;
    final unit = _planUnit(data[key]);
    if (unit == null || (declared != null && declared != unit)) _unitError();
    declared = unit;
  }
  return declared;
}

/// JS `v > 0` for a value that may be anything.
bool _gt0(dynamic v) => v is num ? v > 0 : (v is String || v is bool ? toNum(v) > 0 : false);

/// `o.key = src.key` the way a JS object literal copies it: a missing key stays missing.
void _copy(JMap o, dynamic src, String key) {
  if (src is Map && src.containsKey(key)) o[key] = src[key];
}

JMap _convertedExercise(JMap e, String? sourceUnit, String destinationUnit) {
  if (sourceUnit == null || sourceUnit == destinationUnit) return e;
  final out = <String, dynamic>{...e};
  if (out['weight'] != null) out['weight'] = convertWeight(out['weight'], sourceUnit, destinationUnit);
  if (modeOf(out) == 'reps' && _gt0(out['inc'])) out['inc'] = convertWeight(out['inc'], sourceUnit, destinationUnit);
  if (out['pyramidWeight'] is List) {
    out['pyramidWeight'] = <dynamic>[
      for (final w in out['pyramidWeight'] as List) _gt0(w) ? convertWeight(w, sourceUnit, destinationUnit) : w,
    ];
  }
  return out;
}

JMap _convertedBundle(JMap bundle, String destinationUnit) {
  final sourceUnit = _declaredPlanUnit(bundle);
  if (sourceUnit == null || sourceUnit == destinationUnit) return bundle;
  return {
    ...bundle,
    'unit': destinationUnit,
    'routines': <dynamic>[
      for (final r in asList(or(bundle['routines'], <dynamic>[])))
        {
          ...asMap(r),
          'ex': <dynamic>[
            for (final e in asList(or(at(r, 'ex'), <dynamic>[]))) _convertedExercise(asMap(e), sourceUnit, destinationUnit),
          ],
        },
    ],
  };
}

JMap _cleanEx(dynamic e) {
  final o = <String, dynamic>{};
  _copy(o, e, 'id');
  _copy(o, e, 'sets');
  final mode = modeOf(e);
  if (mode == 'cardio') {
    if (at(e, 'min') != null) o['min'] = at(e, 'min');
    if (at(e, 'speed') != null) o['speed'] = at(e, 'speed');
  } else if (mode == 'time') {
    o['mode'] = 'time';
    if (at(e, 'sec') != null) o['sec'] = at(e, 'sec');
    if (truthy(at(e, 'weight'))) o['weight'] = at(e, 'weight');
  } else {
    if (at(e, 'reps') != null) o['reps'] = at(e, 'reps');
    if (truthy(at(e, 'weight'))) o['weight'] = at(e, 'weight');
    if (isPyramid(e)) {
      final pyramid = normalizePyramid(at(e, 'pyramid'));
      o['pyramid'] = pyramid;
      final rest = normalizePyramidRest(at(e, 'pyramidRest'), pyramid.length);
      if (rest.isNotEmpty) o['pyramidRest'] = rest;
      final weight = normalizePyramidWeight(at(e, 'pyramidWeight'), pyramid.length);
      if (weight.isNotEmpty) o['pyramidWeight'] = weight;
    }
  }
  final bw = at(e, 'bodyweight');
  if (bw != null && bw != isBodyweightEq(at(e, 'id'))) o['bodyweight'] = bw;
  if (truthy(at(e, 'side')) && mode != 'cardio') o['side'] = true;
  if (truthy(at(e, 'prog'))) o['prog'] = at(e, 'prog');
  if (_gt0(at(e, 'inc'))) o['inc'] = at(e, 'inc');
  if (isBackoff(e)) o['backoff'] = true;
  if (at(e, 'lastToFailure') == true && mode != 'cardio') o['lastToFailure'] = true;
  final deload = at(e, 'deloadFactor');
  if (deload != null && toNum(deload) != 0.9) o['deloadFactor'] = deload;
  final db = dbLoadOf(at(e, 'dbLoad'));
  if (db != null) o['dbLoad'] = db;
  if (at(e, 'repsMin') != null) o['repsMin'] = at(e, 'repsMin');
  if (mode == 'reps' && _gt0(at(e, 'setsMax'))) o['setsMax'] = math.min(MAX_TRIPLE_SETS, mathRound(toNum(at(e, 'setsMax'))));
  if (at(e, 'repsMax') != null) o['repsMax'] = at(e, 'repsMax');
  if (_gt0(at(e, 'restSec'))) o['restSec'] = at(e, 'restSec');
  if (_gt0(at(e, 'warmupRestSec'))) o['warmupRestSec'] = at(e, 'warmupRestSec');
  if (truthy(at(e, 'sg'))) o['sg'] = at(e, 'sg');
  if (truthy(at(e, 'note'))) o['note'] = at(e, 'note');
  final warm = _cleanWarmupSets(at(e, 'warmupSets'));
  if (warm > 0) o['warmupSets'] = warm;
  final intens = _cleanIntensifier(at(e, 'intensifier'));
  if (intens != null) o['intensifier'] = intens;
  return o;
}

/// `Math.round(Number(v)) || 0`.
num _roundOr0(dynamic v) {
  final n = mathRound(toNum(v));
  return truthy(n) ? n : 0;
}

num _cleanWarmupSets(dynamic v) {
  final n = _roundOr0(v);
  return n > 0 ? math.min(MAX_PLANNED_WARMUPS, n) : 0;
}

num _cleanRestSec(dynamic v) {
  final n = _roundOr0(v);
  return n > 0 ? n : 0;
}

JMap? _cleanIntensifier(dynamic x) {
  final type = truthy(x) ? at(x, 'type') : x;
  num field(String key, num fallback) {
    final n = mathRound(toNum(at(x, key)));
    return truthy(n) ? n : fallback;
  }

  if (type == 'dropset') {
    return {'type': type, 'count': math.max(1, field('count', 1)), 'pct': math.max(5, field('pct', 20))};
  }
  if (type == 'restpause') {
    return {'type': type, 'totalReps': math.max(1, field('totalReps', 1)), 'restSec': math.max(5, field('restSec', 15))};
  }
  return null;
}

final Set<String> _CUSTOM_MUSCLES = {...MUSCLES, 'cardiovascular system'};

List<dynamic> _muscleList(dynamic v) =>
    inMuscleOrder(<dynamic>{...asList(v).where((m) => _CUSTOM_MUSCLES.contains(m))}.toList());

JMap _cleanCustom(dynamic c) {
  final o = <String, dynamic>{};
  _copy(o, c, 'id');
  _copy(o, c, 'n');
  _copy(o, c, 'bp');
  if (truthy(at(c, 'desc'))) o['desc'] = at(c, 'desc');
  final url = cleanUrl(at(c, 'url'));
  if (url != null) o['url'] = url;
  final eq = at(c, 'eq');
  if (eq is String && eq.isNotEmpty) o['eq'] = eq;
  final prim = _muscleList(at(c, 'primaries'));
  final sm = _muscleList(at(c, 'secondaries')).where((m) => !prim.contains(m)).toList();
  final ctg = at(c, 'tg');
  final tg = prim.isNotEmpty ? prim[0] : (_CUSTOM_MUSCLES.contains(ctg) ? ctg : '');
  if (truthy(tg)) o['tg'] = tg;
  if (prim.isNotEmpty) o['primaries'] = prim;
  if (sm.isNotEmpty) o['secondaries'] = sm;
  if (prim.isNotEmpty || sm.isNotEmpty) o['muscleGroups'] = <dynamic>[...prim, ...sm];
  return o;
}

/// `week?.[d]` for a weekday index: JSON state has string keys, a hand-built map may have ints.
dynamic _day(dynamic week, int d) {
  if (week is! Map) return null;
  return week.containsKey('$d') ? week['$d'] : week[d];
}

/// `v?.length` read as a truthy count: arrays and strings have one, anything else does not.
int _len(dynamic v) => v is List ? v.length : (v is String ? v.length : 0);

/// `[].concat(v)`.
List<dynamic> _concat(dynamic v) => v is List ? <dynamic>[...v] : <dynamic>[v];

String _key(dynamic v) => v is String ? v : jsString(v);

/// Build the shareable bundle: every routine, the week schedule, referenced customs.
JMap buildPlanBundle(dynamic S, [dynamic name]) {
  final unit = _planUnit(at(S, 'unit') ?? 'kg');
  if (unit == null) _unitError();
  final routines = <dynamic>[
    for (final r in asList(or(at(S, 'routines'), <dynamic>[])))
      <String, dynamic>{
        ...(() {
          final o = <String, dynamic>{};
          _copy(o, r, 'id');
          _copy(o, r, 'name');
          _copy(o, r, 'emoji');
          return o;
        })(),
        if (truthy(at(r, 'prog'))) 'prog': at(r, 'prog'),
        if (at(r, 'excludeFromProgression') == true) 'excludeFromProgression': true,
        'ex': <dynamic>[for (final e in asList(or(at(r, 'ex'), <dynamic>[]))) _cleanEx(e)],
      },
  ];
  final usedIds = <dynamic>{for (final r in routines) for (final e in r['ex'] as List) at(e, 'id')};
  final customEx = <dynamic>[
    for (final c in asList(or(at(S, 'customEx'), <dynamic>[])))
      if (usedIds.contains(at(c, 'id'))) _cleanCustom(c),
  ];
  final week = <String, dynamic>{};
  for (final d in [...WEEK_DAYS]..sort()) {
    final v = _day(at(S, 'week'), d);
    if (_len(v) > 0) week['$d'] = _concat(v);
  }
  return {
    'opengym_plan': PLAN_FMT,
    'exported': todayISO(),
    'name': truthy(name) ? name : '',
    'unit': unit,
    'week': week,
    'routines': routines,
    'customEx': customEx,
  };
}

const _stripped = {'warmupSets', 'intensifier', 'restSec', 'warmupRestSec', 'pyramid', 'pyramidRest', 'pyramidWeight'};

/// Validate + normalise an imported file (a JSON string or an already-decoded map). Throws a
/// [PlanFormatException] with a friendly message if it isn't one. Exercises whose id resolves
/// neither to the library nor to a custom exercise in the same file are dropped (`dropped`).
JMap parsePlan(dynamic raw, [dynamic destinationUnit = 'kg']) {
  PlanFormatException notPlan() => PlanFormatException(t('this isn’t an openGym plan file'), code: 'not-plan');
  var data = raw;
  if (raw is String) {
    try {
      data = jsonDecode(raw);
    } catch (_) {
      throw notPlan();
    }
  }
  final destination = _planUnit(destinationUnit);
  if (data is! Map || !truthy(data['opengym_plan']) || data['routines'] is! List || destination == null) {
    throw notPlan();
  }
  final d = asMap(data);
  final sourceUnit = _declaredPlanUnit(d);
  final customEx = asList(d['customEx']).where((c) => truthy(c) && truthy(at(c, 'id'))).toList();
  final known = <dynamic>{for (final c in customEx) at(c, 'id')};
  var dropped = 0;
  final routines = <dynamic>[];
  for (final r in d['routines'] as List) {
    if (!truthy(r) || at(r, 'ex') is! List) continue;
    final ex = <dynamic>[];
    for (final e in at(r, 'ex') as List) {
      final ok = truthy(e) && (known.contains(at(e, 'id')) || exById(at(e, 'id')) != null);
      if (!ok) {
        dropped++;
        continue;
      }
      final warm = _cleanWarmupSets(at(e, 'warmupSets'));
      final intens = _cleanIntensifier(at(e, 'intensifier'));
      final rest = _cleanRestSec(at(e, 'restSec'));
      final warmRest = _cleanRestSec(at(e, 'warmupRestSec'));
      final pyramid = normalizePyramid(at(e, 'pyramid'));
      final pyramidRest = pyramid.isNotEmpty ? normalizePyramidRest(at(e, 'pyramidRest'), pyramid.length) : <num>[];
      final pyramidWeight = pyramid.isNotEmpty ? normalizePyramidWeight(at(e, 'pyramidWeight'), pyramid.length) : <num>[];
      final passthrough = <String, dynamic>{
        for (final kv in asMap(e).entries)
          if (!_stripped.contains(kv.key)) kv.key: kv.value,
      };
      if (!known.contains(passthrough['id'])) passthrough['id'] = canonicalExId(passthrough['id']);
      ex.add(_convertedExercise({
        ...passthrough,
        if (pyramid.isNotEmpty) 'pyramid': pyramid,
        if (pyramidRest.isNotEmpty) 'pyramidRest': pyramidRest,
        if (pyramidWeight.isNotEmpty) 'pyramidWeight': pyramidWeight,
        if (warm > 0) 'warmupSets': warm,
        'intensifier': ?intens,
        if (rest > 0) 'restSec': rest,
        if (warmRest > 0) 'warmupRestSec': warmRest,
      }, sourceUnit ?? destination, destination));
    }
    routines.add(<String, dynamic>{...asMap(r), 'ex': ex});
  }
  final nm = or(d['name'], '');
  return {
    'name': (nm is String ? nm : jsString(nm)).trim(),
    'routines': routines,
    'week': or(d['week'], <String, dynamic>{}),
    'customEx': customEx,
    'dropped': dropped,
    'routineCount': routines.length,
    'exerciseCount': routines.fold<int>(0, (n, r) => n + (r['ex'] as List).length),
    'scheduledDays': WEEK_DAYS.where((day) => _len(_day(d['week'], day)) > 0).length,
    'unit': destination,
    'sourceUnit': sourceUnit,
    'destinationUnit': destination,
  };
}

/// Merge a parsed bundle into the state [s] in place (call inside store.update):
///  - customs: reuse one you already have with the same name + body part, else add it fresh
///  - routines: always added as NEW routines (fresh ids) — never overwrites yours
///  - [schedule]: when on, the shared week REPLACES yours
/// Returns `{routines: n}` (the number of routines added).
JMap mergePlan(JMap s, dynamic bundle, {bool schedule = false}) {
  final destination = _planUnit(s['unit'] ?? 'kg');
  if (destination == null) _unitError();
  final source = _convertedBundle(asMap(bundle), destination);
  // Fresh growable lists of dynamic: a hand-built state may hold typed or fixed ones.
  final customs = s['customEx'] = <dynamic>[...asList(s['customEx'])];
  final routines = s['routines'] = <dynamic>[...asList(s['routines'])];
  final exIdMap = <String, dynamic>{};
  String lc(dynamic v) => (truthy(v) ? jsString(v) : '').toLowerCase();
  for (final c in asList(or(source['customEx'], <dynamic>[]))) {
    final same = jsFind(customs, (x) => lc(at(x, 'n')) == lc(at(c, 'n')) && at(x, 'bp') == at(c, 'bp'));
    if (same != null) {
      exIdMap[_key(at(c, 'id'))] = at(same, 'id');
      continue;
    }
    final nid = uid();
    exIdMap[_key(at(c, 'id'))] = nid;
    final clean = _cleanCustom(c);
    customs.add(<String, dynamic>{
      ...clean,
      'id': nid,
      'sm': ?clean['secondaries'],
      'custom': true,
    });
  }
  final ridMap = <String, dynamic>{};
  final added = asList(source['routines']);
  for (final r in added) {
    final nid = uid();
    ridMap[_key(at(r, 'id'))] = nid;
    final o = <String, dynamic>{'id': nid, 'name': or(at(r, 'name'), t('Shared routine'))};
    _copy(o, r, 'emoji');
    if (truthy(at(r, 'prog'))) o['prog'] = at(r, 'prog');
    if (at(r, 'excludeFromProgression') == true) o['excludeFromProgression'] = true;
    o['ex'] = <dynamic>[
      for (final e in asList(or(at(r, 'ex'), <dynamic>[])))
        <String, dynamic>{...asMap(e), 'id': or(exIdMap[_key(at(e, 'id'))], canonicalExId(at(e, 'id')))},
    ];
    routines.add(o);
  }
  if (schedule) {
    final week = s['week'] = <String, dynamic>{
      if (s['week'] is Map)
        for (final kv in (s['week'] as Map).entries) _key(kv.key): kv.value,
    };
    for (final d in WEEK_DAYS) {
      week.remove('$d');
    }
    final sw = or(source['week'], <String, dynamic>{});
    final keys = sw is Map ? jsKeys(sw) : <String>[];
    for (final k in keys) {
      final ids = _concat(sw.containsKey(k) ? sw[k] : sw[int.tryParse(k)]).map((oldId) => ridMap[_key(oldId)]).where(truthy).toList();
      if (ids.isNotEmpty) week[k] = ids;
    }
  }
  return {'routines': added.length};
}
