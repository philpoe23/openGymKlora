/* The coaching record's rules (training.js): what the client may see, what counts as unread,
   what an assignment has to be, and when one can still be taken back. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as T from '../training.js';

const plan = { opengym_plan: 1, routines: [{ id: 'r1', name: 'Lower A', ex: [{ id: '0001' }, { id: '0002' }] }], week: {}, customEx: [] };

test('normalize turns any file into a record with every list', () => {
  for (const raw of [null, 7, [], { notes: 'x', messages: [null, 1, { id: 'm' }] }]) {
    const r = T.normalize(raw);
    assert.ok(Array.isArray(r.notes) && Array.isArray(r.assignments) && Array.isArray(r.messages));
    assert.ok(r.messages.every(m => typeof m === 'object'));
  }
});

test('the client view never carries the trainer notes', () => {
  const r = T.normalize(null);
  T.addNote(r, 'knee is sore, keep squats light');
  T.addMessage(r, 'trainer', 'Great week!');
  const v = T.clientView(r);
  assert.equal(JSON.stringify(v).includes('knee'), false);
  assert.equal(v.messages.length, 1);
});

test('unread counts only the other side, since that side last looked', () => {
  const r = T.normalize(null);
  T.addMessage(r, 'client', 'Done leg day', 1000);
  T.addMessage(r, 'client', 'Felt strong', 2000);
  assert.equal(T.unreadFor(r, 'trainer'), 2);
  assert.equal(T.unreadFor(r, 'client'), 0);
  T.addMessage(r, 'trainer', 'Nice', 3000);
  assert.equal(T.unreadFor(r, 'trainer'), 0, 'replying reads the thread');
  assert.equal(T.unreadFor(r, 'client'), 1);
});

test('empty text is refused as the caller’s mistake', () => {
  const r = T.normalize(null);
  assert.throws(() => T.addNote(r, '   '), e => e.status === 400 && e.input);
  assert.throws(() => T.addMessage(r, 'client', ''), e => e.status === 400 && e.input);
});

test('an assignment has to be a plan bundle', () => {
  const r = T.normalize(null);
  for (const bad of [null, {}, { opengym_plan: 1, routines: [] }, { opengym_plan: 1, routines: [{ name: 'x' }] }, { routines: plan.routines }]) {
    assert.throws(() => T.addAssignment(r, { bundle: bad }), e => e.status === 400);
  }
  const a = T.addAssignment(r, { bundle: plan, note: 'Twice a week' });
  assert.equal(a.name, 'Lower A');
  assert.equal(a.exercises, 2);
  assert.equal(a.accepted, null);
});

test('only an assignment not yet added can be withdrawn', () => {
  const r = T.normalize(null);
  const a = T.addAssignment(r, { bundle: plan });
  const b = T.addAssignment(r, { bundle: plan });
  T.acceptAssignment(r, a.id, 5)
  assert.equal(T.withdrawAssignment(r, a.id), 'accepted');
  assert.equal(T.withdrawAssignment(r, b.id), 'ok');
  assert.equal(T.withdrawAssignment(r, b.id), 'missing');
  assert.equal(T.acceptAssignment(r, a.id, 9).accepted, 5, 'accepting twice keeps the first time');
});

test('the roster summary counts unread and pending', () => {
  const r = T.normalize(null);
  T.addAssignment(r, { bundle: plan });
  T.addMessage(r, 'client', 'x'.repeat(300));
  const s = T.rosterSummary(r);
  assert.equal(s.unread, 1);
  assert.equal(s.pending, 1);
  assert.equal(s.lastMessage.text.length, 120);
});

test('recentCount reads the workout date', () => {
  const now = Date.parse('2026-10-22T12:00:00Z');
  const w = [{ d: '2026-10-21' }, { d: '2026-10-10' }, { d: '2026-08-01' }, {}];
  assert.equal(T.recentCount(w, 7, now), 1);
  assert.equal(T.recentCount(w, 28, now), 2);
});

test('recentDays lists each trained date once, oldest first', () => {
  const now = Date.parse('2026-10-22T12:00:00Z');
  assert.deepEqual(T.recentDays([{ d: '2026-10-21' }, { d: '2026-10-10' }, { d: '2026-10-21' }, { d: '2026-08-01' }], 28, now), ['2026-10-10', '2026-10-21']);
});

test('an assignment with no exercises is refused', () => {
  const r = T.normalize(null);
  const empty = { ...plan, routines: [{ id: 'r1', name: 'Day 1', ex: [] }] };
  assert.throws(() => T.addAssignment(r, { bundle: empty }), e => e.status === 400);
  assert.equal(T.addAssignment(r, { bundle: plan, programId: 'p1' }).programId, 'p1');
});

test('programs are saved by id, newest first, and deleted', () => {
  const lib = T.normalizePrograms(null);
  const a = T.saveProgram(lib, { name: ' Strong glutes ', note: '8 weeks', bundle: plan }, 'pt', 1);
  const b = T.saveProgram(lib, { id: 'mine-2', name: '', bundle: plan }, 'pt', 2);
  assert.deepEqual(lib.programs.map(p => p.id), ['mine-2', a.id]);
  assert.equal(a.name, 'Strong glutes');
  assert.equal(b.name, 'Untitled program');
  const again = T.saveProgram(lib, { id: a.id, name: 'Strong glutes v2', bundle: plan }, 'other', 3);
  assert.equal(lib.programs.length, 2);
  assert.equal(again.created, 1);
  assert.equal(again.owner, 'pt', 'editing keeps who made it');
  assert.throws(() => T.saveProgram(lib, { bundle: { opengym_plan: 1, routines: [] } }, 'pt'), e => e.status === 400);
  assert.ok(T.deleteProgram(lib, 'mine-2'));
  assert.ok(!T.deleteProgram(lib, 'mine-2'));
  const row = T.programSummary(lib.programs[0], 3);
  assert.equal(row.bundle, undefined);
  assert.deepEqual([row.days, row.exercises, row.assigned, row.dayNames[0]], [1, 2, 3, 'Lower A']);
});
