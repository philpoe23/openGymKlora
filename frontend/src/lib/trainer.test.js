import { describe, it, expect } from 'vitest'
import { daysSince, standing, sortRoster, rosterTotals, pickRoutines } from './trainer.js'

const NOW = new Date('2026-10-22T15:00:00').getTime()

describe('daysSince', () => {
  it('counts whole calendar days', () => {
    expect(daysSince('2026-10-22', NOW)).toBe(0)
    expect(daysSince('2026-10-21', NOW)).toBe(1)
    expect(daysSince('2026-10-01', NOW)).toBe(21)
  })
  it('is null without a date', () => {
    expect(daysSince(null, NOW)).toBeNull()
    expect(daysSince('soon', NOW)).toBeNull()
  })
})

describe('standing', () => {
  it('an unread check-in outranks everything', () => {
    expect(standing({ unread: 1, lastWorkout: '2026-10-22', week: 3 }, NOW)).toBe('needs-you')
  })
  it('reads the last workout', () => {
    expect(standing({ lastWorkout: null }, NOW)).toBe('new')
    expect(standing({ lastWorkout: '2026-10-05', week: 0 }, NOW)).toBe('quiet')
    expect(standing({ lastWorkout: '2026-10-20', week: 2 }, NOW)).toBe('on-track')
    expect(standing({ lastWorkout: '2026-10-14', week: 0 }, NOW)).toBe('drifting')
  })
})

describe('sortRoster', () => {
  it('puts who needs her first, the longest silence ahead of a shorter one', () => {
    const roster = [
      { name: 'Ana', lastWorkout: '2026-10-21', week: 2 },
      { name: 'Bea', lastWorkout: '2026-09-30', week: 0 },
      { name: 'Cleo', lastWorkout: '2026-10-21', week: 1, unread: 2 },
      { name: 'Dee', lastWorkout: '2026-10-08', week: 0 },
      { name: 'Eve', lastWorkout: null }
    ]
    expect(sortRoster(roster, NOW).map(c => c.name)).toEqual(['Cleo', 'Bea', 'Dee', 'Eve', 'Ana'])
  })
})

describe('rosterTotals', () => {
  it('adds up the book', () => {
    const t = rosterTotals([
      { lastWorkout: '2026-10-21', week: 2 },
      { lastWorkout: '2026-09-01', week: 0, unread: 1 },
      { lastWorkout: '2026-09-01', week: 0 }
    ], NOW)
    expect(t).toEqual({ clients: 3, needsYou: 1, quiet: 1, trainedThisWeek: 1, sessionsThisWeek: 2 })
  })
})

describe('pickRoutines', () => {
  it('keeps the picked routines and only the custom exercises they use', () => {
    const b = {
      opengym_plan: 1, week: { 1: ['a'] },
      routines: [{ id: 'a', ex: [{ id: 'c1' }] }, { id: 'b', ex: [{ id: 'c2' }] }],
      customEx: [{ id: 'c1' }, { id: 'c2' }]
    }
    const p = pickRoutines(b, ['a'])
    expect(p.routines.map(r => r.id)).toEqual(['a'])
    expect(p.customEx).toEqual([{ id: 'c1' }])
    expect(p.week).toEqual({})
  })
})

import { tierMap, dayRack } from './trainer.js'

describe('tierMap', () => {
  it('gives the first six clients six different colours, in sign-up order', () => {
    const cs = Array.from({ length: 7 }, (_, i) => ({ id: 'c' + i, created: '2026-01-0' + (i + 1) }))
    const m = tierMap([...cs].reverse())
    expect(new Set(cs.slice(0, 6).map(c => m[c.id])).size).toBe(6)
    expect(m.c0).toBe(0)
    expect(m.c6).toBe(0)
  })
})

describe('dayRack', () => {
  it('marks the trained days of the last week, today last', () => {
    const r = dayRack(['2026-10-22', '2026-10-17', '2026-10-01'], 7, NOW)
    expect(r.map(d => d.iso)).toEqual(['2026-10-16', '2026-10-17', '2026-10-18', '2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22'])
    expect(r.filter(d => d.trained).map(d => d.iso)).toEqual(['2026-10-17', '2026-10-22'])
  })
})

import { newProgram, programBundle, programDraft, copyDay, programExercises } from './trainer.js'

describe('programs', () => {
  const S = { unit: 'kg', customEx: [{ id: 'cx1', n: 'Hip thrust machine', bp: 'upper legs', custom: true }, { id: 'cx2', n: 'Unused', bp: 'back' }], routines: [{ id: 'mine', name: 'Her own', ex: [] }], week: { 1: ['mine'] } }
  const draft = () => ({
    id: 'p1', name: 'Glute builder', note: '3x a week',
    days: [
      { id: 'd1', name: 'Day 1', emoji: 'figureStrength', ex: [{ id: '1000', sets: 3, reps: 10, weight: 40 }, { id: 'cx1', sets: 4, reps: 8, weight: 60, sg: 'a' }, { id: '1001', sets: 4, reps: 8, sg: 'a' }] },
      { id: 'd2', name: 'Day 2', emoji: 'figureStrength', prog: 'double', ex: [{ id: '1002', sets: 2, reps: 15 }] }
    ]
  })

  it('a new program starts with one empty day', () => {
    const p = newProgram()
    expect(p.days.map(d => d.name)).toEqual(['Day 1'])
    expect(programExercises(p)).toBe(0)
  })

  it('bundles only the program days and the customs they use, never her own plan or week', () => {
    const b = programBundle(S, draft())
    expect(b.opengym_plan).toBeTruthy()
    expect(b.routines.map(r => r.name)).toEqual(['Day 1', 'Day 2'])
    expect(b.week).toEqual({})
    expect(b.customEx.map(c => c.id)).toEqual(['cx1'])
    expect(b.routines[1].prog).toBe('double')
  })

  it('round-trips through the stored bundle, converting to the reader unit', () => {
    const stored = { id: 'p1', name: 'Glute builder', note: '3x a week', bundle: programBundle(S, draft()) }
    const back = programDraft(stored, 'kg')
    expect(back.days.map(d => d.ex.length)).toEqual([3, 1])
    expect(back.days[0].ex[0].weight).toBe(40)
    expect(back.note).toBe('3x a week')
    expect(programDraft(stored, 'lb').days[0].ex[0].weight).toBeGreaterThan(80)
  })

  it('copying a day gives it its own id and its own superset links', () => {
    const d = draft().days[0]
    const c = copyDay(d, 'Day 3')
    expect(c.id).not.toBe(d.id)
    expect(c.name).toBe('Day 3')
    expect(c.ex[1].sg).toBe(c.ex[2].sg)
    expect(c.ex[1].sg).not.toBe('a')
    c.ex[0].sets = 9
    expect(d.ex[0].sets).toBe(3)
  })
})
