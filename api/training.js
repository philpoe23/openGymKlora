/* Trainer ↔ client coaching record (Klora Fitness).
 *
 * One file per client, `training-<uid>.json` beside their state file: the trainer's private
 * notes, the routines she has sent them, and the check-in thread between the two. Kept out of
 * the client's state document on purpose: that document is the client's own, synced from their
 * devices with its own write ids, and a server-side write into it would race their next push.
 * An assignment is a plan bundle (the plan-share file format) the client adds to their own plan
 * from their device, through the same merge an imported plan file takes.
 *
 * Everything here but `createTrainingStore` is pure, so the rules have tests of their own.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const LIMITS = {
  noteChars: 2000, messageChars: 1000, nameChars: 60, assignNoteChars: 500,
  notes: 200, messages: 500, assignments: 100, bundleBytes: 200_000,
  programs: 200, programNoteChars: 1000
};

const id = () => crypto.randomBytes(8).toString('base64url');
const str = v => (typeof v === 'string' ? v : '');
const list = v => (Array.isArray(v) ? v.filter(x => x && typeof x === 'object' && !Array.isArray(x)) : []);

/** A record as read from disk, every list present and every entry an object. */
export function normalize(raw) {
  const r = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  const seen = r.seen && typeof r.seen === 'object' ? r.seen : {};
  return {
    notes: list(r.notes), assignments: list(r.assignments), messages: list(r.messages),
    seen: { trainer: +seen.trainer || 0, client: +seen.client || 0 }
  };
}

// Newest kept when a list is full: the thread is a conversation, not an archive.
const capped = (arr, n) => (arr.length > n ? arr.slice(arr.length - n) : arr);

export function addNote(rec, textIn, now = Date.now()) {
  const text = str(textIn).trim().slice(0, LIMITS.noteChars);
  if (!text) throw Object.assign(new Error('note is empty'), { status: 400, input: true });
  const note = { id: id(), text, at: now };
  rec.notes = capped([...rec.notes, note], LIMITS.notes);
  return note;
}

export function deleteNote(rec, noteId) {
  const before = rec.notes.length;
  rec.notes = rec.notes.filter(n => n.id !== noteId);
  return rec.notes.length !== before;
}

export function addMessage(rec, from, textIn, now = Date.now()) {
  if (from !== 'client' && from !== 'trainer') throw new Error('bad sender');
  const text = str(textIn).trim().slice(0, LIMITS.messageChars);
  if (!text) throw Object.assign(new Error('message is empty'), { status: 400, input: true });
  const msg = { id: id(), from, text, at: now };
  rec.messages = capped([...rec.messages, msg], LIMITS.messages);
  // Writing in the thread means having read it.
  rec.seen[from] = now;
  return msg;
}

/** A plan bundle as the plan-share format writes it; refused if it is not one, or too big. */
export function validBundle(bundle) {
  if (!bundle || typeof bundle !== 'object' || Array.isArray(bundle)) return false;
  if (!bundle.opengym_plan || !Array.isArray(bundle.routines) || !bundle.routines.length) return false;
  if (!bundle.routines.every(r => r && typeof r === 'object' && Array.isArray(r.ex))) return false;
  return Buffer.byteLength(JSON.stringify(bundle)) <= LIMITS.bundleBytes;
}

const exerciseCount = bundle => bundle.routines.reduce((n, r) => n + r.ex.length, 0);

export function addAssignment(rec, { name, note, bundle, programId }, now = Date.now()) {
  if (!validBundle(bundle)) throw Object.assign(new Error('not a plan'), { status: 400, input: true });
  if (!exerciseCount(bundle)) throw Object.assign(new Error('there are no exercises in it yet'), { status: 400, input: true });
  const a = {
    id: id(), at: now,
    name: str(name).trim().slice(0, LIMITS.nameChars) || str(bundle.routines[0]?.name).slice(0, LIMITS.nameChars) || 'Routine',
    note: str(note).trim().slice(0, LIMITS.assignNoteChars),
    routines: bundle.routines.length,
    exercises: exerciseCount(bundle),
    ...(str(programId) ? { programId: str(programId).slice(0, 40) } : {}),
    bundle, accepted: null
  };
  rec.assignments = capped([...rec.assignments, a], LIMITS.assignments);
  return a;
}

/** Only one the client has not added yet can be taken back. */
export function withdrawAssignment(rec, assignmentId) {
  const a = rec.assignments.find(x => x.id === assignmentId);
  if (!a) return 'missing';
  if (a.accepted) return 'accepted';
  rec.assignments = rec.assignments.filter(x => x !== a);
  return 'ok';
}

export function acceptAssignment(rec, assignmentId, now = Date.now()) {
  const a = rec.assignments.find(x => x.id === assignmentId);
  if (!a) return null;
  if (!a.accepted) a.accepted = now;
  return a;
}

/** Messages the other side wrote since `who` last looked. */
export const unreadFor = (rec, who) =>
  rec.messages.filter(m => m.from !== who && m.at > (rec.seen[who] || 0)).length;

/** What the client gets: everything but the trainer's private notes. */
export function clientView(rec) {
  return {
    assignments: [...rec.assignments].reverse(),
    messages: rec.messages,
    unread: unreadFor(rec, 'client')
  };
}

/** One roster row's coaching half (the training half comes from the state file). */
export function rosterSummary(rec) {
  const last = rec.messages[rec.messages.length - 1] || null;
  return {
    unread: unreadFor(rec, 'trainer'),
    pending: rec.assignments.filter(a => !a.accepted).length,
    lastMessage: last ? { from: last.from, text: last.text.slice(0, 120), at: last.at } : null,
    notes: rec.notes.length
  };
}

/** The distinct dates (YYYY-MM-DD) trained in the last `days` days, oldest first. */
export function recentDays(workouts, days, now = Date.now()) {
  const since = new Date(now - days * 86400000).toISOString().slice(0, 10);
  return [...new Set(workouts.map(w => w.d).filter(d => typeof d === 'string' && d.slice(0, 10) >= since).map(d => d.slice(0, 10)))].sort();
}

/** Workouts logged in the last `days` days, by the workout's own date (`d`, YYYY-MM-DD). */
export function recentCount(workouts, days, now = Date.now()) {
  const since = new Date(now - days * 86400000).toISOString().slice(0, 10);
  return workouts.filter(w => typeof w.d === 'string' && w.d >= since).length;
}

/* ---------- the trainer's program library ----------
 * Programs she builds once and hands to any number of clients: `programs.json`, one list for the
 * instance. A program is a plan bundle plus a name and a description; assigning one copies its
 * bundle into the client's record, so editing the program later never changes what a client has.
 */

export function normalizePrograms(raw) {
  const r = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  return { programs: list(r.programs).filter(p => typeof p.id === 'string' && validBundle(p.bundle)) };
}

/** Create or replace one program (by id); a new one goes to the top of the list. */
export function saveProgram(lib, { id: pid, name, note, bundle }, owner, now = Date.now()) {
  if (!validBundle(bundle)) throw Object.assign(new Error('a program needs at least one day'), { status: 400, input: true });
  const key = str(pid).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 40) || id();
  const had = lib.programs.find(p => p.id === key);
  if (!had && lib.programs.length >= LIMITS.programs) throw Object.assign(new Error('the program library is full'), { status: 400, input: true });
  const program = {
    id: key, owner: had?.owner || owner,
    name: str(name).trim().slice(0, LIMITS.nameChars) || 'Untitled program',
    note: str(note).trim().slice(0, LIMITS.programNoteChars),
    bundle, created: had?.created || now, updated: now
  };
  lib.programs = had ? lib.programs.map(p => (p === had ? program : p)) : [program, ...lib.programs];
  return program;
}

export function deleteProgram(lib, pid) {
  const before = lib.programs.length;
  lib.programs = lib.programs.filter(p => p.id !== pid);
  return lib.programs.length !== before;
}

/** A library row: what the list shows, without the bundle. `assigned` counts clients holding it. */
export function programSummary(p, assigned = 0) {
  return {
    id: p.id, name: p.name, note: p.note, created: p.created, updated: p.updated,
    days: p.bundle.routines.length, exercises: exerciseCount(p.bundle),
    dayNames: p.bundle.routines.map(r => str(r.name).slice(0, LIMITS.nameChars)), assigned
  };
}

export function createProgramStore(dataDir, write) {
  const file = path.join(dataDir, 'programs.json');
  return {
    read() {
      try { return normalizePrograms(JSON.parse(fs.readFileSync(file, 'utf8'))); }
      catch { return normalizePrograms(null); }
    },
    save(lib) { write(file, JSON.stringify(lib)); }
  };
}

export function createTrainingStore(dataDir, write) {
  const file = uid => path.join(dataDir, 'training-' + uid.replace(/[^a-zA-Z0-9_-]/g, '') + '.json');
  return {
    read(uid) {
      try { return normalize(JSON.parse(fs.readFileSync(file(uid), 'utf8'))); }
      catch { return normalize(null); }
    },
    save(uid, rec) { write(file(uid), JSON.stringify(rec)); },
    remove(uid) { try { fs.unlinkSync(file(uid)); } catch { /* none kept */ } }
  };
}
