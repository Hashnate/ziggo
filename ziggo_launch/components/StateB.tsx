'use client';

import Image from 'next/image';
import MagneticButton from './MagneticButton';

// ── Service definitions ────────────────────────────────────
// Drop real photos into /public/ and update the `image` field.
// Set `hasPhoto: true` when a real photo is available.
const SERVICES = [
  {
    id: 'rides',
    name: 'Rides',
    tagline: 'Your city, your pace',
    image: '/service-rides.jpg',
    hasPhoto: true,
    gradient: 'from-blue-900/80 via-blue-800/50 to-slate-900/80',
    accent: '#60A5FA',
    icon: '🚗',
  },
  {
    id: 'food',
    name: 'Food Delivery',
    tagline: 'Restaurant-grade to your door',
    image: null,
    hasPhoto: false,
    gradient: 'from-orange-900/80 via-amber-800/50 to-slate-900/80',
    accent: '#FB923C',
    icon: '🍽️',
  },
  {
    id: 'mart',
    name: 'Ziggo Mart',
    tagline: 'Daily essentials in minutes',
    image: null,
    hasPhoto: false,
    gradient: 'from-emerald-900/80 via-green-800/50 to-slate-900/80',
    accent: '#34D399',
    icon: '🛒',
  },
  {
    id: 'trucks',
    name: 'Trucks',
    tagline: 'Island-wide freight, on-demand',
    image: null,
    hasPhoto: false,
    gradient: 'from-yellow-900/80 via-amber-900/50 to-slate-900/80',
    accent: '#FCD34D',
    icon: '🚛',
  },
  {
    id: 'rental',
    name: 'Vehicle Rental',
    tagline: 'Premium fleet at your fingertips',
    image: null,
    hasPhoto: false,
    gradient: 'from-purple-900/80 via-violet-800/50 to-slate-900/80',
    accent: '#C084FC',
    icon: '🔑',
  },
  {
    id: 'events',
    name: 'Events',
    tagline: 'Access the best of Sri Lanka',
    image: null,
    hasPhoto: false,
    gradient: 'from-pink-900/80 via-rose-800/50 to-slate-900/80',
    accent: '#F472B6',
    icon: '🎟️',
  },
  {
    id: 'scan',
    name: 'Scan & Go',
    tagline: 'Retail reimagined, queue-free',
    image: null,
    hasPhoto: false,
    gradient: 'from-cyan-900/80 via-teal-800/50 to-slate-900/80',
    accent: '#22D3EE',
    icon: '📱',
  },
  {
    id: 'wallet',
    name: 'Ziggo Wallet',
    tagline: 'One wallet for everything',
    image: null,
    hasPhoto: false,
    gradient: 'from-rose-900/80 via-red-900/50 to-slate-900/80',
    accent: '#FB7185',
    icon: '💳',
  },
];

const APP_LINK = process.env.NEXT_PUBLIC_APP_LINK ?? 'https://ziggo.app';

export default function StateB() {
  return (
    <div className="relative w-screen h-screen flex flex-col overflow-hidden select-none bg-[#03061A]">
      {/* Ambient background glow */}
      <div
        className="absolute inset-0 z-0 pointer-events-none"
        style={{
          background: `
            radial-gradient(ellipse 80% 50% at 50% 20%, rgba(37,99,235,0.22) 0%, transparent 60%),
            radial-gradient(ellipse 60% 60% at 80% 80%, rgba(245,158,11,0.12) 0%, transparent 55%),
            linear-gradient(180deg, #03061A 0%, #050A1A 100%)
          `,
        }}
        aria-hidden="true"
      />

      {/* ── LIVE BANNER ─── */}
      <header className="relative z-30 flex-none w-full py-2.5 px-5 sm:px-10 flex items-center justify-between bg-emerald-900/20 border-b border-emerald-500/20 backdrop-blur-xl">
        <div className="flex items-center gap-2.5">
          <span className="relative flex h-2.5 w-2.5">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
            <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-emerald-500 shadow-[0_0_10px_#10B981]" />
          </span>
          <span className="font-['Outfit'] font-black text-xs sm:text-sm tracking-[0.2em] uppercase text-emerald-300">
            🟢 Ziggo is Live · Sri Lanka
          </span>
        </div>

        <MagneticButton strength={0.25}>
          <a
            href={APP_LINK}
            target="_blank"
            rel="noopener noreferrer"
            className="btn-cta !py-1.5 !px-5 !text-xs"
            aria-label="Open Ziggo App"
          >
            Open the App →
          </a>
        </MagneticButton>
      </header>

      {/* ── SERVICES GRID: 4 × 2, fills remaining height ─── */}
      <main className="relative z-10 flex-1 grid grid-cols-4 grid-rows-2 gap-2 sm:gap-3 p-2 sm:p-3 min-h-0">
        {SERVICES.map((svc) => (
          <ServiceCard key={svc.id} svc={svc} />
        ))}
      </main>

      {/* Footer strip */}
      <footer className="relative z-20 flex-none w-full px-6 py-2 border-t border-white/[0.04] bg-black/20 backdrop-blur-xl flex items-center justify-between">
        <Image src="/logo-light.png" alt="Ziggo" width={70} height={24} className="h-4 w-auto opacity-35" />
        <p className="text-[10px] text-white/20 font-['DM_Sans']">
          © {new Date().getFullYear()} Ziggo Technologies (Pvt) Ltd · Sri Lanka 🇱🇰
        </p>
        <p className="text-[10px] text-white/20 font-['DM_Sans'] hidden sm:block">All 8 services live now</p>
      </footer>
    </div>
  );
}

// ── Service Card ───────────────────────────────────────────
function ServiceCard({ svc }: { svc: typeof SERVICES[number] }) {
  return (
    <article
      className={`relative rounded-xl sm:rounded-2xl overflow-hidden border border-white/[0.08] group cursor-default transition-all duration-300 hover:-translate-y-0.5 hover:border-opacity-50`}
      style={{
        boxShadow: `0 8px 30px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.04)`,
        borderColor: `${svc.accent}22`,
      }}
      aria-label={`${svc.name} — ${svc.tagline}`}
    >
      {/* Background: real photo or premium gradient */}
      {svc.hasPhoto && svc.image ? (
        <Image
          src={svc.image}
          alt={`${svc.name} service — ${svc.tagline}`}
          fill
          className="object-cover transition-transform duration-700 group-hover:scale-[1.06]"
          sizes="25vw"
        />
      ) : (
        // Placeholder gradient until real photo is provided
        <div
          className={`absolute inset-0 bg-gradient-to-br ${svc.gradient}`}
          aria-hidden="true"
        >
          {/* Placeholder icon + drop real photo here hint */}
          <div className="absolute inset-0 flex items-center justify-center opacity-20">
            <span className="text-6xl sm:text-7xl" role="img" aria-hidden="true">{svc.icon}</span>
          </div>
          {/* Subtle grid texture */}
          <div
            className="absolute inset-0 opacity-[0.06]"
            style={{
              backgroundImage: 'linear-gradient(rgba(255,255,255,0.8) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.8) 1px, transparent 1px)',
              backgroundSize: '30px 30px',
            }}
          />
        </div>
      )}

      {/* Dark overlay for text legibility */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          background: 'linear-gradient(to bottom, rgba(0,0,0,0.1) 0%, rgba(0,0,0,0.75) 100%)',
        }}
        aria-hidden="true"
      />

      {/* Top glow accent on hover */}
      <div
        className="absolute top-0 left-0 right-0 h-px opacity-0 group-hover:opacity-100 transition-opacity duration-300"
        style={{ background: `linear-gradient(90deg, transparent, ${svc.accent}, transparent)` }}
        aria-hidden="true"
      />

      {/* Content */}
      <div className="absolute inset-0 flex flex-col justify-end p-3 sm:p-4">
        {/* Service badge */}
        <div className="mb-1.5">
          <span
            className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[9px] sm:text-[10px] font-bold uppercase tracking-wider border"
            style={{
              color: svc.accent,
              borderColor: `${svc.accent}40`,
              backgroundColor: `${svc.accent}15`,
            }}
          >
            <span>{svc.icon}</span>
            {svc.name}
          </span>
        </div>

        <p className="font-['DM_Sans'] text-[10px] sm:text-xs text-white/60 leading-snug line-clamp-1">
          {svc.tagline}
        </p>
      </div>

      {/* Corner "Live" indicator */}
      <div className="absolute top-2.5 right-2.5 flex items-center gap-1 px-1.5 py-0.5 rounded-full bg-black/50 border border-emerald-500/30 backdrop-blur-sm">
        <span className="w-1 h-1 rounded-full bg-emerald-400 animate-pulse" />
        <span className="text-[8px] font-bold text-emerald-300 uppercase tracking-wider">Live</span>
      </div>

      {/* PHOTO SLOT LABEL — remove this div when real photo is added */}
      {!svc.hasPhoto && (
        <div className="absolute inset-0 flex items-start justify-start p-2 pointer-events-none">
          <span className="text-[8px] text-white/20 font-['DM_Sans'] uppercase tracking-widest">
            ← Drop photo: /public/service-{svc.id}.jpg
          </span>
        </div>
      )}
    </article>
  );
}
