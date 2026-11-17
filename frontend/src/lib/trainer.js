// Klora Fitness: the trainer's roster and the client's side of it.
//
// The server (api/training.js) keeps the record; this decides what the trainer looks at first.
// A roster is sorted by who needs her today, not by name: an unread check-in first, then anyone
// who has gone quiet, then everyone else by their last workout.

import { api } from './api.js'
import { buildPlanBundle, parsePlan } from './plan-share.js'
import { uid } from './format.js'
import { DEFAULT_GLYPH } from './glyphs.js'

const DAY = 86400000

/** Whole days since an ISO date (YYYY-MM-DD), or null when there is none. */
export function daysSince(iso, now = Date.now()) {
  if (typeof iso !== 'string' || !/^\d{4}-\d{2}-\d{2}/.test(iso)) return null
  const then = Date.parse(iso.slice(0, 10) + 'T00:00:00')
  const today = new Date(now); today.setHours(0, 0, 0, 0)
  return Math.max(0, Math.round((today.getTime() - then) / DAY))
}

/**
 * One client's standing, the word the roster prints beside them:
 *  - 'needs-you'  an unread check-in is waiting
 *  - 'new'        never logged a workout
 *  - 'quiet'      nothing logged for `quietDays` days or more
 *  - 'on-track'   trained in the last week
 *  - 'drifting'   in between
 */
export function standing(c, now = Date.now(), quietDays = 10) {
  if (c.unread > 0) return 'needs-you'
  const d = daysSince(c.lastWorkout, now)
  if (d === null) return 'new'
  if (d >= quietDays) return 'quiet'
  if (c.week > 0) return 'on-track'
  return 'drifting'
}

const RANK = { 'needs-you': 0, quiet: 1, drifting: 2, new: 3, 'on-track': 4 }

/** The roster in the order she should look at it. Ties go to the longer silence, then by name. */
export function sortRoster(clients, now = Date.now()) {
  return [...clients].sort((a, b) => {
    const r = RANK[standing(a, now)] - RANK[standing(b, now)]
    if (r) return r
    const da = daysSince(a.lastWorkout, now) ?? -1, db = daysSince(b.lastWorkout, now) ?? -1
    if (da !== db) return db - da
    return String(a.name).localeCompare(String(b.name))
  })
}

/** Headline counts across the book. */
export function rosterTotals(clients, now = Date.now()) {
  const t = { clients: clients.length, needsYou: 0, quiet: 0, trainedThisWeek: 0, sessionsThisWeek: 0 }
  for (const c of clients) {
    const s = standing(c, now)
    if (s === 'needs-you') t.needsYou++
    if (s === 'quiet') t.quiet++
    if (c.week > 0) t.trainedThisWeek++
    t.sessionsThisWeek += c.week || 0
  }
  return t
}

/** A plan bundle holding only the routines picked (by id), and no week schedule. */
export function pickRoutines(bundle, ids) {
  const keep = new Set(ids)
  const routines = bundle.routines.filter(r => keep.has(r.id))
  const used = new Set(routines.flatMap(r => r.ex.map(e => e.id)))
  return { ...bundle, week: {}, routines, customEx: (bundle.customEx || []).filter(c => used.has(c.id)) }
}

const post = (path, body) => api(path, { method: 'POST', body: JSON.stringify(body) })

export const trainerApi = {
  clients: () => api('/api/trainer/clients'),
  client: id => api('/api/trainer/client?id=' + encodeURIComponent(id)),
  progress: id => api('/api/admin/user?id=' + encodeURIComponent(id)),
  addNote: (id, text) => post('/api/trainer/client/note', { id, text }),
  deleteNote: (id, noteId) => post('/api/trainer/client/note/delete', { id, noteId }),
  assign: (id, { name, note, bundle, programId }) => post('/api/trainer/client/assign', { id, name, note, bundle, programId }),
  withdraw: (id, assignmentId) => post('/api/trainer/client/assign/withdraw', { id, assignmentId }),
  message: (id, text) => post('/api/trainer/client/message', { id, text }),
  invites: () => api('/api/admin/invites'),
  newInvite: note => post('/api/admin/invites/new', { note })
}

export const programApi = {
  list: () => api('/api/trainer/programs'),
  get: id => api('/api/trainer/program?id=' + encodeURIComponent(id)),
  save: ({ id, name, note, bundle }) => post('/api/trainer/program/save', { id, name, note, bundle }),
  remove: id => post('/api/trainer/program/delete', { id })
}

/* ---------- programs: what the trainer builds once and sends to many ----------
 * A program is edited as a draft { id, name, note, days }, each day a routine in the shape the
 * routine editor writes ({ id, name, emoji, prog?, ex }). It is stored and sent as a plan bundle,
 * the same file a shared plan is, so a client adds it through the import merge they already have.
 */

export const newDay = n => ({ id: uid(), name: 'Day ' + n, emoji: DEFAULT_GLYPH, ex: [] })

export const newProgram = () => ({ id: uid(), name: '', note: '', days: [newDay(1)] })

/** The plan bundle for a draft: its days and the custom exercises they use, no week schedule. */
export function programBundle(S, draft) {
  const b = buildPlanBundle({ unit: S.unit, customEx: S.customEx, routines: draft.days, week: {} }, draft.name)
  return { ...b, week: {} }
}

/** A stored program back into a draft, its weights in the trainer's unit. */
export function programDraft(program, unit = 'kg') {
  const plan = parsePlan(program.bundle, unit)
  return { id: program.id, name: program.name || '', note: program.note || '', days: plan.routines }
}

/** A copy of one day, the exercises and their superset links kept, under a fresh id. */
export function copyDay(day, name) {
  const links = {}
  return {
    ...structuredClone(day), id: uid(), name,
    ex: day.ex.map(e => (e.sg ? { ...structuredClone(e), sg: (links[e.sg] ||= 'sg' + uid()) } : structuredClone(e)))
  }
}

export const programExercises = draft => draft.days.reduce((n, d) => n + d.ex.length, 0)

export const clientApi = {
  training: (read = false) => api('/api/client/training' + (read ? '?read=1' : '')),
  message: text => post('/api/client/message', { text }),
  accept: assignmentId => post('/api/client/assignment/accept', { assignmentId })
}

/**
 * One rack colour per client (0..5), handed out in sign-up order so the first six clients never
 * share one; only a seventh client repeats a colour. Stable: a new client never recolours anyone.
 */
export function tierMap(clients) {
  const order = [...clients].sort((a, b) => String(a.created || '').localeCompare(String(b.created || '')) || String(a.id).localeCompare(String(b.id)))
  return Object.fromEntries(order.map((c, i) => [c.id, i % 6]))
}

/** The last `n` days ending today, oldest first, each { iso, trained }. */
export function dayRack(days, n = 7, now = Date.now()) {
  const set = new Set(days || [])
  const out = []
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(now); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() - i)
    const iso = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0')
    out.push({ iso, trained: set.has(iso) })
  }
  return out
}
