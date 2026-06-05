import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import { api } from '../api'

const NAV = [
  { group: 'Overview', items: [{ to: '/', icon: 'fa-grip', label: 'Dashboard', end: true }] },
  // Future groups (Operations, Finance, …) drop in as pages are built.
]

export default function Layout({ user }) {
  const navigate = useNavigate()
  async function logout() {
    try { await api.logout() } catch (e) {}
    navigate('/login'); window.location.reload()
  }

  return (
    <div className="flex h-screen overflow-hidden bg-[#FAFBFD]">
      {/* Clean white sidebar */}
      <aside className="w-[252px] shrink-0 flex flex-col bg-white border-r border-ziggo-line">
        <div className="px-5 h-[64px] flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-blue-500 to-ziggo flex items-center justify-center font-black text-white">Z</div>
          <span className="font-display font-extrabold text-[16px] text-ziggo-ink">Ziggo</span>
          <span className="ml-1 text-[9px] font-bold text-ziggo px-1.5 py-0.5 rounded bg-ziggo-soft uppercase tracking-wider">Admin</span>
        </div>

        <nav className="flex-1 px-3 py-3 overflow-y-auto">
          {NAV.map((g) => (
            <div key={g.group} className="mb-5">
              <p className="px-3 pb-2 text-[10px] font-bold uppercase tracking-[0.14em] text-ziggo-faint">{g.group}</p>
              <div className="space-y-0.5">
                {g.items.map((n) => (
                  <NavLink key={n.to} to={n.to} end={n.end}
                    className={({ isActive }) =>
                      `group relative flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-semibold transition-all ${
                        isActive ? 'bg-ziggo-soft text-ziggo' : 'text-ziggo-muted hover:bg-ziggo-canvas hover:text-ziggo-ink'
                      }`}>
                    {({ isActive }) => (
                      <>
                        {isActive && <span className="absolute left-0 top-1/2 -translate-y-1/2 w-1 h-5 rounded-r-full bg-ziggo" />}
                        <i className={`fas ${n.icon} w-5 text-center text-[15px] ${isActive ? 'text-ziggo' : 'text-ziggo-faint group-hover:text-ziggo-muted'}`} />
                        {n.label}
                      </>
                    )}
                  </NavLink>
                ))}
              </div>
            </div>
          ))}
        </nav>

        <div className="p-3 border-t border-ziggo-line">
          <button onClick={logout} className="w-full px-3 py-2.5 rounded-lg text-sm font-semibold text-ziggo-muted hover:bg-rose-50 hover:text-rose-600 transition flex items-center gap-3">
            <i className="fas fa-arrow-right-from-bracket w-5 text-center text-[15px]" /> Sign out
          </button>
        </div>
      </aside>

      {/* Content */}
      <main className="flex-1 flex flex-col overflow-hidden min-w-0">
        <header className="h-[64px] shrink-0 bg-white/80 backdrop-blur border-b border-ziggo-line px-7 flex items-center justify-between">
          <div className="relative hidden sm:block w-80">
            <i className="fas fa-magnifying-glass absolute left-3.5 top-1/2 -translate-y-1/2 text-ziggo-faint text-[13px]" />
            <input placeholder="Search…" className="w-full pl-10 pr-3 py-2.5 rounded-lg bg-ziggo-canvas border border-transparent text-sm text-ziggo-ink placeholder-ziggo-faint outline-none focus:border-ziggo focus:bg-white transition" />
          </div>
          <div className="flex items-center gap-4">
            <button className="text-ziggo-muted hover:text-ziggo-ink transition relative w-9 h-9 flex items-center justify-center">
              <i className="far fa-bell text-lg" />
              <span className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-rose-500 ring-2 ring-white" />
            </button>
            <div className="flex items-center gap-3 pl-4 border-l border-ziggo-line">
              <div className="text-right leading-tight hidden sm:block">
                <p className="text-sm font-bold text-ziggo-ink">{user.name}</p>
                <p className="text-[10px] text-ziggo-faint capitalize">{user.role}</p>
              </div>
              <div className="w-9 h-9 rounded-full bg-gradient-to-br from-blue-500 to-ziggo text-white flex items-center justify-center font-bold text-sm">
                {(user.name || 'A')[0].toUpperCase()}
              </div>
            </div>
          </div>
        </header>

        <div className="flex-1 overflow-y-auto px-6 py-5">
          <div className="max-w-[1680px] mx-auto zi-in">
            <Outlet />
          </div>
        </div>
      </main>
    </div>
  )
}
