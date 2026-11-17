// Port of frontend/src/lib/day-notes.js — a note on a day you did not train (#261).
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'format.dart';
import 'history.dart';
import 'js.dart';

const List<String> DAY_NOTE_TAGS = ['sick', 'travel', 'rest', 'injured'];
const Map<String, String> DAY_NOTE_LABEL = {'sick': 'Sick', 'travel': 'Travelling', 'rest': 'Rest day', 'injured': 'Injured'};
const Map<String, String> DAY_NOTE_ICON = {'sick': 'cloud', 'travel': 'globe', 'rest': 'moon', 'injured': 'warning'};

final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A stored entry read back: { tag, text }, or null for none or a cleared one.
JMap? readDayNote(dynamic entry) {
  if (entry is! Map) return null;
  final tag = DAY_NOTE_TAGS.contains(entry['tag']) ? entry['tag'] as String : null;
  final raw = entry['text'];
  var text = raw is String ? raw.trim() : '';
  if (text.length > NOTE_MAX) text = text.substring(0, NOTE_MAX);
  return tag != null || text.isNotEmpty ? {'tag': tag, 'text': text} : null;
}

JMap? dayNoteOf(dynamic S, dynamic iso) {
  final m = at(S, 'dayNotes');
  return readDayNote(m is Map ? m[iso] : null);
}

bool excusedOn(dynamic S, dynamic iso) => dayNoteOf(S, iso) != null;

bool canNoteDay(dynamic iso, [String? today]) =>
    _iso.hasMatch(truthy(iso) ? jsString(iso) : '') && (iso as String).compareTo(today ?? todayISO()) <= 0;

/// S.dayNotes with [iso] set to [note], stamped; an empty note is a stamped clear.
JMap withDayNote(dynamic map, String iso, dynamic note, [num? now]) {
  final ts = now ?? DateTime.now().millisecondsSinceEpoch;
  final clean = readDayNote(note);
  final entry = clean != null
      ? <String, dynamic>{
          if (truthy(clean['tag'])) 'tag': clean['tag'],
          if (truthy(clean['text'])) 'text': clean['text'],
          '_ts': ts,
        }
      : <String, dynamic>{'_ts': ts};
  return {...asMap(map is Map ? map : null), iso: entry};
}

/// The label a note reads as: its quick pick, its text, or both.
dynamic dayNoteLine(dynamic note, [dynamic Function(dynamic)? tr]) {
  tr ??= (s) => s;
  if (!truthy(note)) return '';
  final label = truthy(at(note, 'tag')) ? tr(DAY_NOTE_LABEL[note['tag']]) : '';
  return truthy(label) && truthy(at(note, 'text')) ? '${jsString(label)} · ${jsString(note['text'])}' : or(label, at(note, 'text'));
}
