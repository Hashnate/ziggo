import Image from 'next/image';

const socials = [
  {
    name: 'Facebook',
    href: 'https://facebook.com/ziggoapp',
    icon: (
      <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M22 12c0-5.523-4.477-10-10-10S2 6.477 2 12c0 4.991 3.657 9.128 8.438 9.878v-6.987h-2.54V12h2.54V9.797c0-2.506 1.492-3.89 3.777-3.89 1.094 0 2.238.195 2.238.195v2.46h-1.26c-1.243 0-1.63.771-1.63 1.562V12h2.773l-.443 2.89h-2.33v6.988C18.343 21.128 22 16.991 22 12z" />
      </svg>
    ),
  },
  {
    name: 'Instagram',
    href: 'https://instagram.com/ziggoapp',
    icon: (
      <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zM12 0C8.741 0 8.333.014 7.053.072 2.695.272.273 2.69.073 7.052.014 8.333 0 8.741 0 12c0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98C8.333 23.986 8.741 24 12 24c3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98C15.668.014 15.259 0 12 0zm0 5.838a6.162 6.162 0 100 12.324 6.162 6.162 0 000-12.324zM12 16a4 4 0 110-8 4 4 0 010 8zm6.406-11.845a1.44 1.44 0 100 2.881 1.44 1.44 0 000-2.881z" />
      </svg>
    ),
  },
  {
    name: 'X (Twitter)',
    href: 'https://twitter.com/ziggoapp',
    icon: (
      <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
      </svg>
    ),
  },
];

export default function Footer() {
  const year = new Date().getFullYear();

  return (
    <footer
      className="relative border-t border-white/[0.06] pt-12 pb-8 px-4"
      role="contentinfo"
    >
      {/* Subtle top glow */}
      <div
        className="absolute top-0 left-1/2 -translate-x-1/2 w-80 h-px"
        style={{
          background: 'linear-gradient(90deg, transparent, rgba(59,130,246,0.5), transparent)',
        }}
        aria-hidden="true"
      />

      <div className="max-w-5xl mx-auto flex flex-col items-center gap-8">
        {/* Logo */}
        <Image
          src="/logo-light.png"
          alt="Ziggo"
          width={100}
          height={36}
          className="w-24 h-auto object-contain opacity-80"
        />

        {/* Tagline */}
        <p className="text-white/40 text-sm font-['DM_Sans'] text-center max-w-xs leading-relaxed">
          Sri Lanka&apos;s super-app for rides, food, grocery, trucks, rental & events.
        </p>

        {/* Social links */}
        <div className="flex items-center gap-4" role="list" aria-label="Ziggo social media">
          {socials.map((s) => (
            <a
              key={s.name}
              href={s.href}
              target="_blank"
              rel="noopener noreferrer"
              className="w-10 h-10 rounded-full glass flex items-center justify-center text-white/50 hover:text-white hover:border-brand-bright/30 transition-all duration-200 hover:scale-110"
              aria-label={`Ziggo on ${s.name}`}
              role="listitem"
            >
              {s.icon}
            </a>
          ))}
        </div>

        {/* Divider */}
        <div className="w-full max-w-md h-px bg-white/[0.06]" aria-hidden="true" />

        {/* Powered by + copyright */}
        <div className="flex flex-col sm:flex-row items-center gap-3 sm:gap-6 text-center">
          <span className="text-xs text-white/30 font-['DM_Sans']">
            Powered by{' '}
            <span className="text-brand-glow/60 font-semibold">Ziggo Wallet</span>
            {' '}·{' '}
            <span className="text-brand-glow/60 font-semibold">PayHere</span>
          </span>
          <span className="hidden sm:block text-white/20 text-xs">|</span>
          <span className="text-xs text-white/25 font-['DM_Sans']">
            © {year} Ziggo. All rights reserved.
          </span>
        </div>
      </div>
    </footer>
  );
}
