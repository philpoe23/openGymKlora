import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { exOr } from '../lib/exercises.js'
import { exerciseNameFor, exerciseNameClass } from '../lib/i18n.js'
import { exerciseNameText, fmtDate } from '../lib/format.js'
import { exLine, defaultConfig, cleanupSg, moveRoutineEntry } from '../lib/history.js'
import { speedUnitOf } from '../lib/speed.js'
import { POLICIES_FOR, POLICY_NAME, POLICY_DESC } from '../lib/progression.js'
import { programApi, trainerApi, newProgram, newDay, programBundle, programDraft, copyDay, programExercises, tierMap } from '../lib/trainer.js'
import { exercisePicker, exConfigSheet, confirmSheet } from '../sheets.jsx'
import { Thumb } from '../components/Media.jsx'
import Icon from '../components/Icon.jsx'
import { Button, SelectRow } from '../components/ui.jsx'
import { Avatar, TrainerSwitch } from './Trainer.jsx'

// Klora Fitness: the trainer's program library. She builds a program once (days of exercises,
// with sets, reps, weights and progression, through the same exercise sheets her own routines
// use) and sends it to any number of clients. Like the rest of her side it is English-only.

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`

/* --------------------------------------------------------------- library -- */

export default function Programs() {
  const nav = useNavigate()
  const [list, setList] = useState(null)
  const [error, setError] = useState(null)
  const load = () => programApi.list().then(d => { setList(d.programs); setError(null) }).catch(e => setError(e.message))
  useEffect(() => { load() }, [])

  return <div className="narrow">
    <div className="hdr">
      <div><h1>Programs</h1>
        <div className="sub">{list ? (list.length ? plural(list.length, 'program', 'programs') + ' in your library' : 'Build once, send to any client') : 'Loading your library…'}</div></div>
      <div className="hdr-actions">
        <button className="iconbtn" onClick={() => nav('/trainer/program/new')} aria-label="New program"><Icon name="plus" /></button>
      </div>
    </div>
    <TrainerSwitch value="programs" />

    {error && <div className="card small" style={{ color: 'var(--red)' }}>Couldn’t load your programs: {error}
      <div style={{ marginTop: 10 }}><Button size="sm" onClick={load}>Try again</Button></div></div>}

    {list && !list.length && <div className="tr-empty">
      <div className="kl-weights" aria-hidden="true"><span className="rk rk-lilac" /><span className="rk rk-butter" /><span className="rk rk-mint" /><span className="rk rk-rose" /></div>
      <h3>No programs yet</h3>
      <p>Lay out the days, pick the exercises and set the sets, reps and weights. Then send it to as many clients as you like.</p>
      <Button variant="primary" icon="plus" onClick={() => nav('/trainer/program/new')}>Build a program</Button>
    </div>}

    {!!list?.length && <>
      <div className="pg-list">
        {list.map(p => <button key={p.id} className="pg-card" onClick={() => nav('/trainer/program/' + encodeURIComponent(p.id))}>
          <span className="pg-card-t">{p.name}</span>
          <span className="pg-card-s">{plural(p.days, 'day', 'days')} · {plural(p.exercises, 'exercise', 'exercises')}
            {p.assigned ? ' · sent to ' + plural(p.assigned, 'client', 'clients') : ''}</span>
          {p.note && <span className="pg-card-n">{p.note}</span>}
          <span className="pg-days">{p.dayNames.slice(0, 6).map((d, i) => <span key={i} className="rk" data-tier={i % 6}>{d}</span>)}</span>
        </button>)}
      </div>
      <div style={{ height: 14 }} />
      <Button icon="plus" onClick={() => nav('/trainer/program/new')}>New program</Button>
    </>}
  </div>
}

/* ----------------------------------------------------------- send sheet -- */

function SendSheet({ close, draft, bundle, only, onSent }) {
  const toast = useUI(s => s.toast)
  const [clients, setClients] = useState(null)
  const [tiers, setTiers] = useState({})
  const [picked, setPicked] = useState(only ? [only] : [])
  const [note, setNote] = useState(draft.note || '')
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    trainerApi.clients().then(d => {
      setClients(d.clients.filter(c => !c.disabled).sort((a, b) => String(a.name).localeCompare(String(b.name))))
      setTiers(tierMap(d.clients))
    }).catch(e => toast(e.message))
  }, [])
  const toggle = id => setPicked(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id])
  const send = async () => {
    setBusy(true)
    const name = draft.name.trim() || 'Program'
    const results = await Promise.allSettled(picked.map(id => trainerApi.assign(id, { name, note, bundle, programId: draft.id })))
    setBusy(false)
    const failed = results.filter(r => r.status === 'rejected')
    if (failed.length) { toast(`Couldn’t send to ${plural(failed.length, 'client', 'clients')}: ${failed[0].reason?.message || ''}`); return }
    toast(picked.length === 1 ? 'Sent. It’s waiting on their Coach tab' : `Sent to ${picked.length} clients`)
    close()
    onSent?.()
  }
  return <>
    <h3>Send “{draft.name.trim() || 'Program'}”</h3>
    <div className="muted small" style={{ marginBottom: 14, lineHeight: 1.45 }}>
      Each client gets their own copy on their Coach tab and adds it to their plan with one tap. Editing the program later doesn’t change copies already sent.
    </div>
    {!clients ? <div className="muted small">Loading clients…</div>
      : !clients.length ? <div className="muted small">No clients yet. Invite one from the Clients tab first.</div>
      : clients.map(c => <button key={c.id} className={'kl-pick' + (picked.includes(c.id) ? ' on' : '')} onClick={() => toggle(c.id)} aria-pressed={picked.includes(c.id)}>
        <span className="kl-check"><Icon name="check" /></span>
        <Avatar id={c.id} name={c.name} tier={tiers[c.id]} />
        <span style={{ flex: 1, minWidth: 0, fontWeight: 600 }}>{c.name}</span>
      </button>)}
    <div style={{ height: 12 }} />
    <textarea className="input" rows={2} maxLength={500} placeholder="A note for them: which days, how heavy to start" value={note} onChange={e => setNote(e.target.value)} />
    <div style={{ height: 12 }} />
    <Button variant="primary" icon="share" disabled={!picked.length || busy} onClick={send}>
      {busy ? 'Sending…' : picked.length > 1 ? `Send to ${picked.length} clients` : 'Send program'}</Button>
  </>
}
export const openSendProgram = (draft, bundle, only, onSent) =>
  useUI.getState().openSheet(close => <SendSheet close={close} draft={draft} bundle={bundle} only={only} onSent={onSent} />)

/* --------------------------------------------------------------- editor -- */

function Day({ day, n, count, unit, speedUnit, edit, onMove, onCopy, onRemove }) {
  const toast = useUI(s => s.toast)
  const editEx = fn => edit(d => fn(d.ex))
  const add = () => exercisePicker((ex, quick) => {
    if (quick) {
      editEx(x => { x.push({ id: ex.id, ...defaultConfig(ex.id) }) })
      toast(`“${exerciseNameText(ex)}” added to ${day.name || 'the day'}`)
    } else exConfigSheet(ex, null, cfg => editEx(x => { x.push({ id: ex.id, ...cfg }) }), null, day, null, null, 'Add to day')
  })
  const remove = i => editEx(x => { x.splice(i, 1); cleanupSg(x) })
  const move = (i, dir) => editEx(x => {
    const next = moveRoutineEntry(x, i, dir)
    if (next) { x.splice(0, x.length, ...next); cleanupSg(x) }
  })
  const link = i => editEx(x => {
    const cur = x[i], prev = x[i - 1]
    if (cur.sg && prev.sg && cur.sg === prev.sg) delete cur.sg
    else { const g = prev.sg || ('sg' + Date.now().toString(36) + i); prev.sg = g; cur.sg = g }
    cleanupSg(x)
  })

  return <section className="pg-day rk" data-tier={(n - 1) % 6}>
    <div className="pg-day-h">
      <span className="pg-day-n">{n}</span>
      <input className="input pg-day-name" value={day.name} maxLength={60} placeholder={'Day ' + n} aria-label={`Day ${n} name`}
        onChange={e => { const v = e.target.value; edit(d => { d.name = v }) }} />
      <button className="iconbtn" disabled={n === 1} onClick={() => onMove(-1)} aria-label="Move day up"><Icon name="chevronUp" /></button>
      <button className="iconbtn" disabled={n === count} onClick={() => onMove(1)} aria-label="Move day down"><Icon name="chevronDown" /></button>
      <button className="iconbtn" onClick={onCopy} aria-label="Duplicate day"><Icon name="copy" /></button>
      <button className="iconbtn" disabled={count === 1} onClick={onRemove} aria-label="Delete day"><Icon name="trash" /></button>
    </div>
    <div className="pg-day-body">
      <SelectRow icon="chartLine" title="Progression" sheetTitle="Progression"
        value={day.prog || 'linear'} onChange={v => edit(d => { d.prog = v })}
        options={POLICIES_FOR.reps.map(p => ({ value: p, label: POLICY_NAME[p], subtitle: POLICY_DESC[p] }))} />
      {day.ex.length ? <div className="pg-ex-list">{day.ex.map((e, i) => {
        const ex = exOr(e.id)
        const linked = i > 0 && e.sg && day.ex[i - 1].sg === e.sg
        return <div key={i} className={'pg-ex' + (e.sg ? ' in-ss' : '') + (linked ? ' linked' : '')}>
          <button type="button" className="pg-ex-open" onClick={() =>
            exConfigSheet(ex, e, cfg => editEx(x => { x[i] = { id: x[i].id, sg: x[i].sg, ...(x[i].sg ? { sgName: x[i].sgName, sgRest: x[i].sgRest } : {}), ...cfg }; cleanupSg(x) }), () => remove(i), day, null, null, 'Save')}>
            <Thumb ex={ex} />
            <span className="pg-ex-m"><span className={'pg-ex-t ' + exerciseNameClass(ex)}>{exerciseNameFor(ex)}</span>
              <span className="pg-ex-s">{exLine(e, unit, speedUnit)}</span>
              {e.note && <span className="pg-ex-s dim">{e.note}</span>}</span>
          </button>
          <div className="pg-ex-ctl">
            {i > 0 && <button className={'iconbtn sm' + (linked ? ' on-ss' : '')} onClick={() => link(i)} aria-label={linked ? 'Unlink from the exercise above' : 'Superset with the exercise above'} aria-pressed={!!linked}><Icon name="link" /></button>}
            <button className="iconbtn sm" disabled={!moveRoutineEntry(day.ex, i, -1)} onClick={() => move(i, -1)} aria-label="Move up"><Icon name="chevronUp" /></button>
            <button className="iconbtn sm" disabled={!moveRoutineEntry(day.ex, i, 1)} onClick={() => move(i, 1)} aria-label="Move down"><Icon name="chevronDown" /></button>
          </div>
        </div>
      })}</div> : <div className="pg-ex-empty">No exercises on this day yet.</div>}
      <Button size="sm" variant="tinted" icon="plus" onClick={add}>Add exercise</Button>
    </div>
  </section>
}

export function ProgramEdit() {
  const { pid } = useParams()
  const nav = useNavigate()
  const toast = useUI(s => s.toast)
  const S = useStore(s => s.S)
  const unit = S.unit || 'kg'
  const [draft, setDraft] = useState(null)
  const [meta, setMeta] = useState(null)
  const [status, setStatus] = useState('saved')
  const [error, setError] = useState(null)
  const dirty = useRef(false)
  const latest = useRef(null)
  const saved = useRef(null)
  const here = useRef(true)
  latest.current = draft

  useEffect(() => {
    // A new program gets its address once it is first saved; that is still the draft on screen.
    if (latest.current && latest.current.id === pid) return
    dirty.current = false
    if (pid === 'new') { setDraft(newProgram()); setMeta(null); return }
    programApi.get(pid).then(d => { setDraft(programDraft(d.program, unit)); setMeta(d.program) }).catch(e => setError(e.message))
  }, [pid])

  const save = d => {
    if (!d || d === saved.current || (!programExercises(d) && !d.name.trim())) return Promise.resolve()
    saved.current = d
    if (here.current) setStatus('saving')
    return programApi.save({ id: d.id, name: d.name, note: d.note, bundle: programBundle(useStore.getState().S, d) })
      .then(r => {
        if (!here.current) return
        setStatus(latest.current === d ? 'saved' : 'dirty')
        setMeta(r.program)
        if (pid === 'new') nav('/trainer/program/' + encodeURIComponent(r.program.id), { replace: true })
      })
      .catch(e => { saved.current = null; if (here.current) setStatus('error'); toast('Couldn’t save: ' + e.message) })
  }
  // Every change saves itself shortly after the last keystroke, the way a routine does.
  useEffect(() => {
    if (!dirty.current || !draft) return
    setStatus('dirty')
    const h = setTimeout(() => save(draft), 700)
    return () => clearTimeout(h)
  }, [draft])
  // Leaving with a change still pending saves it on the way out.
  useEffect(() => () => { here.current = false; if (dirty.current) save(latest.current) }, [])

  const change = fn => { dirty.current = true; setDraft(d => { const n = structuredClone(d); fn(n); return n }) }
  const editDay = id => fn => change(d => fn(d.days.find(x => x.id === id)))

  if (error) return <div className="narrow">
    <div className="hdr"><button className="iconbtn" onClick={() => nav('/trainer/programs')} aria-label="Back to programs"><Icon name="chevronLeft" /></button></div>
    <div className="card small" style={{ color: 'var(--red)' }}>Couldn’t open this program: {error}</div>
  </div>
  if (!draft) return <div className="narrow"><div className="hdr"><div><h1>Program</h1><div className="sub">Loading…</div></div></div></div>

  const total = programExercises(draft)
  const speedUnit = speedUnitOf(S)
  const send = () => {
    if (!draft.name.trim()) { toast('Give the program a name first'); return }
    save(draft).then(() => openSendProgram(draft, programBundle(S, draft)))
  }
  const duplicate = () => {
    const copy = { ...structuredClone(draft), id: newProgram().id, name: (draft.name.trim() || 'Program') + ' (copy)' }
    programApi.save({ id: copy.id, name: copy.name, note: copy.note, bundle: programBundle(S, copy) })
      .then(r => { toast('Duplicated'); nav('/trainer/program/' + encodeURIComponent(r.program.id)) })
      .catch(e => toast(e.message))
  }
  const del = () => confirmSheet({
    title: `Delete “${draft.name.trim() || 'this program'}”?`,
    message: 'It leaves your library. Clients who were sent it keep their copy.',
    confirmText: 'Delete', danger: true,
    onConfirm: () => {
      dirty.current = false
      const done = () => { toast('Program deleted'); nav('/trainer/programs') }
      if (!meta) { done(); return }
      programApi.remove(draft.id).then(done).catch(e => toast(e.message))
    }
  })
  const statusText = { saved: meta ? 'Saved' : 'Not saved yet', saving: 'Saving…', dirty: 'Editing…', error: 'Not saved' }[status]

  return <div className="narrow">
    <div className="hdr" style={{ marginBottom: 8 }}>
      <button className="iconbtn" onClick={() => nav('/trainer/programs')} aria-label="Back to programs"><Icon name="chevronLeft" /></button>
      <span className={'pg-status ' + status} role="status">{statusText}</span>
    </div>
    <input className="pg-title" value={draft.name} maxLength={60} placeholder="Name this program" aria-label="Program name"
      autoFocus={pid === 'new'} onChange={e => { const v = e.target.value; change(d => { d.name = v }) }} />
    <div className="pg-sub">{plural(draft.days.length, 'day', 'days')} · {plural(total, 'exercise', 'exercises')}
      {meta?.updated ? ' · edited ' + fmtDate(new Date(meta.updated).toISOString().slice(0, 10), true) : ''}</div>
    <textarea className="input pg-note" rows={2} maxLength={1000} value={draft.note}
      placeholder="What it’s for and how to run it: goal, days per week, how to progress. Sent along with it."
      onChange={e => { const v = e.target.value; change(d => { d.note = v }) }} />

    {draft.days.map((day, i) => <Day key={day.id} day={day} n={i + 1} count={draft.days.length} unit={unit} speedUnit={speedUnit}
      edit={editDay(day.id)}
      onMove={dir => change(d => { const [x] = d.days.splice(i, 1); d.days.splice(i + dir, 0, x) })}
      onCopy={() => change(d => { d.days.splice(i + 1, 0, copyDay(day, (day.name || 'Day ' + (i + 1)) + ' (copy)')) })}
      onRemove={() => confirmSheet({
        title: `Delete ${day.name || 'this day'}?`, message: day.ex.length ? `Its ${plural(day.ex.length, 'exercise', 'exercises')} go with it.` : 'It has no exercises yet.',
        confirmText: 'Delete', danger: true, onConfirm: () => change(d => { d.days.splice(i, 1) })
      })} />)}

    <Button icon="plus" onClick={() => change(d => { d.days.push(newDay(d.days.length + 1)) })}>Add a day</Button>

    <div className="pg-send">
      <Button variant="primary" icon="share" disabled={!total} onClick={send}>Send to clients</Button>
      {!total && <div className="dim small" style={{ marginTop: 8, textAlign: 'center' }}>Add an exercise to send it.</div>}
    </div>
    <div style={{ height: 10 }} />
    <Button icon="copy" disabled={!meta} onClick={duplicate}>Duplicate program</Button>
    <div style={{ height: 10 }} />
    <Button variant="danger" onClick={del}>Delete program</Button>
  </div>
}
