// Port of frontend/src/lib/accent.test.js — the cases for what accent.dart ports (cleanHex,
// sanitizeAccent). The rest of accent.js (colour maths, CSS vars, applyAccent on the DOM) is not
// part of this port; those groups are skipped below.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/accent.dart';

import '_helpers.dart';

void main() {
  group('cleanHex', () {
    test('takes #rrggbb only, in lowercase', () {
      expect(cleanHex('#A1b2C3'), '#a1b2c3');
      expect(cleanHex(' #00ff00 '), '#00ff00');
      for (final bad in [
        '#abc', 'abcdef', '#abcdeg', '#abcdef00', 'red', 'rgb(1,2,3)', '', null, 123, {}, ['#abcdef'],
        '#000000;background:url(x)', '#000000}body{display:none', 'var(--x)',
      ]) {
        expect(cleanHex(bad), isNull, reason: '$bad');
      }
    });
  });

  group('sanitizeAccent', () {
    test('drops a malformed own colour and keeps a good one', () {
      expect(sanitizeAccent({'accent': 'custom', 'accentCustom': '#FF00AA'}), jeq({'accent': 'custom', 'accentCustom': '#ff00aa'}));
      expect(sanitizeAccent({'accent': 'custom', 'accentCustom': 'red;}'}), jeq({'accent': 'custom'}));
    });
    test('keeps an unknown preset word (a newer app’s) but not junk', () {
      expect(sanitizeAccent(<String, dynamic>{'accent': 'mint'})['accent'], 'mint');
      expect(sanitizeAccent(<String, dynamic>{'accent': '"><script>'})['accent'], 'pink');
      expect(sanitizeAccent(<String, dynamic>{'accent': 42})['accent'], 'pink');
      expect(sanitizeAccent({'theme': 'dark'}), jeq({'theme': 'dark'}));
    });
  });

  // skipped (not ported — accentKey/accentValue, contrast/inkOn/readableIn/inkOnBoth/mix,
  // customAccentVars/applyAccent (DOM), accentPair): 'accentKey / accentValue' (1), 'contrast and
  // the text on the accent' (3), 'readable on the theme' (6), 'CSS for the own colour' (5),
  // 'the native countdown colours' (1).
  // skipped: 'sync with an app from before own colours' (4) and 'an own colour and a preset
  // picked on two devices' (2) — mergeStates / stampChange are sync-merge.js (Task 6).
}
