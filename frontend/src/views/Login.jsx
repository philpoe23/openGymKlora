import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { webauthnOK, passkeyLogin, passkeyRegister, passkeyError, bio } from '../lib/api.js'
import { hasData } from '../store/useStore.js'
import { t } from '../lib/i18n.js'
import { DEMO, REPO } from '../lib/demo.js'
import { guestAllowed } from '../lib/guest.js'
import { useState, useRef, useEffect } from 'react'
import Icon from '../components/Icon.jsx'
import { Button, Segmented } from '../components/ui.jsx'
import { askAddDeviceData } from '../sheets.jsx'
import { passwordOn, PasswordRegisterForm, openPasswordSignIn } from '../components/PasswordAuth.jsx'
import { openDeviceLinkRedeem } from '../components/Passkeys.jsx'
import logoUrl from '../assets/klora-logo.png'

function RegisterSheet({ close }) {
  const { setUser, pushState, pullState, loadConfig } = useStore()
  const config = useStore(s => s.config)
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const inviteOnly = !!config?.invite_only
  // A password is offered only where the instance allows it (#118), and is the only choice in a
  // browser that cannot make a passkey. Where both work, the passkey stays the first one.
  const pwOn = passwordOn(config)
  const [how, setHow] = useState(webauthnOK() ? 'passkey' : 'password')
  const ref = useRef(null)
  useEffect(() => { setTimeout(() => ref.current?.focus(), 250) }, [])
  // Boot already fetched this; retry here only if that attempt failed, so the invite field still
  // appears on an instance whose config arrived late rather than never.
  useEffect(() => { loadConfig() }, [loadConfig])
  const go = async () => {
    const n = name.trim()
    if (!n) { useUI.getState().toast(t('Enter a name')); return }
    if (inviteOnly && !code.trim()) { useUI.getState().toast(t('An invite code is required')); return }
    try {
      const u = await passkeyRegister(n, code.trim())
      setUser(u); close()
      if (hasData(useStore.getState().S)) { await pushState(); useUI.getState().toast(t('Profile created, and this device’s data moved into it')) }
      else { await pullState(); useUI.getState().toast(t('Welcome, {0}', u.name)) }
    } catch (e) { if (e.name !== 'NotAllowedError' && e.name !== 'AbortError') useUI.getState().toast(passkeyError(e, t('Registration failed'))) }
  }
  const choose = pwOn && webauthnOK() && <>
    <Segmented options={[{ value: 'passkey', label: t('Passkey'), icon: 'fingerprint' }, { value: 'password', label: t('Password'), icon: 'key' }]}
      value={how} onChange={setHow} />
    <div style={{ height: 12 }} />
  </>
  if (pwOn && how === 'password') return <>
    <h3>{t('Create your profile')}</h3>
    {choose}
    <div className="muted small" style={{ marginBottom: 14 }}>{t('Pick a name and a password. You sign in with both.')}</div>
    <PasswordRegisterForm close={close} inviteOnly={inviteOnly} name={name} setName={setName} code={code} setCode={setCode} />
  </>
  return <>
    <h3>{t('Create your profile')}</h3>
    {choose}
    <div className="muted small" style={{ marginBottom: 14 }}>{t('Pick a name, then confirm with {0}. The passkey lives on your device, so no password needed.', bio())}</div>
    <input ref={ref} className="input" placeholder={t('Your name')} maxLength={40} value={name} onChange={e => setName(e.target.value)} />
    {inviteOnly && <>
      <div style={{ height: 10 }} />
      <input className="input" placeholder={t('Invite code')} maxLength={40} value={code}
        onChange={e => setCode(e.target.value.toUpperCase())} style={{ letterSpacing: '.14em', fontWeight: 600, textAlign: 'center' }} />
      <div className="dim small" style={{ marginTop: 6 }}>{t('This app is invite-only. Enter the code you were given.')}</div>
    </>}
    <div style={{ height: 12 }} />
    <Button variant="primary" onClick={go}>{t('Create passkey')}</Button>
  </>
}

// The brand mark: Klora's own logo, the cream wordmark on its pink pebble (assets/).
export function KloraMark() {
  return <div className="kl-mark"><img src={logoUrl} alt="Klora" width="180" height="81" /></div>
}

function Intro() {
  return <div>
    <KloraMark />
    <h1 className="kl-hero">{t('Train with')} <em>Klora.</em></h1>
    <p className="kl-lede">{t('Your sessions, your progress and your coach, in one place.')}</p>
    <div className="kl-weights" aria-hidden="true">
      <span className="rk rk-rose" /><span className="rk rk-lilac" /><span className="rk rk-mint" /><span className="rk rk-butter" />
    </div>
  </div>
}

export default function Login() {
  const { setUser, adoptProfile, setGuest } = useStore()
  const config = useStore(s => s.config)
  const canGuest = guestAllowed(config)
  const pwOn = passwordOn(config)
  const canJoin = webauthnOK() || pwOn
  const [mode, setMode] = useState('in')
  const signIn = async () => {
    try { const u = await passkeyLogin(); setUser(u, { adopt: true }); await adoptProfile(askAddDeviceData); useUI.getState().toast(t('Welcome back, {0}', u.name)) }
    catch (e) { if (e.name !== 'NotAllowedError' && e.name !== 'AbortError') useUI.getState().toast(passkeyError(e, t('Sign-in failed'))) }
  }

  // Demo build: no backend to sign in against — the only way in is the local guest profile.
  if (DEMO) return (
    <div className="kl-login">
      <Intro />
      <div className="kl-panel">
        <div className="muted" style={{ marginBottom: 16 }}>{t('Live demo. Everything stays in this browser.')}</div>
        <Button variant="primary" icon="play" onClick={() => setGuest(true)}>{t('Start the demo')}</Button>
        <div className="small muted" style={{ marginTop: 14, lineHeight: 1.45 }}>
          {t('This demo runs entirely in your browser on example data. Nothing is sent anywhere.')}
        </div>
        <div className="kl-foot"><a href={REPO} target="_blank" rel="noopener">{t('Self-host it in a minute →')}</a></div>
      </div>
    </div>
  )

  const signInPanel = webauthnOK() ? <>
    <h3>{t('Welcome back')}</h3>
    <div className="muted small" style={{ marginBottom: 16 }}>{t('Sign in to pick up where you left off.')}</div>
    <Button variant="primary" icon="fingerprint" onClick={signIn}>{t('Sign in with passkey')}</Button>
    {pwOn && <><div style={{ height: 10 }} /><Button icon="key" onClick={() => openPasswordSignIn()}>{t('Sign in with password')}</Button></>}
    {/* Already signed in on another device: a code from there gives this one a passkey of
        its own (#95), instead of a new, empty profile. */}
    <div style={{ height: 6 }} />
    <Button variant="ghost" icon="qr" onClick={openDeviceLinkRedeem}>{t('Use a code from your other device')}</Button>
  </> : pwOn ? <>
    {/* Plain http on a LAN address, or a browser without passkey support: the password is
        the way in, and the only way to create a profile from here. */}
    <h3>{t('Welcome back')}</h3>
    <div className="muted small" style={{ marginBottom: 16 }}>{t("This browser doesn't support passkeys. Sign in with your name and password instead.")}</div>
    <Button variant="primary" icon="key" onClick={() => openPasswordSignIn()}>{t('Sign in with password')}</Button>
  </> : <div className="small muted" style={{ lineHeight: 1.45 }}>{canGuest
    ? t("This browser doesn't do passkeys, but you can still use Klora locally on this device.")
    // Without passkeys and without the guest entrance there is no way in from this browser,
    // so say that plainly instead of offering a local profile that cannot be created.
    : t("This browser doesn't support passkeys, and this instance requires an account. Try a browser or device with passkey support.")}</div>

  return (
    <div className="kl-login">
      <Intro />
      <div>
        <div className="kl-panel">
          {canJoin && <Segmented options={[{ value: 'in', label: t('Sign in') }, { value: 'join', label: t('Create new profile') }]} value={mode} onChange={setMode} />}
          {mode === 'join' && canJoin ? <RegisterSheet close={() => setMode('in')} /> : signInPanel}
          {canGuest && <><div className="kl-or">{t('or')}</div>
            <Button variant="ghost" onClick={() => setGuest(true)}>{t('Continue without account')}</Button></>}
        </div>
        <div className="kl-foot">{pwOn ? t('Passkeys use {0}. A password works too, where passkeys do not.', bio()) : t('Passkeys use {0}. No passwords to remember.', bio())}<br />{t('Each profile keeps its own plan, workouts & body weight.')}</div>
      </div>
    </div>
  )
}
