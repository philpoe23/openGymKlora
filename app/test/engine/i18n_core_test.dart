// Port of frontend/src/lib/i18n-core.test.js. The app is English-only (no locale, instruction or
// exercise-name packs), so the cases that exercise those packs are skipped as noted.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/i18n_core.dart';

import '_helpers.dart';

void main() {
  group('baseLang', () {
    test('maps a derived locale to the language whose packs it loads', () {
      expect(baseLang('de-CH'), 'de');
    });

    test('leaves every other language as itself', () {
      expect(baseLang('de'), 'de');
      expect(baseLang('pt-BR'), 'pt-BR');
      expect(baseLang('en'), 'en');
      expect(baseLang('nonsense'), 'nonsense');
    });

    // skipped: 'keeps derived locales in step with their base' — reads INSTR_LANGS /
    // EXERCISE_NAME_LANGS, the non-English pack catalogue, which is not ported.
  });

  group('derivePack', () {
    test('rewrites ß as ss for Swiss German', () {
      expect(derivePack('de-CH', {'a': 'Gesäß', 'b': 'Füße', 'c': 'schließen'}), jeq({'a': 'Gesäss', 'b': 'Füsse', 'c': 'schliessen'}));
    });

    test('leaves legitimate ss alone', () {
      expect(derivePack('de-CH', {'a': 'Arbeitssätze', 'b': 'Schlüssel', 'c': 'Latissimus'}),
          jeq({'a': 'Arbeitssätze', 'b': 'Schlüssel', 'c': 'Latissimus'}));
    });

    test('walks instruction packs, which nest steps in arrays', () {
      expect(derivePack('de-CH', {'0007': ['Setz dich aufs Gerät.', 'Spann das Gesäß an.']}),
          jeq({'0007': ['Setz dich aufs Gerät.', 'Spann das Gesäss an.']}));
    });

    test('returns the pack untouched for a language that is not derived', () {
      final pack = {'a': 'Gesäß'};
      expect(derivePack('de', pack), same(pack));
      expect(derivePack('en', pack), same(pack));
    });

    test('passes a null pack through', () {
      expect(derivePack('de-CH', null), isNull);
    });

    // skipped: 'derives the whole German locale…' — needs the German locale pack (catalogue).
  });

  // skipped: the whole 'de-CH as a selectable language' group — Intl number formatting, the
  // locale pack glob and _setLangState, none of which exist in the English-only shim.

  group('exerciseNameClass', () {
    test('title-cases while the English fallback is showing (en part of the JS case)', () {
      // The JS case also switches to German with a name pack; only its English assertions apply.
      expect(exerciseNameClass({'id': '0025', 'n': 'barbell bench press'}), 'capitalize');
      expect(exerciseNameClass(null), 'capitalize');
    });
    // skipped: 'decides per exercise…' — needs a German exercise-name pack.
  });

  // skipped: 'title-casing per exercise-name pack' and 'English-name switches with every
  // exercise-name pack' — both iterate the non-English exercise-name packs.

  group('English shim', () {
    test('t substitutes, tn picks the form by n', () {
      expect(t('{0}h {1}m', [1, 5]), '1h 5m');
      expect(tn('{0} set', '{0} sets', 1), '1 set');
      expect(tn('{0} set · {1} work', '{0} sets · {1} work', 3, [2]), '3 sets · 2 work');
      expect(getLang(), 'en');
      expect(exerciseNameFor({'n': 'push-up'}), 'push-up');
      expect(exerciseNameFor(null), '');
    });
  });
}
