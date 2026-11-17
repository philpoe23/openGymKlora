// The exercise library for the UI: loaded once from the bundled JSON assets (the engine's
// [loadExerciseDb] builds the index), and display names for plan and workout entries.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../engine/exercises.dart';
import '../../engine/format.dart' show capWords, exerciseNameText;
import '../../engine/js.dart';

/// True once [CATALOGUE] holds the library. Screens listen to repaint names after a late load.
final ValueNotifier<bool> exerciseDbReady = ValueNotifier<bool>(false);

Future<void>? _loading;

/// Loads the library unless something (the app's boot, a test) already did. Never throws: a
/// screen falls back to the names stored on the entries.
Future<void> ensureExerciseDb() {
  if (CATALOGUE.isNotEmpty) {
    // Not during a build: listeners elsewhere may be mounted.
    if (!exerciseDbReady.value) scheduleMicrotask(() => exerciseDbReady.value = true);
    return SynchronousFuture<void>(null);
  }
  return _loading ??= _load();
}

Future<void> _load() async {
  try {
    Future<dynamic> json(String path) async => jsonDecode(await rootBundle.loadString(path));
    final db = await json('assets/exercises.json');
    final muscles = await json('assets/exercise-muscle-map.json');
    final aliases = await json('assets/exercise-aliases.json');
    final v13 = await json('assets/catalogue-v13-ids.json');
    if (CATALOGUE.isEmpty) {
      loadExerciseDb(
        db as List<dynamic>,
        muscleMap: asMap(muscles),
        aliases: asMap(aliases),
        v13Ids: v13 is List ? v13 : null,
      );
    }
    exerciseDbReady.value = true;
  } catch (_) {
    _loading = null;
  }
}

/// The display name of a plan or workout entry (`{id, n?}`) or an exercise id.
String exName(dynamic entryOrId) {
  final id = entryOrId is Map ? entryOrId['id'] : entryOrId;
  final ex = exById(id);
  if (ex != null) return exerciseNameText(ex);
  final n = entryOrId is Map ? entryOrId['n'] : null;
  return truthy(n) ? capWords(n) : 'Exercise';
}
