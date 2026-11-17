import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { t } from '../lib/i18n.js'
import { trainerApi, clientApi, sortRoster, rosterTotals, standing, tierMap } from '../lib/trainer.js'
import { tappable } from '../lib/use-sheet-keyboard.js'
import Icon from './Icon.jsx'
import { Avatar } from '../views/Trainer.jsx'

// Home's line to the coaching side (Klora). For the trainer: who needs her today. For a client:
// a routine or a reply waiting from their coach. Says nothing when there is nothing to say, and
// nothing when the server cannot be reached; the tab is always there.
export default function CoachingCard({ admin }) {
  const nav = useNavigate()
  const [d, setD] = useState(null)
  useEffect(() => {
    let gone = false
    ;(admin ? trainerApi.clients() : clientApi.training()).then(v => { if (!gone) setD(v) }).catch(() => {})
    return () => { gone = true }
  }, [admin])
  if (!d) return null

  if (admin) {
    const now = d.now || Date.now()
    const roster = sortRoster((d.clients || []).filter(c => !c.disabled), now)
    const totals = rosterTotals(roster, now)
    const tiers = tierMap(d.clients || [])
    const needing = roster.filter(c => ['needs-you', 'quiet'].includes(standing(c, now)))
    if (!roster.length) return null
    return <div className="card tappable pt-card kl-nudge" style={{ cursor: 'pointer', marginBottom: 12 }} {...tappable(() => nav('/trainer'))}>
      <div className="kl-stack">
        {(needing.length ? needing : roster).slice(0, 3).map(c => <Avatar key={c.id} id={c.id} name={c.name} tier={tiers[c.id]} />)}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <h2>{totals.needsYou ? `${totals.needsYou} ${totals.needsYou === 1 ? 'client needs' : 'clients need'} you` : needing.length ? `${needing.length} gone quiet` : 'Everyone’s on track'}</h2>
        <p>{totals.trainedThisWeek} of {totals.clients} trained this week</p>
      </div>
      <Icon name="chevronRight" className="chev" />
    </div>
  }

  const fresh = (d.assignments || []).filter(a => !a.accepted).length
  if (!d.trainer || (!fresh && !d.unread)) return null
  return <div className="card tappable pt-card kl-nudge" style={{ cursor: 'pointer', marginBottom: 12 }} {...tappable(() => nav('/coaching'))}>
    <Avatar id={d.trainer.name} name={d.trainer.name} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <h2>{fresh ? (fresh === 1 ? t('A new routine') : t('{0} new routines', fresh)) : (d.unread === 1 ? t('A new message') : t('{0} new messages', d.unread))}</h2>
      <p>{t('From {0}', d.trainer.name)}</p>
    </div>
    <Icon name="chevronRight" className="chev" />
  </div>
}
