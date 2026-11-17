// Generates app/test/fixtures/engine_crosscheck.json: realistic inputs run through the JS training
// engine (frontend/src/lib), recorded as [{ name, fn, args, result, ... }], so
// test/engine/crosscheck_test.dart can feed the same inputs to the Dart port and compare.
//
//   cd app && node tool/gen_fixtures.mjs && flutter test test/engine/crosscheck_test.dart
//
// Determinism:
//   - Every timestamp is a fixed epoch-ms literal; `now`/`end`/`wall`/`today` are passed in
//     explicitly wherever the API takes them. Date.now() is pinned below as a backstop.
//   - Two outputs cannot be pinned on the Dart side (it reads DateTime.now()/Random directly):
//     buildPlanBundle's `exported` (todayISO) is masked on both sides (`mask`), and mergePlan's
//     fresh routine/custom ids (uid) are renamed to NEW1, NEW2, ... on both sides (`freshIds`).
//   - Local-time readers (weekKey, `new Date(iso + 'T12:00:00').getDay()`, isoOf) use the
//     machine's time zone on both sides. The fixtures only use noon-anchored ISO dates, so they
//     hold in any zone; regenerate and test on the same machine if that ever changes.
//
// Args are serialised BEFORE the call (the function then runs on a JSON round-trip of them, so
// the JS side sees exactly what the Dart side will: no undefined, no shared references). An
// in-place function records `{ returned, mutated }` and is marked `mutates: true`.

import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

// Minimal browser globals some modules touch at import time.
const mem = new Map()
globalThis.localStorage ??= {
  getItem: k => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, String(v)),
  removeItem: k => mem.delete(k), clear: () => mem.clear(),
}
const FIXED_NOW = 1794657600000 // 2026-11-14T12:00:00Z
Date.now = () => FIXED_NOW

const here = dirname(fileURLToPath(import.meta.url))
const lib = resolve(here, '../../frontend/src/lib')
const load = f => import(pathToFileURL(resolve(lib, f)).href)

const progression = await load('progression.js')
const onerm = await load('onerm.js')
const finish = await load('finish-workout.js')
const history = await load('history.js')
const sessionMerge = await load('session-merge.js')
const syncMerge = await load('sync-merge.js')
const planShare = await load('plan-share.js')
const queue = await load('queue.js')

const FNS = {
  'progression.nextPrescription': progression.nextPrescription,
  'progression.applyPrescription': progression.applyPrescription,
  'onerm.estimate1RM': onerm.estimate1RM,
  'onerm.bestSetOf': onerm.bestSetOf,
  'onerm.e1rmSeries': onerm.e1rmSeries,
  'onerm.best1RM': onerm.best1RM,
  'onerm.is1RMRecord': onerm.is1RMRecord,
  'finish.sessionEnd': finish.sessionEnd,
  'finish.buildCompletedWorkout': finish.buildCompletedWorkout,
  'history.workoutVolume': history.workoutVolume,
  'history.bestWeightForEntry': history.bestWeightForEntry,
  'history.effectiveRoutineIds': history.effectiveRoutineIds,
  'sessionMerge.buildCombinedEntries': sessionMerge.buildCombinedEntries,
  'syncMerge.mergeStates': syncMerge.mergeStates,
  'syncMerge.stampChange': syncMerge.stampChange,
  'planShare.buildPlanBundle': planShare.buildPlanBundle,
  'planShare.parsePlan': planShare.parsePlan,
  'planShare.mergePlan': planShare.mergePlan,
  'queue.queueView': queue.queueView,
  'queue.weekTally': queue.weekTally,
}

const json = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)))
const cases = []
const names = new Set()

/** Run `fn` on a JSON copy of `args` and record it. Returns the (JSON) result for chaining. */
function run(name, fn, args, opts = {}) {
  if (names.has(name)) throw new Error('duplicate case ' + name)
  names.add(name)
  if (!FNS[fn]) throw new Error('unknown fn ' + fn)
  const a = json(args)
  const callArgs = json(a)
  const before = opts.freshIds ? json(callArgs[0]) : null
  const ret = FNS[fn](...callArgs)
  let result = opts.mutates ? { returned: json(ret), mutated: json(callArgs[0]) } : json(ret)
  if (opts.mask) result = mask(result, opts.mask)
  if (opts.freshIds) result = renameFresh(result, before, opts.mutates)
  const rec = { name, fn, args: a, result }
  if (opts.mutates) rec.mutates = true
  if (opts.mask) rec.mask = opts.mask
  if (opts.freshIds) rec.freshIds = true
  cases.push(rec)
  return opts.mutates ? json(callArgs[0]) : json(ret)
}

// Same post-processing as crosscheck_test.dart's `_post`: keep the two in step.
function mask(v, paths) {
  const out = json(v)
  for (const p of paths) {
    const keys = p.split('.')
    let o = out
    for (const k of keys.slice(0, -1)) o = o?.[k]
    if (o && typeof o === 'object' && keys.at(-1) in o) o[keys.at(-1)] = '<masked>'
  }
  return out
}
function renameFresh(result, before, mutates) {
  const st = mutates ? result.mutated : result
  const old = new Set([...(before.routines || []), ...(before.customEx || [])].map(x => x?.id))
  const map = new Map()
  for (const x of [...(st.routines || []), ...(st.customEx || [])]) {
    if (x?.id != null && !old.has(x.id) && !map.has(x.id)) map.set(x.id, 'NEW' + (map.size + 1))
  }
  const walk = v => Array.isArray(v) ? v.map(walk)
    : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [map.get(k) ?? k, walk(x)]))
      : typeof v === 'string' && map.has(v) ? map.get(v) : v
  return walk(result)
}

/* ------------------------------------------------------------------ data builders */

const BENCH = '0025', SQUAT = '0043', DEADLIFT = '0032', ROW = '0027', CURL = '0294', LATERAL = '0334'
const CHINUP = '1326', PULLUP = '0652', PUSHUP = '0662', ASSIST_PULLUP = '0017', WPULLUP = '0841'
const PLANK = '0463', DB_BENCH = '0289'

const DAY = 86400000
const T0 = Date.UTC(2026, 9, 5, 17, 0, 0) // Mon 2026-10-05 17:00Z
const iso = i => new Date(Date.UTC(2026, 9, 5) + i * DAY).toISOString().slice(0, 10)

const warmups = (w, n = 2) => (w > 20 ? Array.from({ length: n }, (_, i) => ({ w: Math.round((w * (i + 1)) / (n + 1) / 2.5) * 2.5 || 20, r: 8 - i * 3, done: true, phase: 'warmup' })) : [])

/** A finished entry the way finishWorkout saves one: warm-ups, work rows, target, planned, rid. */
function entry(cfg, w, reps, { rid, warm = true, target, extra = {} } = {}) {
  const mode = history.modeOf(cfg)
  const work = reps.map(r => (mode === 'time'
    ? (r === null ? { sec: 0, w, done: false } : { sec: r, w, done: true })
    : (r === null ? { w, r: 0, done: false } : { w, r, done: true })))
  const sets = [...(warm && mode === 'reps' ? warmups(w) : []), ...work]
  return {
    id: cfg.id,
    sets,
    topW: w || null,
    target: target || (mode === 'time' ? { sets: cfg.sets, sec: cfg.sec, mode: 'time' } : { sets: cfg.sets, reps: cfg.reps, weight: w }),
    ...(rid ? { rid } : {}),
    planned: progression.plannedOf(cfg),
    ...extra,
  }
}

let wid = 0
function workout(i, entries, { rid, name = 'Session' } = {}) {
  wid++
  return {
    id: 'w' + wid, d: iso(i), start: T0 + i * DAY, end: T0 + i * DAY + 3600000,
    routineIds: rid ? [rid] : [], routineId: rid || null, name, bw: 80, entries, prs: [],
  }
}

/** S with one exercise's history: sessions = [[weight, ...reps], ...], every other day. */
function hist(cfg, sessions, { rid = 'rA', unit = 'kg', extra = {} } = {}) {
  wid = 0
  return {
    unit,
    workouts: sessions.map(([w, ...reps], i) => workout(i * 2, [entry(cfg, w, reps, { rid })], { rid })),
    routines: [{ id: rid, name: 'Day A', emoji: '💪', ex: [cfg] }],
    exWeights: {}, bodyweight: [{ d: iso(0), w: 80, t: T0 }], week: {}, dayPlan: {},
    ...extra,
  }
}

/* ------------------------------------------------------------------ progression */

const rA = cfg => ({ id: 'rA', name: 'Day A', ex: [cfg] })

{
  const cfg = { id: BENCH, sets: 3, reps: 5, weight: 60, prog: 'linear' }
  run('prog.linear.first', 'progression.nextPrescription', [hist(cfg, []), cfg, rA(cfg)])
  run('prog.linear.up', 'progression.nextPrescription', [hist(cfg, [[57.5, 5, 5, 5], [60, 5, 5, 5]]), cfg, rA(cfg)])
  run('prog.linear.hold', 'progression.nextPrescription', [hist(cfg, [[60, 5, 5, 5], [62.5, 5, 5, 3]]), cfg, rA(cfg)])
  run('prog.linear.deload', 'progression.nextPrescription', [hist(cfg, [[62.5, 5, 5, 5], [65, 5, 4, 4], [65, 5, 5, 3], [65, 4, 4, 3]]), cfg, rA(cfg)])
  run('prog.linear.unchecked-set', 'progression.nextPrescription', [hist(cfg, [[60, 5, 5, null]]), cfg, rA(cfg)])
  const sq = { id: SQUAT, sets: 5, reps: 5, weight: 100, prog: 'linear' }
  run('prog.linear.lower-body-step', 'progression.nextPrescription', [hist(sq, [[95, 5, 5, 5, 5, 5], [100, 5, 5, 5, 5, 5]]), sq, rA(sq)])
  const lb = { id: BENCH, sets: 3, reps: 5, weight: 135, prog: 'linear' }
  run('prog.linear.lb', 'progression.nextPrescription', [hist(lb, [[135, 5, 5, 5]], { unit: 'lb' }), lb, rA(lb)])
  const edited = { id: BENCH, sets: 4, reps: 8, weight: 50, prog: 'linear' }
  run('prog.linear.plan-changed', 'progression.nextPrescription', [hist(cfg, [[60, 5, 5, 5]]), edited, rA(edited)])
}
{
  const cfg = { id: ROW, sets: 3, reps: 5, weight: 50, prog: 'greyskull' }
  run('prog.greyskull.amrap-up', 'progression.nextPrescription', [hist(cfg, [[50, 5, 5, 12]]), cfg, rA(cfg)])
  run('prog.greyskull.up', 'progression.nextPrescription', [hist(cfg, [[50, 5, 5, 6]]), cfg, rA(cfg)])
  run('prog.greyskull.deload', 'progression.nextPrescription', [hist(cfg, [[50, 5, 5, 6], [52.5, 5, 4, 3]]), cfg, rA(cfg)])
}
{
  const cfg = { id: DB_BENCH, sets: 3, reps: 12, repsMin: 8, weight: 22, prog: 'double' }
  run('prog.double.climb', 'progression.nextPrescription', [hist(cfg, [[22, 9, 8, 8], [22, 10, 9, 9]]), cfg, rA(cfg)])
  run('prog.double.top-raise', 'progression.nextPrescription', [hist(cfg, [[22, 11, 11, 10], [22, 12, 12, 12]]), cfg, rA(cfg)])
  run('prog.double.stall-deload', 'progression.nextPrescription', [hist(cfg, [[24, 8, 7, 6], [24, 7, 7, 6], [24, 8, 6, 6], [24, 7, 6, 6]]), cfg, rA(cfg)])
  const curl = { id: CURL, sets: 3, reps: 12, repsMin: 8, weight: 12, prog: 'double' }
  run('prog.double.owned-dumbbells', 'progression.nextPrescription', [hist(curl, [[12, 12, 12, 12]], { extra: { dumbbells: { kg: { weights: [8, 10, 12, 14, 16], _ts: 100 } } } }), curl, rA(curl)])
}
{
  const cfg = { id: LATERAL, sets: 3, reps: 12, repsMin: 8, setsMax: 5, weight: 8, prog: 'triple' }
  run('prog.triple.first', 'progression.nextPrescription', [hist(cfg, []), cfg, rA(cfg)])
  run('prog.triple.climb', 'progression.nextPrescription', [hist(cfg, [[8, 8, 8, 8], [8, 9, 9, 9]]), cfg, rA(cfg)])
}
{
  const cfg = { id: PLANK, mode: 'time', sets: 3, sec: 45, prog: 'time' }
  run('prog.time.up', 'progression.nextPrescription', [hist(cfg, [[0, 45, 45, 45]]), cfg, rA(cfg)])
  run('prog.time.hold', 'progression.nextPrescription', [hist(cfg, [[0, 45, 45, 30]]), cfg, rA(cfg)])
  const c60 = { ...cfg, sec: 60 }
  run('prog.time.deload', 'progression.nextPrescription', [hist(c60, [[0, 60, 50, 40], [0, 60, 45, 40], [0, 55, 45, 40]]), c60, rA(c60)])
}
{
  const cfg = { id: CHINUP, sets: 3, reps: 8, repsMax: 12, prog: 'linear' }
  run('prog.bodyweight.reps-up', 'progression.nextPrescription', [hist(cfg, [[0, 8, 8, 8]]), cfg, rA(cfg)])
  run('prog.bodyweight.ceiling-adds-set', 'progression.nextPrescription', [hist({ ...cfg, reps: 12 }, [[0, 12, 12, 12]]), { ...cfg, reps: 12 }, rA({ ...cfg, reps: 12 })])
  const asst = { id: ASSIST_PULLUP, sets: 3, reps: 8, weight: 30, prog: 'linear' }
  run('prog.assisted.less-help', 'progression.nextPrescription', [hist(asst, [[30, 8, 8, 8]]), asst, rA(asst)])
  const off = { id: BENCH, sets: 3, reps: 5, weight: 60, prog: 'off' }
  run('prog.off', 'progression.nextPrescription', [hist(off, [[60, 5, 5, 5]]), off, rA(off)])
}
{
  // applyPrescription on built rows: warm-ups, one already-ticked row, growth by sets.
  const rows = [
    { w: 20, r: 8, done: false, phase: 'warmup' }, { w: 40, r: 5, done: false, phase: 'warmup' },
    { w: 60, r: 5, done: true }, { w: 60, r: 5, done: false }, { w: 60, r: 5, done: false },
  ]
  run('applyPrescription.up', 'progression.applyPrescription', [rows, { policy: 'linear', kind: 'up', weight: 62.5 }, 2.5, 20])
  run('applyPrescription.sets-grow', 'progression.applyPrescription', [[{ w: 0, r: 10, done: false }, { w: 0, r: 10, done: false }], { policy: 'linear', kind: 'up', weight: 0, reps: 8, sets: 3 }, 2.5, 0])
  run('applyPrescription.first-noop', 'progression.applyPrescription', [rows, { policy: 'linear', kind: 'first' }, 2.5, 20])
}

/* ------------------------------------------------------------------ onerm */

for (const f of [...Object.keys(onerm.FORMULAS), 'weighted']) run(`onerm.estimate.${f}`, 'onerm.estimate1RM', [100, 5, f, null])
run('onerm.estimate.weighted-rir', 'onerm.estimate1RM', [100, 6, 'weighted', 2])
run('onerm.estimate.single', 'onerm.estimate1RM', [142.5, 1, 'epley', null])
run('onerm.estimate.over-cap', 'onerm.estimate1RM', [60, 15, 'epley', null])
run('onerm.estimate.zero-load', 'onerm.estimate1RM', [0, 10, 'epley', null])
run('onerm.estimate.string-args', 'onerm.estimate1RM', ['82.5', '7', 'brzycki', null])
{
  const bench = entry({ id: BENCH, sets: 3, reps: 5 }, 100, [5, 5, 4])
  run('onerm.bestSetOf.weighted', 'onerm.bestSetOf', [bench, 'epley'])
  run('onerm.bestSetOf.weighted-rir', 'onerm.bestSetOf', [{ ...bench, sets: bench.sets.map((s, i) => (i === 3 ? { ...s, rir: 2 } : s)) }, 'weighted'])
  run('onerm.bestSetOf.bodyweight', 'onerm.bestSetOf', [entry({ id: CHINUP, sets: 3, reps: 8 }, 0, [10, 9, 8]), 'epley'])
  run('onerm.bestSetOf.weighted-pullup', 'onerm.bestSetOf', [entry({ id: WPULLUP, sets: 3, reps: 5 }, 20, [6, 5, 5]), 'brzycki'])
  run('onerm.bestSetOf.assisted', 'onerm.bestSetOf', [entry({ id: ASSIST_PULLUP, sets: 3, reps: 8 }, 30, [8, 8, 8]), 'epley'])
  run('onerm.bestSetOf.dumbbell', 'onerm.bestSetOf', [entry({ id: CURL, sets: 3, reps: 10 }, 16, [10, 9, 8]), 'mayhew'])

  const cfg = { id: BENCH, sets: 3, reps: 5, weight: 90 }
  const S = hist(cfg, [[90, 5, 5, 5], [92.5, 5, 5, 5], [95, 5, 5, 4], [95, 6, 5, 5]])
  S.workouts[1].entries.push(entry({ id: CURL, sets: 3, reps: 10 }, 14, [10, 10, 10], { rid: 'rA' }))
  run('onerm.e1rmSeries.bench', 'onerm.e1rmSeries', [S, BENCH, 'epley'])
  run('onerm.e1rmSeries.weighted', 'onerm.e1rmSeries', [S, BENCH, 'weighted'])
  run('onerm.best1RM.bench', 'onerm.best1RM', [S, BENCH, 'lander'])
  run('onerm.best1RM.formula-from-state', 'onerm.best1RM', [{ ...S, oneRmFormula: 'wathan' }, BENCH])
  run('onerm.is1RMRecord.yes', 'onerm.is1RMRecord', [S, BENCH, entry(cfg, 100, [5, 5, 5]), 'epley'])
  run('onerm.is1RMRecord.no', 'onerm.is1RMRecord', [S, BENCH, entry(cfg, 90, [5, 5, 5]), 'epley'])
  run('onerm.is1RMRecord.first-dumbbell', 'onerm.is1RMRecord', [S, DB_BENCH, entry({ id: DB_BENCH, sets: 3, reps: 10 }, 24, [10, 9, 8]), 'epley'])
  run('onerm.is1RMRecord.assisted', 'onerm.is1RMRecord', [S, ASSIST_PULLUP, entry({ id: ASSIST_PULLUP, sets: 3, reps: 8 }, 20, [8, 8, 8]), 'epley'])
}

/* ------------------------------------------------------------------ finish-workout */

{
  const at = k => T0 + 20 * DAY + k * 180000
  const active = {
    id: 'act1', d: iso(20), start: T0 + 20 * DAY - 300000, routineIds: ['rA'], name: 'Push A', bw: 81.2,
    note: '  good session  ',
    entries: [
      { id: BENCH, sg: 'g1', rid: 'rA', note: ' left shoulder ok ', notePin: true,
        target: { sets: 3, reps: 5, weight: 80 }, planned: { sets: 3, reps: 5, weight: 80 },
        sets: [
          { w: 40, r: 8, done: true, phase: 'warmup', at: at(0) },
          { w: 60, r: 3, done: true, phase: 'warmup', at: at(1) },
          { w: 80, r: 5, done: true, at: at(2), weightOrigin: 'manual' },
          { w: 80, r: 5, done: true, at: at(4) },
          { w: 80, r: 4, done: true, at: at(6), planSec: 120 },
        ] },
      { id: ROW, sg: 'g1', rid: 'rA', target: { sets: 3, reps: 8, weight: 60 }, planned: { sets: 3, reps: 8 },
        sets: [
          { w: 60, r: 8, done: true, at: at(3) },
          { w: 60, r: 8, done: true, at: at(5) },
          { w: 60, r: 7, done: false },
        ] },
      { id: CURL, rid: 'rA', target: { sets: 2, reps: 10, weight: 14 },
        sets: [
          { w: 14, r: 10, done: true, at: at(8) },
          { w: 14, r: 9, done: true, type: 'dropset', drops: [{ w: 10, r: 6 }, { w: 6, r: 8 }], at: at(9) },
        ] },
      // Nothing logged: drops out, and its superset partner is left a superset of one.
      { id: LATERAL, sg: 'g2', rid: 'rA', target: { sets: 3, reps: 12, weight: 8 }, sets: [{ w: 8, r: 12, done: false }] },
      { id: PUSHUP, sg: 'g2', rid: 'rA', noProg: true, target: { sets: 2, reps: 15 }, sets: [{ w: 0, r: 15, done: true, at: at(10) }, { w: 0, r: 12, done: true, at: at(11) }] },
    ],
  }
  run('finish.sessionEnd.forgotten', 'finish.sessionEnd', [active, at(11) + 5 * 3600000])
  run('finish.sessionEnd.on-time', 'finish.sessionEnd', [active, at(11) + 600000])
  const done = run('finish.buildCompletedWorkout', 'finish.buildCompletedWorkout', [active, { end: at(12), prs: [{ id: BENCH, w: 80, r: 5 }] }])
  run('history.workoutVolume.finished', 'history.workoutVolume', [done])
  run('history.bestWeightForEntry.bench', 'history.bestWeightForEntry', [done.entries[0]])
  run('history.bestWeightForEntry.dropset', 'history.bestWeightForEntry', [done.entries[2]])
  const legacy = { id: 'act2', d: iso(21), start: T0 + 21 * DAY, routineId: 'rB', name: 'Legs', bw: 81,
    entries: [{ id: SQUAT, sets: [{ w: 100, r: 5, done: true }, { w: 100, r: 5, done: true }], noProg: true }] }
  run('finish.buildCompletedWorkout.legacy-routineId', 'finish.buildCompletedWorkout', [legacy, { end: T0 + 21 * DAY + 3000000 }])
}

/* ------------------------------------------------------------------ session-merge */

{
  const bench = { id: BENCH, sets: 3, reps: 5, weight: 80, prog: 'linear', warmupSets: 2 }
  const row = { id: ROW, sets: 3, reps: 8, weight: 60, sg: 'g1' }
  const curl = { id: CURL, sets: 3, reps: 12, repsMin: 8, weight: 12, prog: 'double', sg: 'g1' }
  const plank = { id: PLANK, mode: 'time', sets: 2, sec: 45, prog: 'time' }
  const S = hist(bench, [[77.5, 5, 5, 5], [80, 5, 5, 5]], { extra: {} })
  S.routines = [
    { id: 'rA', name: 'Push', ex: [bench, row, curl] },
    { id: 'rC', name: 'Core', excludeFromProgression: true, ex: [plank] },
  ]
  S.workouts[1].entries.push(entry(curl, 12, [12, 11, 10], { rid: 'rA' }))
  run('sessionMerge.two-routines', 'sessionMerge.buildCombinedEntries', [S, ['rA', 'rC', 'rA', 'gone']])
  run('sessionMerge.single', 'sessionMerge.buildCombinedEntries', [S, 'rC'])
}

/* ------------------------------------------------------------------ sync-merge */

{
  const base = {
    unit: 'kg', _ts: 1000,
    routines: [
      { id: 'rA', name: 'Push', _ts: 500, ex: [{ id: BENCH, sets: 3, reps: 5, weight: 80 }] },
      { id: 'rB', name: 'Pull', _ts: 500, ex: [{ id: ROW, sets: 3, reps: 8, weight: 60 }] },
      { id: 'rC', name: 'Legs', _ts: 500, ex: [{ id: SQUAT, sets: 5, reps: 5, weight: 100 }] },
    ],
    workouts: [
      { id: 'w1', d: iso(0), start: T0, end: T0 + 3600000, routineIds: ['rA'], routineId: 'rA', name: 'Push', entries: [entry({ id: BENCH, sets: 3, reps: 5 }, 80, [5, 5, 5])], prs: [] },
    ],
    bodyweight: [{ d: iso(0), w: 80, t: 900 }],
    exWeights: { [BENCH]: { w: 80, d: iso(0) } },
    week: { 1: ['rA'], 3: ['rB'], 5: ['rC'] }, dayPlan: {}, favEx: [BENCH], restSec: 120,
  }
  // Phone: logs a workout, weighs in, renames Pull, removes Legs, newer overall.
  const phone = json(base)
  phone._ts = 3000
  phone.routines[1] = { ...phone.routines[1], name: 'Pull (heavy)', _ts: 2500 }
  phone.routines.splice(2, 1)
  phone.deleted = { routines: { rC: 2600 } }
  phone.workouts.push({ id: 'w2', d: iso(2), start: T0 + 2 * DAY, end: T0 + 2 * DAY + 3600000, routineIds: ['rB'], routineId: 'rB', name: 'Pull', entries: [entry({ id: ROW, sets: 3, reps: 8 }, 62.5, [8, 8, 8])], prs: [] })
  phone.bodyweight.push({ d: iso(2), w: 79.6, t: 2700 })
  phone.exWeights[ROW] = { w: 62.5, d: iso(2) }
  // Desktop: edits Push's reps, logs another workout, a different weigh-in, a new setting.
  const desk = json(base)
  desk._ts = 2000
  desk.routines[0] = { ...desk.routines[0], ex: [{ id: BENCH, sets: 4, reps: 6, weight: 75 }], _ts: 1900 }
  desk.workouts.push({ id: 'w3', d: iso(1), start: T0 + DAY, end: T0 + DAY + 3000000, routineIds: [], routineId: null, name: 'Freestyle', entries: [entry({ id: CURL, sets: 3, reps: 10 }, 14, [10, 10, 9])], prs: [] })
  desk.bodyweight[0] = { d: iso(0), w: 80.4, t: 1800 }
  desk.restSec = 90
  desk.edited = { restSec: 1950 }
  desk.favEx = [CURL]
  run('syncMerge.diverged', 'syncMerge.mergeStates', [phone, desk])
  run('syncMerge.diverged-reversed', 'syncMerge.mergeStates', [desk, phone])
  run('syncMerge.prefer-b', 'syncMerge.mergeStates', [phone, desk, { prefer: 'b' }])
  // A copy switched to lb meets the kg one.
  const lbCopy = json(desk)
  lbCopy.unit = 'lb'
  lbCopy.unitSet = { at: 2100, convert: true }
  lbCopy._ts = 2100
  lbCopy.routines[0].ex[0].weight = 165
  lbCopy.workouts = lbCopy.workouts.map(w => ({ ...w, entries: w.entries.map(e => ({ ...e, sets: e.sets.map(s => ({ ...s, w: Math.round(s.w * 2.20462 * 2) / 2 })) })) }))
  lbCopy.bodyweight = lbCopy.bodyweight.map(b => ({ ...b, w: Math.round(b.w * 2.20462 * 10) / 10 }))
  lbCopy.exWeights = { [BENCH]: { w: 175, d: iso(0) } }
  run('syncMerge.unit-difference', 'syncMerge.mergeStates', [phone, lbCopy])

  // stampChange: rename a routine, add a weigh-in, delete a workout, change a setting.
  const prev = json(base)
  const next = json(base)
  next.routines[0].name = 'Push (5x5)'
  next.bodyweight.push({ d: iso(3), w: 79.9, t: 1500 })
  next.workouts = []
  next.restSec = 150
  run('syncMerge.stampChange', 'syncMerge.stampChange', [prev, next, 1234567], { mutates: true })
  run('syncMerge.stampChange.clock-behind', 'syncMerge.stampChange', [phone, json(phone), 10], { mutates: true })
}

/* ------------------------------------------------------------------ plan-share */

{
  const S = {
    unit: 'kg',
    routines: [
      { id: 'rA', name: 'Upper', emoji: '💪', prog: 'double', ex: [
        { id: BENCH, sets: 3, reps: 10, repsMin: 6, weight: 70, warmupSets: 2, restSec: 150, sg: 'g1' },
        { id: ROW, sets: 3, reps: 10, repsMin: 6, weight: 60, sg: 'g1' },
        { id: 'cx1', sets: 3, reps: 12, weight: 20 },
      ] },
      { id: 'rB', name: 'Lower', emoji: '🦵', excludeFromProgression: true, ex: [
        { id: SQUAT, sets: 5, reps: 5, weight: 100, prog: 'linear' },
        { id: PLANK, mode: 'time', sets: 3, sec: 45 },
      ] },
    ],
    customEx: [
      { id: 'cx1', n: 'Landmine press', bp: 'shoulders', eq: 'barbell', tg: 'delts', primaries: ['delts'], secondaries: ['triceps'], custom: true },
      { id: 'cx2', n: 'Unused custom', bp: 'back', custom: true },
    ],
    week: { 1: ['rA'], 3: ['rB'], 5: ['rA', 'rB'] },
  }
  const bundle = run('planShare.buildPlanBundle', 'planShare.buildPlanBundle', [S, 'Upper/Lower'], { mask: ['exported'] })
  bundle.exported = '2026-11-14'
  const parsedKg = run('planShare.parsePlan.kg', 'planShare.parsePlan', [bundle, 'kg'])
  run('planShare.parsePlan.to-lb', 'planShare.parsePlan', [bundle, 'lb'])
  run('planShare.parsePlan.string-with-unknown-id', 'planShare.parsePlan', [JSON.stringify({ ...bundle, routines: [{ ...bundle.routines[0], ex: [...bundle.routines[0].ex, { id: 'nope-123', sets: 3 }] }] }), 'kg'])
  const dest = {
    unit: 'kg', routines: [{ id: 'mine', name: 'My day', ex: [{ id: CURL, sets: 3, reps: 10 }] }],
    customEx: [{ id: 'myLandmine', n: 'landmine press', bp: 'shoulders', custom: true }],
    week: { 0: ['mine'], 1: ['mine'] }, workouts: [],
  }
  run('planShare.mergePlan.schedule', 'planShare.mergePlan', [dest, parsedKg, { schedule: true }], { mutates: true, freshIds: true })
  run('planShare.mergePlan.no-schedule', 'planShare.mergePlan', [{ ...dest, customEx: [] }, parsedKg], { mutates: true, freshIds: true })
}

/* ------------------------------------------------------------------ queue / effectiveRoutineIds */

{
  const since = Date.UTC(2026, 10, 9, 8, 0, 0) // Mon 2026-11-09
  const S = {
    unit: 'kg', weekStart: 1,
    routines: [
      { id: 'q1', name: 'US W1 D1', ex: [] }, { id: 'q2', name: 'US W1 D2', ex: [] },
      { id: 'q3', name: 'US W1 D3', ex: [] }, { id: 'own', name: 'Core', ex: [] },
    ],
    queue: { ids: ['q1', 'q2', 'q3', 'q2', 'deleted'], since, startsOn: '2026-11-09', label: 'US W1' },
    workouts: [
      { id: 'x0', d: '2026-11-08', start: since - DAY, routineIds: ['q1'], name: 'US W1 D1', entries: [] },
      { id: 'x1', d: '2026-11-10', start: since + DAY, routineIds: ['q1', 'own'], name: 'US W1 D1 + Core', entries: [] },
      { id: 'x2', d: '2026-11-11', start: since + 2 * DAY, routineIds: [], name: 'Freestyle', entries: [] },
    ],
    week: { 3: ['own'], 6: ['own', 'q3'] },
    dayPlan: { '2026-11-14': 'q3' },
  }
  run('queue.queueView.pinned', 'queue.queueView', [S, '2026-11-12'])
  run('queue.queueView.waiting', 'queue.queueView', [{ ...S, queue: { ...S.queue, startsOn: '2026-11-16' } }, '2026-11-12'])
  run('queue.weekTally.queue', 'queue.weekTally', [S, '2026-11-12'])
  run('queue.weekTally.no-queue', 'queue.weekTally', [{ ...S, queue: null }, '2026-11-12'])
  run('history.effectiveRoutineIds.today', 'history.effectiveRoutineIds', [S, '2026-11-12', '2026-11-12'])
  run('history.effectiveRoutineIds.pinned-day', 'history.effectiveRoutineIds', [S, '2026-11-14', '2026-11-12'])
  run('history.effectiveRoutineIds.weekday', 'history.effectiveRoutineIds', [{ ...S, queue: null }, '2026-11-11', '2026-11-12'])
  run('history.effectiveRoutineIds.rest-override', 'history.effectiveRoutineIds', [{ ...S, dayPlan: { '2026-11-12': 'rest' } }, '2026-11-12', '2026-11-12'])
}

const out = resolve(here, '../test/fixtures/engine_crosscheck.json')
mkdirSync(dirname(out), { recursive: true })
writeFileSync(out, JSON.stringify(cases, null, 1) + '\n')
console.log(`wrote ${cases.length} cases to ${out}`)
