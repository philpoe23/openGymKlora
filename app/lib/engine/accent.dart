// Port of frontend/src/lib/accent.js — only what the other engine modules use (sync-merge.js
// imports sanitizeAccent). The colour maths and the DOM helpers are not ported.
// ignore_for_file: constant_identifier_names

import 'js.dart';

const String DEFAULT_ACCENT = 'pink';
const String CUSTOM = 'custom';

final _hex = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);
final _key = RegExp(r'^[a-z][a-z0-9-]{0,23}$');

/// '#rrggbb' in lowercase, or null for anything else.
String? cleanHex(dynamic v) => v is String && _hex.hasMatch(v.trim()) ? v.trim().toLowerCase() : null;

/// A copy's accent fields made safe, in place: a malformed `accentCustom` is dropped and an
/// `accent` that is not even a word goes back to the default. Returns the copy.
dynamic sanitizeAccent(dynamic s) {
  if (!truthy(s) || s is! Map) return s;
  if (s.containsKey('accentCustom')) {
    final hex = cleanHex(s['accentCustom']);
    if (hex != null) {
      s['accentCustom'] = hex;
    } else {
      s.remove('accentCustom');
    }
  }
  if (s.containsKey('accent')) {
    final a = s['accent'];
    if (!(a is String && _key.hasMatch(a))) s['accent'] = DEFAULT_ACCENT;
  }
  return s;
}
