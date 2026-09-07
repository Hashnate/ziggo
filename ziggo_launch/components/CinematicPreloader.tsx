'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';

export default function CinematicPreloader() {
  const [progress, setProgress] = useState(0);
  const [isRevealing, setIsRevealing] = useState(false);
  const [isHidden, setIsHidden] = useState(false);

  useEffect(() => {
    // Check if already shown in this session
    if (typeof window !== 'undefined') {
      const seen = sessionStorage.getItem('ziggo_preloader_seen');
      if (seen === 'true') {
        setIsHidden(true);
        return;
      }
    }

    // Check reduced motion
    const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (prefersReducedMotion) {
      setIsHidden(true);
      sessionStorage.setItem('ziggo_preloader_seen', 'true');
      return;
    }

    // Progress counter animation
    let current = 0;
    const interval = setInterval(() => {
      // Accelerate towards end
      const step = current < 60 ? Math.floor(Math.random() * 6) + 2 : Math.floor(Math.random() * 10) + 4;
      current = Math.min(100, current + step);
      setProgress(current);

      if (current >= 100) {
        clearInterval(interval);
        // Begin curtain reveal
        setTimeout(() => {
          setIsRevealing(true);
          sessionStorage.setItem('ziggo_preloader_seen', 'true');
          // Fully remove from DOM after wipe finishes
          setTimeout(() => {
            setIsHidden(true);
          }, 1250);
        }, 300);
      }
    }, 45);

    return () => clearInterval(interval);
  }, []);

  if (isHidden) return null;

  return (
    <div
      className={`fixed inset-0 z-[100] flex items-center justify-center pointer-events-none select-none overflow-hidden transition-opacity duration-500 ${
        isRevealing ? 'pointer-events-none' : 'pointer-events-auto'
      }`}
      aria-label="Loading Ziggo VIP Launch"
    >
      {/* ── Top Curtain Panel ─────────────────────────────────── */}
      <div
        className="absolute top-0 left-0 right-0 h-1/2 bg-[#030712] border-b border-amber-400/25 transition-transform duration-[1200ms] ease-[cubic-bezier(0.16,1,0.3,1)] z-10"
        style={{
          transform: isRevealing ? 'translateY(-101%)' : 'translateY(0%)',
          boxShadow: '0 20px 60px rgba(0,0,0,0.9)',
        }}
      />

      {/* ── Bottom Curtain Panel ──────────────────────────────── */}
      <div
        className="absolute bottom-0 left-0 right-0 h-1/2 bg-[#030712] border-t border-amber-400/25 transition-transform duration-[1200ms] ease-[cubic-bezier(0.16,1,0.3,1)] z-10"
        style={{
          transform: isRevealing ? 'translateY(101%)' : 'translateY(0%)',
          boxShadow: '0 -20px 60px rgba(0,0,0,0.9)',
        }}
      />

      {/* ── Center Stage Emblem & Counter ─────────────────────── */}
      <div
        className={`relative z-20 flex flex-col items-center gap-6 text-center transition-all duration-700 ease-out ${
          isRevealing ? 'opacity-0 scale-110 blur-sm' : 'opacity-100 scale-100'
        }`}
      >
        {/* Luminous Brand Backlight */}
        <div className="relative">
          <div
            className="absolute -inset-10 rounded-full blur-3xl opacity-40 transition-opacity duration-300"
            style={{
              background: `radial-gradient(circle, rgba(245,158,11,${progress / 120}) 0%, rgba(59,130,246,0.3) 60%, transparent 80%)`,
            }}
            aria-hidden="true"
          />

          <Image
            src="/logo-light.png"
            alt="Ziggo Logo"
            width={240}
            height={85}
            className="w-48 sm:w-56 h-auto object-contain drop-shadow-[0_0_35px_rgba(245,158,11,0.4)]"
            priority
          />
        </div>

        {/* Counter & Status */}
        <div className="flex flex-col items-center gap-2 mt-2">
          {/* Progress Percent with Gold Digits */}
          <div className="font-['Outfit'] font-black text-4xl sm:text-5xl tracking-tight leading-none text-transparent bg-clip-text bg-gradient-to-b from-white via-amber-200 to-amber-500 drop-shadow-[0_0_20px_rgba(245,158,11,0.5)]">
            {progress}
            <span className="text-xl sm:text-2xl ml-1 text-amber-400 font-bold">%</span>
          </div>

          {/* Subtitle */}
          <span className="font-['DM_Sans'] text-[11px] font-bold tracking-[0.28em] uppercase text-white/50">
            {progress < 100 ? 'Preparing VIP Launch Ceremony…' : 'Access Granted'}
          </span>
        </div>

        {/* Sleek Golden Loading Bar */}
        <div className="w-48 sm:w-64 h-1 rounded-full bg-white/10 overflow-hidden relative mt-1">
          <div
            className="h-full bg-gradient-to-r from-blue-500 via-amber-300 to-amber-500 transition-all duration-150 ease-out rounded-full"
            style={{
              width: `${progress}%`,
              boxShadow: '0 0 14px rgba(245, 158, 11, 0.8)',
            }}
          />
        </div>
      </div>
    </div>
  );
}
