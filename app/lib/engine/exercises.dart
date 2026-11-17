// Port of frontend/src/lib/exercises.js — the exercise library, its index and the search.
//
// The JS builds CATALOGUE / EXIDX / BODYPARTS at module load from exercises-data.js (EXDB,
// EXALIAS), exercise-muscle-map.json and catalogue-v13-ids.json. The Dart app reads those as JSON
// assets (assets/exercises.json, exercise-muscle-map.json, exercise-aliases.json,
// catalogue-v13-ids.json) and hands them to [loadExerciseDb], which builds the same indices.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:collection';

import 'i18n_core.dart';
import 'js.dart';
import 'nfd_table.dart';

/// The raw catalogue (EXDB), as loaded.
JList EXDB = <dynamic>[];

/// EXDB with the muscle-map layer applied (what every picker and map sees).
JList CATALOGUE = <dynamic>[];

/// The drawing id → exercise id table (EXALIAS).
JMap EXALIAS = <String, dynamic>{};

JList BODYPARTS = <dynamic>[];

JMap _muscleMap = <String, dynamic>{};
Set<String> _classic = <String>{};
Set<Object> _builtin = Set<Object>.identity();

/// The id index. Like the JS object with its non-enumerable alias properties: a drawing's id
/// reads the exercise it draws, but walking the map sees every exercise once.
class ExIndex extends MapBase<String, dynamic> {
  final Map<String, dynamic> _m = <String, dynamic>{};
  final Map<String, dynamic> _alias = <String, dynamic>{};

  @override
  dynamic operator [](Object? key) {
    if (key is! String) return null;
    return _m.containsKey(key) ? _m[key] : _alias[key];
  }

  @override
  void operator []=(String key, dynamic value) => _m[key] = value;

  @override
  void clear() {
    _m.clear();
    _alias.clear();
  }

  @override
  Iterable<String> get keys => _m.keys;

  @override
  dynamic remove(Object? key) => _m.containsKey(key) ? _m.remove(key) : _alias.remove(key);

  @override
  bool containsKey(Object? key) => _m.containsKey(key) || _alias.containsKey(key);

  void _setAlias(String id, dynamic ex) => _alias[id] = ex;
}

final ExIndex EXIDX = ExIndex();

/// `EXIDX[id]` for any id value (JS turns a number key into its string).
dynamic exById(Object? id) => id == null ? null : EXIDX[id is String ? id : jsString(id)];

dynamic _catalogueExercise(dynamic ex) {
  final metadata = _muscleMap[at(ex, 'id')];
  if (metadata == null) return ex;
  final out = <String, dynamic>{...asMap(ex), ...asMap(metadata)};
  if (out['primaries'] is List) out['primaries'] = [...out['primaries'] as List];
  if (out['secondaries'] is List) out['secondaries'] = [...out['secondaries'] as List];
  return out;
}

/// Builds what exercises.js builds at module load. [muscleMap] is exercise-muscle-map.json,
/// [aliases] EXALIAS, [v13Ids] catalogue-v13-ids.json.
void loadExerciseDb(List<dynamic> db, {Map<String, dynamic>? muscleMap, Map<String, dynamic>? aliases, List<dynamic>? v13Ids}) {
  EXDB = db;
  _muscleMap = muscleMap ?? <String, dynamic>{};
  EXALIAS = aliases ?? <String, dynamic>{};
  _classic = {for (final id in v13Ids ?? const []) id.toString()};
  CATALOGUE = EXDB.map(_catalogueExercise).toList();
  EXIDX.clear();
  for (final e in CATALOGUE) {
    EXIDX[jsString(at(e, 'id'))] = e;
  }
  for (final e in EXALIAS.entries) {
    final to = EXIDX[e.value];
    if (to != null && !EXIDX._m.containsKey(e.key)) EXIDX._setAlias(e.key, to);
  }
  final bps = <dynamic>{for (final e in CATALOGUE) at(e, 'bp')}.toList();
  BODYPARTS = jsSort(bps, (a, b) {
    if (a == null || b == null) return a == null ? (b == null ? 0 : 1) : -1;
    return jsString(a).compareTo(jsString(b));
  });
  _builtin = Set<Object>.identity()..addAll(CATALOGUE.whereType<Object>());
  _customIds = <dynamic>{};
  _corpusCache = Expando<_Corpus>();
  _vocab.clear();
}

const Map<String, List<String>> _SECONDARY_ADDITIONS = {
  '0027': ['rear deltoids'],
  '0293': ['rear deltoids'],
  '0499': ['rear deltoids'],
  '0861': ['rear deltoids'],
};

/// Secondary muscles, with the conservative additions applied as an overlay.
List<dynamic> smOf(dynamic ex) {
  final sm = at(ex, 'sm');
  final base = sm is List ? sm : (truthy(sm) ? [sm] : const []);
  return <dynamic>{...base, ...(_SECONDARY_ADDITIONS[at(ex, 'id')] ?? const [])}.toList();
}

/// The exercise a drawing's id stands for; any other id as it is.
dynamic canonicalExId(dynamic id) =>
    id is String && EXALIAS.containsKey(id) && EXIDX[EXALIAS[id]] != null ? EXALIAS[id] : id;

/// Equipment present in [list], most common first.
List<String> equipmentOf(List<dynamic> list) {
  final c = <String, int>{};
  for (final e in list) {
    final eq = at(e, 'eq');
    if (truthy(eq)) c[jsString(eq)] = (c[jsString(eq)] ?? 0) + 1;
  }
  final keys = jsKeys(c);
  return jsSort(keys, (a, b) => c[b]! - c[a]! != 0 ? c[b]! - c[a]! : (a.compareTo(b) < 0 ? -1 : 1));
}

const List<String> CATEGORIES = ['strength', 'calisthenics', 'olympic', 'plyometrics', 'isometric', 'cardio', 'stretching', 'mobility', 'yoga', 'pilates', 'combat', 'rehab'];

List<String> categoriesOf(List<dynamic> list) {
  final have = {for (final e in list) at(e, 'cat')}..removeWhere((c) => !truthy(c));
  return CATEGORIES.where(have.contains).toList();
}

/// The Type chip row's filter: { opts, on, list }.
JMap byCategory(List<dynamic> list, Object? cat) {
  final opts = categoriesOf(list);
  final on = opts.contains(cat) ? cat as String : '';
  return {'opts': opts, 'on': on, 'list': on.isNotEmpty ? list.where((e) => at(e, 'cat') == on).toList() : list};
}

Set<dynamic> _customIds = <dynamic>{};

/// Merges the user's custom exercises (S.customEx) into the index.
void registerCustom(dynamic list) {
  for (final id in _customIds) {
    final key = jsString(id);
    EXIDX.remove(key);
    final builtIn = jsFind(CATALOGUE, (ex) => at(ex, 'id') == id);
    if (builtIn != null) EXIDX[key] = builtIn;
  }
  final xs = asList(list).where((e) => truthy(e) && at(e, 'id') != null).toList();
  _customIds = {for (final e in xs) at(e, 'id')};
  for (final e in xs) {
    EXIDX[jsString(at(e, 'id'))] = e;
  }
}

/// Whether an exercise is one of the user's own (where it lives decides, not only the flag).
bool isCustomEx(dynamic ex) =>
    ex is Map && !_builtin.contains(ex) && (ex['custom'] == true || _customIds.contains(ex['id']));

/// The stored list with the custom flag put back where it was lost; the same list when nothing is.
dynamic healCustomEx(dynamic list) {
  if (list is! List) return list;
  var changed = false;
  final out = list.map((c) {
    if (c is! Map || c['custom'] == true) return c;
    changed = true;
    final m = <String, dynamic>{...asMap(c), 'custom': true};
    if (c['eq'] == null) m['eq'] = '';
    return m;
  }).toList();
  return changed ? out : list;
}

List<dynamic> allExercises(dynamic st) => [...asList(or(at(st, 'customEx'), const [])), ...CATALOGUE];

String _searchableText(dynamic value) {
  if (value is List) return value.map(_searchableText).join(' ');
  if (value == null) return '';
  return jsString(value);
}

bool _isSubsequence(String needle, String hay) {
  var i = 0;
  for (final r in hay.runes) {
    final ch = String.fromCharCode(r);
    if (i < needle.length && ch == needle[i]) i++;
    if (i == needle.length) return true;
  }
  return false;
}

final _nonAlnum = RegExp(r'[^a-z0-9]+');

/// Fuzzy match score for one exercise against a query; 0 = no match.
num searchScore(dynamic exercise, dynamic query) {
  final needle = _searchableText(query).toLowerCase().trim();
  if (needle.isEmpty) return 1;
  final source = exercise is Map ? exercise : const {};
  const fields = [('n', 100), ('tg', 40), ('eq', 40), ('sm', 30), ('muscleGroups', 30), ('primaries', 30), ('secondaries', 30), ('desc', 10), ('cues', 10)];
  final tokens = needle.split(_nonAlnum).where((s) => s.isNotEmpty).toList();
  if (tokens.isEmpty) return 0;
  num total = 0;
  for (final token in tokens) {
    num best = 0;
    for (final (field, weight) in fields) {
      final hay = _searchableText(source[field]).toLowerCase();
      if (hay.isEmpty) continue;
      if (hay == token) {
        best = maxOf([best, weight * 4]);
      } else if (hay.startsWith(token)) {
        best = maxOf([best, weight * 3]);
      }
      final idx = hay.indexOf(token);
      if (idx > 0) best = maxOf([best, weight * 2 - minOf([idx, 20]) * 0.5]);
      if (hay.split(_nonAlnum).any((w) => w.startsWith(token))) best = maxOf([best, weight * 2.5]);
      if (_isSubsequence(token, hay)) best = maxOf([best, weight + maxOf([0, 10 - (hay.length - token.length)])]);
    }
    if (best == 0) return 0;
    total += best;
  }
  return total;
}

bool matchesExerciseSearch(dynamic exercise, dynamic query) => searchScore(exercise, query) > 0;

// Media bases: VITE_IMG_BASE / VITE_GIF_BASE / VITE_CLIP_EXT in the web build.
String _imgBase = 'exercise-media/still/';
String _gifBase = 'exercise-media/clip/';
String _clipExt = '.mp4';

/// The web build's env (VITE_IMG_BASE, VITE_GIF_BASE, VITE_CLIP_EXT); null leaves a value as is.
void configureExerciseMedia({String? imgBase, String? gifBase, String? clipExt}) {
  if (imgBase != null) _imgBase = imgBase;
  if (gifBase != null) _gifBase = gifBase;
  if (clipExt != null) _clipExt = clipExt == 'webp' ? '.webp' : '.mp4';
}

String figureOf(dynamic S) {
  final f = at(S, 'exFigure');
  if (f == 'female' || f == 'male') return f as String;
  return at(S, 'body') == 'female' ? 'female' : 'male';
}

dynamic _drawing(dynamic ex, dynamic figure) {
  final v = figure == 'female' ? at(ex, 'fv') : (figure == 'male' ? at(ex, 'mv') : null);
  return truthy(v) ? v : null;
}

String imgSrc(dynamic ex, [dynamic figure]) {
  final d = _drawing(ex, figure);
  return _imgBase + (d != null ? '${jsString(d)}.webp' : jsString(at(ex, 'img')));
}

String _clipFile(String f) => _clipExt != '.mp4' && f.endsWith('.mp4') ? f.substring(0, f.length - 4) + _clipExt : f;

String gifSrc(dynamic ex, [dynamic figure]) {
  final d = _drawing(ex, figure);
  return _gifBase + _clipFile(d != null ? '${jsString(d)}.mp4' : jsString(at(ex, 'gif')));
}

bool isVideoSrc(dynamic src) => RegExp(r'\.(mp4|webm)(\?|$)', caseSensitive: false).hasMatch(truthy(src) ? jsString(src) : '');

dynamic _exOf(dynamic idOrEx) => idOrEx is String ? EXIDX[idOrEx] : idOrEx;

bool isCardio(dynamic idOrEx) => at(_exOf(idOrEx), 'bp') == 'cardio';

const Set<String> _BODYWEIGHT_EQ = {'body weight', 'band', 'resistance band'};
bool isBodyweightEq(dynamic idOrEx) => _BODYWEIGHT_EQ.contains(at(_exOf(idOrEx), 'eq'));

const Set<String> _LOADED_EQ = {'barbell', 'ez barbell', 'olympic barbell', 'trap bar', 'dumbbell', 'kettlebell', 'clubbell', 'macebell', 'cable', 'leverage machine', 'smith machine', 'sled machine', 'weighted'};
bool isLoadedEq(dynamic idOrEx) => _LOADED_EQ.contains(at(_exOf(idOrEx), 'eq'));

const _ASSISTED_EQ = 'leverage machine';
bool _assistedName(dynamic n) => RegExp(r'\bassist(ed)?\b', caseSensitive: false).hasMatch(truthy(n) ? jsString(n) : '');

bool _assistedShape(dynamic ex) {
  final a = at(ex, 'assisted');
  if (a is bool) return a;
  return at(ex, 'eq') == _ASSISTED_EQ && _assistedName(at(ex, 'n'));
}

const List<String> _HEAVY_BP = ['upper legs', 'lower legs', 'back', 'hips', 'glutes'];

/// Default load step: the bigger jump for lower-body lifts.
num defaultIncrement(dynamic exId, [dynamic unit]) {
  final ex = exById(exId);
  final heavy = ex != null && _HEAVY_BP.contains(at(ex, 'bp'));
  if (unit == 'lb') return heavy ? 10 : 5;
  return heavy ? 5 : 2.5;
}

bool isAssisted(dynamic idOrEx) {
  if (!truthy(idOrEx)) return false;
  if (idOrEx is String) return _assistedShape(EXIDX[idOrEx]);
  if (idOrEx is! Map) return false;
  if (idOrEx['assisted'] is bool) return idOrEx['assisted'] as bool;
  final ta = at(idOrEx['target'], 'assisted');
  if (ta is bool) return ta;
  final known = truthy(idOrEx['id']) ? exById(idOrEx['id']) : null;
  return _assistedShape(or(known, idOrEx));
}

/// The better of two loads for this exercise: less assistance, or more weight.
num betterWeight(dynamic idOrEx, dynamic a, dynamic b) =>
    isAssisted(idOrEx) ? minOf([toNum(a), toNum(b)]) : maxOf([toNum(a), toNum(b)]);

/// Is [w] a better load than [prev]? prev of 0 means nothing logged yet.
bool beatsWeight(dynamic idOrEx, dynamic w, dynamic prev) {
  final x = toNum(w), p = toNum(prev);
  return x > 0 && (p <= 0 || (isAssisted(idOrEx) ? x < p : x > p));
}

/// The exercise, or a placeholder for an id that resolves to nothing.
dynamic exOr(dynamic id) =>
    or(exById(id), <String, dynamic>{'id': id, 'n': t('Unknown exercise'), 'bp': '', 'tg': '', 'eq': '', 'sm': <dynamic>[], 'st': <dynamic>[], 'missing': true});

/// Lower-cases and strips diacritics: `s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()`.
String normalizeStr(dynamic s) {
  final src = truthy(s) ? jsString(s) : '';
  final out = StringBuffer();
  for (final r in src.runes) {
    if (r >= 0x300 && r <= 0x36f) continue;
    if (r >= 0xac00 && r <= 0xd7a3) {
      // Hangul syllables decompose algorithmically into their jamo.
      final si = r - 0xac00;
      out.writeCharCode(0x1100 + si ~/ 588);
      out.writeCharCode(0x1161 + (si % 588) ~/ 28);
      if (si % 28 != 0) out.writeCharCode(0x11a7 + si % 28);
      continue;
    }
    final d = nfdStripped[r];
    if (d != null) {
      for (final c in d) {
        out.writeCharCode(c);
      }
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString().toLowerCase();
}

class _Corpus {
  _Corpus(this.v, this.s, this.name, this.joined, this.starts, this.nameWords);
  final int v;
  final String s;
  final String name;
  final String joined;
  final Set<int> starts;
  final List<String> nameWords;
}

Expando<_Corpus> _corpusCache = Expando<_Corpus>();
final Set<String> _vocab = <String>{};

String _tOf(dynamic v) => v is String ? t(v) : jsString(v);

final _nameWordSplit = RegExp(r'[\s\-‐-―()/,]+');

_Corpus _corpusOf(dynamic e) {
  final v = getVersion();
  final hit = e is Map || e is List ? _corpusCache[e as Object] : null;
  if (hit != null && hit.v == v) return hit;
  final smRaw = at(e, 'sm');
  final sm = smRaw is List ? smRaw : const [];
  final name = normalizeStr(exerciseNameSearchText(e));
  String f(String k) => truthy(at(e, k)) ? jsString(at(e, k)) : '';
  final s = normalizeStr(jsJoin([
    name,
    f('tg'), _tOf(f('tg')),
    f('eq'), _tOf(f('eq')),
    f('bp'), _tOf(f('bp')),
    ...sm, ...sm.map(_tOf),
    f('desc'),
  ], ' '));
  final j = _joinedOf(name);
  final entry = _Corpus(v, s, name, j.$1, j.$2, name.split(_nameWordSplit).where((w) => w.isNotEmpty).toList());
  _vocab.addAll(entry.nameWords);
  if (e is Map || e is List) _corpusCache[e as Object] = entry;
  return entry;
}

int _editDistance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  List<int>? prev2;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    var rowMin = i;
    for (var j = 1; j <= b.length; j++) {
      var v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
      if (prev2 != null && i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        if (prev2[j - 2] + 1 < v) v = prev2[j - 2] + 1;
      }
      cur.add(v);
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    prev2 = prev;
    prev = cur;
  }
  return prev[b.length];
}

int _typosFor(String word) => word.length < 4 ? 0 : (word.length < 7 ? 1 : 2);

bool _nearWordUncached(String a, String b) {
  final max = _typosFor(a);
  if (max == 0) return false;
  if (_editDistance(a, b, max) <= max) return true;
  return a.length >= 5 && b.length > a.length && _editDistance(a, b.substring(0, a.length), max) <= max;
}

Map<String, bool> _nearCache = <String, bool>{};
void _resetNearCache() {
  if (_nearCache.isNotEmpty) _nearCache = <String, bool>{};
}

bool _nearWord(String a, String b) => _nearCache.putIfAbsent('n$a\u0000$b', () => _nearWordUncached(a, b));

const Map<String, List<String>> _SYNONYMS = {
  'db': ['dumbbell'], 'dbs': ['dumbbell'], 'bb': ['barbell'], 'kb': ['kettlebell'], 'kbs': ['kettlebell'],
  'ez': ['ez barbell'], 'sm': ['smith'], 'bw': ['body weight'], 'bodyweight': ['body weight'],
  'ohp': ['overhead press', 'shoulder press', 'military press'], 'rdl': ['romanian deadlift'],
  'sldl': ['stiff leg deadlift'], 'dl': ['deadlift'], 'bp': ['bench press'], 'skullcrusher': ['lying triceps extension', 'skull crusher'],
  'skullcrushers': ['lying triceps extension', 'skull crusher'], 'pulldown': ['pull down', 'pulldown'],
  'pullup': ['pull up', 'pull-up'], 'chinup': ['chin up', 'chin-up'], 'pushup': ['push up', 'push-up'],
  'pressup': ['push up', 'push-up'], 'situp': ['sit up', 'sit-up'], 'flye': ['fly'], 'flyes': ['fly'], 'flies': ['fly'],
  'machine': ['lever', 'machine', 'sled'], 'lever': ['lever', 'machine'], 'abs': ['crunch', 'abs'],
  'hammy': ['hamstring'], 'hammies': ['hamstring'], 'quad': ['quads', 'quadriceps'], 'tricep': ['triceps'], 'bicep': ['biceps'],
  'delt': ['delts', 'shoulder'], 'lat': ['lats', 'latissimus', 'pulldown'], 'trap': ['traps', 'shrug'],
  'glute': ['glutes', 'gluteus'], 'calf': ['calf', 'calves'], 'hip': ['hip'], 'rope': ['rope'], 'trx': ['suspension'],
  'ring': ['ring', 'suspension'], 'rings': ['ring', 'suspension'], 'kettle': ['kettlebell'], 'dumbel': ['dumbbell'],
};

final Map<String, List<String>> _formsCache = <String, List<String>>{};

List<String> _formsOf(String tok) {
  final hit = _formsCache[tok];
  if (hit != null) return hit;
  final forms = _formsOfUncached(tok);
  if (_formsCache.length > 500) _formsCache.clear();
  _formsCache[tok] = forms;
  return forms;
}

List<String> _formsOfUncached(String tok) {
  final out = <String>[tok, ...?_SYNONYMS[tok]];
  if (tok.length >= 4 && tok.endsWith('es') && !tok.endsWith('ses')) {
    out.addAll([tok.substring(0, tok.length - 2), tok.substring(0, tok.length - 1)]);
  } else if (tok.length >= 4 && tok.endsWith('ses')) {
    out.add(tok.substring(0, tok.length - 2));
  } else if (tok.length >= 3 && tok.endsWith('s') && !tok.endsWith('ss') && tok != 'abs') {
    out.add(tok.substring(0, tok.length - 1));
  }
  return out.toSet().toList();
}

List<String> _queryTokens(dynamic query) => normalizeStr(truthy(query) ? query : '').split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
final _separator = RegExp(r'[\s\-‐-―]');
final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
String _joinWords(String s) => s.replaceAll(RegExp(r'[\s\-‐-―]+'), '');

(String, Set<int>) _joinedOf(String name) {
  final joined = StringBuffer();
  var len = 0;
  final starts = <int>{};
  for (var i = 0; i < name.length; i++) {
    if (_separator.hasMatch(name[i])) continue;
    if (i == 0 || !_wordChar.hasMatch(name[i - 1])) starts.add(len);
    joined.write(name[i]);
    len++;
  }
  return (joined.toString(), starts);
}

bool _joinedHit(_Corpus entry, String tok) {
  final needle = _joinWords(tok);
  for (var at = entry.joined.indexOf(needle); at != -1; at = entry.joined.indexOf(needle, at + 1)) {
    if (entry.starts.contains(at)) return true;
  }
  return false;
}

bool _literalHit(_Corpus entry, String tok) => entry.s.contains(tok) || (tok.length >= 4 && _joinedHit(entry, tok));
bool _hits(_Corpus entry, String tok) => _formsOf(tok).any((form) => _literalHit(entry, form));

bool _matchTokens(dynamic e, List<String> tokens, Set<String> fuzzy) {
  final entry = _corpusOf(e);
  return tokens.every((tok) =>
      _hits(entry, tok) || (fuzzy.contains(tok) && _formsOf(tok).any((f) => entry.nameWords.any((word) => _nearWord(f, word)))));
}

/// Single-exercise check; every token may fall back to the typo tolerance.
bool matchExercise(dynamic e, dynamic query) {
  final tokens = _queryTokens(query);
  if (tokens.isEmpty) return true;
  if (e is! Map) return false;
  return _matchTokens(e, tokens, tokens.toSet());
}

/// Search a list, exact hits first, ranked by relevance.
List<dynamic> searchExercises(List<dynamic> list, dynamic query) {
  final tokens = _queryTokens(query);
  if (tokens.isEmpty) return list;
  _resetNearCache();
  final fuzzy = tokens.where((tok) => !list.any((e) => _hits(_corpusOf(e), tok))).toSet();
  return _rankByRelevance(list.where((e) => _matchTokens(e, tokens, fuzzy)).toList(), tokens);
}

class _Ctx {
  final Set<String> prefix = {}, near = {}, extra = {};
}

Map<String, _Ctx> _queryContext(List<String> tokens) {
  final ctx = <String, _Ctx>{};
  for (final tok in tokens) {
    for (final form in _formsOf(tok)) {
      if (ctx.containsKey(form) || form.contains(' ')) continue;
      final extraMax = tok.length >= 6 ? _typosFor(tok) + 1 : _typosFor(tok);
      final c = _Ctx();
      for (final w in _vocab) {
        if (w.startsWith(form)) c.prefix.add(w);
        if (_nearWordUncached(form, w)) {
          c.near.add(w);
        } else if (tok.length >= 4 && _editDistance(form, w, extraMax) <= extraMax) {
          c.extra.add(w);
        }
      }
      ctx[form] = c;
    }
  }
  return ctx;
}

num _tokenScore(_Corpus entry, String tok, Map<String, _Ctx>? ctx) {
  num best = 0;
  for (final form in _formsOf(tok)) {
    final c = ctx?[form];
    final exact = form == tok || (tok.length <= 4 && (_SYNONYMS[tok]?.contains(form) ?? false)) ? 0 : 5;
    final words = form.split(' ');
    if (words.length > 1) {
      if (entry.name.contains(form)) {
        best = maxOf([best, 100 - exact]);
      } else if (entry.s.contains(form)) {
        best = maxOf([best, 20 - exact]);
      }
      continue;
    }
    if (entry.nameWords.contains(form)) {
      best = maxOf([best, 100 - exact]);
    } else if (c != null ? entry.nameWords.any(c.prefix.contains) : entry.nameWords.any((w) => w.startsWith(form))) {
      best = maxOf([best, 80 - exact]);
    } else if (entry.name.contains(form)) {
      best = maxOf([best, 60 - exact]);
    } else if (form.length >= 4 && _joinedHit(entry, form)) {
      best = maxOf([best, 55 - exact]);
    } else if (c != null ? entry.nameWords.any(c.near.contains) : entry.nameWords.any((w) => _nearWord(form, w))) {
      best = maxOf([best, 40 - exact]);
    } else if (entry.s.contains(form)) {
      best = maxOf([best, 20 - exact]);
    }
  }
  return best;
}

const Map<String, int> _EQ_PRIOR = {'barbell': 4, 'dumbbell': 4, 'cable': 3, 'leverage machine': 3, 'body weight': 3, 'smith machine': 2, 'kettlebell': 2, 'ez barbell': 2, 'sled machine': 2};
const Map<String, int> _CAT_PRIOR = {'strength': 3, 'calisthenics': 3, 'olympic': 2, 'plyometrics': 1, 'isometric': 1, 'stretching': -3, 'mobility': -3, 'rehab': -4, 'yoga': -2, 'pilates': -2};
const Map<String, int> _EVERYDAY = {'0739': 6};

int _priorOf(dynamic e) =>
    (_classic.contains(at(e, 'id')) ? 3 : 0) + (_EQ_PRIOR[at(e, 'eq')] ?? 0) + (_CAT_PRIOR[at(e, 'cat')] ?? 0) + (_EVERYDAY[at(e, 'id')] ?? 0);

int _wholeNameScore(String plain, List<String> typedForms) {
  if (typedForms.contains(plain)) return 50;
  return typedForms.any((q) {
    final max = _typosFor(q);
    return max > 0 && _editDistance(q, plain, max) <= max;
  })
      ? 40
      : 0;
}

final _dashes = RegExp(r'[-‐-―]');

class _Scored {
  _Scored(this.e, this.i, this.score, this.len);
  final dynamic e;
  final int i;
  final num score;
  final int len;
}

int _cmpScored(_Scored a, _Scored b) {
  final s = cmpNum(b.score - a.score);
  if (s != 0) return s;
  if (a.len != b.len) return a.len - b.len;
  return a.i - b.i;
}

List<dynamic> _rankByRelevance(List<dynamic> found, List<String> tokens) {
  final ctx = _queryContext(tokens);
  final singular = tokens.map((tok) => _formsOf(tok).firstWhere((f) => f != tok && !f.contains(' '), orElse: () => tok)).toList();
  final typedForms = {for (final list in [tokens, singular]) list.join(' ').replaceAll(_dashes, ' ')}.toList();
  final scored = <_Scored>[];
  for (var i = 0; i < found.length; i++) {
    final e = found[i];
    final entry = _corpusOf(e);
    final plain = entry.name.split(' (')[0].replaceAll(_dashes, ' ');
    final whole = _wholeNameScore(plain, typedForms);
    final extra = maxOf([0, entry.nameWords.length - tokens.length]) * 3;
    final score = tokens.fold<num>(0, (sum, tok) => sum + _tokenScore(entry, tok, ctx)) + _priorOf(e) + whole - extra;
    scored.add(_Scored(e, i, score, entry.nameWords.length));
  }
  scored.sort(_cmpScored);
  return scored.map((x) => x.e).toList();
}

/// Exercises that come close to a query without matching all of it, best first.
List<dynamic> similarExercises(List<dynamic> list, dynamic query, [List<dynamic> exclude = const [], int limit = 30]) {
  final tokens = _queryTokens(query);
  if (tokens.isEmpty) return [];
  _resetNearCache();
  final skip = Set<Object?>.identity()..addAll(exclude);
  final tgCount = <String, int>{};
  for (final e in exclude.take(8)) {
    final tg = at(e, 'tg');
    if (truthy(tg)) tgCount[jsString(tg)] = (tgCount[jsString(tg)] ?? 0) + 1;
  }
  final tgKeys = jsSort(jsKeys(tgCount), (a, b) => tgCount[b]! - tgCount[a]!);
  final mainTg = tgKeys.isEmpty ? null : tgKeys.first;
  for (final e in list) {
    _corpusOf(e);
  }
  final ctx = _queryContext(tokens);
  final out = <_Scored>[];
  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    if (skip.contains(e)) continue;
    final entry = _corpusOf(e);
    num score = 0;
    var found = 0;
    for (final tok in tokens) {
      var best = _tokenScore(entry, tok, ctx);
      if (best == 0 &&
          _formsOf(tok).any((f) {
            final c = ctx[f];
            return c != null && entry.nameWords.any(c.extra.contains);
          })) {
        best = 25;
      }
      if (best != 0) {
        found++;
        score += best;
      }
    }
    if (found * 2 < tokens.length || found == 0 || (tokens.length == 1 && score < 25)) continue;
    out.add(_Scored(e, i, score + found * 30 + _priorOf(e) + (mainTg != null && at(e, 'tg') == mainTg ? 40 : 0), entry.nameWords.length));
  }
  out.sort(_cmpScored);
  return out.take(limit).map((x) => x.e).toList();
}
