const services = [
  {
    icon: '🚗',
    name: 'Ziggo Rides',
    tagline: 'Book a ride in seconds',
    description: 'Safe, fast, affordable rides at the tap of a button.',
    color: 'from-blue-500/20 to-blue-700/10',
    accent: 'rgba(59,130,246,0.35)',
  },
  {
    icon: '🍔',
    name: 'Ziggo Food',
    tagline: 'Fresh food, delivered fast',
    description: 'Your favourite restaurants, delivered to your door.',
    color: 'from-orange-500/20 to-red-700/10',
    accent: 'rgba(249,115,22,0.30)',
  },
  {
    icon: '🛍️',
    name: 'Ziggo Mart',
    tagline: 'Groceries & more',
    description: 'Supermarket essentials and everyday goods, delivered.',
    color: 'from-emerald-500/20 to-green-700/10',
    accent: 'rgba(16,185,129,0.30)',
  },
  {
    icon: '🚛',
    name: 'Ziggo Trucks',
    tagline: 'Move anything, anywhere',
    description: 'Heavy-duty truck hire for moves, deliveries & logistics.',
    color: 'from-yellow-500/20 to-amber-700/10',
    accent: 'rgba(245,158,11,0.30)',
  },
  {
    icon: '🏍️',
    name: 'Ziggo Rental',
    tagline: 'Vehicles on your schedule',
    description: 'Rent cars, bikes & tuk-tuks by the hour or the day.',
    color: 'from-purple-500/20 to-violet-700/10',
    accent: 'rgba(139,92,246,0.30)',
  },
  {
    icon: '🎟️',
    name: 'Ziggo Events',
    tagline: 'Discover what\'s happening',
    description: 'Find, book & attend the best events across Sri Lanka.',
    color: 'from-pink-500/20 to-rose-700/10',
    accent: 'rgba(236,72,153,0.30)',
  },
];

export default function FeatureTeaser() {
  return (
    <section
      className="relative py-20 md:py-28 px-4 overflow-hidden"
      aria-labelledby="features-heading"
    >
      {/* Subtle background accent */}
      <div
        className="absolute inset-0 opacity-30"
        style={{
          background:
            'radial-gradient(ellipse at 50% 50%, rgba(30,58,138,0.3) 0%, transparent 70%)',
        }}
        aria-hidden="true"
      />

      <div className="relative z-10 max-w-6xl mx-auto">
        {/* Section header */}
        <div className="text-center mb-12 md:mb-16">
          <span className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full glass text-xs font-semibold tracking-widest uppercase text-brand-glow/80 mb-5">
            Everything in One App
          </span>
          <h2
            id="features-heading"
            className="font-['Outfit'] font-black text-white leading-tight"
            style={{
              fontSize: 'clamp(1.8rem, 4vw, 3rem)',
              letterSpacing: '-0.025em',
            }}
          >
            Six super-powers.{' '}
            <span
              style={{
                background: 'linear-gradient(135deg, #60A5FA 0%, #93C5FD 100%)',
                WebkitBackgroundClip: 'text',
                backgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
              }}
            >
              One app.
            </span>
          </h2>
          <p className="mt-3 text-white/50 font-['DM_Sans'] max-w-md mx-auto leading-relaxed">
            Ziggo brings everything you need to live, move, eat and explore — all under one roof.
          </p>
        </div>

        {/* Cards grid */}
        <div
          className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 md:gap-5"
          role="list"
        >
          {services.map((service, i) => (
            <article
              key={service.name}
              className="feature-card glass rounded-2xl p-6 md:p-7 flex flex-col gap-3 cursor-default"
              style={{
                animationDelay: `${i * 80}ms`,
              }}
              role="listitem"
            >
              {/* Icon */}
              <div
                className="w-14 h-14 rounded-2xl flex items-center justify-center text-3xl flex-shrink-0"
                style={{
                  background: `radial-gradient(ellipse at 30% 30%, ${service.accent} 0%, rgba(255,255,255,0.05) 100%)`,
                  border: '1px solid rgba(255,255,255,0.10)',
                  boxShadow: `0 4px 16px ${service.accent.replace('0.3', '0.2').replace('0.35', '0.2')}`,
                }}
                aria-hidden="true"
              >
                {service.icon}
              </div>

              {/* Text */}
              <div>
                <h3 className="font-['Outfit'] font-bold text-white text-lg leading-tight">
                  {service.name}
                </h3>
                <p className="text-brand-glow/70 text-xs font-semibold tracking-wide uppercase mt-0.5 font-['DM_Sans']">
                  {service.tagline}
                </p>
              </div>

              <p className="text-white/45 text-sm font-['DM_Sans'] leading-relaxed">
                {service.description}
              </p>

              {/* Coming soon pill */}
              <div className="mt-auto pt-2">
                <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-brand-bright/70 font-['DM_Sans']">
                  <span className="w-1.5 h-1.5 rounded-full bg-brand-bright/60 animate-pulse" />
                  Coming Soon
                </span>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
