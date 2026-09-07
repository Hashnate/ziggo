'use client';

const SERVICES = [
  {
    id: 'rides',
    name: 'Rides',
    subtitle: 'City Mobility',
    icon: '🚗',
    color: '#60A5FA',
    borderGlow: 'rgba(96, 165, 250, 0.4)',
    badge: 'LIVE ON DAY 1',
  },
  {
    id: 'food',
    name: 'Food',
    subtitle: 'Fast Delivery',
    icon: '🍔',
    color: '#FB923C',
    borderGlow: 'rgba(251, 146, 60, 0.4)',
    badge: 'TOP RESTAURANTS',
  },
  {
    id: 'mart',
    name: 'Mart',
    subtitle: 'Instant Grocery',
    icon: '🛍️',
    color: '#34D399',
    borderGlow: 'rgba(52, 211, 153, 0.4)',
    badge: 'SUPERMARKET',
  },
  {
    id: 'trucks',
    name: 'Trucks',
    subtitle: 'Logistics & Moves',
    icon: '🚚',
    color: '#FBBF24',
    borderGlow: 'rgba(251, 191, 36, 0.4)',
    badge: 'HEAVY MOVERS',
  },
  {
    id: 'rental',
    name: 'Rental',
    subtitle: 'Vehicle Fleet',
    icon: '🔑',
    color: '#A78BFA',
    borderGlow: 'rgba(167, 139, 250, 0.4)',
    badge: 'CARS & BIKES',
  },
  {
    id: 'events',
    name: 'Events',
    subtitle: 'VIP Experiences',
    icon: '🎟️',
    color: '#F472B6',
    borderGlow: 'rgba(244, 114, 182, 0.4)',
    badge: 'CONCERTS & SHOWS',
  },
];

export default function StageServicePills() {
  return (
    <div className="w-full max-w-5xl mx-auto px-2">
      {/* Category Header Label */}
      <div className="flex items-center justify-center gap-3 mb-3 sm:mb-4">
        <div className="h-px w-8 sm:w-16 bg-gradient-to-r from-transparent to-blue-400/40" />
        <span className="font-['DM_Sans'] text-[11px] sm:text-xs font-bold uppercase tracking-[0.25em] text-blue-200/70">
          6 Core Pillars • Powered by One Super App
        </span>
        <div className="h-px w-8 sm:w-16 bg-gradient-to-l from-transparent to-blue-400/40" />
      </div>

      {/* Grid of 6 Service Capsules */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2.5 sm:gap-3">
        {SERVICES.map((s, idx) => (
          <div
            key={s.id}
            className="service-hud-card p-3 sm:p-3.5 flex flex-col items-center text-center cursor-default transition-all duration-300 hover:scale-105 group"
            style={{
              boxShadow: `0 10px 30px -10px ${s.borderGlow}`,
              animationDelay: `${idx * 60}ms`,
            }}
          >
            {/* Top Micro Glowing Dot */}
            <div
              className="w-1.5 h-1.5 rounded-full mb-1.5 transition-transform group-hover:scale-150"
              style={{ backgroundColor: s.color, boxShadow: `0 0 8px ${s.color}` }}
            />

            {/* Icon */}
            <span className="text-2xl sm:text-3xl filter drop-shadow-md mb-1 transition-transform group-hover:scale-110">
              {s.icon}
            </span>

            {/* Service Name */}
            <span className="font-['Outfit'] font-bold text-white text-sm sm:text-base leading-tight">
              {s.name}
            </span>

            {/* Subtitle */}
            <span className="font-['DM_Sans'] text-[10px] sm:text-[11px] text-white/50 group-hover:text-white/80 transition-colors">
              {s.subtitle}
            </span>

            {/* Micro Badge */}
            <span
              className="mt-2 text-[8px] sm:text-[9px] font-extrabold uppercase px-2 py-0.5 rounded-full border tracking-wider"
              style={{
                borderColor: `${s.color}40`,
                color: s.color,
                backgroundColor: `${s.color}15`,
              }}
            >
              {s.badge}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
