'use client';

import { useEffect, useState, useRef } from 'react';

interface LaunchRevealProps {
  onClose: () => void;
  result: { sent: number; failed: number; skipped: number } | null;
}

import { playCelebrationAudio } from '@/lib/audio';

// Ziggo brand celebratory colors
const BRAND_COLORS = [
  '#3B82F6', '#60A5FA', '#93C5FD', '#1E3A8A',
  '#C9A961', '#F59E0B', '#10B981', '#EC4899', '#FFFFFF'
];

export default function LaunchReveal({ onClose, result }: LaunchRevealProps) {
  const [rocketLaunched, setRocketLaunched] = useState(false);
  const [showCard, setShowCard] = useState(false);
  const reducedMotion =
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  useEffect(() => {
    // Play sound
    playCelebrationAudio();

    // Trigger rocket blast off animation
    const rocketTimer = setTimeout(() => {
      setRocketLaunched(true);
    }, 150);

    const cardTimer = setTimeout(() => {
      setShowCard(true);
    }, 600);

    // Multi-tier confetti cannon sequence
    if (!reducedMotion) {
      import('canvas-confetti').then((confettiModule) => {
        const confetti = confettiModule.default;

        // Wave 1: Center starburst
        confetti({
          particleCount: 160,
          spread: 120,
          origin: { x: 0.5, y: 0.6 },
          colors: BRAND_COLORS,
          startVelocity: 60,
          gravity: 0.8,
          ticks: 350,
          shapes: ['circle', 'square'],
        });

        // Wave 2: Left Cannon
        setTimeout(() => {
          confetti({
            particleCount: 130,
            angle: 55,
            spread: 80,
            origin: { x: 0.05, y: 0.65 },
            colors: BRAND_COLORS,
            startVelocity: 75,
            gravity: 0.85,
            ticks: 320,
          });
        }, 350);

        // Wave 3: Right Cannon
        setTimeout(() => {
          confetti({
            particleCount: 130,
            angle: 125,
            spread: 80,
            origin: { x: 0.95, y: 0.65 },
            colors: BRAND_COLORS,
            startVelocity: 75,
            gravity: 0.85,
            ticks: 320,
          });
        }, 500);

        // Wave 4: Golden Rain Shower
        setTimeout(() => {
          confetti({
            particleCount: 220,
            spread: 160,
            origin: { x: 0.5, y: 0.05 },
            colors: ['#C9A961', '#F59E0B', '#FCD34D', '#FFFFFF', '#60A5FA'],
            startVelocity: 35,
            gravity: 0.6,
            ticks: 450,
          });
        }, 1100);
      }).catch(() => {});
    }

    return () => {
      clearTimeout(rocketTimer);
      clearTimeout(cardTimer);
    };
  }, [reducedMotion]);

  const appLink = process.env.NEXT_PUBLIC_APP_LINK ?? 'https://ziggo.app';

  return (
    <div
      className="fixed inset-0 z-[999] flex flex-col items-center justify-center p-4 select-none overflow-hidden"
      style={{
        backgroundColor: '#050814',
        backgroundImage: `
          radial-gradient(circle at 50% 30%, rgba(30, 58, 138, 0.45) 0%, transparent 60%),
          radial-gradient(circle at 20% 80%, rgba(59, 130, 246, 0.25) 0%, transparent 50%),
          radial-gradient(circle at 80% 80%, rgba(201, 169, 97, 0.18) 0%, transparent 50%)
        `,
      }}
      role="dialog"
      aria-modal="true"
      aria-label="Ziggo Live Celebration"
    >
      {/* Dynamic Cosmic Background Grid */}
      <div
        className="absolute inset-0 opacity-10 pointer-events-none"
        style={{
          backgroundImage:
            'linear-gradient(rgba(255,255,255,0.4) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.4) 1px, transparent 1px)',
          backgroundSize: '48px 48px',
        }}
        aria-hidden="true"
      />

      {/* Floating Star Sparkles */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none" aria-hidden="true">
        {Array.from({ length: 24 }).map((_, i) => (
          <div
            key={i}
            className="absolute rounded-full animate-pulse"
            style={{
              width: `${(i % 3) + 2}px`,
              height: `${(i % 3) + 2}px`,
              backgroundColor: BRAND_COLORS[i % BRAND_COLORS.length],
              top: `${(i * 19) % 100}%`,
              left: `${(i * 29) % 100}%`,
              boxShadow: `0 0 10px ${BRAND_COLORS[i % BRAND_COLORS.length]}`,
              animationDuration: `${(i % 3) + 2}s`,
            }}
          />
        ))}
      </div>

      {/* ── Cinematic 3D Rocket Blast ────────────────────────── */}
      <div
        className="absolute pointer-events-none transition-all duration-1000 ease-out z-10"
        style={{
          transform: rocketLaunched
            ? 'translateY(-140vh) scale(1.6) rotate(-5deg)'
            : 'translateY(20vh) scale(0.6) rotate(0deg)',
          opacity: rocketLaunched ? 0 : 1,
        }}
        aria-hidden="true"
      >
        <div className="relative flex flex-col items-center">
          <div className="text-8xl md:text-9xl filter drop-shadow-[0_0_50px_rgba(59,130,246,0.9)]">
            🚀
          </div>
          {/* Flame Trail */}
          <div
            className="w-8 h-32 rounded-full mt-[-20px] blur-md animate-pulse"
            style={{
              background: 'linear-gradient(to bottom, #F59E0B, #EF4444, transparent)',
            }}
          />
        </div>
      </div>

      {/* ── Main Celebration Luxury Card ─────────────────────── */}
      <div
        className={`relative z-20 max-w-xl w-full transition-all duration-700 ease-out ${
          showCard ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-90 translate-y-8'
        }`}
      >
        <div
          className="rounded-3xl p-8 md:p-10 text-center flex flex-col items-center gap-6"
          style={{
            background: 'linear-gradient(145deg, rgba(19, 28, 61, 0.85) 0%, rgba(10, 15, 31, 0.95) 100%)',
            backdropFilter: 'blur(30px)',
            WebkitBackdropFilter: 'blur(30px)',
            border: '1px solid rgba(96, 165, 250, 0.35)',
            boxShadow: '0 30px 100px -15px rgba(0, 0, 0, 0.9), 0 0 60px rgba(59, 130, 246, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.2)',
          }}
        >
          {/* Live Status Pill */}
          <div className="inline-flex items-center gap-2.5 px-4 py-1.5 rounded-full bg-emerald-500/15 border border-emerald-400/40 text-emerald-300 text-xs font-semibold tracking-wider uppercase font-['DM_Sans']">
            <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-ping" />
            <span className="w-2 h-2 rounded-full bg-emerald-400 -ml-4" />
            <span>Broadcast Sent Successfully</span>
          </div>

          {/* Heading */}
          <div className="flex flex-col gap-3">
            <h1
              className="font-['Outfit'] font-black text-white leading-tight tracking-tight"
              style={{
                fontSize: 'clamp(2.2rem, 6vw, 3.4rem)',
                textShadow: '0 0 40px rgba(96, 165, 250, 0.6)',
              }}
            >
              Ziggo is{' '}
              <span
                style={{
                  background: 'linear-gradient(135deg, #60A5FA 0%, #FFFFFF 40%, #FBBF24 100%)',
                  WebkitBackgroundClip: 'text',
                  backgroundClip: 'text',
                  WebkitTextFillColor: 'transparent',
                }}
              >
                Now Live! 🚀
              </span>
            </h1>
            <p className="text-white/70 font-['DM_Sans'] text-base md:text-lg max-w-md mx-auto leading-relaxed">
              Sri Lanka&apos;s ultimate super-app has officially launched. Rides, Food, Market, Trucks, Rental &amp; Events are ready!
            </p>
          </div>

          {/* Notification Broadcast Metrics */}
          <div
            className="w-full rounded-2xl p-4 flex items-center justify-around gap-2 border border-white/10"
            style={{ background: 'rgba(255, 255, 255, 0.04)' }}
          >
            <div className="flex flex-col items-center">
              <span className="text-white/40 text-xs font-['DM_Sans'] uppercase tracking-wider">Subscribers</span>
              <span className="font-['Outfit'] font-extrabold text-2xl text-emerald-400">
                {result ? result.sent : 'All'}
              </span>
              <span className="text-[11px] text-emerald-300/80 font-['DM_Sans']">Notified Instant</span>
            </div>
            <div className="w-px h-10 bg-white/10" />
            <div className="flex flex-col items-center">
              <span className="text-white/40 text-xs font-['DM_Sans'] uppercase tracking-wider">Gateway</span>
              <span className="font-['Outfit'] font-extrabold text-2xl text-blue-400">
                Web Push
              </span>
              <span className="text-[11px] text-blue-300/80 font-['DM_Sans']">High Priority</span>
            </div>
            <div className="w-px h-10 bg-white/10" />
            <div className="flex flex-col items-center">
              <span className="text-white/40 text-xs font-['DM_Sans'] uppercase tracking-wider">App Status</span>
              <span className="font-['Outfit'] font-extrabold text-2xl text-amber-300">
                Active 🇱🇰
              </span>
              <span className="text-[11px] text-amber-300/80 font-['DM_Sans']">Nationwide</span>
            </div>
          </div>

          {/* Action Buttons */}
          <div className="flex flex-col sm:flex-row items-center gap-3.5 w-full mt-2">
            <a
              href={appLink}
              target="_blank"
              rel="noopener noreferrer"
              className="w-full sm:flex-1 py-4 px-6 rounded-2xl font-['Outfit'] font-bold text-white text-base text-center transition-all duration-300 hover:scale-[1.03] active:scale-[0.98] flex items-center justify-center gap-2"
              style={{
                background: 'linear-gradient(135deg, #2563EB 0%, #1D4ED8 100%)',
                boxShadow: '0 12px 30px rgba(37, 99, 235, 0.5), inset 0 1px 0 rgba(255, 255, 255, 0.3)',
              }}
            >
              <span>Explore Ziggo App</span>
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M14 5l7 7m0 0l-7 7m7-7H3" />
              </svg>
            </a>

            <button
              onClick={onClose}
              className="w-full sm:w-auto py-4 px-6 rounded-2xl font-['DM_Sans'] font-semibold text-white/70 hover:text-white transition-all duration-200 border border-white/10 hover:border-white/20 hover:bg-white/5"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
