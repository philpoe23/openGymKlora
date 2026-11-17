// Port of frontend/src/lib/i18n-core.js — an English-only shim.
//
// The client app ships in English (v1), so there is no locale pack, no instruction pack and no
// exercise-name pack: every reader behaves exactly as the JS does while the language is 'en' and
// nothing has been loaded. The pure helpers (baseLang, derivePack) are ported as they are.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'js.dart';

const Map<String, String> LANGS = {'en': 'English'};

/// Languages rendered right-to-left. None in an English-only app.
const List<String> RTL_LANGS = [];

const Map<String, String> DATE_LOCALES = {'en': 'en-GB'};

/// Locales derived from another language by a pure text transform (see i18n-core.js).
final Map<String, ({String base, String Function(String) transform})> DERIVED_LOCALES = {
  'de-CH': (base: 'de', transform: (String s) => s.replaceAll('ß', 'ss')),
};

/// The language whose packs a locale actually loads.
String baseLang(String l) => DERIVED_LOCALES[l]?.base ?? l;

/// Applies a derived locale's transform to a pack (strings, lists and maps walked), returning the
/// pack itself for a language that is not derived.
dynamic derivePack(String l, dynamic pack) {
  final transform = DERIVED_LOCALES[l]?.transform;
  if (transform == null || !truthy(pack)) return pack;
  dynamic walk(dynamic v) {
    if (v is String) return transform(v);
    if (v is List) return v.map(walk).toList();
    if (v is Map) return <String, dynamic>{for (final e in v.entries) e.key.toString(): walk(e.value)};
    return v;
  }

  return walk(pack);
}

String getLang() => 'en';

/// The JS returns DATE_LOCALES[lang] ('en-GB'); the shim answers 'en' as the port's contract asks.
/// The formatters in format.dart write en-GB conventions themselves.
String dateLocale() => 'en';

int getVersion() => 0;

String _sub(String v, List<dynamic> args) {
  for (var i = 0; i < args.length; i++) {
    v = v.replaceAll('{$i}', jsString(args[i]));
  }
  return v;
}

/// Translate a source string: English, so the string itself with {0},{1}… replaced by [args].
String t(String s, [List<dynamic> args = const []]) => _sub(s, args);

/// A counted string: [one] when n == 1, else [other]; {0} is n, {1}… are [rest].
String tn(String one, String other, dynamic n, [List<dynamic> rest = const []]) => t(n == 1 ? one : other, [n, ...rest]);

/// Instructions for an exercise: the exercise's own steps (no English pack is bundled).
dynamic instrFor(dynamic ex) => or(at(ex, 'st'), <dynamic>[]);

bool instrTranslated(dynamic ex) => false;

String descFor(dynamic ex) {
  if (!truthy(ex)) return '';
  final d = at(ex, 'desc');
  return truthy(d) ? d.toString() : '';
}

/// An exercise's display name: the catalogue title (English).
String exerciseNameFor(dynamic ex) {
  final n = at(ex, 'n');
  return truthy(n) ? n.toString() : '';
}

const List<String> CASED_NAME_LANGS = ['de'];

/// English names are stored lower-case and title-cased by the UI.
String exerciseNameClass(dynamic ex) => 'capitalize';

String exerciseNameSearchText(dynamic ex) => exerciseNameFor(ex);
