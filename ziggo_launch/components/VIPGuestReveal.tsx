'use client';

import { useEffect, useRef } from 'react';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

const VIP_GUESTS = [
  {
    id: 1,
    category: 'Cinema Luminary',
    title: 'Silver Screen Icon',
    hint: 'Award-Winning Leading Actor',
    badge: 'Red Carpet VIP',
    initials: 'LK',
    glowColor: '#F59E0B',
  },
  {
    id: 2,
    category: 'Chart-Topping Artist',
    title: 'Global Music Sensation',
    hint: 'International Billboard Artist',
    badge: 'Live Performance',
    initials: 'YS',
    glowColor: '#EC4899',
  },
  {
    id: 3,
    category: 'Sporting Legend',
    title: 'World Champion Captain',
    hint: 'Cricket Hall of Famer',
    badge: 'Guest of Honor',
    initials: 'KC',
    glowColor: '#3B82F6',
  },
  {
    id: 4,
    category: 'Tech Visionary',
    title: 'Super-App Architect',
    hint: 'Silicon Valley Investor',
    badge: 'Keynote Speaker',
    initials: 'RD',
    glowColor: '#10B981',
  },
  {
    id: 5,
    category: 'Cultural Icon',
    title: 'National Voice',
    hint: 'Beloved Media Personality',
    badge: 'Ceremony Host',
    initials: 'NP',
    glowColor: '#8B5CF6',
  },
  {
    id: 6,
    category: 'Fashion & Style',
    title: 'Haute Couture Pioneer',
    hint: 'Global Brand Ambassador',
    badge: 'Gala Host',
    initials: 'AT',
    glowColor: '#F59E0B',
  },
];

export default function VIPGuestReveal() {
  const sectionRef = useRef<HTMLElement>(null);
  const cardsRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    gsap.registerPlugin(ScrollTrigger);

    if (!sectionRef.current || !cardsRef.current) return;

    const cards = cardsRef.current.children;

    gsap.fromTo(
      cards,
      {
        opacity: 0,
        y: 60,
        scale: 0.94,
      },
      {
        opacity: 1,
        y: 0,
        scale: 1,
        duration: 0.9,
        stagger: 0.12,
        ease: 'power3.out',
        scrollTrigger: {
          trigger: sectionRef.current,
          start: 'top 75%',
        },
      }
    );
  }, []);

  return (
    <section
      ref={sectionRef}
      className="relative py-20 sm:py-28 px-4 overflow-hidden border-t border-white/[0.06]"
      aria-label="VIP Celebrity Lineup"
    >
      {/* Ambient Spotlight */}
      <div
        className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[300px] rounded-full blur-[140px] opacity-25 pointer-events-none"
        style={{
          background: 'radial-gradient(ellipse, rgba(245, 158, 11, 0.4) 0%, rgba(59, 130, 246, 0.2) 60%, transparent 80%)',
        }}
        aria-hidden="true"
      />

      <div className="max-w-6xl mx-auto flex flex-col items-center">
        {/* Header Tagline */}
        <div className="flex items-center gap-2 px-4 py-1.5 rounded-full bg-amber-400/10 border border-amber-400/30 text-[11px] font-bold tracking-[0.24em] uppercase text-amber-300 mb-4 shadow-[0_0_20px_rgba(245,158,11,0.2)]">
          <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-ping" />
          <span>Exclusive Celebrity Lineup</span>
        </div>

        {/* Section Title */}
        <h2
          className="font-['Outfit'] font-black text-white text-center tracking-tight leading-tight mb-3"
          style={{ fontSize: 'clamp(2rem, 5vw, 3.6rem)' }}
        >
          Walking the{' '}
          <span
            className="animate-text-shimmer"
            style={{
              background: 'linear-gradient(90deg, #FFFFFF 0%, #F59E0B 35%, #FDE68A 70%, #FFFFFF 100%)',
              WebkitBackgroundClip: 'text',
              backgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
            }}
          >
            Digital Red Carpet
          </span>
        </h2>

        <p className="font-['DM_Sans'] text-white/60 text-sm sm:text-base text-center max-w-xl mb-12 sm:mb-16">
          Sri Lanka’s most revered celebrities, music icons, and industry titans unite for an unforgettable evening of technology and spectacle.
        </p>

        {/* Cards Grid */}
        <div
          ref={cardsRef}
          className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5 sm:gap-6 w-full"
        >
          {VIP_GUESTS.map((guest) => (
            <div
              key={guest.id}
              className="service-hud-card p-6 sm:p-7 flex flex-col justify-between min-h-[220px] transition-all duration-300 hover:-translate-y-2 hover:border-amber-400/50 group"
              data-cursor="VIP"
              style={{
                boxShadow: '0 20px 45px -15px rgba(0,0,0,0.8), 0 0 25px rgba(245,158,11,0.1)',
              }}
            >
              {/* Top row */}
              <div className="flex items-center justify-between">
                <span
                  className="text-[10px] font-extrabold uppercase px-2.5 py-1 rounded-full border tracking-wider"
                  style={{
                    borderColor: `${guest.glowColor}50`,
                    color: guest.glowColor,
                    backgroundColor: `${guest.glowColor}15`,
                  }}
                >
                  {guest.badge}
                </span>

                {/* Secret silhouette badge */}
                <div
                  className="w-10 h-10 rounded-full flex items-center justify-center font-['Outfit'] font-black text-sm text-white/80 border border-white/10 group-hover:border-amber-400/40 group-hover:scale-110 transition-all duration-300 shadow-inner"
                  style={{
                    background: 'radial-gradient(circle, rgba(255,255,255,0.1) 0%, rgba(0,0,0,0.5) 100%)',
                  }}
                >
                  {guest.initials}
                </div>
              </div>

              {/* Center info */}
              <div className="my-4">
                <span className="font-['DM_Sans'] text-xs font-bold uppercase tracking-widest text-amber-300/80 block mb-1">
                  {guest.category}
                </span>
                <h3 className="font-['Outfit'] font-extrabold text-white text-xl sm:text-2xl leading-tight group-hover:text-amber-200 transition-colors">
                  {guest.title}
                </h3>
                <p className="font-['DM_Sans'] text-xs text-white/50 mt-1.5 flex items-center gap-1.5">
                  <span className="text-amber-400">🔒</span>
                  <span>{guest.hint}</span>
                </p>
              </div>

              {/* Bottom VIP invitation note */}
              <div className="flex items-center justify-between pt-3 border-t border-white/[0.06] text-[11px] text-white/40 font-['DM_Sans']">
                <span>By Invitation Only</span>
                <span className="text-amber-400 font-bold group-hover:translate-x-1 transition-transform">
                  Exclusive Reveal →
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
