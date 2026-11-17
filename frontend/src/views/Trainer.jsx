import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { fmtDate, fmtDur, fmtVol, fmtNum } from '../lib/format.js'
import { workoutVolume, setsDone } from '../lib/history.js'
import { EXIDX } from '../lib/exercises.js'
import { exerciseNameFor } from '../lib/i18n-core.js'
import { buildPlanBundle } from '../lib/plan-share.js'
import { trainerApi, programApi, sortRoster, rosterTotals, standing, daysSince, pickRoutines, tierMap, dayRack } from '../lib/trainer.js'
import { confirmSheet } from '../sheets.jsx'
import { openSendProgram } from './Programs.jsx'
import Icon from '../components/Icon.jsx'
import { Button, Segmented } from '../components/ui.jsx'

// Klora Fitness: the trainer's side. Admin-only (the route checks, and so does every
// /api/trainer route). Like the operator dashboard it is English-only for now: it is her screen,
// not part of the translated client surface.

/* ------------------------------------------------------------------ bits -- */

// A client keeps one rack colour everywhere: the same id always lands on the same tier.
export const tierOf = id => { let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return h % 6 }
export const initials = name => String(name || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]?.toUpperCase() || '').join('') || '?'

export function Avatar({ id, name, lg, tier }) {
  return <span className={'kl-av rk' + (lg ? ' lg' : '')} data-tier={tier ?? tierOf(id)} aria-hidden="true">{initials(name)}</span>
}

// A client's recent days as a rack of capsules: trained days filled mint, today ringed.
export function DayRack({ days, n = 7, now, label }) {
  const rack = dayRack(days, n, now)
  return <span className={'kl-dayrack' + (n > 7 ? ' wide' : '')} role="img" aria-label={label}>
    {rack.map((d, i) => <i key={d.iso} className={(d.trained ? 'on' : '') + (i === rack.length - 1 ? ' today' : '')} />)}
  </span>
}

const STANDING = {
  'needs-you': { label: 'Needs you', tier: 'hot', icon: 'chat' },
  quiet: { label: 'Gone quiet', tier: 'rk-peach', icon: 'moon' },
  drifting: { label: 'Drifting', tier: 'rk-butter', icon: 'hourglass' },
  new: { label: 'New', tier: 'rk-lilac', icon: 'sparkles' },
  'on-track': { label: 'On track', tier: 'rk-mint', icon: 'check' }
}
export function StandingBadge({ s }) {
  const v = STANDING[s]
  return <span className={'kl-badge rk ' + v.tier}><Icon name={v.icon} />{v.label}</span>
}

const ago = (iso, now) => {
  const d = daysSince(iso, now)
  if (d === null) return 'No workouts yet'
  if (d === 0) return 'Trained today'
  if (d === 1) return 'Trained yesterday'
  return `Last trained ${d} days ago`
}
const when = ts => {
  const d = new Date(ts)
  const time = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  return d.toDateString() === new Date().toDateString() ? time : fmtDate(d.toISOString().slice(0, 10), true) + ' · ' + time
}
const exLabel = e => {
  const ex = EXIDX[e.id]
  return ex ? exerciseNameFor(ex) : (e.n || e.name || 'Custom exercise')
}

/* ---------------------------------------------------------------- invite -- */

function InviteSheet({ close, inviteOnly }) {
  const toast = useUI(s => s.toast)
  const [note, setNote] = useState('')
  const [code, setCode] = useState(null)
  const appUrl = location.origin + location.pathname
  const make = () => trainerApi.newInvite(note.trim()).then(r => setCode(r.invite.code)).catch(e => toast(e.message))
  const copy = text => { navigator.clipboard?.writeText(text).then(() => toast('Copied'), () => toast(text)) }
  const message = code
    ? `Join me on Klora Fitness: ${appUrl}\nChoose "Create new profile" and enter the invite code ${code}.`
    : `Join me on Klora Fitness: ${appUrl}\nChoose "Create new profile" to set up your account.`
  const share = () => navigator.share ? navigator.share({ text: message }).catch(() => {}) : copy(message)
  return <>
    <h3>Invite a client</h3>
    <div className="muted small" style={{ marginBottom: 14, lineHeight: 1.45 }}>
      {inviteOnly
        ? 'Sign-up is invite-only, so each new client needs a code. A code works once.'
        : 'Sign-up is open: anyone with the app address can create a profile. A code is optional and records who you invited.'}
    </div>
    {code ? <>
      <div className="tr-invite"><code>{code}</code>
        <button className="iconbtn" onClick={() => copy(code)} aria-label="Copy code"><Icon name="copy" /></button></div>
      <div style={{ height: 12 }} />
      <Button variant="primary" icon="share" onClick={share}>Send the invite</Button>
      <div style={{ height: 8 }} />
      <Button onClick={close}>Done</Button>
    </> : <>
      <input className="input" placeholder="Who is it for? (optional)" maxLength={60} value={note} onChange={e => setNote(e.target.value)} />
      <div style={{ height: 12 }} />
      <Button variant="primary" icon="plus" onClick={make}>Create invite code</Button>
      {!inviteOnly && <><div style={{ height: 8 }} /><Button icon="share" onClick={share}>Send the app link only</Button></>}
    </>}
  </>
}
export const openInvite = inviteOnly => useUI.getState().openSheet(close => <InviteSheet close={close} inviteOnly={inviteOnly} />)

/* ---------------------------------------------------------------- roster -- */

// Her two lists, side by side at the top of each: the people, and the programs she gives them.
export function TrainerSwitch({ value }) {
  const nav = useNavigate()
  return <Segmented className="tr-switch" value={value} onChange={v => nav(v === 'programs' ? '/trainer/programs' : '/trainer')}
    options={[{ value: 'clients', label: 'Clients' }, { value: 'programs', label: 'Programs' }]} />
}

const FILTERS = [
  { key: 'needs', label: 'Need you', tier: 'rk-rose', test: c => c._s === 'needs-you' },
  { key: 'quiet', label: 'Gone quiet', tier: 'rk-peach', test: c => c._s === 'quiet' || c._s === 'drifting' },
  { key: 'week', label: 'Trained this week', tier: 'rk-mint', test: c => c.week > 0 },
  { key: 'all', label: 'All clients', tier: 'rk-lilac', test: () => true }
]

export default function Trainer() {
  const nav = useNavigate()
  const toast = useUI(s => s.toast)
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)
  const [filter, setFilter] = useState('all')
  const load = () => trainerApi.clients().then(d => { setData(d); setError(null) }).catch(e => setError(e.message))
  useEffect(() => { load() }, [])

  const now = data?.now || Date.now()
  const roster = useMemo(() => sortRoster((data?.clients || []).filter(c => !c.disabled), now).map(c => ({ ...c, _s: standing(c, now) })), [data])
  const tiers = useMemo(() => tierMap(data?.clients || []), [data])
  const totals = rosterTotals(roster, now)
  const counts = { needs: totals.needsYou, quiet: roster.filter(FILTERS[1].test).length, week: totals.trainedThisWeek, all: totals.clients }
  const shown = roster.filter(FILTERS.find(f => f.key === filter).test)

  return <div className="narrow">
    <div className="hdr">
      <div><h1>Clients</h1>
        <div className="sub">{data ? `${totals.clients} ${totals.clients === 1 ? 'client' : 'clients'} · ${totals.sessionsThisWeek} ${totals.sessionsThisWeek === 1 ? 'session' : 'sessions'} this week` : 'Loading your book…'}</div></div>
      <div className="hdr-actions">
        <button className="iconbtn" onClick={() => openInvite(!!data?.invite_only)} aria-label="Invite a client"><Icon name="plus" /></button>
        <button className="iconbtn" onClick={() => nav('/admin')} aria-label="Instance settings"><Icon name="wrench" /></button>
      </div>
    </div>
    <TrainerSwitch value="clients" />

    {error && <div className="card small" style={{ color: 'var(--red)' }}>Couldn’t load your clients: {error}
      <div style={{ marginTop: 10 }}><Button size="sm" onClick={load}>Try again</Button></div></div>}

    {data && !roster.length && <div className="tr-empty">
      <div className="kl-weights" aria-hidden="true"><span className="rk rk-rose" /><span className="rk rk-lilac" /><span className="rk rk-mint" /><span className="rk rk-butter" /></div>
      <h3>Your rack is empty</h3>
      <p>Invite your first client. Once they sign up, their workouts and check-ins land here.</p>
      <Button variant="primary" icon="plus" onClick={() => openInvite(!!data.invite_only)}>Invite a client</Button>
    </div>}

    {!!roster.length && <>
      <div className="tr-rack" role="group" aria-label="Filter clients">
        {FILTERS.map(f => <button key={f.key} className={'tr-weight rk ' + f.tier + (filter === f.key ? ' on' : '')}
          aria-pressed={filter === f.key} onClick={() => setFilter(f.key)}>
          <span className="tr-num">{counts[f.key]}</span><span className="tr-lbl">{f.label}</span>
        </button>)}
      </div>
      <div className="tr-list">
        {shown.map(c => <button key={c.id} className={'tr-row rk' + (c._s === 'needs-you' ? ' needs' : '')} data-tier={tiers[c.id]} onClick={() => nav('/trainer/' + encodeURIComponent(c.id))}>
          <Avatar id={c.id} name={c.name} tier={tiers[c.id]} />
          <div className="tr-row-m">
            <span className="tr-row-t">{c.name}</span>
            <span className="tr-row-s">{c.unread && c.lastMessage?.from === 'client' ? '“' + c.lastMessage.text + '”' : ago(c.lastWorkout, now) + (c.pending ? ` · ${c.pending} routine${c.pending > 1 ? 's' : ''} waiting` : '')}</span>
          </div>
          <div className="tr-row-e">
            <StandingBadge s={c._s} />
            <DayRack days={c.days} now={now} label={`${c.week} ${c.week === 1 ? 'session' : 'sessions'} in the last 7 days`} />
          </div>
          {c.unread > 0 && <span className="tr-unread" aria-label={`${c.unread} unread`}>{c.unread}</span>}
        </button>)}
        {!shown.length && <div className="tr-empty"><p style={{ margin: 0 }}>Nobody here right now.</p></div>}
      </div>
    </>}
    {data && <div style={{ display: 'flex', justifyContent: 'center', marginTop: 18 }}>
      <Button size="sm" variant="ghost" icon="repeat" onClick={() => { load(); toast('Refreshed') }}>Refresh</Button>
    </div>}
  </div>
}

/* ---------------------------------------------------------- one client -- */

function Progress({ p, c, now }) {
  if (!p) return <div className="muted small">Loading…</div>
  const workouts = (p.workouts || []).filter(w => w && Array.isArray(w.entries))
  const bw = (p.bodyweight || []).slice(-1)[0]
  return <>
    <div className="card">
      <h2>Last 4 weeks</h2>
      <DayRack days={c.days} n={28} now={now} label={`${c.month} sessions in the last 4 weeks`} />
      <p className="tr-sentence"><b>{c.week}</b> {c.week === 1 ? 'session' : 'sessions'} this week, <b>{c.month}</b> in the last four weeks, <b>{workouts.length}</b> since they joined.</p>
    </div>
    <div className="card">
      <div className="row between"><h2 style={{ margin: 0 }}>Body weight</h2>
        <span className="small muted">{(p.bodyweight || []).length} {(p.bodyweight || []).length === 1 ? 'weigh-in' : 'weigh-ins'}</span></div>
      {bw ? <div className="big" style={{ marginTop: 8 }}>{fmtNum(bw.w)} <span className="muted" style={{ fontSize: '1rem' }}>{p.unit}</span>
        <span className="dim small" style={{ marginInlineStart: 8, fontFamily: 'inherit' }}>{fmtDate(bw.d, true)}</span></div>
        : <div className="muted small" style={{ marginTop: 6 }}>No weigh-ins yet.</div>}
    </div>
    <div className="card">
      <h2>Recent sessions · {ago(c.lastWorkout, now).toLowerCase()}</h2>
      {workouts.length ? workouts.slice(0, 12).map(w => {
        const d = new Date(w.d + 'T00:00:00')
        const names = w.entries.slice(0, 4).map(exLabel).join(', ') + (w.entries.length > 4 ? ` +${w.entries.length - 4}` : '')
        return <div key={w.id} className="tr-session">
          <div className="tr-session-d"><b>{d.getDate()}</b><span>{d.toLocaleDateString([], { month: 'short' })}</span></div>
          <div className="tr-session-m">
            <div className="tr-session-t">{w.name || 'Workout'}{w.prs?.length ? <span className="kl-badge rk rk-butter" style={{ marginInlineStart: 8 }}><Icon name="trophy" />{w.prs.length} PR</span> : null}</div>
            <div className="tr-session-s">{setsDone(w)} sets · {fmtVol(w.vol ?? workoutVolume(w), p.unit)}{w.end && w.start ? ' · ' + fmtDur(w.end - w.start) : ''}</div>
            {names && <div className="tr-session-s">{names}</div>}
          </div>
        </div>
      }) : <div className="muted small">Nothing logged yet. Their sessions appear here as soon as they sync.</div>}
    </div>
    {!!p.routines?.length && <div className="card">
      <h2>Their plan</h2>
      {p.routines.map(r => <div key={r.id} className="row between" style={{ padding: '6px 0' }}>
        <span>{r.name}</span><span className="small muted">{r.count} exercises</span></div>)}
    </div>}
  </>
}

function Thread({ messages, mine, onSend, quick, placeholder }) {
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const send = async v => {
    const body = (v ?? text).trim()
    if (!body || busy) return
    setBusy(true)
    try { await onSend(body); setText('') } finally { setBusy(false) }
  }
  return <>
    {messages.length ? <div className="kl-thread">
      {messages.map(m => <div key={m.id} className={'kl-msg ' + (m.from === mine ? 'me' : 'them')}>{m.text}<time>{when(m.at)}</time></div>)}
    </div> : <div className="muted small" style={{ marginBottom: 12 }}>No check-ins yet.</div>}
    {quick && <div className="kl-quick">{quick.map(q => <button key={q} className="chip nocap" onClick={() => send(q)}>{q}</button>)}</div>}
    <div className="kl-compose">
      <textarea className="input" rows={1} maxLength={1000} placeholder={placeholder} value={text} onChange={e => setText(e.target.value)}
        onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() } }} />
      <Button variant="primary" icon="arrowUp" onClick={() => send()} disabled={!text.trim() || busy} aria-label="Send" />
    </div>
  </>
}
export { Thread }

function Program({ id, name, rec, reload }) {
  const toast = useUI(s => s.toast)
  const nav = useNavigate()
  const S = useStore(s => s.S)
  const mine = (S.routines || []).filter(r => r.ex?.length)
  const [programs, setPrograms] = useState(null)
  const [own, setOwn] = useState(false)
  const [picked, setPicked] = useState([])
  const [note, setNote] = useState('')
  useEffect(() => { programApi.list().then(d => setPrograms(d.programs)).catch(() => setPrograms([])) }, [])
  const toggle = rid => setPicked(p => p.includes(rid) ? p.filter(x => x !== rid) : [...p, rid])
  const sendProgram = p => programApi.get(p.id)
    .then(d => openSendProgram({ id: p.id, name: d.program.name, note: d.program.note }, d.program.bundle, id, reload))
    .catch(e => toast(e.message))
  const sendOwn = () => {
    const bundle = pickRoutines(buildPlanBundle(S, ''), picked)
    const title = bundle.routines.length === 1 ? bundle.routines[0].name : `${bundle.routines.length} routines`
    trainerApi.assign(id, { name: title, note, bundle })
      .then(() => { toast('Sent. They’ll see it on their Coach tab'); setPicked([]); setNote(''); reload() })
      .catch(e => toast(e.message))
  }
  const withdraw = a => confirmSheet({
    title: `Take back “${a.name}”?`, message: 'They haven’t added it yet. It disappears from their Coach tab.',
    confirmText: 'Take back', danger: true,
    onConfirm: () => trainerApi.withdraw(id, a.id).then(() => { toast('Taken back'); reload() }).catch(e => toast(e.message))
  })
  const given = new Set(rec.assignments.map(a => a.programId).filter(Boolean))
  return <>
    <div className="card">
      <div className="row between" style={{ marginBottom: 10 }}>
        <h2 style={{ margin: 0 }}>Send a program</h2>
        <Button size="sm" variant="tinted" icon="plus" onClick={() => nav('/trainer/program/new')}>New</Button>
      </div>
      {!programs ? <div className="muted small">Loading your programs…</div>
        : programs.length ? programs.map(p => <div key={p.id} className="pg-row">
          <div className="pg-row-m">
            <div className="kl-assign-t">{p.name}</div>
            <div className="kl-assign-s">{p.days} {p.days === 1 ? 'day' : 'days'} · {p.exercises} exercises{given.has(p.id) ? ' · sent before' : ''}</div>
          </div>
          <Button size="sm" variant="primary" icon="share" disabled={!p.exercises} onClick={() => sendProgram(p)}>Send</Button>
        </div>)
        : <div className="muted small" style={{ lineHeight: 1.45 }}>
          Build a program once (days, exercises, sets and weights) and send it to {name || 'this client'} and anyone else.
          <div style={{ height: 10 }} /><Button icon="plus" onClick={() => nav('/trainer/program/new')}>Build a program</Button></div>}
    </div>
    {!!mine.length && <div className="card">
      <button className="row between pg-own-t" onClick={() => setOwn(v => !v)} aria-expanded={own}>
        <h2 style={{ margin: 0 }}>Or send from your own plan</h2><Icon name={own ? 'chevronUp' : 'chevronDown'} />
      </button>
      {own && <div style={{ marginTop: 12 }}>
        {mine.map(r => <button key={r.id} className={'kl-pick' + (picked.includes(r.id) ? ' on' : '')} onClick={() => toggle(r.id)} aria-pressed={picked.includes(r.id)}>
          <span className="kl-check"><Icon name="check" /></span>
          <span style={{ flex: 1, minWidth: 0 }}><span style={{ display: 'block', fontWeight: 600 }}>{r.name}</span>
            <span className="small muted">{r.ex.length} exercises</span></span>
        </button>)}
        <div style={{ height: 12 }} />
        <textarea className="input" rows={2} maxLength={500} placeholder="A note for them: days, cues, how heavy to start" value={note} onChange={e => setNote(e.target.value)} />
        <div style={{ height: 12 }} />
        <Button variant="primary" icon="share" disabled={!picked.length} onClick={sendOwn}>{picked.length > 1 ? `Send ${picked.length} routines` : 'Send routine'}</Button>
      </div>}
    </div>}
    <h4 className="sec">Sent</h4>
    {rec.assignments.length ? rec.assignments.map(a => <div key={a.id} className="kl-assign">
      <div className="kl-assign-m">
        <div className="kl-assign-t">{a.name}</div>
        <div className="kl-assign-s">{a.routines > 1 ? `${a.routines} days · ` : ''}{a.exercises} exercises · sent {fmtDate(new Date(a.at).toISOString().slice(0, 10), true)}{a.note ? ' · ' + a.note : ''}</div>
      </div>
      {a.accepted ? <span className="kl-badge rk rk-mint"><Icon name="check" />Added</span>
        : <><span className="kl-badge rk rk-butter">Waiting</span>
          <button className="iconbtn" onClick={() => withdraw(a)} aria-label="Take back"><Icon name="undo" /></button></>}
    </div>) : <div className="muted small" style={{ padding: '0 4px' }}>Nothing sent yet.</div>}
  </>
}

function Notes({ id, rec, reload }) {
  const toast = useUI(s => s.toast)
  const [text, setText] = useState('')
  const add = () => trainerApi.addNote(id, text).then(() => { setText(''); reload() }).catch(e => toast(e.message))
  const del = n => confirmSheet({ title: 'Delete this note?', message: n.text.slice(0, 140), confirmText: 'Delete', danger: true,
    onConfirm: () => trainerApi.deleteNote(id, n.id).then(reload).catch(e => toast(e.message)) })
  return <>
    <div className="card">
      <h2>Private to you. They never see these.</h2>
      <textarea className="input" rows={3} maxLength={2000} placeholder="Injuries, goals, what worked last session…" value={text} onChange={e => setText(e.target.value)} />
      <div style={{ height: 10 }} />
      <Button variant="primary" icon="note" disabled={!text.trim()} onClick={add}>Save note</Button>
    </div>
    {rec.notes.map(n => <div key={n.id} className="kl-note">{n.text}<time>{new Date(n.at).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</time>
      <button className="iconbtn" onClick={() => del(n)} aria-label="Delete note"><Icon name="trash" /></button></div>)}
  </>
}

export function TrainerClient() {
  const { id } = useParams()
  const nav = useNavigate()
  const toast = useUI(s => s.toast)
  const [tab, setTab] = useState('progress')
  const [rec, setRec] = useState(null)
  const [p, setP] = useState(null)
  const [row, setRow] = useState(null)
  const [tier, setTier] = useState(undefined)
  const reload = () => trainerApi.client(id).then(setRec).catch(e => toast(e.message))
  useEffect(() => {
    reload()
    trainerApi.progress(id).then(setP).catch(e => toast(e.message))
    trainerApi.clients().then(d => { setRow(d.clients.find(c => c.id === id) || null); setTier(tierMap(d.clients)[id]) }).catch(() => {})
  }, [id])
  const now = Date.now()
  const c = row || { week: 0, month: 0, lastWorkout: null, unread: 0 }
  const name = rec?.name || p?.user?.name || ''
  const unread = c.unread || 0

  return <div className="narrow">
    <div className="hdr" style={{ marginBottom: 6 }}>
      <button className="iconbtn" onClick={() => nav('/trainer')} aria-label="Back to clients"><Icon name="chevronLeft" /></button>
    </div>
    <div className="tr-head">
      <Avatar id={id} name={name} tier={tier} lg />
      <div style={{ minWidth: 0 }}>
        <h1>{name || ' '}</h1>
        <div className="sub">{p?.user?.created ? 'Client since ' + fmtDate(p.user.created.slice(0, 10), true) + ' · ' : ''}{ago(c.lastWorkout, now)}</div>
        {row && <div style={{ marginTop: 8 }}><StandingBadge s={standing(c, now)} /></div>}
      </div>
    </div>
    <Segmented className="tr-tabs" value={tab} onChange={setTab} options={[
      { value: 'progress', label: 'Progress' },
      { value: 'checkins', label: unread && tab !== 'checkins' ? `Check-ins (${unread})` : 'Check-ins' },
      { value: 'program', label: 'Program' },
      { value: 'notes', label: 'Notes' }
    ]} />
    {!rec ? <div className="muted small">Loading…</div>
      : tab === 'progress' ? <Progress p={p} c={c} now={now} />
      : tab === 'checkins' ? <div className="card"><Thread messages={rec.messages} mine="trainer" placeholder={`Reply to ${name}`}
          quick={['Great session!', 'How did that feel?', 'Let’s go heavier next time', 'Rest up today']}
          onSend={text => trainerApi.message(id, text).then(reload).catch(e => toast(e.message))} /></div>
      : tab === 'program' ? <Program id={id} name={name} rec={rec} reload={reload} />
      : <Notes id={id} rec={rec} reload={reload} />}
  </div>
}
