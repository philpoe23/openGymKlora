import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t, tn } from '../lib/i18n.js'
import { fmtDate, exCount } from '../lib/format.js'
import { parsePlan, mergePlan } from '../lib/plan-share.js'
import { clientApi } from '../lib/trainer.js'
import Icon from '../components/Icon.jsx'
import { Button } from '../components/ui.jsx'
import { Avatar, Thread } from './Trainer.jsx'

// Klora Fitness: the client's side. What their trainer sent them, and the check-in thread.
// A routine she sends is a plan file; adding it goes through the same merge as importing one
// (lib/plan-share.js), so it lands as new routines and never touches the ones already there.

export default function Coaching() {
  const nav = useNavigate()
  const toast = useUI(s => s.toast)
  const update = useStore(s => s.update)
  const unit = useStore(s => s.S.unit) || 'kg'
  const [d, setD] = useState(null)
  const [error, setError] = useState(null)
  const load = (read = false) => clientApi.training(read).then(v => { setD(v); setError(null) }).catch(e => setError(e.message))
  useEffect(() => { load(true) }, [])

  const add = async a => {
    let bundle
    try { bundle = parsePlan(a.bundle, unit) }
    catch (e) { toast(t('Couldn’t read that plan: {0}', e.message)); return }
    update(s => mergePlan(s, bundle))
    try { await clientApi.accept(a.id) } catch { /* added locally either way; marked next time */ }
    toast(tn('Added {0} routine to your plan', 'Added {0} routines to your plan', bundle.routineCount))
    load()
  }

  if (error) return <div className="narrow">
    <div className="hdr"><div><h1>{t('Coach')}</h1></div></div>
    <div className="card small" style={{ color: 'var(--red)' }}>{t('Couldn’t reach your coach’s server: {0}', error)}
      <div style={{ marginTop: 10 }}><Button size="sm" onClick={() => load(true)}>{t('Try again')}</Button></div></div>
  </div>
  if (!d) return <div className="narrow"><div className="hdr"><div><h1>{t('Coach')}</h1><div className="sub">{t('Loading…')}</div></div></div></div>

  const fresh = d.assignments.filter(a => !a.accepted)
  const added = d.assignments.filter(a => a.accepted)
  const coach = d.trainer?.name

  return <div className="narrow">
    <div className="hdr"><div><h1>{t('Coach')}</h1>
      <div className="sub">{fresh.length ? (fresh.length === 1 ? t('A new routine from your coach') : t('{0} new routines from your coach', fresh.length)) : t('Programs and check-ins')}</div></div></div>

    <div className="pt-card">
      {coach ? <Avatar id={coach} name={coach} lg /> : <span className="kl-av lg"><Icon name="person" /></span>}
      <div style={{ minWidth: 0 }}>
        <h2>{coach || t('No coach yet')}</h2>
        <p>{coach ? t('Your personal trainer. Check in after a session, ask anything.') : t('When your trainer sends you a routine, it shows up here.')}</p>
      </div>
    </div>

    {fresh.map(a => <div key={a.id} className="pt-new">
      <div className="row between" style={{ alignItems: 'flex-start', gap: 10 }}>
        <div style={{ minWidth: 0 }}>
          <div className="kl-assign-t">{a.name}</div>
          <div className="kl-assign-s">{exCount(a.exercises)} · {fmtDate(new Date(a.at).toISOString().slice(0, 10), true)}</div>
        </div>
        <span className="kl-badge hot"><Icon name="sparkles" />{t('New')}</span>
      </div>
      {a.note && <div className="pt-note">{a.note}</div>}
      {!a.note && <div style={{ height: 12 }} />}
      <Button variant="primary" icon="plus" onClick={() => add(a)}>{t('Add to my plan')}</Button>
    </div>)}

    {coach && <>
      <h4 className="sec">{t('Check-ins')}</h4>
      <div className="card">
        <Thread messages={d.messages} mine="client" placeholder={t('Message {0}', coach)}
          quick={[t('Finished today’s session'), t('Feeling sore today'), t('Can we adjust my plan?')]}
          onSend={text => clientApi.message(text).then(() => load(true)).catch(e => toast(e.message))} />
      </div>
    </>}

    {!!added.length && <>
      <h4 className="sec">{t('In your plan')}</h4>
      {added.map(a => <div key={a.id} className="kl-assign">
        <div className="kl-assign-m">
          <div className="kl-assign-t">{a.name}</div>
          <div className="kl-assign-s">{t('Added {0}', fmtDate(new Date(a.accepted).toISOString().slice(0, 10), true))}</div>
        </div>
        <Button size="sm" variant="tinted" trailingIcon="chevronRight" onClick={() => nav('/plan')}>{t('Plan')}</Button>
      </div>)}
    </>}
  </div>
}
