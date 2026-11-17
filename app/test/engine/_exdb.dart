// Loads the exercise library for engine tests from the app's own assets (tests run with
// cwd = app/), once per test isolate.
import 'dart:convert';
import 'dart:io';

import 'package:klora_app/engine/exercises.dart';

bool _loaded = false;

dynamic _json(String path) => jsonDecode(File(path).readAsStringSync());

void loadTestExerciseDb() {
  if (_loaded) return;
  _loaded = true;
  loadExerciseDb(
    _json('assets/exercises.json') as List<dynamic>,
    muscleMap: _json('assets/exercise-muscle-map.json') as Map<String, dynamic>,
    aliases: _json('assets/exercise-aliases.json') as Map<String, dynamic>,
    v13Ids: _json('assets/catalogue-v13-ids.json') as List<dynamic>,
  );
}

/// catalogue-v13-ids.json, for tests that read it directly.
List<dynamic> testV13Ids() => _json('assets/catalogue-v13-ids.json') as List<dynamic>;
