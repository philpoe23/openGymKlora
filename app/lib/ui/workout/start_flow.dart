// Starting a workout (sheets.jsx startFlow + beginWorkout): which routines (today's plan, the one
// named, or a pick between routines and freestyle), the weigh-in when the profile asks for one,
// then `S.active`. A running session is never replaced: starting with one resumes it.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../engine/history.dart' show lastBW;
import '../../engine/js.dart';
import '../screens/home.dart' show logBodyWeight;
import 'rest_timer.dart';
import 'session_ops.dart';
import 'sheets.dart';
import 'workout_device.dart';

/// Builds the session the start asked for. [routineIds] null is the Start pill: today's plan when
/// it holds exercises, else a chooser (straight to freestyle when there is nothing to choose).
/// Resolves to true when a session is there to open (new or already running), false when the
/// person backed out of a sheet.
Future<bool> startWorkoutFlow(BuildContext context, {List<String>? routineIds}) async {
  final store = context.read<AppStore>();
  if (store.S['active'] is Map) return true;

  var ids = routineIds;
  if (ids == null) {
    final today = todaysRoutineIds(store.S);
    if (today.isNotEmpty) {
      ids = today.map(jsString).toList();
    } else {
      final choices = [
        for (final r in asList(store.S['routines']))
          if (asList(at(r, 'ex')).isNotEmpty)
            (id: jsString(at(r, 'id')), name: jsString(or(at(r, 'name'), 'Routine')), count: asList(at(r, 'ex')).length),
      ];
      if (choices.isEmpty) {
        ids = const [];
      } else {
        ids = await showStartChooser(context, choices);
        if (ids == null || !context.mounted) return false;
      }
    }
  }

  num? bw;
  if (store.S['weighIn'] != false) {
    final unit = store.S['unit'] == 'lb' ? 'lb' : 'kg';
    final last = at(lastBW(store.S), 'w');
    final r = await showWorkoutWeighIn(context, initial: last is num && last > 0 ? last : (unit == 'lb' ? 160 : 70), unit: unit);
    if (r == null || !context.mounted) return false;
    bw = r.$2;
  }

  // Something may have started a session while a sheet was open (a sync from another device
  // never carries one, but a double tap might).
  if (store.S['active'] is Map) return true;
  final chosen = ids;
  store.update((s) {
    if (bw != null) logBodyWeight(s, bw);
    s['active'] = buildActive(s, chosen, bw);
  });
  RestTimer.instance.stop();
  unawaited(WorkoutDevice.instance.requestPermissions());
  return true;
}
