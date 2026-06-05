import { useEffect, useState } from 'react'
import { api } from '../api'

/* ---------- mini sparkline ---------- */
function Spark({ data, stroke = '#2563EB', fill = 'rgba(37,99,235,0.14)' }) {
  const W = 140, H = 40, P = 3
  const max = Math.max(...data, 1)
  const n = data.length
  const X = (i) => P + (i * (W - 2 * P)) / Math.max(n - 1, 1)
  const Y = (v) => H - P - (v / max) * (H - 2 * P)
  const pts = data.map((v, i) => [X(i), Y(v)])
  const smooth = (ps) => {
    if (ps.length < 2) return ''
    let d = `M ${ps[0][0]},${ps[0][1]}`
    for (let i = 0; i < ps.length - 1; i++) {
      const p0 = ps[i - 1] || ps[i], p1 = ps[i], p2 = ps[i + 1], p3 = ps[i + 2] || p2
      d += ` C ${p1[0] + (p2[0] - p0[0]) / 6},${p1[1] + (p2[1] - p0[1]) / 6} ${p2[0] - (p3[0] - p1[0]) / 6},${p2[1] - (p3[1] - p1[1]) / 6} ${p2[0]},${p2[1]}`
    }
    return d
  }
  const line = smooth(pts)
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full" style={{ height: 40 }} preserveAspectRatio="none">
      <path d={`${line} L ${X(n - 1)},${H} L ${X(0)},${H} Z`} fill={fill} />
      <path d={line} fill="none" stroke={stroke} strokeWidth="2.2" strokeLinecap="round" />
    </svg>
  )
}

/* ---------- main area chart ---------- */
function AreaChart({ labels, data }) {
  const W = 680, H = 230, P = 28
  const n = data.length, max = Math.max(...data, 1)
  const X = (i) => P + (i * (W - 2 * P)) / Math.max(n - 1, 1)
  const Y = (v) => H - P - (v / max) * (H - 2 * P)
  const pts = data.map((v, i) => [X(i), Y(v)])
  const smooth = (ps) => {
    if (ps.length < 2) return ''
    let d = `M ${ps[0][0]},${ps[0][1]}`
    for (let i = 0; i < ps.length - 1; i++) {
      const p0 = ps[i - 1] || ps[i], p1 = ps[i], p2 = ps[i + 1], p3 = ps[i + 2] || p2
      d += ` C ${p1[0] + (p2[0] - p0[0]) / 6},${p1[1] + (p2[1] - p0[1]) / 6} ${p2[0] - (p3[0] - p1[0]) / 6},${p2[1] - (p3[1] - p1[1]) / 6} ${p2[0]},${p2[1]}`
    }
    return d
  }
  const line = smooth(pts)
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full" style={{ height: 210 }} preserveAspectRatio="none">
      <defs>
        <linearGradient id="rf" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#2563EB" stopOpacity="0.18" /><stop offset="100%" stopColor="#2563EB" stopOpacity="0" /></linearGradient>
      </defs>
      {[0, 0.33, 0.66, 1].map((t, i) => <line key={i} x1={P} x2={W - P} y1={P + t * (H - 2 * P)} y2={P + t * (H - 2 * P)} stroke="#F0F2F7" strokeWidth="1" />)}
      <path d={`${line} L ${X(n - 1)},${H - P} L ${X(0)},${H - P} Z`} fill="url(#rf)" />
      <path d={line} fill="none" stroke="#2563EB" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      {pts.map((p, i) => (<g key={i}><circle cx={p[0]} cy={p[1]} r="4" fill="#fff" stroke="#2563EB" strokeWidth="2.5" /><text x={p[0]} y={H - 6} textAnchor="middle" fontSize="11" fill="#94A0B2" fontWeight="600" fontFamily="Manrope">{labels[i]}</text></g>))}
    </svg>
  )
}

function Donut({ value, total }) {
  const r = 50, c = 2 * Math.PI * r, pct = total ? value / total : 0
  return (
    <svg viewBox="0 0 130 130" className="w-32 h-32">
      <circle cx="65" cy="65" r={r} fill="none" stroke="#EEF1F7" strokeWidth="13" />
      <circle cx="65" cy="65" r={r} fill="none" stroke="#2563EB" strokeWidth="13" strokeLinecap="round" strokeDasharray={`${c * pct} ${c}`} transform="rotate(-90 65 65)" />
      <text x="65" y="62" textAnchor="middle" fontSize="24" fontWeight="800" fill="#0B1220" fontFamily="Sora">{Math.round(pct * 100)}%</text>
      <text x="65" y="81" textAnchor="middle" fontSize="10" fill="#94A0B2" fontWeight="600" fontFamily="Manrope">online</text>
    </svg>
  )
}

const trendOf = (series) => {
  const recent = series.slice(-3).reduce((a, b) => a + b, 0)
  const older = series.slice(-6, -3).reduce((a, b) => a + b, 0)
  return older ? Math.round(((recent - older) / older) * 100) : (recent ? 100 : 0)
}

function Stat({ label, value, icon, tint, spark, sparkColor, sparkFill }) {
  const t = trendOf(spark), up = t >= 0
  return (
    <div className="bg-white rounded-2xl border border-ziggo-line p-5 transition-all hover:shadow-card hover:-translate-y-0.5">
      <div className="flex items-center justify-between">
        <span className={`w-10 h-10 rounded-xl flex items-center justify-center text-[16px] ${tint}`}><i className={`fas ${icon}`} /></span>
        <span className={`text-[11px] font-bold px-2 py-0.5 rounded-md flex items-center gap-1 ${up ? 'text-emerald-700 bg-emerald-50' : 'text-rose-700 bg-rose-50'}`}>
          <i className={`fas ${up ? 'fa-arrow-up' : 'fa-arrow-down'} text-[9px]`} />{Math.abs(t)}%
        </span>
      </div>
      <p className="mt-4 text-[12px] font-semibold text-ziggo-muted">{label}</p>
      <p className="text-[26px] font-display font-extrabold text-ziggo-ink leading-none mt-1 tnum">{value}</p>
      <div className="mt-3 -mx-1"><Spark data={spark} stroke={sparkColor} fill={sparkFill} /></div>
    </div>
  )
}

export default function Dashboard() {
  const [d, setD] = useState(null)
  const [err, setErr] = useState('')
  useEffect(() => { api.dashboard().then(setD).catch(() => setErr('Failed to load dashboard')) }, [])

  if (err) return <p className="text-rose-600 font-semibold">{err}</p>
  if (!d) return <DashSkeleton />

  const s = d.stats, sp = d.spark
  const series = d.revenue_7d.data
  const week = series.reduce((a, b) => a + b, 0)
  const rt = trendOf(series), up = rt >= 0
  const today = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })

  return (
    <div className="space-y-4">
      {/* Hero */}
      <div className="relative overflow-hidden rounded-2xl p-6 text-white bg-gradient-to-br from-ziggo via-ziggo-light to-blue-500 shadow-card">
        <div className="absolute -top-16 -right-10 w-72 h-72 rounded-full bg-white/10 blur-2xl" />
        <div className="absolute -bottom-20 right-40 w-56 h-56 rounded-full bg-white/10 blur-2xl" />
        <div className="relative flex flex-col md:flex-row md:items-end md:justify-between gap-5">
          <div>
            <p className="text-[12px] uppercase tracking-[0.18em] text-white/70 font-semibold">{today}</p>
            <h2 className="text-[28px] font-display font-extrabold mt-1.5">Welcome back, Admin 👋</h2>
            <p className="text-white/75 mt-1 text-sm">Here's everything happening across Ziggo today.</p>
          </div>
          <div className="flex items-center gap-3">
            <div className="rounded-xl bg-white/10 backdrop-blur px-4 py-3 border border-white/15">
              <p className="text-[11px] uppercase tracking-wider text-white/70 font-semibold">This week</p>
              <div className="flex items-center gap-2">
                <p className="text-2xl font-display font-extrabold tnum">Rs.{week.toLocaleString()}</p>
                <span className="text-[11px] font-bold bg-white/15 rounded-md px-1.5 py-0.5">{up ? '▲' : '▼'} {Math.abs(rt)}%</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* KPI cards with sparklines */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Stat label="Total Customers" value={s.customers.toLocaleString()} icon="fa-users" tint="bg-blue-50 text-blue-600" spark={sp.customers} sparkColor="#2563EB" sparkFill="rgba(37,99,235,0.14)" />
        <Stat label="Total Drivers" value={s.drivers.toLocaleString()} icon="fa-id-card" tint="bg-orange-50 text-orange-600" spark={sp.drivers} sparkColor="#EA580C" sparkFill="rgba(234,88,12,0.12)" />
        <Stat label="Total Bookings" value={s.bookings.toLocaleString()} icon="fa-receipt" tint="bg-emerald-50 text-emerald-600" spark={sp.bookings} sparkColor="#059669" sparkFill="rgba(5,150,105,0.12)" />
        <Stat label="Revenue" value={'Rs.' + s.revenue.toLocaleString()} icon="fa-coins" tint="bg-amber-50 text-amber-600" spark={sp.revenue} sparkColor="#D97706" sparkFill="rgba(217,119,6,0.12)" />
      </div>

      {/* Chart + Donut */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="lg:col-span-2 bg-white rounded-2xl border border-ziggo-line p-6">
          <div className="flex items-start justify-between mb-2">
            <div>
              <div className="flex items-center gap-2.5">
                <h3 className="font-display font-bold text-ziggo-ink text-[17px]">Revenue performance</h3>
                <span className={`text-[11px] font-bold px-2 py-0.5 rounded-md flex items-center gap-1 ${up ? 'text-emerald-700 bg-emerald-50' : 'text-rose-700 bg-rose-50'}`}><i className={`fas ${up ? 'fa-arrow-up' : 'fa-arrow-down'} text-[9px]`} />{Math.abs(rt)}%</span>
              </div>
              <p className="text-xs text-ziggo-muted mt-0.5">Daily revenue across all services · last 7 days</p>
            </div>
            <div className="text-right"><p className="text-[11px] uppercase tracking-wider text-ziggo-faint font-semibold">7-day total</p><p className="text-lg font-display font-extrabold text-ziggo-ink tnum">Rs.{week.toLocaleString()}</p></div>
          </div>
          <AreaChart labels={d.revenue_7d.labels} data={series} />
        </div>

        <div className="bg-white rounded-2xl border border-ziggo-line p-6 flex flex-col">
          <h3 className="font-display font-bold text-ziggo-ink text-[17px]">Fleet status</h3>
          <p className="text-xs text-ziggo-muted">Drivers currently online</p>
          <div className="flex-1 flex items-center justify-center py-3"><Donut value={s.online_drivers} total={s.drivers} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-xl bg-ziggo-canvas p-3 text-center"><p className="text-[11px] text-ziggo-muted font-semibold">Online</p><p className="text-lg font-display font-extrabold text-ziggo-ink tnum">{s.online_drivers}</p></div>
            <div className="rounded-xl bg-ziggo-canvas p-3 text-center"><p className="text-[11px] text-ziggo-muted font-semibold">Offline</p><p className="text-lg font-display font-extrabold text-ziggo-ink tnum">{Math.max(s.drivers - s.online_drivers, 0)}</p></div>
          </div>
        </div>
      </div>

      {/* Today */}
      <div className="bg-white rounded-2xl border border-ziggo-line p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-display font-bold text-ziggo-ink text-[17px]">Today's activity</h3>
          <span className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-emerald-600"><i className="fas fa-circle text-[6px] animate-pulse" /> Live</span>
        </div>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <Mini icon="fa-car-side" color="text-blue-600 bg-blue-50" label="Online drivers" value={s.online_drivers} />
          <Mini icon="fa-user-clock" color="text-amber-600 bg-amber-50" label="Pending approvals" value={s.pending_drivers} />
          <Mini icon="fa-circle-check" color="text-emerald-600 bg-emerald-50" label="Completed today" value={s.completed_today} />
          <Mini icon="fa-circle-xmark" color="text-rose-600 bg-rose-50" label="Cancelled today" value={s.cancelled_today} />
        </div>
      </div>
    </div>
  )
}

function Mini({ icon, color, label, value }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-ziggo-line p-3.5">
      <span className={`w-10 h-10 rounded-xl flex items-center justify-center ${color}`}><i className={`fas ${icon}`} /></span>
      <div><p className="text-[11px] text-ziggo-muted font-semibold">{label}</p><p className="text-xl font-display font-extrabold text-ziggo-ink tnum leading-none mt-0.5">{value}</p></div>
    </div>
  )
}

function DashSkeleton() {
  return (
    <div className="space-y-4 animate-pulse">
      <div className="h-40 bg-white rounded-2xl border border-ziggo-line" />
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">{[0, 1, 2, 3].map((i) => <div key={i} className="h-44 bg-white rounded-2xl border border-ziggo-line" />)}</div>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4"><div className="lg:col-span-2 h-80 bg-white rounded-2xl border border-ziggo-line" /><div className="h-80 bg-white rounded-2xl border border-ziggo-line" /></div>
    </div>
  )
}
