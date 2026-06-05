import { useState } from 'react'
import { api } from '../api'

export default function Login({ onLogin }) {
  const [phone, setPhone] = useState('')
  const [pw, setPw] = useState('')
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setBusy(true); setErr('')
    try {
      await api.login(phone, pw)
      const me = await api.me()
      onLogin(me)
    } catch (e) {
      setErr(e.detail || 'Login failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="min-h-screen grid lg:grid-cols-2">
      {/* Left brand panel */}
      <div className="hidden lg:flex flex-col justify-between p-12 text-white relative overflow-hidden bg-ziggo-dark">
        <div className="absolute -top-24 -left-16 w-96 h-96 rounded-full bg-blue-600/30 blur-3xl" />
        <div className="absolute bottom-0 right-0 w-80 h-80 rounded-full bg-indigo-500/20 blur-3xl" />
        <div className="relative flex items-center gap-3">
          <div className="w-11 h-11 rounded-xl bg-gradient-to-br from-blue-500 to-ziggo flex items-center justify-center font-black text-xl shadow-glow">Z</div>
          <span className="font-display font-extrabold text-lg">Ziggo Admin</span>
        </div>
        <div className="relative">
          <h1 className="text-4xl font-display font-extrabold leading-tight">Run Sri Lanka's<br />super app, beautifully.</h1>
          <p className="text-white/60 mt-4 max-w-md">Rides, food, market, parcels & finance — one premium console for your whole operation.</p>
        </div>
        <p className="relative text-[11px] text-white/40">© 2026 Ziggo Lanka (Pvt) Ltd</p>
      </div>

      {/* Right form */}
      <div className="flex items-center justify-center p-6">
        <div className="w-full max-w-sm zi-in">
          <div className="lg:hidden text-center mb-7">
            <div className="w-14 h-14 mx-auto rounded-2xl bg-gradient-to-br from-blue-500 to-ziggo text-white flex items-center justify-center text-2xl font-black shadow-glow">Z</div>
          </div>
          <h2 className="text-2xl font-display font-extrabold text-ziggo-ink">Welcome back</h2>
          <p className="text-sm text-ziggo-muted mt-1 mb-6">Sign in to continue to the dashboard.</p>

          <form onSubmit={submit} className="space-y-4">
            {err && (
              <div className="bg-rose-50 text-rose-600 text-sm rounded-xl px-4 py-3 font-semibold flex items-center gap-2">
                <i className="fas fa-circle-exclamation" /> {err}
              </div>
            )}
            <div>
              <label className="text-xs font-semibold text-ziggo-muted">Phone number</label>
              <div className="relative mt-1.5">
                <i className="fas fa-phone absolute left-3.5 top-1/2 -translate-y-1/2 text-ziggo-faint text-sm" />
                <input value={phone} onChange={(e) => setPhone(e.target.value)} className="w-full pl-10 pr-3 py-3 bg-ziggo-canvas border border-transparent rounded-xl outline-none focus:border-ziggo focus:bg-white transition" placeholder="0700000000" />
              </div>
            </div>
            <div>
              <label className="text-xs font-semibold text-ziggo-muted">Password</label>
              <div className="relative mt-1.5">
                <i className="fas fa-lock absolute left-3.5 top-1/2 -translate-y-1/2 text-ziggo-faint text-sm" />
                <input type="password" value={pw} onChange={(e) => setPw(e.target.value)} className="w-full pl-10 pr-3 py-3 bg-ziggo-canvas border border-transparent rounded-xl outline-none focus:border-ziggo focus:bg-white transition" placeholder="••••••••" />
              </div>
            </div>
            <button disabled={busy} className="w-full py-3 bg-ziggo text-white rounded-xl font-bold shadow-glow hover:bg-ziggo-light transition disabled:opacity-60 flex items-center justify-center gap-2">
              {busy ? <><i className="fas fa-spinner fa-spin" /> Signing in…</> : <>Sign In <i className="fas fa-arrow-right text-xs" /></>}
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}
