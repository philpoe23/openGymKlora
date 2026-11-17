// Port of frontend/src/lib/history.test.js.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';
import 'package:klora_app/engine/format.dart';
import 'package:klora_app/engine/history.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/workout_model.dart';

import '_exdb.dart';
import '_helpers.dart';

// Real ids out of the shipped catalogue, so the body-part fallback is exercised for real.
String get CARDIO => jsFind(EXDB, (e) => e['bp'] == 'cardio')['id'] as String;
// A *loaded* lift (the first non-cardio entry is a sit-up, which defaults to bodyweight).
String get LIFT => jsFind(EXDB, (e) => e['bp'] != 'cardio' && e['eq'] != 'body weight')['id'] as String;
String get BW => jsFind(EXDB, (e) => e['eq'] == 'body weight')['id'] as String;

Map<String, dynamic> get emptyS => <String, dynamic>{'workouts': [], 'exWeights': <String, dynamic>{}};

int parseLocal(String s) => DateTime.parse(s).millisecondsSinceEpoch;

void main() {
  setUpAll(loadTestExerciseDb);

  group('modeOf', () {
    test('falls back to the body part when a plan has no mode — every existing plan keeps working', () {
      expect(modeOf({'id': CARDIO}), 'cardio');
      expect(modeOf({'id': LIFT}), 'reps');
      expect(modeOf({'id': 'no-such-exercise'}), 'reps');
      expect(modeOf({}), 'reps');
      expect(modeOf(null), 'reps');
    });

    test('lets an explicit mode win over the body part', () {
      expect(modeOf({'id': LIFT, 'mode': 'time'}), 'time');
      expect(modeOf({'id': CARDIO, 'mode': 'reps'}), 'reps');
      expect(modeOf({'id': CARDIO, 'mode': 'time'}), 'time');
    });

    test('ignores a mode it does not know rather than trusting a bad file', () {
      expect(modeOf({'id': LIFT, 'mode': 'nonsense'}), 'reps');
      expect(modeOf({'id': CARDIO, 'mode': ''}), 'cardio');
    });

    test('exposes the timed check', () {
      expect(isTimed({'id': LIFT, 'mode': 'time'}), isTrue);
      expect(isTimed({'id': LIFT}), isFalse);
    });
  });

  group('fmtSec', () {
    test('reads as a clock, not a pile of seconds', () {
      expect(fmtSec(0), '0:00');
      expect(fmtSec(9), '0:09');
      expect(fmtSec(45), '0:45');
      expect(fmtSec(60), '1:00');
      expect(fmtSec(90), '1:30');
      expect(fmtSec(605), '10:05');
    });
    test('is defensive about junk input', () {
      expect(fmtSec(-5), '0:00');
      expect(fmtSec(null), '0:00');
      expect(fmtSec(double.nan), '0:00');
      expect(fmtSec(44.6), '0:45');
    });
  });

  group('setLabel', () {
    test('describes each mode in its own terms', () {
      expect(setLabel(LIFT, {'w': 60, 'r': 10}), '60×10');
      expect(setLabel(CARDIO, {'min': 20, 'speed': 9}), '20 min @ 9 km/h');
      expect(setLabel(LIFT, {'sec': 45, 'w': 0}, {'mode': 'time'}), '0:45');
      expect(setLabel(LIFT, {'sec': 90, 'w': 20}, {'mode': 'time'}), '1:30 · 20');
    });

    test('reads a legacy set with no config exactly as before', () {
      expect(setLabel(LIFT, {'w': 0, 'r': 0}), '0×0');
      expect(setLabel(CARDIO, {}), '0 min @ 0 km/h');
    });

    test('reads a cardio set by the exercise id when its target carries neither id nor mode', () {
      expect(setLabel(CARDIO, {'min': 20, 'speed': 9}, {'sets': 1, 'min': 20, 'speed': 8}), '20 min @ 9 km/h');
      expect(setLabel(CARDIO, {'sec': 45, 'w': 0}, {'mode': 'time'}), '0:45');
    });

    test('reads a rep set as reps when its exercise has become cardio since', () {
      expect(setLabel(CARDIO, {'w': 50, 'r': 10}, {'sets': 3, 'reps': 10, 'weight': 50, 'bodyweight': false}), '50×10');
      expect(setLabel(CARDIO, {'w': 50, 'r': 10}), '+50 × 10');
      expect(setLabel(CARDIO, {'min': 20, 'speed': 9, 'r': 0}, {'sets': 1}), '20 min @ 9 km/h');
      expect(setLabel(CARDIO, {'w': 50, 'r': 10}, {'mode': 'cardio'}), '0 min @ 0 km/h');
    });

    test('appends RIR when present, including a valid 0', () {
      expect(setLabel(LIFT, {'w': 60, 'r': 10, 'rir': 2}), '60×10 (RIR 2)');
      expect(setLabel(LIFT, {'w': 60, 'r': 10, 'rir': 1.5}), '60×10 (RIR 1.5)');
      expect(setLabel(LIFT, {'w': 60, 'r': 10, 'rir': 0}), '60×10 (RIR 0)');
    });

    test('says nothing about RIR on a set that never logged one', () {
      expect(setLabel(LIFT, {'w': 60, 'r': 10}), '60×10');
      expect(setLabel(LIFT, {'w': 60, 'r': 10, 'rir': null}), '60×10');
    });

    test('appends RPE for a set logged on that scale', () {
      expect(setLabel(LIFT, {'w': 60, 'r': 10, 'rpe': 8}), '60×10 (RPE 8)');
      expect(setLabel(LIFT, {'w': 60, 'r': 10, 'rpe': 9.5}), '60×10 (RPE 9.5)');
      expect(setLabel(LIFT, {'w': 60, 'r': 10, 'rpe': null}), '60×10');
    });

    test('keeps each set on the scale it was logged with', () {
      expect(setLabel(LIFT, {'w': 60, 'r': 10, 'rir': 2}), '60×10 (RIR 2)');
      expect(setLabel(LIFT, {'w': 60, 'r': 10, 'rir': 2, 'rpe': 8}), '60×10 (RIR 2)');
    });

    test("lists a drop-set's drops after the main set, effort last", () {
      final drop = <String, dynamic>{'w': 100, 'r': 8, 'type': 'dropset', 'drops': [{'w': 80, 'r': 6}, {'w': 60, 'r': 5}]};
      expect(setLabel(LIFT, drop), '100×8 ↘ 80×6 ↘ 60×5');
      expect(setLabel(LIFT, {...drop, 'rir': 0}), '100×8 ↘ 80×6 ↘ 60×5 (RIR 0)');
      expect(setLabel(LIFT, {'w': 100, 'r': 8, 'type': 'dropset', 'drops': [{'w': 80, 'r': 0}]}), '100×8');
      expect(setLabel(LIFT, {'w': 100, 'r': 8, 'type': 'straight', 'drops': [{'w': 80, 'r': 6}]}), '100×8');
    });

    test('writes a rest-pause set as its bursts, adding up to the logged total', () {
      expect(setLabel(LIFT, {'w': 60, 'r': 16, 'type': 'restpause', 'clusters': [{'r': 4, 'restSec': 15}, {'r': 2, 'restSec': 15}]}), '60×10+4+2');
      expect(setLabel(LIFT, {'w': 60, 'r': 12, 'type': 'restpause', 'clusters': [for (final r in [6, 3, 2, 1]) {'r': r, 'restSec': 15}]}), '60×6+3+2+1');
      expect(setLabel(LIFT, {'w': 60, 'r': 5, 'type': 'restpause', 'clusters': [{'r': 4}, {'r': 3}]}), '60×5');
    });

    test('reads a planned rest-pause set whose total was raised by hand as its plain total', () {
      final cfg = <String, dynamic>{'id': LIFT, 'reps': 8, 'intensifier': {'type': 'restpause', 'totalReps': 12, 'restSec': 15}};
      final work = applyIntensifierPlan([<String, dynamic>{'w': 60, 'r': 8, 'done': false}], cfg)[1] as Map<String, dynamic>;
      expect(setLabel(LIFT, work, cfg), '60×6+3+2+1');
      expect(setLabel(LIFT, {...work, 'r': 14}, cfg), '60×14');
      final added = {...work, 'r': 13, 'clusters': [...work['clusters'] as List, {'r': 1, 'restSec': 15}]};
      expect(setLabel(LIFT, added, cfg), '60×6+3+2+1+1');
      final sided = applyIntensifierPlan([makeSideSet({'w': 20, 'r': 8, 'done': false})], {...cfg, 'side': true})[1];
      sided['sides']['L'] = {...sided['sides']['L'] as Map<String, dynamic>, 'r': sided['sides']['L']['r'] + 2};
      expect(setLabel(LIFT, sided, {...cfg, 'side': true}), 'L 20×8 · R 20×3+2+1');
      expect(setLabel(LIFT, {'w': 60, 'r': 16, 'type': 'restpause', 'clusters': [{'r': 4}, {'r': 2}]}, {'id': LIFT, 'reps': 10}), '60×10+4+2');
    });

    test('reads drops and bursts of a bodyweight exercise as reps and added weight', () {
      final cfg = {'id': BW, 'bodyweight': true};
      expect(setLabel(BW, {'w': 10, 'r': 8, 'type': 'dropset', 'drops': [{'w': 0, 'r': 5}]}, cfg), '+10 × 8 ↘ 5');
      expect(setLabel(BW, {'w': 0, 'r': 12, 'type': 'restpause', 'clusters': [{'r': 3}]}, cfg), '9+3');
    });

    test("shows each side's own drops on a unilateral drop-set", () {
      Map<String, dynamic> side(num w, num r, List<dynamic> drops) => {'w': w, 'r': r, 'done': true, 'type': 'dropset', 'drops': drops};
      final s = {
        'w': 20, 'r': 16, 'done': true, 'type': 'dropset',
        'sides': {'L': side(20, 8, [{'w': 15, 'r': 6}]), 'R': side(20, 8, [{'w': 15, 'r': 5}])},
      };
      expect(setLabel(LIFT, s, {'id': LIFT, 'side': true}), 'L 20×8 ↘ 15×6 · R 20×8 ↘ 15×5');
    });
  });

  group('effortOf', () {
    test('reads the scale a profile logs', () {
      expect(effortOf({'effort': 'rpe'}), 'rpe');
      expect(effortOf({'effort': 'rir'}), 'rir');
      expect(effortOf({'effort': 'none'}), 'none');
      expect(effortOf({}), 'none');
    });

    test('keeps the column for a profile still carrying the old showRir flag', () {
      expect(effortOf({'showRir': true}), 'rir');
      expect(effortOf({'effort': null, 'showRir': true}), 'rir');
      expect(effortOf({'effort': null}), 'none');
      expect(effortOf({'showRir': false}), 'none');
      expect(effortOf({'showRir': true, 'effort': 'rpe'}), 'rpe');
      expect(effortOf({'showRir': true, 'effort': 'none'}), 'none');
    });

    Map<String, dynamic> overlay(Map<String, dynamic> stored) => {'unit': 'kg', 'effort': null, ...stored};

    test('survives the overlay every load path performs', () {
      expect(effortOf(overlay({'showRir': true})), 'rir');
      expect(effortOf(overlay({'showRir': false})), 'none');
      expect(effortOf(overlay({})), 'none');
      expect(effortOf(overlay({'effort': 'rpe'})), 'rpe');
      expect(effortOf(overlay({'showRir': true, 'effort': null})), 'rir');
    });

    test('is not fooled by a junk value', () {
      expect(effortOf({'effort': 'rpe10'}), 'none');
      expect(effortOf({'effort': 'RIR'}), 'none');
      expect(effortOf({'effort': 'f'}), 'none');
      expect(effortOf(null), 'none');
      expect(effortOf({'effort': 'nope', 'showRir': true}), 'rir');
    });
  });

  group('stepEffort', () {
    test('starts at the bottom of the scale and walks up', () {
      expect(stepEffort('rir', null, 1), 0);
      expect(stepEffort('rpe', null, 1), 6);
      expect(stepEffort('rir', 0, 1), 0.5);
      expect(stepEffort('rir', 0.5, 1), 1);
      expect(stepEffort('rpe', 6, 1), 6.5);
    });

    test('leaves an untouched cell unlogged when stepped down', () {
      expect(stepEffort('rir', null, -1), isNull);
      expect(stepEffort('rpe', null, -1), isNull);
    });

    test('clears the cell again when stepped back off the floor', () {
      expect(stepEffort('rir', 0, -1), isNull);
      expect(stepEffort('rpe', 6, -1), isNull);
      expect(stepEffort('rir', 0.5, -1), 0);
      expect(stepEffort('rpe', 6.5, -1), 6);
    });

    test('stops at the top of the scale', () {
      expect(stepEffort('rir', 9.5, 1), 10);
      expect(stepEffort('rir', 10, 1), 10);
      expect(stepEffort('rpe', 10, 1), 10);
    });

    test('keeps halves clean instead of drifting into float dust', () {
      dynamic v;
      for (var i = 0; i < 6; i++) {
        v = stepEffort('rpe', v, 1);
      }
      expect(v, 8.5);
      expect(stepEffort('rir', 0.1 + 0.2, 1), 0.8);
    });

    test('steps evenly from a value typed below the floor rather than snapping', () {
      expect(stepEffort('rpe', 3, 1), 3.5);
      expect(stepEffort('rpe', 3, -1), isNull);
    });

    test('does nothing when the profile logs no effort at all', () {
      expect(stepEffort('none', null, 1), isNull);
      expect(stepEffort('none', 2, 1), 2);
      expect(stepEffort(null, 2, -1), 2);
    });
  });

  group('capEffort', () {
    test('caps a typed value at the top of the scale', () {
      expect(capEffort('rir', 12), 10);
      expect(capEffort('rpe', 99), 10);
      expect(capEffort('rpe', 8), 8);
    });

    test('does not floor a typed value, so typing "10" survives its first keystroke', () {
      expect(capEffort('rpe', 1), 1);
      expect(capEffort('rir', 0), 0);
    });

    test('passes an emptied field through untouched', () {
      expect(capEffort('rir', null), isNull);
      expect(capEffort('none', 12), 12);
    });
  });

  group('logging effort across a session', () {
    test('logs a working set on the chosen scale', () {
      dynamic v;
      for (var i = 0; i < 4; i++) {
        v = stepEffort('rpe', v, 1);
      }
      expect(setLabel(LIFT, {'w': 80, 'r': 5, 'rpe': v}), '80×5 (RPE 7.5)');
    });

    test('a set taken to failure is logged, not left blank', () {
      final v = stepEffort('rir', null, 1);
      expect(v, 0);
      expect(setLabel(LIFT, {'w': 100, 'r': 3, 'rir': v}), '100×3 (RIR 0)');
    });

    test('switching the setting mid-history rewrites nothing', () {
      final old = {'w': 60, 'r': 10, 'rir': 2};
      final fresh = {'w': 60, 'r': 10, 'rpe': 8};
      expect(effortOf({'effort': 'rpe'}), 'rpe');
      expect(setLabel(LIFT, old), '60×10 (RIR 2)');
      expect(setLabel(LIFT, fresh), '60×10 (RPE 8)');
      expect(effortOf({'effort': 'none'}), 'none');
      expect(setLabel(LIFT, old), '60×10 (RIR 2)');
    });

    test('never attaches effort to a mode that has no place for it', () {
      expect(setLabel(CARDIO, {'min': 20, 'speed': 9, 'rpe': 8}), '20 min @ 9 km/h');
      expect(setLabel(LIFT, {'sec': 45, 'rir': 2}, {'id': LIFT, 'mode': 'time'}), '0:45');
    });
  });

  group('defaultConfig', () {
    test('gives each mode a sensible starting point', () {
      expect(defaultConfig(LIFT), jeq({'sets': 3, 'reps': 10, 'weight': 0, 'mode': 'reps'}));
      expect(defaultConfig(CARDIO), jeq({'sets': 1, 'min': 20, 'speed': 8}));
      expect(defaultConfig(LIFT, 'time'), jeq({'sets': 3, 'sec': 45, 'weight': 0, 'mode': 'time'}));
    });
    test('seeds the bodyweight flag from the catalogue, and only when it is true', () {
      expect(defaultConfig(BW), jeq({'sets': 3, 'reps': 10, 'weight': 0, 'mode': 'reps', 'bodyweight': true}));
      expect(defaultConfig(BW, 'time'), jeq({'sets': 3, 'sec': 45, 'weight': 0, 'mode': 'time', 'bodyweight': true}));
      expect(defaultConfig(LIFT).containsKey('bodyweight'), isFalse);
    });
  });

  group('isBw', () {
    test('defaults from the catalogue so an existing plan needs no flag', () {
      expect(isBw({'id': BW}), isTrue);
      expect(isBw({'id': LIFT}), isFalse);
    });
    test('lets the config win in both directions — a belt on a dip, a flag on a machine', () {
      expect(isBw({'id': BW, 'bodyweight': false}), isFalse);
      expect(isBw({'id': LIFT, 'bodyweight': true}), isTrue);
    });
  });

  group('sideReps', () {
    test('halves the logged total, because the total is what was logged', () {
      expect(sideReps(16), 8);
      expect(sideReps(0), 0);
    });
    test('shows an odd total as it falls rather than rounding the imbalance away', () {
      expect(sideReps(17), 8.5);
    });
  });

  group('exLine — per side on a timed hold', () {
    test('reads "per side" rather than splitting a duration in half', () {
      expect(exLine({'id': LIFT, 'sets': 3, 'sec': 45, 'mode': 'time', 'side': true}, 'kg'), '3 × 0:45 · per side');
    });
    test('leaves a plain hold untouched', () {
      expect(exLine({'id': LIFT, 'sets': 3, 'sec': 45, 'mode': 'time'}, 'kg'), '3 × 0:45');
    });
  });

  group('repStep', () {
    test('steps unilateral work in twos so the total stays splittable', () {
      expect(repStep({'side': true}), 2);
      expect(repStep({}), 1);
      expect(repStep(null), 1);
    });
  });

  group('setLabel — bodyweight', () {
    test('reads as reps alone, because "0×12" describes nothing', () {
      expect(setLabel(BW, {'w': 0, 'r': 12}, {'id': BW}), '12');
    });
    test('spells out a belt as an addition', () {
      expect(setLabel(BW, {'w': 10, 'r': 8}, {'id': BW}), '+10 × 8');
    });
    test('logs a per-side set as the plain total, like every other set in the app', () {
      expect(setLabel(BW, {'w': 0, 'r': 16}, {'id': BW, 'side': true}), '16');
      expect(setLabel(LIFT, {'w': 20, 'r': 16}, {'id': LIFT, 'side': true}), '20×16');
    });
    test('keeps the effort tail', () {
      expect(setLabel(BW, {'w': 0, 'r': 12, 'rir': 2}, {'id': BW}), '12 (RIR 2)');
    });
  });

  group('exLine', () {
    test('shows the split where there is room for it, next to the total you log', () {
      expect(exLine({'id': LIFT, 'sets': 3, 'reps': 16, 'side': true}, 'kg'), '3 × 16 · 8/side');
    });
    test('marks added weight as added', () {
      expect(exLine({'id': BW, 'sets': 3, 'reps': 8, 'weight': 10}, 'kg'), '3 × 8 · +10 kg');
    });
    test('summarises a planned exercise per mode', () {
      expect(exLine({'id': LIFT, 'sets': 3, 'reps': 10}, 'kg'), '3 × 10');
      expect(exLine({'id': LIFT, 'sets': 3, 'reps': 10, 'weight': 60}, 'kg'), '3 × 10 · 60 kg');
      expect(exLine({'id': LIFT, 'sets': 3, 'sec': 45, 'mode': 'time'}, 'kg'), '3 × 0:45');
      expect(exLine({'id': LIFT, 'sets': 2, 'sec': 90, 'weight': 20, 'mode': 'time'}, 'kg'), '2 × 1:30 · 20 kg');
      expect(exLine({'id': CARDIO, 'sets': 1, 'min': 20, 'speed': 8}, 'kg'), '1 × 20 min @ 8 km/h');
    });
    test('reads a double-progression range as the range, not as its top', () {
      expect(exLine({'id': LIFT, 'sets': 2, 'reps': 15, 'repsMin': 10, 'weight': 40}, 'kg'), '2 × 10–15 · 40 kg');
      expect(exLine({'id': LIFT, 'sets': 3, 'reps': 16, 'repsMin': 12, 'side': true}, 'kg'), '3 × 12–16 · 6–8/side');
      expect(exLine({'id': LIFT, 'sets': 2, 'reps': 10, 'repsMin': 10}, 'kg'), '2 × 10');
    });
    test('gives the sets and reps alone for the workout card', () {
      expect(setsRepsOf({'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 60}), '2 × 10');
      expect(setsRepsOf({'id': LIFT, 'sets': 3, 'reps': 12, 'repsMin': 8, 'weight': 40}), '3 × 8–12');
      expect(setsRepsOf({'id': LIFT, 'sets': 2, 'sec': 45, 'mode': 'time'}), '2 × 0:45');
    });
  });

  group('freestyleConfig', () {
    test('inherits the last target and completed set count for a newly added exercise', () {
      final S = {
        'exWeights': {},
        'workouts': [
          {
            'd': '2026-01-01',
            'entries': [
              {
                'id': LIFT,
                'target': {'mode': 'reps', 'sets': 4, 'reps': 8, 'weight': 60, 'prog': 'linear'},
                'sets': [
                  {'w': 60, 'r': 8, 'done': true},
                  {'w': 62.5, 'r': 7, 'done': true},
                  {'w': 62.5, 'r': 6, 'done': true},
                  {'w': 62.5, 'r': 5, 'done': true},
                ],
              },
            ],
          },
        ],
      };
      final cfg = freestyleConfig(S, {'id': LIFT, 'mode': 'reps', 'sets': 3, 'reps': 10, 'weight': 0});
      expect(cfg, jeq({'id': LIFT, 'mode': 'reps', 'sets': 4, 'reps': 8, 'weight': 60, 'prog': 'linear'}));
      expect(buildSets(S, cfg), jeq([
        {'w': 60, 'r': 8, 'done': false},
        {'w': 62.5, 'r': 7, 'done': false},
        {'w': 62.5, 'r': 6, 'done': false},
        {'w': 62.5, 'r': 5, 'done': false},
      ]));
    });

    test('adds no rows when the config asks for no warm-ups', () {
      final S = {'exWeights': {}, 'workouts': []};
      final cfg = {'id': '0025', 'mode': 'reps', 'sets': 2, 'reps': 5, 'weight': 100};
      expect(buildSets(S, cfg), jeq([
        {'w': 100, 'r': 5, 'done': false},
        {'w': 100, 'r': 5, 'done': false},
      ]));
    });

    test('prepends the planned warm-ups as a ramp toward the work weight', () {
      final S = {'exWeights': {}, 'workouts': []};
      final cfg = {'id': '0025', 'mode': 'reps', 'sets': 2, 'reps': 5, 'weight': 100, 'warmupSets': 3};
      final rows = buildSets(S, cfg, {'step': 2.5});
      expect(rows.map((r) => r['w']).toList(), jeq([50, 75, 87.5, 100, 100]));
      expect(rows.sublist(0, 3).every((r) => r['phase'] == 'warmup'), isTrue);
      expect(rows.sublist(3).every((r) => r['phase'] == null), isTrue);
    });

    test('never ramps a barbell warm-up below the bar it is done with', () {
      final S = <String, dynamic>{'unit': 'lb', 'exWeights': {}, 'workouts': []};
      final bench = <String, dynamic>{'id': '0025', 'mode': 'reps', 'sets': 3, 'reps': 10, 'weight': 55, 'warmupSets': 1};
      expect(buildSets(S, bench, {'step': 5}).map((r) => r['w']).toList(), jeq([45, 55, 55, 55]));
      expect(buildSets(S, {...bench, 'warmupSets': 2}, {'step': 5}).map((r) => r['w']).toList().sublist(0, 2), jeq([45, 50]));
      expect(buildSets(S, {...bench, 'weight': 135, 'warmupSets': 3}, {'step': 5}).map((r) => r['w']).toList().sublist(0, 3), jeq([65, 100, 115]));
      expect(buildSets({...S, 'barWeights': {'0025': 35}}, bench, {'step': 5})[0]['w'], 35);
      expect(buildSets({...S, 'barWeights': {'0025': 0}}, bench, {'step': 5})[0]['w'], 25);
      expect(buildSets({...S, 'barWeights': {'0025': 65}}, bench, {'step': 5})[0]['w'], 55);
      expect(buildSets(S, {'id': '0289', 'mode': 'reps', 'sets': 1, 'reps': 10, 'weight': 50, 'warmupSets': 1}, {'step': 5})[0]['w'], 25);
      final rows = <dynamic>[<String, dynamic>{'w': 55, 'r': 10, 'done': false}];
      expect(insertWarmupRow(rows, 'reps', bench, 5, 45)[0]['w'], 45);
      expect(insertWarmupRow(rows, 'reps', bench, 5)[0]['w'], 25);
    });

    test('caps the planned warm-ups and ignores nonsense values', () {
      final S = {'exWeights': {}, 'workouts': []};
      final base = <String, dynamic>{'id': '0025', 'mode': 'reps', 'sets': 1, 'reps': 5, 'weight': 100};
      expect(buildSets(S, {...base, 'warmupSets': 99}, {'step': 2.5}).where((r) => r['phase'] == 'warmup'), hasLength(5));
      expect(buildSets(S, {...base, 'warmupSets': -2}, {'step': 2.5}), hasLength(1));
      expect(buildSets(S, {...base, 'warmupSets': 'x'}, {'step': 2.5}), hasLength(1));
    });

    test('keeps planned warm-ups out of the work-set count', () {
      final S = {'exWeights': {}, 'workouts': []};
      final rows = buildSets(S, {'id': '0025', 'mode': 'reps', 'sets': 3, 'reps': 5, 'weight': 100, 'warmupSets': 2}, {'step': 2.5});
      final logged = {
        'entries': [
          {'id': '0025', 'sets': rows.map((r) => {...r as Map<String, dynamic>, 'done': true}).toList()},
        ],
      };
      expect(logged['entries']![0]['sets'], hasLength(5));
      expect(workSetsDone(logged), 3);
    });

    test('inherits the target for timed and cardio exercises too', () {
      final timed = {
        'exWeights': {},
        'workouts': [
          {
            'd': '2026-01-02',
            'entries': [
              {
                'id': LIFT,
                'target': {'mode': 'time', 'sets': 2, 'sec': 60, 'weight': 15},
                'sets': [{'sec': 55, 'w': 15, 'done': true}, {'sec': 60, 'w': 17.5, 'done': true}],
              },
            ],
          },
        ],
      };
      final cardio = {
        'exWeights': {},
        'workouts': [
          {
            'd': '2026-01-03',
            'entries': [
              {
                'id': CARDIO,
                'target': {'sets': 2, 'min': 30, 'speed': 7},
                'sets': [{'min': 28, 'speed': 7, 'done': true}, {'min': 30, 'speed': 7.5, 'done': true}],
              },
            ],
          },
        ],
      };

      final timedCfg = freestyleConfig(timed, {'id': LIFT, 'mode': 'time', 'sets': 3, 'sec': 45, 'weight': 0});
      expect(timedCfg, jeq({'id': LIFT, 'mode': 'time', 'sets': 2, 'sec': 60, 'weight': 15}));
      expect(buildSets(timed, timedCfg), jeq([
        {'sec': 55, 'w': 15, 'done': false},
        {'sec': 60, 'w': 17.5, 'done': false},
      ]));

      final cardioCfg = freestyleConfig(cardio, {'id': CARDIO, 'sets': 1, 'min': 20, 'speed': 8});
      expect(cardioCfg, jeq({'id': CARDIO, 'sets': 2, 'min': 30, 'speed': 7}));
      expect(buildSets(cardio, cardioCfg), jeq([
        {'min': 28, 'speed': 7, 'done': false},
        {'min': 30, 'speed': 7.5, 'done': false},
      ]));
    });

    test('keeps the supplied defaults when there is no completed matching workout', () {
      final cfg = freestyleConfig(emptyS, {'id': LIFT, 'mode': 'reps', 'sets': 3, 'reps': 10, 'weight': 50});
      expect(cfg, jeq({'id': LIFT, 'mode': 'reps', 'sets': 3, 'reps': 10, 'weight': 50}));
    });
  });

  group('buildSets', () {
    test('builds reps sets from the plan when there is no history', () {
      expect(buildSets(emptyS, {'id': LIFT, 'sets': 3, 'reps': 8, 'weight': 50}),
          jeq([{'w': 50, 'r': 8, 'done': false}, {'w': 50, 'r': 8, 'done': false}, {'w': 50, 'r': 8, 'done': false}]));
    });

    test('builds timed sets, carrying the planned duration and load', () {
      expect(buildSets(emptyS, {'id': LIFT, 'mode': 'time', 'sets': 2, 'sec': 60, 'weight': 20}),
          jeq([{'sec': 60, 'w': 20, 'done': false}, {'sec': 60, 'w': 20, 'done': false}]));
    });

    test('doubles a per-side timed hold — once on each side, full duration both times', () {
      expect(buildSets(emptyS, {'id': LIFT, 'mode': 'time', 'sets': 2, 'sec': 30, 'weight': 0, 'side': true}), jeq([
        {'sec': 30, 'w': 0, 'done': false, 'side': 'L'}, {'sec': 30, 'w': 0, 'done': false, 'side': 'R'},
        {'sec': 30, 'w': 0, 'done': false, 'side': 'L'}, {'sec': 30, 'w': 0, 'done': false, 'side': 'R'},
      ]));
    });

    test('carries a per-side timed hold forward by row, L and R each keeping their own history', () {
      final S = {
        'exWeights': {},
        'workouts': [
          {
            'd': '2026-01-01',
            'entries': [
              {
                'id': LIFT,
                'target': {'mode': 'time', 'side': true},
                'sets': [{'sec': 40, 'w': 5, 'done': true, 'side': 'L'}, {'sec': 35, 'w': 5, 'done': true, 'side': 'R'}],
              },
            ],
          },
        ],
      };
      expect(buildSets(S, {'id': LIFT, 'mode': 'time', 'sets': 1, 'sec': 30, 'weight': 0, 'side': true}),
          jeq([{'sec': 40, 'w': 5, 'done': false, 'side': 'L'}, {'sec': 35, 'w': 5, 'done': false, 'side': 'R'}]));
    });

    test('builds cardio sets unchanged', () {
      expect(buildSets(emptyS, {'id': CARDIO, 'sets': 1, 'min': 25, 'speed': 9}), jeq([{'min': 25, 'speed': 9, 'done': false}]));
    });

    test("carries last time's numbers forward within the same mode", () {
      final S = {
        'exWeights': {},
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'target': {'mode': 'time'}, 'sets': [{'sec': 70, 'w': 10, 'done': true}]}]},
        ],
      };
      expect(buildSets(S, {'id': LIFT, 'mode': 'time', 'sets': 2, 'sec': 45, 'weight': 0}),
          jeq([{'sec': 70, 'w': 10, 'done': false}, {'sec': 70, 'w': 10, 'done': false}]));
    });

    test('does not seed a duration from a rep count when an exercise switches to time', () {
      final S = {
        'exWeights': {},
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'sets': [{'w': 60, 'r': 10, 'done': true}]}]},
        ],
      };
      expect(buildSets(S, {'id': LIFT, 'mode': 'time', 'sets': 1, 'sec': 45, 'weight': 0}), jeq([{'sec': 45, 'w': 0, 'done': false}]));
    });

    test('does not seed reps from a timed set when an exercise switches back', () {
      final S = {
        'exWeights': {},
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'target': {'mode': 'time'}, 'sets': [{'sec': 70, 'w': 10, 'done': true}]}]},
        ],
      };
      expect(buildSets(S, {'id': LIFT, 'mode': 'reps', 'sets': 1, 'reps': 8, 'weight': 40}), jeq([{'w': 40, 'r': 8, 'done': false}]));
    });

    test('seeds the weight from the last session, and the confirmed working weight only when there is none', () {
      final S = <String, dynamic>{
        'exWeights': {LIFT: {'w': 75}},
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'sets': [{'w': 60, 'r': 10, 'done': true}]}]},
        ],
      };
      expect(buildSets(S, {'id': LIFT, 'sets': 1, 'reps': 8, 'weight': 50}), jeq([{'w': 60, 'r': 10, 'done': false}]));
      expect(buildSets({...S, 'workouts': []}, {'id': LIFT, 'sets': 1, 'reps': 8, 'weight': 50}), jeq([{'w': 75, 'r': 8, 'done': false}]));
    });

    test("opens at the plan's reps with planReps, taking only the weight from the last session", () {
      final S = {
        'exWeights': {},
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'sets': [{'w': 60, 'r': 15, 'done': true}, {'w': 62.5, 'r': 12, 'done': true}]}]},
        ],
      };
      expect(buildSets(S, {'id': LIFT, 'sets': 2, 'reps': 10, 'weight': 50}, {'planReps': true}),
          jeq([{'w': 60, 'r': 10, 'done': false}, {'w': 62.5, 'r': 10, 'done': false}]));
      expect(buildSets(S, {'id': LIFT, 'sets': 1, 'reps': 10, 'weight': 50, 'warmupSets': 1}, {'planReps': true, 'step': 2.5}).map((s) => s['r']).toList(),
          jeq([10, 10]));
    });

    test("keeps each side's carried weight and splits the plan's reps evenly with planReps", () {
      Map<String, dynamic> side(num w, num r) => {'w': w, 'r': r, 'done': true};
      final S = {
        'exWeights': {},
        'workouts': [
          {
            'd': '2026-01-01',
            'entries': [
              {
                'id': LIFT,
                'target': {'side': true},
                'sets': [{'w': 22.5, 'r': 13, 'done': true, 'sides': {'L': side(22.5, 7), 'R': side(20, 6)}}],
              },
            ],
          },
        ],
      };
      final row = buildSets(S, {'id': LIFT, 'sets': 1, 'reps': 16, 'weight': 20, 'side': true}, {'planReps': true})[0];
      expect(row['sides']['L'], matchObj({'w': 22.5, 'r': 8}));
      expect(row['sides']['R'], matchObj({'w': 20, 'r': 8}));
      expect(row['r'], 16);
      final carried = buildSets(S, {'id': LIFT, 'sets': 1, 'reps': 16, 'weight': 20, 'side': true})[0];
      expect([carried['sides']['L']['r'], carried['sides']['R']['r']], jeq([7, 6]));
    });

    test('ignores planReps for freestyle, which reproduces what you did', () {
      final S = {
        'exWeights': {},
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'sets': [{'w': 60, 'r': 15, 'done': true}]}]},
        ],
      };
      expect(buildSets(S, {'id': LIFT, 'sets': 1, 'reps': 10, 'weight': 50}, {'planReps': true, 'preferLast': true}),
          jeq([{'w': 60, 'r': 15, 'done': false}]));
    });

    test('can preserve each last set weight for freestyle instead of using the working-weight hint', () {
      final S = {
        'exWeights': {LIFT: {'w': 75}},
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'sets': [{'w': 60, 'r': 10, 'done': true}, {'w': 62.5, 'r': 8, 'done': true}]}]},
        ],
      };
      expect(buildSets(S, {'id': LIFT, 'sets': 2, 'reps': 8, 'weight': 50}, {'preferLast': true}),
          jeq([{'w': 60, 'r': 10, 'done': false}, {'w': 62.5, 'r': 8, 'done': false}]));
    });

    test('can use a deload target without carrying regular-session values into it', () {
      final S = {
        'exWeights': {LIFT: {'w': 75}},
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'sets': [{'w': 75, 'r': 10, 'done': true}, {'w': 75, 'r': 9, 'done': true}]}]},
        ],
      };
      expect(buildSets(S, {'id': LIFT, 'sets': 2, 'reps': 12, 'weight': 40}, {'useTarget': true}),
          jeq([{'w': 40, 'r': 12, 'done': false}, {'w': 40, 'r': 12, 'done': false}]));
    });

    test("uses the current routine target instead of another routine's bodyweight history", () {
      final S = {
        'exWeights': {},
        'workouts': [
          {
            'd': '2026-01-01',
            'routineId': 'routine-a',
            'entries': [
              {
                'id': BW,
                'target': {'sets': 2, 'reps': 15, 'weight': 0, 'bodyweight': true},
                'sets': [{'w': 0, 'r': 15, 'done': true}, {'w': 0, 'r': 15, 'done': true}],
              },
            ],
          },
        ],
      };
      final cfg = <String, dynamic>{'id': BW, 'sets': 4, 'reps': 8, 'weight': 0, 'bodyweight': true, 'prog': 'off'};
      expect(buildSets(S, cfg, {'useTarget': true}), jeq([
        {'w': 0, 'r': 8, 'done': false},
        {'w': 0, 'r': 8, 'done': false},
        {'w': 0, 'r': 8, 'done': false},
        {'w': 0, 'r': 8, 'done': false},
      ]));

      final reverseS = {
        'exWeights': {},
        'workouts': [
          {
            'd': '2026-01-02',
            'routineId': 'routine-b',
            'entries': [
              {
                'id': BW,
                'target': {'sets': 4, 'reps': 8, 'weight': 0, 'bodyweight': true},
                'sets': [
                  {'w': 0, 'r': 8, 'done': true}, {'w': 0, 'r': 8, 'done': true},
                  {'w': 0, 'r': 8, 'done': true}, {'w': 0, 'r': 8, 'done': true},
                ],
              },
            ],
          },
        ],
      };
      expect(buildSets(reverseS, {...cfg, 'sets': 2, 'reps': 15}, {'useTarget': true}), jeq([
        {'w': 0, 'r': 15, 'done': false},
        {'w': 0, 'r': 15, 'done': false},
      ]));
    });

    test('preserves configured load, reps, duration and cardio targets when history is present', () {
      final repsS = {
        'exWeights': {LIFT: {'w': 75}},
        'workouts': [
          {'d': '2026-01-01', 'entries': [{'id': LIFT, 'sets': [{'w': 75, 'r': 15, 'done': true}]}]},
        ],
      };
      expect(buildSets(repsS, {'id': LIFT, 'sets': 2, 'reps': 8, 'weight': 40}, {'useTarget': true}),
          jeq([{'w': 40, 'r': 8, 'done': false}, {'w': 40, 'r': 8, 'done': false}]));

      final timedS = {
        'exWeights': {},
        'workouts': [
          {'d': '2026-01-02', 'entries': [{'id': LIFT, 'target': {'mode': 'time'}, 'sets': [{'sec': 90, 'w': 20, 'done': true}]}]},
        ],
      };
      expect(buildSets(timedS, {'id': LIFT, 'mode': 'time', 'sets': 2, 'sec': 30, 'weight': 5}, {'useTarget': true}),
          jeq([{'sec': 30, 'w': 5, 'done': false}, {'sec': 30, 'w': 5, 'done': false}]));

      final cardioS = {
        'exWeights': {},
        'workouts': [
          {'d': '2026-01-03', 'entries': [{'id': CARDIO, 'sets': [{'min': 45, 'speed': 10, 'done': true}]}]},
        ],
      };
      expect(buildSets(cardioS, {'id': CARDIO, 'sets': 2, 'min': 20, 'speed': 8}, {'useTarget': true}),
          jeq([{'min': 20, 'speed': 8, 'done': false}, {'min': 20, 'speed': 8, 'done': false}]));
    });
  });

  group('applyIntensifierPlan', () {
    test('pre-fills every work row with a chain of drops, each pct% lighter than the one before', () {
      final sets = <dynamic>[{'w': 100, 'r': 8, 'done': false}, {'w': 100, 'r': 8, 'done': false}];
      final out = applyIntensifierPlan(sets, {'intensifier': {'type': 'dropset', 'count': 2, 'pct': 20}});
      expect(out, jeq([
        {'w': 100, 'r': 8, 'done': false, 'type': 'dropset', 'drops': [{'w': 80, 'r': 8}, {'w': 64, 'r': 8}]},
        {'w': 100, 'r': 8, 'done': false, 'type': 'dropset', 'drops': [{'w': 80, 'r': 8}, {'w': 64, 'r': 8}]},
      ]));
    });

    test("collapses rest-pause to exactly two rows regardless of how many sets were configured: a warm-up at the exercise's own reps, then one work set whose own reps ARE the total", () {
      final sets = <dynamic>[{'w': 60, 'r': 8, 'done': false}, {'w': 60, 'r': 8, 'done': false}, {'w': 60, 'r': 8, 'done': false}];
      final out = applyIntensifierPlan(sets, {'reps': 8, 'intensifier': {'type': 'restpause', 'totalReps': 12, 'restSec': 15}});
      expect(out, jeq([
        {'w': 60, 'r': 8, 'done': false, 'phase': 'warmup'},
        {
          'w': 60, 'r': 12, 'done': false, 'type': 'restpause',
          'clusters': [{'r': 6, 'restSec': 15}, {'r': 3, 'restSec': 15}, {'r': 2, 'restSec': 15}, {'r': 1, 'restSec': 15}],
        },
      ]));
      expect((out[1]['clusters'] as List).fold<num>(0, (sum, c) => sum + (c['r'] as num)), out[1]['r']);
    });

    test("the warm-up reps come from the exercise's own configured reps, not the rest-pause total", () {
      final sets = <dynamic>[{'w': 60, 'r': 8, 'done': false}];
      final out = applyIntensifierPlan(sets, {'reps': 5, 'intensifier': {'type': 'restpause', 'totalReps': 20, 'restSec': 15}});
      expect(out[0], jeq({'w': 60, 'r': 5, 'done': false, 'phase': 'warmup'}));
    });

    test('carries the prescribed weight from the built sets onto both new rows', () {
      final sets = <dynamic>[{'w': 82.5, 'r': 8, 'done': false}];
      final out = applyIntensifierPlan(sets, {'reps': 8, 'intensifier': {'type': 'restpause', 'totalReps': 4, 'restSec': 15}});
      expect(out[0]['w'], 82.5);
      expect(out[1]['w'], 82.5);
    });

    test('never touches a warm-up row', () {
      final sets = <dynamic>[{'w': 20, 'r': 8, 'done': false, 'phase': 'warmup'}, {'w': 100, 'r': 8, 'done': false}];
      final out = applyIntensifierPlan(sets, {'intensifier': {'type': 'dropset', 'count': 1, 'pct': 20}});
      expect(out[0], jeq({'w': 20, 'r': 8, 'done': false, 'phase': 'warmup'}));
      expect(out[1]['type'], 'dropset');
    });

    test('leaves sets untouched with no intensifier configured', () {
      final sets = <dynamic>[{'w': 100, 'r': 8, 'done': false}];
      expect(applyIntensifierPlan(sets, {}), same(sets));
      expect(applyIntensifierPlan(sets, {'intensifier': {'type': 'nonsense'}}), same(sets));
    });
  });

  group('workoutVolume', () {
    test('counts reps work and leaves timed/cardio sets out — there is no weight × reps for a hold', () {
      final w = {
        'entries': [
          {'id': LIFT, 'sets': [{'w': 60, 'r': 10, 'done': true}, {'w': 60, 'r': 10, 'done': false}]},
          {'id': LIFT, 'target': {'mode': 'time'}, 'sets': [{'sec': 60, 'w': 20, 'done': true}]},
          {'id': CARDIO, 'sets': [{'min': 20, 'speed': 9, 'done': true}]},
        ],
      };
      expect(workoutVolume(w), 600);
    });

    test('needs no per-side case — the logged reps are already both sides (issue #31)', () {
      final w = {
        'entries': [
          {'id': LIFT, 'target': {'side': true}, 'sets': [{'w': 20, 'r': 16, 'done': true}]},
        ],
      };
      expect(workoutVolume(w), 320);
    });

    test("adds drop-set drops on top of the row's main set", () {
      final dropRow = {'type': 'dropset', 'w': 100, 'r': 5, 'done': true, 'drops': [{'w': 80, 'r': 5}, {'w': 60, 'r': 5}]};
      expect(workoutVolume({'entries': [{'id': LIFT, 'sets': [dropRow]}]}), 100 * 5 + 80 * 5 + 60 * 5);
    });

    test('counts a rest-pause row once — its own r is already the total across every burst', () {
      final burstRow = {
        'type': 'restpause', 'w': 60, 'r': 20, 'done': true,
        'clusters': [{'r': 10, 'restSec': 15}, {'r': 5, 'restSec': 15}, {'r': 3, 'restSec': 15}, {'r': 1, 'restSec': 15}, {'r': 1, 'restSec': 15}],
      };
      expect(workoutVolume({'entries': [{'id': LIFT, 'sets': [burstRow]}]}), 60 * 20);
    });

    test('ignores drops/bursts on a row that was never checked off', () {
      final dropRow = {'type': 'dropset', 'w': 100, 'r': 5, 'done': false, 'drops': [{'w': 80, 'r': 5}]};
      expect(workoutVolume({'entries': [{'id': LIFT, 'sets': [dropRow]}]}), 0);
    });

    test('leaves an unloaded bodyweight set at zero volume rather than inventing a number', () {
      final w = {
        'entries': [
          {'id': BW, 'target': {'bodyweight': true}, 'sets': [{'w': 0, 'r': 20, 'done': true}]},
        ],
      };
      expect(workoutVolume(w), 0);
    });

    test('recognizes both warm-up schemas in work-set counts', () {
      final w = {
        'unit': 'kg',
        'entries': [
          {
            'id': LIFT,
            'unit': 'kg',
            'sets': [
              {'warmup': true, 'unit': 'kg', 'w': 20, 'r': 5, 'done': true},
              {'phase': 'warmup', 'unit': 'kg', 'w': 30, 'r': 5, 'done': true},
              {'phase': 'work', 'unit': 'kg', 'w': 60, 'r': 5, 'done': true},
            ],
          },
        ],
      };
      expect(workSetsDone(w), 1);
    });

    test('counts work sets the way it counts all sets: each side of a unilateral row (QA 1.3.9)', () {
      final both = toggleSide(toggleSide(makeSideSet({'w': 20, 'r': 20}), 'L'), 'R');
      final one = toggleSide(makeSideSet({'w': 20, 'r': 20}), 'L');
      final w = {
        'entries': [
          {'id': LIFT, 'sets': [both, one, {'w': 30, 'r': 5, 'done': true}]},
        ],
      };
      expect(setsDone(w), 4);
      expect(workSetsDone(w), 4);
    });

    test('does not use a warm-up as the previous best working weight', () {
      expect(
          bestWeightFor({
            'workouts': [
              {
                'entries': [
                  {
                    'id': LIFT,
                    'topW': 120,
                    'sets': [{'phase': 'warmup', 'done': true, 'w': 120}, {'phase': 'work', 'done': true, 'w': 80}],
                  },
                ],
              },
            ],
          }, LIFT),
          80);
      expect(
          bestWeightFor({
            'workouts': [
              {
                'entries': [
                  {'id': LIFT, 'topW': 120, 'sets': [{'phase': 'warmup', 'done': true, 'w': 120}]},
                ],
              },
            ],
          }, LIFT),
          0);
    });

    test('uses completed non-warm-up load for timed entries', () {
      expect(
          bestWeightForEntry({
            'target': {'mode': 'time'},
            'topW': 200,
            'sets': [
              {'phase': 'warmup', 'sec': 30, 'w': 30, 'done': true},
              {'phase': 'work', 'sec': 60, 'w': 20, 'done': true},
              {'phase': 'work', 'sec': 75, 'w': 25, 'done': true},
              {'phase': 'work', 'sec': 90, 'w': 40, 'done': false},
            ],
          }),
          25);
    });

    test('does not report a repeated weighted timed hold as a new load PR (blocker 3)', () {
      final prior = {
        'id': LIFT,
        'target': {'mode': 'time'},
        'sets': [{'phase': 'work', 'sec': 60, 'w': 20, 'done': true}],
      };
      final repeated = {
        'id': LIFT,
        'target': {'mode': 'time'},
        'sets': [{'phase': 'work', 'sec': 60, 'w': 20, 'done': true}],
      };
      final state = {
        'workouts': [
          {'entries': [prior]},
        ],
      };
      final repeatedWeight = maxOf([
        0,
        ...(repeated['sets'] as List).where((set) => set['done'] == true).map((set) => numOr(set['w'], 0)),
      ]);

      expect(bestWeightForEntry(prior), 20);
      expect(repeatedWeight > bestWeightFor(state, LIFT), isFalse);
    });
  });

  // ---- history.test.js lines 875–end ----

  String liftId() => jsFind(EXDB, (e) => e['bp'] != 'cardio' && e['eq'] != 'body weight')['id'] as String;
  String bwId() => jsFind(EXDB, (e) => e['eq'] == 'body weight')['id'] as String;

  List<dynamic> L(List<dynamic> xs) => <dynamic>[for (final x in xs) x is Map ? <String, dynamic>{...x} : x];

  group('superset editing', () {
    test('pairs adjacent entries without mutating the source and keeps the display units contiguous', () {
      final entries = L([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}]);
      final paired = pairAdjacent(entries, 1, 2, 'sg-new');
      expect(paired, jeq([{'id': 'a'}, {'id': 'b', 'sg': 'sg-new'}, {'id': 'c', 'sg': 'sg-new'}]));
      expect(entries, jeq([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}]));
      expect(supersetUnits(paired), jeq([[0], [1, 2]]));
    });

    test('merges both contiguous groups when their boundary entries are paired', () {
      final entries = L([
        {'id': 'a', 'sg': 'left'}, {'id': 'b', 'sg': 'left'},
        {'id': 'c', 'sg': 'right'}, {'id': 'd', 'sg': 'right'},
      ]);
      final merged = pairAdjacent(entries, 1, 2);
      expect(merged.map((e) => e['sg']).toList(), jeq(['left', 'left', 'left', 'left']));
      expect(entries.map((e) => e['sg']).toList(), jeq(['left', 'left', 'right', 'right']));
    });

    test('unpairs one entry and removes sg values left without an adjacent partner', () {
      final entries = L([
        {'id': 'a', 'sg': 'group'}, {'id': 'b', 'sg': 'group'}, {'id': 'c', 'sg': 'group'},
        {'id': 'd', 'sg': 'orphan'},
      ]);
      final unpaired = unpairSuperset(entries, 1);
      expect(unpaired, jeq([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}, {'id': 'd'}]));
      expect(entries.map((e) => e['sg']).toList(), jeq(['group', 'group', 'group', 'orphan']));
    });

    test('rejects a non-adjacent pairing request', () {
      final entries = L([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}]);
      expect(() => pairAdjacent(entries, 0, 2, 'sg-invalid'),
          throwsA(predicate((e) => e is RangeError && e.toString().contains('adjacent'))));
      expect(entries, jeq([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}]));
    });
  });

  group('sessionSections', () {
    test('splits by routine in the order each first appears and pairs supersets only inside a section', () {
      final entries = [
        {'id': 'a', 'rid': 'A', 'sg': 'x'}, {'id': 'b', 'rid': 'B', 'sg': 'x'}, {'id': 'c', 'rid': 'B', 'sg': 'y'},
        {'id': 'd', 'rid': 'B', 'sg': 'y'}, {'id': 'e', 'rid': 'A'},
      ];
      expect(sessionSections(entries), jeq([
        {'rid': 'A', 'items': [0, 4], 'units': [[0], [4]]},
        {'rid': 'B', 'items': [1, 2, 3], 'units': [[1], [2, 3]]},
      ]));
    });

    test('keeps a workout without routines as one section, the flat list', () {
      final entries = [{'id': 'a', 'sg': 'x'}, {'id': 'b', 'sg': 'x'}, {'id': 'c'}];
      expect(sessionSections(entries), jeq([{'rid': null, 'items': [0, 1, 2], 'units': supersetUnits(entries)}]));
      expect(sessionSections(null), jeq([]));
    });
  });

  // skipped: the second describe('superset editing') block (4 cases) — a verbatim duplicate of the
  // first one in the JS file; ported once above.

  group('session row helpers', () {
    test('cascadeWeight propagates to same-flag undone rows and never rewrites done sets', () {
      final rows = L([
        {'warmup': true, 'w': 20, 'done': true},
        {'warmup': true, 'w': 20, 'done': false},
        {'w': 60, 'done': true},
        {'w': 60, 'done': false},
        {'w': 60, 'done': false},
      ]);
      final next = cascadeWeight(rows, 2, 62.5);
      expect(next[2]['w'], 60);
      expect(next[3]['w'], 62.5);
      expect(next[4]['w'], 62.5);
      expect(next[1]['w'], 20);
    });

    test('cascadeWeight leaves the later warm-up rungs on their ramp loads', () {
      final S = {'unit': 'lb', 'exWeights': {}, 'workouts': []};
      final rows = buildSets(S, {'id': '0047', 'mode': 'reps', 'sets': 4, 'reps': 8, 'weight': 125, 'warmupSets': 3}, {'step': 5});
      expect(rows.map((r) => r['w']).toList(), jeq([60, 90, 105, 125, 125, 125, 125]));
      final next = cascadeWeight(rows, 0, 70);
      expect(next.map((r) => r['w']).toList(), jeq([60, 90, 105, 125, 125, 125, 125]));
      final later = cascadeWeight(rows, 1, 100);
      expect(later.map((r) => r['w']).toList(), jeq([60, 90, 105, 125, 125, 125, 125]));
      expect(cascadeWeight(rows, 3, 130).map((r) => r['w']).toList(), jeq([60, 90, 105, 125, 130, 130, 130]));
    });

    test('cascadeWeight leaves later one-side warm-up rungs alone too', () {
      final rows = <dynamic>[
        {...makeSideSet({'w': 10, 'r': 16}), 'phase': 'warmup'},
        {...makeSideSet({'w': 15, 'r': 16}), 'phase': 'warmup'},
        makeSideSet({'w': 25, 'r': 16}),
      ];
      final next = cascadeWeight(rows, 0, 5, 'L');
      expect(next[1]['sides']['L']['w'], 15);
      expect(next[1]['sides']['R']['w'], 15);
      expect(next[2]['sides']['L']['w'], 25);
    });

    test('cascadeWeight deleting the weight removes the key from following undone rows only', () {
      final rows = L([{'w': 60, 'done': true}, {'w': 60, 'done': false}, {'w': 60, 'done': false}]);
      final next = cascadeWeight(rows, 0, null);
      expect(next[0]['w'], 60);
      expect((next[1] as Map).containsKey('w'), isFalse);
      expect((next[2] as Map).containsKey('w'), isFalse);
    });

    test('cascadeWeight lowers inherited rows but keeps an explicitly edited heavier row and done rows', () {
      final rows = L([
        {'w': 100, 'done': false},
        {'w': 100, 'done': false},
        {'w': 120, 'weightOrigin': WEIGHT_ORIGIN_MANUAL, 'done': false},
        {'w': 100, 'done': true},
        {'w': 100, 'done': false},
      ]);
      final next = cascadeWeight(rows, 0, 80);
      expect(next[1]['w'], 80);
      expect(next[2]['w'], 120);
      expect(next[3]['w'], 100);
      expect(next[4]['w'], 80);
    });

    test('cascadeWeight cascades one per-side lane, preserving manual and completed limbs', () {
      final inherited = makeSideSet({'w': 20, 'r': 16});
      final manualRight = setSideField(makeSideSet({'w': 20, 'r': 16}), 'R', 'w', 25);
      manualRight['sides']['R']['weightOrigin'] = WEIGHT_ORIGIN_MANUAL;
      final partial = toggleSide(makeSideSet({'w': 20, 'r': 16}), 'L');
      final rows = <dynamic>[makeSideSet({'w': 20, 'r': 16}), inherited, manualRight, partial];
      final next = cascadeWeight(rows, 0, 15, 'L');
      expect(next[1]['sides']['L']['w'], 15);
      expect(next[1]['sides']['R']['w'], 20);
      expect(next[2]['sides']['L']['w'], 15);
      expect(next[2]['sides']['R']['w'], 25);
      expect(next[3]['sides']['L']['w'], 20);
      expect(next[3]['sides']['R']['w'], 20);
    });

    test('insertWarmupRow inserts before the first work row, ramping toward the work weight', () {
      final rows = L([
        {'warmup': true, 'w': 20, 'r': 8, 'done': true},
        {'warmup': true, 'w': 30, 'r': 8, 'done': false},
        {'w': 60, 'r': 8, 'done': false},
      ]);
      final next = insertWarmupRow(rows, 'reps', {'reps': 8}, 2.5);
      expect(next.length, 4);
      expect(next[2]['warmup'], true);
      expect(next[2]['w'], 45);
      expect(next[3]['w'], 60);
    });

    test('gives the first warm-up half the working weight, not the working weight itself', () {
      final next = insertWarmupRow(L([{'w': 100, 'r': 5, 'done': false}]), 'reps', {'reps': 5}, 2.5);
      expect(next.length, 2);
      expect(next[0], matchObj({'w': 50, 'r': 5, 'phase': 'warmup', 'warmup': true, 'done': false}));
      expect(next[1]['w'], 100);
    });

    test('rounds the ramp to the exercise loading step', () {
      expect(insertWarmupRow(L([{'w': 95, 'r': 5}]), 'reps', {'reps': 5}, 5)[0]['w'], 45);
    });

    test('keeps bodyweight warm-ups at zero and never exceeds the work set', () {
      expect(insertWarmupRow(L([{'w': 0, 'r': 12}]), 'reps', {'reps': 12}, 2.5)[0]['w'], 0);
      final at100 = insertWarmupRow(L([{'warmup': true, 'w': 100, 'r': 5}, {'w': 100, 'r': 5}]), 'reps', {'reps': 5}, 2.5);
      expect(at100[1]['w'], 100);
    });

    test('ramps a timed hold the same way and leaves cardio on the work row values', () {
      expect(insertWarmupRow(L([{'sec': 45, 'w': 40, 'done': false}]), 'time', {'sec': 45}, 2.5)[0],
          matchObj({'sec': 45, 'w': 20, 'phase': 'warmup'}));
      expect(insertWarmupRow(L([{'min': 20, 'speed': 10, 'done': false}]), 'cardio', {'min': 20}, 2.5)[0],
          matchObj({'min': 20, 'speed': 10, 'phase': 'warmup'}));
    });

    test('removeRowAt never empties an entry below one row', () {
      expect(removeRowAt(L([{'w': 60}]), 0).length, 1);
      final rows = L([{'w': 60}, {'w': 70}]);
      final next = removeRowAt(rows, 0);
      expect(next.length, 1);
      expect(next[0]['w'], 70);
    });
  });

  group('warm-up rows identified by phase alone', () {
    final imported = {'w': 40, 'r': 10, 'done': true, 'phase': 'warmup'};
    final work = {'w': 100, 'r': 5, 'done': true};

    test('workSetsDone does not count a phase-only warm-up', () {
      expect(workSetsDone({'entries': [{'sets': [imported, work]}]}), 1);
    });

    test('cascadeWeight treats a phase-only warm-up as a warm-up: the edit stays on its row', () {
      final rows = L([
        {'w': 40, 'r': 10, 'phase': 'warmup'},
        {'w': 45, 'r': 10, 'phase': 'warmup'},
        {'w': 100, 'r': 5},
      ]);
      final next = cascadeWeight(rows, 0, 50);
      expect(next[1]['w'], 45);
      expect(next[2]['w'], 100);
    });
  });

  // Shared by both JS describe('nextTrainingDay') blocks (lines 1134 and 1239).
  const TUE = '2026-08-18';
  Map<String, dynamic> base([Map<String, dynamic> over = const {}]) => {
        'dayPlan': {},
        'routines': [
          {'id': 'r1', 'name': 'A', 'ex': [{'id': '0001'}]},
          {'id': 'r2', 'name': 'B', 'ex': [{'id': '0002'}]},
        ],
        'week': {},
        ...over,
      };

  void nextTrainingDayCases() {
    test('finds the next scheduled day and names its routine', () {
      final S = base({'week': {'4': 'r2'}});
      expect(nextTrainingDay(S, TUE), matchObj({'iso': '2026-08-20', 'weekday': 4}));
      expect(nextTrainingDay(S, TUE)!['routine']['name'], 'B');
    });

    test('looks forward only — today itself is never the answer', () {
      final S = base({'week': {'2': 'r1'}});
      expect(nextTrainingDay(S, TUE), matchObj({'iso': '2026-08-25', 'weekday': 2}));
    });

    test('wraps around the end of the week', () {
      final S = base({'week': {'1': 'r1'}});
      expect(nextTrainingDay(S, TUE), matchObj({'iso': '2026-08-24', 'weekday': 1}));
    });

    test('is null when every day is rest', () {
      expect(nextTrainingDay(base(), TUE), isNull);
    });

    test('skips a day whose routine no longer exists', () {
      final S = base({'week': {'3': 'gone', '5': 'r1'}});
      expect(nextTrainingDay(S, TUE), matchObj({'iso': '2026-08-21', 'weekday': 5}));
    });

    test('skips a routine with no exercises — starting it would open an empty session', () {
      final S = base({
        'routines': [{'id': 'r1', 'name': 'A', 'ex': []}, {'id': 'r2', 'name': 'B', 'ex': [{'id': '1'}]}],
        'week': {'3': 'r1', '5': 'r2'},
      });
      expect(nextTrainingDay(S, TUE), matchObj({'weekday': 5}));
    });

    test('respects a per-date override in both directions', () {
      final moved = base({'week': {}, 'dayPlan': {'2026-08-19': 'r1'}});
      expect(nextTrainingDay(moved, TUE), matchObj({'iso': '2026-08-19'}));
      final off = base({'week': {'3': 'r1', '5': 'r2'}, 'dayPlan': {'2026-08-19': 'rest'}});
      expect(nextTrainingDay(off, TUE), matchObj({'weekday': 5}));
    });
  }

  group('nextTrainingDay', () {
    nextTrainingDayCases();

    test('finds a coach week waiting on its start day (lib/queue.js)', () {
      final today = todayISO();
      final t0 = isoNoon(today)!;
      final startsOn = isoOf(DateTime(t0.year, t0.month, t0.day + 3, 12));
      final S = base({
        'workouts': [],
        'queue': {'ids': ['r2'], 'since': DateTime.now().millisecondsSinceEpoch, 'startsOn': startsOn, 'label': 'W2'},
      });
      expect(nextTrainingDay(S, today), matchObj({'iso': startsOn}));
      expect(nextTrainingDay(S, today)!['routine']['name'], 'B');
    });
  });

  group('pinnedNoteFor', () {
    final S = {
      'workouts': [
        {'d': '2026-08-01', 'entries': [{'id': '0025', 'note': 'felt heavy', 'notePin': true}]},
        {'d': '2026-08-08', 'entries': [{'id': '0025', 'note': 'just a diary line'}]},
        {'d': '2026-08-15', 'entries': [{'id': '0025', 'note': 'go narrower', 'notePin': true}]},
        {'d': '2026-08-22', 'entries': [{'id': '0293', 'note': 'other exercise', 'notePin': true}]},
      ],
    };

    test('returns only the newest pinned note for that exercise', () {
      expect(pinnedNoteFor(S, '0025'), jeq({'note': 'go narrower', 'd': '2026-08-15'}));
    });

    test('ignores notes that were not pinned', () {
      expect(pinnedNoteFor({'workouts': [{'d': '2026-08-08', 'entries': [{'id': '0025', 'note': 'diary'}]}]}, '0025'), isNull);
    });

    test('skips the workout being edited, whose note the editor already shows', () {
      final ws = [
        {'id': 'w1', 'd': '2026-08-01', 'entries': [{'id': '0025', 'note': 'older pin', 'notePin': true}]},
        {'id': 'w2', 'd': '2026-08-15', 'entries': [{'id': '0025', 'note': 'its own pin', 'notePin': true}]},
      ];
      expect(pinnedNoteFor({'workouts': ws, 'active': {'editingWorkoutId': 'w2'}}, '0025'), jeq({'note': 'older pin', 'd': '2026-08-01'}));
      expect(pinnedNoteFor({'workouts': ws, 'active': {'editingWorkoutId': 'w1'}}, '0025'), jeq({'note': 'its own pin', 'd': '2026-08-15'}));
      final legacy = [
        {'d': '2026-08-15', 'start': 1000, 'entries': [{'id': '0025', 'note': 'its own pin', 'notePin': true}]},
      ];
      expect(pinnedNoteFor({'workouts': legacy, 'active': {'editingWorkoutId': '2026-08-15|1000'}}, '0025'), isNull);
    });

    test('is null for an exercise with no notes, and safe on empty state', () {
      expect(pinnedNoteFor(S, '9999'), isNull);
      expect(pinnedNoteFor({}, '0025'), isNull);
    });
  });

  group('exNoteFor', () {
    test('reads the standing note and trims it away when blank', () {
      expect(exNoteFor({'exNotes': {'0025': ' seat 4, pin 7 '}}, '0025'), 'seat 4, pin 7');
      expect(exNoteFor({'exNotes': {'0025': '   '}}, '0025'), isNull);
      expect(exNoteFor({}, '0025'), isNull);
    });
  });

  // The JS file repeats describe('nextTrainingDay') (7 cases, minus the queue case) verbatim.
  group('nextTrainingDay (repeat block)', nextTrainingDayCases);

  group('setLabel — per side', () {
    test('shows both sides so an asymmetry is visible, not a single combined total', () {
      final s = setSideField(setSideField(makeSideSet({'w': 15, 'r': 16}), 'R', 'r', 7), 'L', 'r', 8);
      expect(setLabel(liftId(), s, {'id': liftId(), 'side': true}), 'L 15×8 · R 15×7');
    });

    test('keeps each side effort tail and reads bodyweight sides as reps alone', () {
      var s = makeSideSet({'w': 0, 'r': 16});
      s = setSideField(s, 'L', 'rir', 1);
      expect(setLabel(bwId(), s, {'id': bwId(), 'side': true}), 'L 8 (RIR 1) · R 8');
    });
  });

  group('per-side aggregate stays readable by existing consumers', () {
    test('workoutVolume counts both sides via the row total, unchanged from a straight set', () {
      final synced = toggleSide(toggleSide(makeSideSet({'w': 15, 'r': 16}), 'L'), 'R');
      final w = {'entries': [{'id': liftId(), 'sets': [synced]}]};
      expect(synced['done'], true);
      expect(workoutVolume(w), 240);
      expect(workoutVolume({'entries': [{'id': liftId(), 'sets': [{'w': 15, 'r': 16, 'done': true}]}]}), 240);
    });

    test('bestWeightForEntry reads the aggregate weight of a completed per-side set', () {
      final s = toggleSide(toggleSide(setSideField(makeSideSet({'w': 15, 'r': 16}), 'R', 'w', 17.5), 'L'), 'R');
      expect(bestWeightForEntry({'id': liftId(), 'target': {'id': liftId(), 'side': true}, 'sets': [s]}), 17.5);
    });

    test('uses only completed side loads and reps when the other limb is unfinished', () {
      final partial = {
        'id': liftId(),
        'target': {'id': liftId(), 'mode': 'reps', 'side': true},
        'sets': [
          {
            'phase': 'work', 'w': 200, 'r': 10, 'done': false,
            'sides': {'L': {'w': 100, 'r': 5, 'done': true}, 'R': {'w': 200, 'r': 5, 'done': false}},
          },
        ],
      };
      expect(bestWeightForEntry(partial), 100);
      expect(completedRepsOf(metricRowsForEntry(partial, 'reps')[0]), 5);
    });
  });

  group('per-side set counters', () {
    test('setUnits counts a per-side row as two, a straight row as one', () {
      expect(setUnits(makeSideSet({'w': 15, 'r': 16})), 2);
      expect(setUnits({'w': 15, 'r': 16}), 1);
    });

    test('doneUnits counts each finished side independently', () {
      final none = makeSideSet({'w': 15, 'r': 16});
      expect(doneUnits(none), 0);
      expect(doneUnits(toggleSide(none, 'L')), 1);
      expect(doneUnits(toggleSide(toggleSide(none, 'L'), 'R')), 2);
      expect(doneUnits({'w': 15, 'r': 16, 'done': true}), 1);
    });

    test('setUnitsTotal / setsDoneActive account for both sides across the session', () {
      final A = {
        'entries': [
          {'id': liftId(), 'sets': [toggleSide(makeSideSet({'w': 15, 'r': 16}), 'L'), makeSideSet({'w': 15, 'r': 16})]},
          {'id': liftId(), 'sets': [{'w': 60, 'r': 8, 'done': true}]},
        ],
      };
      expect(setUnitsTotal(A['entries']), 5);
      expect(setsDoneActive(A), 2);
      expect(setsDone({'entries': A['entries']}), 2);
    });
  });

  group('effectiveRoutineIds / effectiveRoutines', () {
    final routines = [{'id': 'r1', 'name': 'A', 'ex': [{'id': '1'}]}, {'id': 'r2', 'name': 'B', 'ex': [{'id': '2'}]}];
    Map<String, dynamic> S(Map<String, dynamic> week, [Map<String, dynamic> dayPlan = const {}]) =>
        {'routines': routines, 'week': week, 'dayPlan': dayPlan};
    const ISO = '2026-08-19';

    test('reads a bare-string weekday value as a one-element list (tolerant reader)', () {
      expect(effectiveRoutineIds(S({'3': 'r1'}), ISO), jeq(['r1']));
    });
    test('resolves a multi-id array and filters out routines that no longer exist', () {
      expect(effectiveRoutineIds(S({'3': ['r1', 'gone', 'r2']}), ISO), jeq(['r1', 'r2']));
      expect(effectiveRoutines(S({'3': ['r1', 'r2']}), ISO).map((r) => r['name']).toList(), jeq(['A', 'B']));
    });
    test('treats [], a stray empty array and an absent key all as rest', () {
      expect(effectiveRoutineIds(S({'3': []}), ISO), jeq([]));
      expect(effectiveRoutineIds(S({}), ISO), jeq([]));
    });
    test('a scalar dayPlan override wins and stays scalar; "rest" is empty', () {
      expect(effectiveRoutineIds(S({'3': ['r1', 'r2']}, {ISO: 'r2'}), ISO), jeq(['r2']));
      expect(effectiveRoutineIds(S({'3': ['r1', 'r2']}, {ISO: 'rest'}), ISO), jeq([]));
    });
    test('the singular wrappers return [0] ?? null', () {
      expect(effectiveRoutineId(S({'3': ['r1', 'r2']}), ISO), 'r1');
      expect(effectiveRoutine(S({'3': ['r1', 'r2']}), ISO)['name'], 'A');
      expect(effectiveRoutineId(S({}), ISO), isNull);
      expect(effectiveRoutine(S({}), ISO), isNull);
    });
  });

  group('effectiveRoutineIds — coach queue', () {
    final routines = [
      {'id': 'd1', 'name': 'US W1 D1', 'ex': [{'id': '1'}]},
      {'id': 'd2', 'name': 'US W1 D2', 'ex': [{'id': '1'}]},
      {'id': 'own', 'name': 'Core', 'ex': [{'id': '2'}]},
    ];
    const TODAY = '2026-09-09';
    final SINCE = parseLocal('2026-09-07T08:00:00');
    Map<String, dynamic> q0() => {'ids': ['d1', 'd2'], 'since': SINCE, 'startsOn': '2026-09-07', 'label': 'US W1'};
    Map<String, dynamic> S([Map<String, dynamic> over = const {}]) =>
        {'routines': routines, 'week': {}, 'dayPlan': {}, 'workouts': [], 'queue': q0(), ...over};
    Map<String, dynamic> done(String id) => {
          'id': 'w$id', 'd': '2026-09-08', 'start': SINCE + 3600000, 'routineIds': [id], 'routineId': id,
          'name': jsFind(routines, (r) => r['id'] == id)['name'],
        };

    test('today gets the first undone session; other days get nothing from the queue', () {
      expect(effectiveRoutineIds(S(), TODAY, TODAY), jeq(['d1']));
      expect(effectiveRoutineIds(S(), '2026-09-10', TODAY), jeq([]));
      expect(effectiveRoutineIds(S({'workouts': [done('d1')]}), TODAY, TODAY), jeq(['d2']));
    });

    test('before startsOn the session sits on that day, not on today', () {
      final s = S({'queue': {...q0(), 'startsOn': '2026-09-14'}});
      expect(effectiveRoutineIds(s, TODAY, TODAY), jeq([]));
      expect(effectiveRoutineIds(s, '2026-09-14', TODAY), jeq(['d1']));
    });

    test('a complete week hands the day back to the weekday plan', () {
      final s = S({'workouts': [done('d1'), done('d2')], 'week': {'3': ['own']}});
      expect(effectiveRoutineIds(s, TODAY, TODAY), jeq(['own']));
      expect(effectiveRoutineIds(S({'workouts': [done('d1'), done('d2')]}), TODAY, TODAY), jeq([]));
    });

    test('a per-date override still wins over the queue', () {
      expect(effectiveRoutineIds(S({'dayPlan': {TODAY: 'rest'}}), TODAY, TODAY), jeq([]));
      expect(effectiveRoutineIds(S({'dayPlan': {TODAY: 'own'}}), TODAY, TODAY), jeq(['own']));
    });

    test('own routines on the weekday ride along behind the session', () {
      expect(effectiveRoutineIds(S({'week': {'3': ['own']}}), TODAY, TODAY), jeq(['d1', 'own']));
    });

    test('legacy coach weekday pointers are hidden behind the queue', () {
      expect(effectiveRoutineIds(S({'week': {'3': ['d2', 'own']}}), TODAY, TODAY), jeq(['d1', 'own']));
      expect(effectiveRoutineIds(S({'week': {'3': 'd1'}}), TODAY, TODAY), jeq(['d1']));
    });

    test('without a queue the weekday plan answers as before', () {
      expect(effectiveRoutineIds(S({'queue': null, 'week': {'3': ['own']}}), TODAY, TODAY), jeq(['own']));
    });

    test("a session pinned to a later day is that day's, with the weekday's own routine riding along; today floats past it", () {
      final s = S({'dayPlan': {'2026-09-11': 'd1'}, 'week': {'5': ['own']}});
      expect(effectiveRoutineIds(s, '2026-09-11', TODAY), jeq(['d1', 'own']));
      expect(effectiveRoutineIds(s, TODAY, TODAY), jeq(['d2']));
      expect(effectiveRoutineIds(S({'dayPlan': {TODAY: 'd2'}}), TODAY, TODAY), jeq(['d2']));
    });

    test('a fulfilled pin reads as no override: the day goes back to the floating rule or the weekday', () {
      final s = S({'dayPlan': {'2026-09-11': 'd1'}, 'workouts': [done('d1')], 'week': {'5': ['own']}});
      expect(effectiveRoutineIds(s, '2026-09-11', TODAY), jeq(['own']));
      expect(effectiveRoutineIds(s, TODAY, TODAY), jeq(['d2']));
      expect(effectiveRoutineIds(S({'dayPlan': {TODAY: 'd1'}, 'workouts': [done('d1')]}), TODAY, TODAY), jeq(['d2']));
    });

    test('with every remaining session pinned to other days, today shows only your own routines — a coach pointer on the weekday stays hidden', () {
      final s = S({'dayPlan': {'2026-09-11': 'd1', '2026-09-12': 'd2'}, 'week': {'3': ['d2', 'own']}});
      expect(effectiveRoutineIds(s, TODAY, TODAY), jeq(['own']));
      expect(effectiveRoutineIds(S({'dayPlan': {'2026-09-11': 'd1', '2026-09-12': 'd2'}, 'week': {'3': 'd1'}}), TODAY, TODAY), jeq([]));
    });

    test("a plain routine override is still single-pick, and 'rest' still wins over a pin", () {
      expect(effectiveRoutineIds(S({'dayPlan': {TODAY: 'own'}, 'week': {'3': ['own']}}), TODAY, TODAY), jeq(['own']));
      expect(effectiveRoutineIds(S({'dayPlan': {TODAY: 'rest', '2026-09-11': 'd1'}}), TODAY, TODAY), jeq([]));
    });
  });

  group('nextTrainingDay on a combined day', () {
    test('is trainable when any one routine of the day has exercises; return shape carries routines', () {
      final S = {
        'routines': [{'id': 'r1', 'name': 'A', 'ex': []}, {'id': 'r2', 'name': 'B', 'ex': [{'id': '1'}]}],
        'week': {'3': ['r1', 'r2']},
        'dayPlan': {},
      };
      final nd = nextTrainingDay(S, TUE)!;
      expect(nd, matchObj({'weekday': 3}));
      expect((nd['routines'] as List).map((r) => r['name']).toList(), jeq(['A', 'B']));
      expect(nd['routine']['name'], 'A');
    });
    test('skips a day whose every routine is empty', () {
      final S = {
        'routines': [
          {'id': 'r1', 'name': 'A', 'ex': []},
          {'id': 'r2', 'name': 'B', 'ex': []},
          {'id': 'r3', 'name': 'C', 'ex': [{'id': '1'}]},
        ],
        'week': {'3': ['r1', 'r2'], '5': ['r3']},
        'dayPlan': {},
      };
      expect(nextTrainingDay(S, TUE), matchObj({'weekday': 5}));
    });
  });

  group('lastEntryFor / buildSets skip a noProg entry', () {
    Map<String, dynamic> wk(String d, num w, num r, [Map<String, dynamic> extra = const {}]) => {
          'd': d,
          'entries': [
            {'id': liftId(), 'target': {'sets': 1, 'reps': r, 'weight': w}, 'sets': [{'w': w, 'r': r, 'done': true}], ...extra},
          ],
        };

    test('lastEntryFor returns the prior counting session, not a later noProg one', () {
      final S = {'workouts': [wk('2026-01-01', 60, 8), wk('2026-01-05', 30, 12, {'noProg': true})]};
      expect(lastEntryFor(S, liftId())!['d'], '2026-01-01');
    });
    test('lastEntryFor skips a legacy whole-workout excludeFromProgression session', () {
      final S = {
        'workouts': [
          wk('2026-01-01', 60, 8),
          {
            'd': '2026-01-05', 'excludeFromProgression': true,
            'entries': [{'id': liftId(), 'target': {'sets': 1, 'reps': 12, 'weight': 30}, 'sets': [{'w': 30, 'r': 12, 'done': true}]}],
          },
        ],
      };
      expect(lastEntryFor(S, liftId())!['d'], '2026-01-01');
    });
    test('buildSets seeds opening rows from the last counting session', () {
      final S = {'exWeights': {}, 'workouts': [wk('2026-01-01', 60, 8), wk('2026-01-05', 30, 12, {'noProg': true})]};
      expect(buildSets(S, {'id': liftId(), 'sets': 1, 'reps': 5, 'weight': 50}), jeq([{'w': 60, 'r': 8, 'done': false}]));
    });
    test('buildSets with only noProg history falls back to the routine target', () {
      final S = {'exWeights': {}, 'workouts': [wk('2026-01-05', 30, 12, {'noProg': true})]};
      expect(buildSets(S, {'id': liftId(), 'sets': 1, 'reps': 5, 'weight': 50}), jeq([{'w': 50, 'r': 5, 'done': false}]));
    });
    test('freestyleConfig ignores a noProg entry', () {
      final S = {'exWeights': {}, 'workouts': [wk('2026-01-05', 30, 12, {'noProg': true})]};
      expect(freestyleConfig(S, {'id': liftId(), 'mode': 'reps', 'sets': 3, 'reps': 10, 'weight': 0}),
          jeq({'id': liftId(), 'mode': 'reps', 'sets': 3, 'reps': 10, 'weight': 0}));
    });
    test('bestWeightFor is unchanged — a heavy noProg set still counts toward Best', () {
      final S = {'workouts': [wk('2026-01-01', 60, 8), wk('2026-01-05', 140, 3, {'noProg': true})]};
      expect(bestWeightFor(S, liftId()), 140);
    });
  });

  group("routine slots: lastEntryFor / buildSets read the routine's own history (#216)", () {
    Map<String, dynamic> session(String d, String? rid, num w, num r) => {
          'id': liftId(),
          'rid': ?rid,
          'target': {'sets': 2, 'reps': r, 'weight': w},
          'sets': [{'w': w, 'r': r, 'done': true}, {'w': w, 'r': r, 'done': true}],
        };
    Map<String, dynamic> S() => {
          'exWeights': {liftId(): {'w': 60}},
          'workouts': [
            {'d': '2026-01-01', 'routineIds': ['A'], 'entries': [session('2026-01-01', 'A', 60, 10)]},
            {'d': '2026-01-03', 'routineIds': ['B'], 'entries': [session('2026-01-03', 'B', 40, 15)]},
          ],
        };

    test("takes the routine's own last session, not the latest one of the exercise", () {
      expect(lastEntryFor(S(), liftId(), 'A'), matchObj({'d': '2026-01-01', 'rid': 'A'}));
      expect(lastEntryFor(S(), liftId(), 'B'), matchObj({'d': '2026-01-03', 'rid': 'B'}));
      expect(lastEntryFor(S(), liftId())!['d'], '2026-01-03');
    });

    test("falls back to the exercise's last session for a routine that never trained it", () {
      expect(lastEntryFor(S(), liftId(), 'C'), matchObj({'d': '2026-01-03', 'rid': 'B'}));
    });

    test('reads a combined day by the entry that belongs to the routine, not the first one', () {
      final combined = {
        'exWeights': {},
        'workouts': [
          {'d': '2026-01-05', 'routineIds': ['A', 'B'], 'entries': [session('', 'A', 60, 10), session('', 'B', 40, 15)]},
        ],
      };
      expect((lastEntryFor(combined, liftId(), 'B')!['sets'] as List).map((s) => [s['w'], s['r']]).toList(), jeq([[40, 15], [40, 15]]));
      expect((lastEntryFor(combined, liftId(), 'A')!['sets'] as List).map((s) => [s['w'], s['r']]).toList(), jeq([[60, 10], [60, 10]]));
    });

    test("opens each routine's rows from its own line", () {
      final cfg = {'id': liftId(), 'sets': 2, 'reps': 10, 'weight': 0};
      expect(buildSets(S(), cfg, {'rid': 'A'}).map((s) => s['w']).toList(), jeq([60, 60]));
      expect(buildSets(S(), cfg, {'rid': 'B'}).map((s) => s['w']).toList(), jeq([40, 40]));
    });

    test("gives a session saved before per-entry routine ids to the workout's routine", () {
      final legacy = {'d': '2026-01-01', 'routineId': 'A', 'entries': [session('', null, 60, 10)]};
      expect(entryRoutineId(legacy, (legacy['entries'] as List)[0]), 'A');
      expect(entryRoutineId({'routineIds': ['B'], 'entries': []}, {'id': liftId()}), 'B');
      expect(lastEntryFor({'workouts': [legacy]}, liftId(), 'A'), matchObj({'rid': 'A'}));
    });

    test('leaves an exercise added to a freestyle session without a routine', () {
      final w = {'routineIds': ['A'], 'entries': [{'id': liftId()}, {'id': 'x', 'rid': 'A'}]};
      expect(entryRoutineId(w, (w['entries'] as List)[0]), isNull);
      expect(entryRoutineId({'routineIds': [], 'entries': [{'id': liftId()}]}, {'id': liftId()}), isNull);
    });
  });

  group('per-side volume and legacy timed sets (QA round 2026-09-12)', () {
    test('sums each side of a unilateral set on its own instead of max weight × total reps', () {
      final w = {
        'entries': [
          {
            'id': 'x',
            'sets': [
              {'done': true, 'sides': {'L': {'w': 14, 'r': 10, 'done': true}, 'R': {'w': 12.5, 'r': 6, 'done': true}}, 'w': 14, 'r': 16},
              {'done': true, 'w': 100, 'r': 10},
            ],
          },
        ],
      };
      expect(workoutVolume(w), 14 * 10 + 12.5 * 6 + 1000);
    });
    test('reads a timed or cardio set saved without a target from the set itself', () {
      expect(setLabel('0001', {'sec': 45, 'done': true}), '0:45');
      expect(setLabel('0001', {'min': 20, 'speed': 8, 'done': true}), '20 min @ 8 km/h');
      expect(setLabel('0025', {'w': 60, 'r': 10, 'done': true}), '60×10');
    });
  });

  group('a rotation day and a fixed weekday day are one combined day', () {
    final routines = [{'id': 'a', 'name': 'A', 'ex': []}, {'id': 'core', 'name': 'Core', 'ex': []}];
    const TODAY = '2026-09-14';
    Map<String, dynamic> S([Map<String, dynamic> over = const {}]) => {
          'routines': routines, 'workouts': [], 'dayPlan': {}, 'week': {'1': ['core']},
          'queue': {'ids': ['a'], 'since': parseLocal('2026-09-13T08:00:00'), 'startsOn': '2026-09-13', 'label': 'My split', 'rotationId': 'r1'},
          'rotation': {'id': 'r1', 'sequence': ['a'], 'label': 'My split'},
          ...over,
        };

    test('the queue session comes first, the weekday routine rides along', () {
      expect(effectiveRoutineIds(S(), TODAY, TODAY), jeq(['a', 'core']));
    });

    test('a malformed queue falls back to the plain weekday plan', () {
      expect(effectiveRoutineIds(S({'queue': {'ids': ['gone'], 'since': 1}}), TODAY, TODAY), jeq(['core']));
    });

    test('a repeated queue id does not repeat the day', () {
      final dup = S({'queue': {'ids': ['a', 'a'], 'since': parseLocal('2026-09-13T08:00:00'), 'startsOn': '2026-09-13', 'label': 'My split'}});
      expect(effectiveRoutineIds(dup, TODAY, TODAY), jeq(['a', 'core']));
    });
  });

  group('switching a row between warm-up and work', () {
    test('makeWarmupAt gives the warm-up shape, keeps the numbers and the tick, and moves it in front of the work', () {
      final rows = L([
        {'w': 40, 'r': 8, 'phase': 'warmup', 'warmup': true, 'done': true},
        {'w': 100, 'r': 5, 'done': true, 'at': 7},
        {'w': 100, 'r': 5, 'done': false, 'type': 'dropset', 'drops': [{'w': 80, 'r': 4}], 'rir': 2},
      ]);
      final plain = <dynamic>[...rows.sublist(0, 2), <String, dynamic>{'w': 100, 'r': 5, 'done': false, 'rir': 2}];
      final next = makeWarmupAt(plain, 2);
      expect(next, jeq([rows[0], {'w': 100, 'r': 5, 'done': false, 'phase': 'warmup', 'warmup': true}, rows[1]]));
      expect(makeWarmupAt(rows, 1)[1], jeq({'w': 100, 'r': 5, 'done': true, 'phase': 'warmup', 'warmup': true, 'at': 7}));
      expect(makeWarmupAt(rows, 0), same(rows));
    });

    test('makeWarmupAt leaves drop, rest-pause and per-side rows as they are', () {
      final drop = L([{'w': 60, 'r': 8, 'done': true}, {'w': 100, 'r': 5, 'done': true, 'type': 'dropset', 'drops': [{'w': 80, 'r': 4}]}]);
      expect(makeWarmupAt(drop, 1), same(drop));
      final rp = L([{'w': 60, 'r': 8, 'done': true}, {'w': 100, 'r': 12, 'done': true, 'type': 'restpause', 'clusters': [{'r': 4, 'rest': 15}]}]);
      expect(makeWarmupAt(rp, 1), same(rp));
      final side = L([
        {'w': 30, 'r': 6, 'done': true},
        {'w': 30, 'r': 11, 'done': false, 'sides': {'L': {'w': 30, 'r': 5, 'done': true}, 'R': {'w': 0, 'r': 6, 'done': false}}},
      ]);
      expect(makeWarmupAt(side, 1), same(side));
      expect([canBeWarmup(drop[1]), canBeWarmup(rp[1]), canBeWarmup(side[1]), canBeWarmup(drop[0])], [false, false, false, true]);
    });

    test('a warm-up made one is left out of the best weight and the work-set count', () {
      final e = {'id': 'x', 'sets': makeWarmupAt(L([{'w': 60, 'r': 5, 'done': true}, {'w': 120, 'r': 3, 'done': true}]), 1)};
      expect(bestWeightForEntry(e), 60);
      expect(workSetsDone({'entries': [e]}), 1);
    });

    test('makeWorkAt makes it the first work set', () {
      final rows = L([
        {'w': 40, 'r': 8, 'phase': 'warmup', 'warmup': true},
        {'w': 60, 'r': 8, 'phase': 'warmup', 'warmup': true, 'done': true},
        {'w': 100, 'r': 5},
      ]);
      expect(makeWorkAt(rows, 0), jeq([rows[1], {'w': 40, 'r': 8}, rows[2]]));
      expect(makeWorkAt(rows, 2), same(rows));
    });
  });

  group('timed per-side pairs come off as a pair', () {
    List<dynamic> pairs(int n) => <dynamic>[
          for (var k = 0; k < n; k++) ...[
            <String, dynamic>{'sec': 30, 'side': 'L', 'k': k},
            <String, dynamic>{'sec': 30, 'side': 'R', 'k': k},
          ],
        ];

    test('removeLastSet pops the last L/R pair, so a later add keeps the pairs in step', () {
      final next = removeLastSet(pairs(3));
      expect(next.map((r) => '${r['side']}${r['k']}').toList(), ['L0', 'R0', 'L1', 'R1']);
      expect(removeLastSet(pairs(1)), jeq(pairs(1)));
      expect(removeLastSet(L([{'w': 50, 'r': 5}, {'w': 50, 'r': 5}])), jeq([{'w': 50, 'r': 5}]));
    });

    test('removeRowAt takes a half out together with its partner', () {
      expect(removeRowAt(pairs(3), 2).map((r) => '${r['side']}${r['k']}').toList(), ['L0', 'R0', 'L2', 'R2']);
      expect(removeRowAt(pairs(3), 3).map((r) => '${r['side']}${r['k']}').toList(), ['L0', 'R0', 'L2', 'R2']);
      expect(setSpanAt(L([{'sec': 30, 'side': 'L'}, {'sec': 30}]), 0), [0, 1]);
    });
  });

  // The JS file repeats the 'superset editing' block verbatim further down; ported again here.
  group('superset editing', () {
    test('pairs adjacent entries without mutating the source and keeps the display units contiguous', () {
      final entries = L([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}]);
      final paired = pairAdjacent(entries, 1, 2, 'sg-new');
      expect(paired, jeq([{'id': 'a'}, {'id': 'b', 'sg': 'sg-new'}, {'id': 'c', 'sg': 'sg-new'}]));
      expect(entries, jeq([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}]));
      expect(supersetUnits(paired), jeq([[0], [1, 2]]));
    });

    test('merges both contiguous groups when their boundary entries are paired', () {
      final entries = L([
        {'id': 'a', 'sg': 'left'}, {'id': 'b', 'sg': 'left'},
        {'id': 'c', 'sg': 'right'}, {'id': 'd', 'sg': 'right'},
      ]);
      final merged = pairAdjacent(entries, 1, 2);
      expect(merged.map((e) => e['sg']).toList(), jeq(['left', 'left', 'left', 'left']));
      expect(entries.map((e) => e['sg']).toList(), jeq(['left', 'left', 'right', 'right']));
    });

    test('unpairs one entry and removes sg values left without an adjacent partner', () {
      final entries = L([
        {'id': 'a', 'sg': 'group'}, {'id': 'b', 'sg': 'group'}, {'id': 'c', 'sg': 'group'},
        {'id': 'd', 'sg': 'orphan'},
      ]);
      final unpaired = unpairSuperset(entries, 1);
      expect(unpaired, jeq([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}, {'id': 'd'}]));
      expect(entries.map((e) => e['sg']).toList(), jeq(['group', 'group', 'group', 'orphan']));
    });

    test('rejects a non-adjacent pairing request', () {
      final entries = L([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}]);
      expect(() => pairAdjacent(entries, 0, 2, 'sg-invalid'),
          throwsA(predicate((e) => e is RangeError && e.toString().contains('adjacent'))));
      expect(entries, jeq([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}]));
    });
  });
}
