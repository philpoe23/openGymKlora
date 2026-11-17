// Port of frontend/src/lib/plan-share.test.js, plus the plan-share cases of other JS test files
// whose Dart ports skipped them until this module existed (pyramid, dumbbells, failure-sets,
// progression.triple, exercise-alias-ids).
// ignore_for_file: constant_identifier_names, non_constant_identifier_names
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/plan_share.dart';
import 'package:klora_app/engine/pyramid.dart';
import 'package:klora_app/engine/units.dart';

import '_exdb.dart';
import '_helpers.dart';

JMap stateWith([JMap ex = const {}]) => <String, dynamic>{
      'routines': <dynamic>[
        {
          'id': 'r1',
          'name': 'Push',
          'ex': <dynamic>[
            {'id': '0025', 'sets': 3, 'reps': 5, 'weight': 100, ...ex},
          ],
        },
      ],
      'week': <String, dynamic>{},
      'customEx': <dynamic>[],
    };

JMap roundTrip([JMap ex = const {}]) =>
    asMap(parsePlan(jsonEncode(buildPlanBundle(stateWith(ex), 'Plan')))['routines'][0]['ex'][0]);

JMap emptyTarget([JMap extra = const {}]) =>
    <String, dynamic>{'routines': <dynamic>[], 'week': <String, dynamic>{}, 'customEx': <dynamic>[], ...extra};

dynamic firstEx(JMap parsed) => parsed['routines'][0]['ex'][0];

void main() {
  setUpAll(loadTestExerciseDb);

  group('plan-share units', () {
    test('exports a unit and converts every load prescription at the import boundary', () {
      final source = <String, dynamic>{
        'unit': 'kg', 'week': {}, 'customEx': [],
        'routines': [
          {'id': 'r', 'name': 'Strength', 'ex': [
            {'id': '0025', 'mode': 'reps', 'sets': 3, 'reps': 5, 'weight': 60, 'inc': 2.5},
            {'id': '0007', 'mode': 'time', 'sets': 1, 'sec': 30, 'weight': 20, 'inc': 5},
          ]},
        ],
      };
      final bundle = buildPlanBundle(source, 'Strength');
      expect(bundle['unit'], 'kg');
      final imported = parsePlan(bundle, 'lb');
      expect(imported['unit'], 'lb');
      expect(imported['routines'][0]['ex'][0], matchObj({'weight': 132.5, 'inc': 5.5}));
      expect(imported['routines'][0]['ex'][1], matchObj({'weight': 44, 'inc': 5}));
    });

    test('converts pounds back to kilograms and merges the converted prescription', () {
      final source = <String, dynamic>{
        'unit': 'lb', 'week': {}, 'customEx': [],
        'routines': [
          {'id': 'r', 'name': 'Strength', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 135, 'inc': 10}]},
        ],
      };
      final bundle = buildPlanBundle(source, 'Strength');
      final target = emptyTarget({'unit': 'kg'});
      mergePlan(target, bundle);
      expect(target['routines'][0]['ex'][0], matchObj({'weight': 61.25, 'inc': 4.5}));
    });

    test('keeps valid legacy bundles without a unit in their destination-unit semantics', () {
      final legacy = <String, dynamic>{
        'opengym_plan': 1, 'name': 'Legacy', 'summary': 'old export',
        'week': {'1': 'r'}, 'customEx': [],
        'routines': [
          {'id': 'r', 'name': 'Strength', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60, 'inc': 2.5}]},
        ],
      };
      final parsed = parsePlan(legacy, 'lb');
      expect(parsed['unit'], 'lb');
      expect(firstEx(parsed), matchObj({'weight': 60, 'inc': 2.5}));
    });

    test('accepts legacy root omissions and the older weightUnit marker', () {
      final legacy = <String, dynamic>{
        'opengym_plan': 1, 'weightUnit': 'lbs', 'legacyNote': 'kept as metadata',
        'routines': [
          {'id': 'r', 'name': 'Strength', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 135, 'inc': 10}]},
        ],
      };
      final parsed = parsePlan(legacy, 'kg');
      expect(firstEx(parsed), matchObj({'weight': 61.25, 'inc': 4.5}));
      expect(parsed['week'], jeq({}));
      expect(parsed['customEx'], jeq([]));
    });
  });

  group('what survives a shared plan', () {
    test('carries Per side on a timed hold, and on reps work; never on cardio', () {
      final hold = roundTrip({'mode': 'time', 'sec': 30, 'sets': 2, 'reps': null, 'weight': null, 'side': true});
      expect(hold, matchObj({'mode': 'time', 'sec': 30, 'sets': 2, 'side': true}));
      expect(roundTrip({'side': true})['side'], true);
      final cardio = firstEx(parsePlan(jsonEncode(buildPlanBundle({
        'routines': [
          {'id': 'r1', 'name': 'Run', 'ex': [{'id': '0025', 'sets': 1, 'mode': 'cardio', 'min': 20, 'side': true}]},
        ],
        'week': {}, 'customEx': [],
      }, 'Plan'))));
      expect(cardio['side'], isNull);
    });

    test('carries a drop-set prescription', () {
      expect(roundTrip({'intensifier': {'type': 'dropset', 'count': 2, 'pct': 20}})['intensifier'],
          jeq({'type': 'dropset', 'count': 2, 'pct': 20}));
    });

    test('carries a rest-pause prescription', () {
      expect(roundTrip({'intensifier': {'type': 'restpause', 'totalReps': 12, 'restSec': 15}})['intensifier'],
          jeq({'type': 'restpause', 'totalReps': 12, 'restSec': 15}));
    });

    test('carries planned warm-ups', () {
      expect(roundTrip({'warmupSets': 3})['warmupSets'], 3);
    });

    test('carries a non-default Epley deload factor and omits the default', () {
      expect(roundTrip({'deloadFactor': 0.8})['deloadFactor'], 0.8);
      expect(roundTrip({'deloadFactor': 0.9}).containsKey('deloadFactor'), isFalse);
    });

    test('carries progression exclusion on a routine through export and merge', () {
      final source = stateWith();
      source['routines'][0]['excludeFromProgression'] = true;
      final bundle = parsePlan(buildPlanBundle(source, 'Plan'));
      final target = emptyTarget();

      expect(bundle['routines'][0]['excludeFromProgression'], true);
      mergePlan(target, bundle);
      expect(target['routines'][0]['excludeFromProgression'], true);
    });

    test('carries a per-exercise rest', () {
      expect(roundTrip({'restSec': 180})['restSec'], 180);
    });

    test('carries a per-exercise warm-up rest, and leaves it out when unset', () {
      expect(roundTrip({'restSec': 150, 'warmupRestSec': 45})['warmupRestSec'], 45);
      expect(roundTrip().containsKey('warmupRestSec'), isFalse);
      expect(roundTrip({'warmupRestSec': 0}).containsKey('warmupRestSec'), isFalse);
    });

    test('leaves an exercise that set no rest free of the field', () {
      expect(roundTrip().containsKey('restSec'), isFalse);
      expect(roundTrip({'restSec': 0}).containsKey('restSec'), isFalse);
    });

    test('carries the rest onto the routine mergePlan adds', () {
      final bundle = parsePlan(jsonEncode(buildPlanBundle(stateWith({'restSec': 180}), 'Plan')));
      final s = emptyTarget();
      mergePlan(s, bundle, schedule: false);
      expect(s['routines'][0]['ex'][0]['restSec'], 180);
    });

    test('drops an intensifier it does not recognise rather than passing it on', () {
      expect(roundTrip({'intensifier': {'type': 'nonsense', 'count': 3}}).containsKey('intensifier'), isFalse);
    });

    test('clamps a hand-edited warm-up count instead of showing it verbatim', () {
      final bundle = {'opengym_plan': 1, 'name': 'x', 'routines': [{'id': 'r', 'name': 'R', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'warmupSets': 999}]}], 'week': {}, 'customEx': []};
      expect(firstEx(parsePlan(bundle))['warmupSets'], 5);
    });

    test('normalises a hand-edited rest to a positive whole number or drops it', () {
      JMap withRest(dynamic restSec) => {'opengym_plan': 1, 'name': 'x', 'routines': [{'id': 'r', 'name': 'R', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'restSec': restSec}]}], 'week': {}, 'customEx': []};
      expect(firstEx(parsePlan(withRest('120')))['restSec'], 120);
      expect(firstEx(parsePlan(withRest(90.6)))['restSec'], 91);
      expect((firstEx(parsePlan(withRest(-30))) as Map).containsKey('restSec'), isFalse);
      expect((firstEx(parsePlan(withRest('abc'))) as Map).containsKey('restSec'), isFalse);
    });

    test('clamps out-of-range intensifier numbers to the floors the app enforces', () {
      final bundle = {'opengym_plan': 1, 'name': 'x', 'routines': [{'id': 'r', 'name': 'R', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'intensifier': {'type': 'dropset', 'count': 0, 'pct': -5}}]}], 'week': {}, 'customEx': []};
      expect(firstEx(parsePlan(bundle))['intensifier'], jeq({'type': 'dropset', 'count': 1, 'pct': 5}));
    });

    test('falls back to the default drop percentage when the file omits it', () {
      final bundle = {'opengym_plan': 1, 'name': 'x', 'routines': [{'id': 'r', 'name': 'R', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'intensifier': {'type': 'dropset'}}]}], 'week': {}, 'customEx': []};
      expect(firstEx(parsePlan(bundle))['intensifier'], jeq({'type': 'dropset', 'count': 1, 'pct': 20}));
    });
  });

  group('week schedule as a routine-id list', () {
    final twoRoutines = <dynamic>[
      {'id': 'a', 'name': 'A', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5}]},
      {'id': 'b', 'name': 'B', 'ex': [{'id': '0031', 'sets': 3, 'reps': 8}]},
    ];

    test('build → parse → merge round-trips an array week with arrays intact', () {
      final src = {'routines': twoRoutines, 'customEx': [], 'week': {'1': ['a', 'b'], '3': ['a']}};
      final parsed = parsePlan(jsonEncode(buildPlanBundle(src, 'Plan')));
      expect(parsed['scheduledDays'], 2);

      final target = emptyTarget();
      mergePlan(target, parsed, schedule: true);
      final ids = (target['routines'] as List).map((r) => r['id']).toList();
      expect(target['week']['1'], jeq([ids[0], ids[1]]));
      expect(target['week']['3'], jeq([ids[0]]));
    });

    test('tolerates a legacy scalar bundle value', () {
      final legacy = {'opengym_plan': 1, 'name': 'x', 'customEx': [], 'week': {'1': 'a'}, 'routines': twoRoutines};
      final parsed = parsePlan(legacy);
      expect(parsed['scheduledDays'], 1);
      final target = emptyTarget();
      mergePlan(target, parsed, schedule: true);
      expect(target['week']['1'], jeq([target['routines'][0]['id']]));
    });

    test('mergePlan drops an element whose id did not survive parsing, never writes undefined', () {
      final bundle = {'routines': [{'id': 'a', 'name': 'A', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5}]}], 'week': {'1': ['a', 'gone'], '2': ['gone']}, 'customEx': []};
      final target = emptyTarget();
      mergePlan(target, bundle, schedule: true);
      expect(target['week']['1'], jeq([target['routines'][0]['id']]));
      expect((target['week'] as Map).containsKey('2'), isFalse); // emptied → left absent, not stored as []
    });

    test('scheduledDays counts a populated array day as 1 and a [] / absent day as 0', () {
      expect(parsePlan({'opengym_plan': 1, 'routines': [], 'customEx': [], 'week': {'1': ['a'], '2': [], '4': 'b'}})['scheduledDays'], 2);
    });
  });

  group('custom exercises in a shared plan', () {
    final landmine = <String, dynamic>{
      'id': 'c1', 'n': 'QA Landmine Row', 'bp': 'back', 'desc': 'Bar in the corner', 'tg': 'upper-back', 'sm': ['biceps'],
      'muscleGroups': ['upper-back', 'biceps'], 'primaries': ['upper-back'], 'secondaries': ['biceps'], 'eq': 'barbell', 'custom': true,
    };
    final source = <String, dynamic>{
      'routines': [{'id': 'r', 'name': 'Back day', 'ex': [{'id': 'c1', 'sets': 3, 'reps': 8, 'weight': 40}]}],
      'week': {}, 'customEx': [landmine],
    };

    test('exports equipment, muscles and description with the custom exercise', () {
      expect(buildPlanBundle(source, 'Plan')['customEx'][0], jeq({
        'id': 'c1', 'n': 'QA Landmine Row', 'bp': 'back', 'desc': 'Bar in the corner', 'eq': 'barbell', 'tg': 'upper-back',
        'primaries': ['upper-back'], 'secondaries': ['biceps'], 'muscleGroups': ['upper-back', 'biceps'],
      }));
    });

    test('stores the imported custom exercise the way the form would have created it', () {
      final parsed = parsePlan(jsonEncode(buildPlanBundle(source, 'Plan')));
      final target = emptyTarget();
      mergePlan(target, parsed);
      final stored = target['customEx'][0];
      expect(stored, matchObj({...landmine, 'id': stored['id']}));
      expect(stored['id'], isNot('c1'));
      expect(target['routines'][0]['ex'][0]['id'], stored['id']);
    });

    test('keeps importing an old name-plus-body-part file, editable at the other end', () {
      final legacy = {'opengym_plan': 1, 'routines': [{'id': 'r', 'name': 'R', 'ex': [{'id': 'x', 'sets': 3, 'reps': 5}]}], 'customEx': [{'id': 'x', 'n': 'Old one', 'bp': 'legs'}]};
      final target = emptyTarget();
      mergePlan(target, parsePlan(legacy));
      expect(target['customEx'][0], jeq({'id': target['customEx'][0]['id'], 'n': 'Old one', 'bp': 'legs', 'custom': true}));
      expect(target['routines'][0]['ex'][0]['id'], target['customEx'][0]['id']);
    });

    test('drops muscles it cannot draw and a secondary that repeats a primary', () {
      final bundle = {'opengym_plan': 1, 'routines': [], 'customEx': [{'id': 'x', 'n': 'Odd', 'bp': 'back', 'eq': 'barbell', 'primaries': ['upper-back', 'wings'], 'secondaries': ['upper-back', 'biceps', 7]}]};
      final target = emptyTarget();
      mergePlan(target, parsePlan(bundle));
      expect(target['customEx'][0], matchObj({'primaries': ['upper-back'], 'secondaries': ['biceps'], 'muscleGroups': ['upper-back', 'biceps'], 'tg': 'upper-back', 'sm': ['biceps']}));
    });

    test('still reuses a custom the recipient already has under the same name and body part', () {
      final parsed = parsePlan(jsonEncode(buildPlanBundle(source, 'Plan')));
      final mine = {'id': 'mine', 'n': 'qa landmine row', 'bp': 'back', 'eq': 'landmine', 'custom': true};
      final target = emptyTarget({'customEx': <dynamic>[mine]});
      mergePlan(target, parsed);
      expect(target['customEx'], jeq([mine]));
      expect(target['routines'][0]['ex'][0]['id'], 'mine');
    });
  });

  group('plan-share links and media (#246)', () {
    final photo = {'kind': 'image', 'hash': 'a' * 64, 'mime': 'image/webp', 'size': 10, 'width': 4, 'height': 3, 'at': 1};
    JMap withCustom(JMap c) => {
          'unit': 'kg', 'week': {},
          'routines': [{'id': 'r1', 'name': 'Push', 'ex': [{'id': 'cx1', 'sets': 3, 'reps': 5}]}],
          'customEx': [{'id': 'cx1', 'n': 'Landmine press', 'bp': 'shoulders', 'custom': true, ...c}],
        };

    test('a link travels with the plan and arrives on the new exercise; the photo never travels', () {
      final bundle = buildPlanBundle(withCustom({'url': 'https://youtu.be/abc', 'media': photo}), 'Plan');
      expect(bundle['customEx'][0]['url'], 'https://youtu.be/abc');
      expect(jsonEncode(bundle), isNot(contains('media')));
      expect(jsonEncode(bundle), isNot(contains('a' * 64)));
      final s = emptyTarget({'unit': 'kg', 'dayPlan': {}});
      mergePlan(s, parsePlan(jsonEncode(bundle)));
      expect(s['customEx'][0], matchObj({'n': 'Landmine press', 'url': 'https://youtu.be/abc', 'custom': true}));
      expect(s['customEx'][0]['media'], isNull);
    });

    test('a link that is not a web address is dropped on the way in, and never backfilled onto an exercise you have', () {
      final file = buildPlanBundle(withCustom({}), 'Plan');
      file['customEx'][0]['url'] = 'javascript:alert(document.cookie)';
      file['customEx'][0]['media'] = photo;
      final s = emptyTarget({'unit': 'kg', 'dayPlan': {}});
      mergePlan(s, parsePlan(jsonEncode(file)));
      expect(s['customEx'][0]['url'], isNull);
      expect(s['customEx'][0]['media'], isNull);

      final mine = emptyTarget({'unit': 'kg', 'dayPlan': {}, 'customEx': <dynamic>[{'id': 'mine', 'n': 'Landmine press', 'bp': 'shoulders', 'custom': true}]});
      mergePlan(mine, parsePlan(jsonEncode(buildPlanBundle(withCustom({'url': 'https://youtu.be/abc'}), 'Plan'))));
      expect(mine['customEx'], hasLength(1));
      expect(mine['customEx'][0]['url'], isNull);
    });
  });

  group('parsePlan refuses a file that is not a plan in words', () {
    test('text that is not JSON says it is not a plan file, not the parser message', () {
      expect(() => parsePlan('hello there'),
          throwsA(isA<PlanFormatException>().having((e) => e.message, 'message', 'this isn’t an openGym plan file')));
      expect(() => parsePlan('{oops'), throwsA(isA<PlanFormatException>().having((e) => e.code, 'code', 'not-plan')));
      // As text the error is its message alone, which is what a screen shows.
      try {
        parsePlan('{oops');
      } catch (e) {
        expect('$e', 'this isn’t an openGym plan file');
      }
    });
  });

  // ---- cases from other JS test files that exercise plan-share ----

  // pyramid.test.js
  const LIFT = '0025';
  const PYR = [12, 8, 6, PYRAMID_MAX, 12];
  JMap pyramidCfg([JMap extra = const {}]) => {'id': LIFT, 'mode': 'reps', 'sets': 5, 'reps': 12, 'weight': 0, 'pyramid': PYR, ...extra};
  JMap oneEx(JMap ex, [String name = 'Push', JMap extra = const {}]) =>
      {...extra, 'routines': [{'id': 'r1', 'name': name, 'ex': [ex]}], 'week': {}, 'customEx': []};

  group('a shared plan keeps the pyramid (pyramid.test.js)', () {
    test('survives export and import', () {
      final back = firstEx(parsePlan(jsonEncode(buildPlanBundle(oneEx(pyramidCfg()), 'Plan'))));
      expect(back['pyramid'], jeq(PYR));
    });
    test('a flat exercise gains no pyramid field', () {
      final back = firstEx(parsePlan(jsonEncode(buildPlanBundle(oneEx({'id': LIFT, 'sets': 3, 'reps': 10}), 'Plan'))));
      expect((back as Map).containsKey('pyramid'), isFalse);
    });
    test('rest per set travels with a shared plan', () {
      final back = firstEx(parsePlan(jsonEncode(buildPlanBundle(oneEx(pyramidCfg({'pyramidRest': [60, 90, 180, 120, 0]})), 'Plan'))));
      expect(back['pyramidRest'], jeq([60, 90, 180, 120, 0]));
    });
    test('weight per set travels with a shared plan and converts between kg and lb', () {
      final bundle = jsonEncode(buildPlanBundle(oneEx(pyramidCfg({'pyramidWeight': [40, 60, 80, 0, 40]}), 'Legs', {'unit': 'kg'}), 'Plan'));
      expect(firstEx(parsePlan(bundle, 'kg'))['pyramidWeight'], jeq([40, 60, 80, 0, 40]));
      expect(firstEx(parsePlan(bundle, 'lb'))['pyramidWeight'],
          jeq([40, 60, 80, 0, 40].map((w) => w > 0 ? convertWeight(w, 'kg', 'lb') : 0).toList()));
    });
  });

  // dumbbells.test.js 'sync and sharing' — only the plan-share case; the mergeStates / stampChange
  // ones belong to dumbbells_test.dart.
  group('dumbbell load (dumbbells.test.js)', () {
    test('travels with a shared plan', () {
      const BENCH = '0289', CURL = '0294';
      final S = {'unit': 'kg', 'workouts': [], 'exWeights': {}, 'routines': [
        {'id': 'r1', 'name': 'Push', 'ex': [
          {'id': BENCH, 'sets': 3, 'reps': 10, 'weight': 20, 'mode': 'reps', 'dbLoad': 'each'},
          {'id': CURL, 'sets': 3, 'reps': 10, 'weight': 10, 'mode': 'reps'},
        ]},
      ]};
      final list = buildPlanBundle(S, 'Push')['routines'][0]['ex'];
      expect(list[0]['dbLoad'], 'each');
      expect(list[1]['dbLoad'], isNull);
      final back = parsePlan(jsonEncode(buildPlanBundle(S, 'Push')), 'kg');
      expect(firstEx(back)['dbLoad'], 'each');
    });
  });

  // failure-sets.test.js — the printout half (planPrintHTML) is not ported.
  group('last set to failure (failure-sets.test.js)', () {
    test('travels with a shared plan', () {
      final S = {'unit': 'kg', 'week': {}, 'customEx': [], 'routines': [{'id': 'r1', 'name': 'Push', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 100, 'lastToFailure': true}]}]};
      final bundle = buildPlanBundle(S, 'Plan');
      expect(bundle['routines'][0]['ex'][0]['lastToFailure'], true);
      expect(firstEx(parsePlan(jsonEncode(bundle)))['lastToFailure'], true);
      final off = buildPlanBundle({...S, 'routines': [{'id': 'r1', 'name': 'Push', 'ex': [{'id': '0025', 'sets': 3, 'reps': 5, 'weight': 100}]}]}, 'Plan');
      expect((off['routines'][0]['ex'][0] as Map).containsKey('lastToFailure'), isFalse);
      // skipped: expect(planPrintHTML(S, 'Me')).toContain('Last set to failure') — HTML print view.
    });
  });

  // progression.triple.test.js
  group('triple progression (progression.triple.test.js)', () {
    test('travels with a shared plan', () {
      final cfg = {'id': LIFT, 'sets': 3, 'setsMax': 5, 'reps': 12, 'repsMin': 8, 'weight': 60, 'inc': 2.5, 'mode': 'reps', 'prog': 'triple'};
      final S = {'unit': 'kg', 'week': {}, 'customEx': [], 'routines': [{'id': 'r', 'name': 'A', 'ex': [cfg]}]};
      final ex = firstEx(parsePlan(jsonEncode(buildPlanBundle(S, 'Plan'))));
      expect(ex, matchObj({'prog': 'triple', 'sets': 3, 'setsMax': 5, 'reps': 12, 'repsMin': 8}));
    });
    test('clamps a set ceiling past the maximum on the way out', () {
      final S = oneEx({'id': LIFT, 'sets': 3, 'setsMax': 40, 'reps': 12, 'mode': 'reps', 'prog': 'triple'});
      expect(buildPlanBundle(S, 'Plan')['routines'][0]['ex'][0]['setsMax'], 10);
    });
  });

  // exercise-alias-ids.test.js — the plan-file cases (the coach / Hevy import ones are not plan-share).
  group('a drawing id on its way in (exercise-alias-ids.test.js)', () {
    late String ALIAS, TO;
    setUpAll(() {
      final hit = jsFind(EXALIAS.entries, (en) => EXIDX[en.value] != null && !EXIDX.keys.contains(en.key)) as MapEntry<String, dynamic>;
      ALIAS = hit.key;
      TO = hit.value as String;
    });
    JMap state() => {
          'unit': 'kg', 'lang': 'en', 'customEx': <dynamic>[], 'workouts': [], 'bodyweight': [], 'exWeights': {}, 'dayPlan': {}, 'week': {},
          'routines': <dynamic>[
            {'id': 'r1', 'name': 'Old', 'ex': [{'id': ALIAS, 'sets': 3, 'reps': 10, 'mode': 'reps'}, {'id': '0001', 'sets': 3, 'reps': 10, 'mode': 'reps'}]},
          ],
        };
    String plan(List<dynamic> ex) => jsonEncode({'opengym_plan': 1, 'unit': 'kg', 'routines': [{'id': 'p1', 'name': 'Shared', 'ex': ex}], 'customEx': []});

    test('a plan file: parsed and merged as the exercise, the routines already there untouched', () {
      final s = state();
      final bundle = parsePlan(plan([{'id': ALIAS, 'sets': 3, 'reps': 8, 'mode': 'reps'}]));
      expect(firstEx(bundle)['id'], TO);
      mergePlan(s, {...bundle, 'routines': [{...asMap(bundle['routines'][0]), 'ex': [{'id': ALIAS, 'sets': 3}]}]});
      expect(s['routines'][1]['ex'][0]['id'], TO);
      expect(s['routines'][0]['ex'][0]['id'], ALIAS);
    });

    test('a plan file whose own custom exercise happens to carry such an id keeps it as a custom one', () {
      final raw = jsonEncode({'opengym_plan': 1, 'unit': 'kg', 'routines': [{'id': 'p1', 'name': 'Shared', 'ex': [{'id': ALIAS, 'sets': 3}]}], 'customEx': [{'id': ALIAS, 'n': 'my thing', 'bp': 'chest'}]});
      final bundle = parsePlan(raw);
      expect(firstEx(bundle)['id'], ALIAS);
      final s = state();
      mergePlan(s, bundle);
      final added = s['routines'][1]['ex'][0]['id'];
      expect((s['customEx'] as List).map((c) => c['id']).toList(), jeq([added]));
    });
  });

  // skipped: speed.test.js "prints a plan in the profile's speed unit" and plan-print.test.js —
  // planPrintHTML is the HTML print view, not ported (DOM/web-only).
  // skipped: workout-media.test.js 'a routine saved from the workout, and a plan file built from
  // it' — needs saveSessionAsRoutine (session-merge/workout-media), not plan-share.
}
