// Port of frontend/src/lib/day-notes.test.js.
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/day_notes.dart';
import 'package:klora_app/engine/history.dart';

import '_helpers.dart';

void main() {
  group('day notes: reading and writing', () {
    test('reads a quick pick, a text, or both; junk and cleared entries read as none', () {
      expect(readDayNote({'tag': 'sick', '_ts': 1}), jeq({'tag': 'sick', 'text': ''}));
      expect(readDayNote({'text': '  Flight  ', '_ts': 1}), jeq({'tag': null, 'text': 'Flight'}));
      expect(readDayNote({'tag': 'travel', 'text': 'Lisbon'}), jeq({'tag': 'travel', 'text': 'Lisbon'}));
      expect(readDayNote({'tag': 'hungover', 'text': '   '}), isNull);
      expect(readDayNote({'_ts': 5}), isNull);
      for (final junk in [null, 'sick', 3, ['sick']]) {
        expect(readDayNote(junk), isNull);
      }
      expect(readDayNote({'text': 'x' * (NOTE_MAX + 50)})!['text'], hasLength(NOTE_MAX));
    });

    test('every quick pick has a label and an icon', () {
      for (final k in DAY_NOTE_TAGS) {
        expect(DAY_NOTE_LABEL[k], isNotEmpty);
        expect(DAY_NOTE_ICON[k], isNotEmpty);
      }
    });

    test('writes a stamped entry per day, and an empty note as a stamped clear', () {
      final m = withDayNote({'2026-10-01': {'tag': 'rest', '_ts': 3}}, '2026-10-02', {'tag': 'sick', 'text': ' flu '}, 10);
      expect(m, jeq({'2026-10-01': {'tag': 'rest', '_ts': 3}, '2026-10-02': {'tag': 'sick', 'text': 'flu', '_ts': 10}}));
      final cleared = withDayNote(m, '2026-10-02', {'tag': null, 'text': '  '}, 11);
      expect(cleared['2026-10-02'], jeq({'_ts': 11}));
      expect(withDayNote(null, '2026-10-03', null, 12), jeq({'2026-10-03': {'_ts': 12}}));
      expect(dayNoteOf({'dayNotes': cleared}, '2026-10-02'), isNull);
      expect(excusedOn({'dayNotes': cleared}, '2026-10-01'), isTrue);
      expect(excusedOn({}, '2026-10-01'), isFalse);
    });

    test('only today and earlier days take a note', () {
      expect(canNoteDay('2026-10-09', '2026-10-09'), isTrue);
      expect(canNoteDay('2026-09-30', '2026-10-09'), isTrue);
      expect(canNoteDay('2026-10-10', '2026-10-09'), isFalse);
      expect(canNoteDay('nope', '2026-10-09'), isFalse);
    });

    test('reads as one line: the pick, the text, or both', () {
      expect(dayNoteLine({'tag': 'sick', 'text': ''}), 'Sick');
      expect(dayNoteLine({'tag': null, 'text': 'Wedding'}), 'Wedding');
      expect(dayNoteLine({'tag': 'travel', 'text': 'Lisbon'}, (s) => (s as String).toUpperCase()), 'TRAVELLING · Lisbon');
      expect(dayNoteLine(null), '');
    });
  });

  // skipped: the 'day notes across devices' group (8 cases) — mergeStates / stampChange /
  // highestStamp / resetIdsOf / localExtras are sync-merge.js (Task 6), and the server parity
  // case reads api/sync-stamps.js.
  // skipped: 'the workout-day reminder on a noted day (mobile)' — buildReminderNotifications is
  // mobile.js (Capacitor), not part of the engine.
}
