'use client';

import { useState, useEffect } from 'react';
import Image from 'next/image';
import CosmicCanvas from './CosmicCanvas';
import FilmGrain from './FilmGrain';
import RegistrationModal from './RegistrationModal';
import MagneticButton from './MagneticButton';
import Countdown from './Countdown';
import { toggleSuspenseAudio, playCelebrationAudio, playCardClickAudio } from '@/lib/audio';

interface StateAProps {
  onLaunched: () => void;
}

export default function StateA({ onLaunched }: StateAProps) {
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isAudioActive, setIsAudioActive] = useState(false);

  useEffect(() => {
    const handleFsChange = () => setIsFullscreen(Boolean(document.fullscreenElement));
    document.addEventListener('fullscreenchange', handleFsChange);
    return () => document.removeEventListener('fullscreenchange', handleFsChange);
  }, []);

  const toggleFullscreen = async () => {
    try {
      if (!document.fullscreenElement) await document.documentElement.requestFullscreen();
      else await document.exitFullscreen();
    } catch { /* blocked */ }
  };

  const handleToggleAudio = () => {
    const next = !isAudioActive;
    const ok = toggleSuspenseAudio(next);
    if (ok !== false) setIsAudioActive(next);
  };

  // Called by the Launch button
  async function triggerReveal() {
    playCelebrationAudio();
    onLaunched();
    try {
      await fetch('/api/launch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ adminToken: 'ziggo_admin_dev_token_change_in_production' }),
      });
    } catch (e) {
      console.error(e);
    }
  }

  return (
    <section
      className="relative w-screen h-screen flex flex-col overflow-hidden select-none"
      aria-label="Ziggo Grand Launch — Pre-Launch"
    >
      {/* ── FULL-BLEED AMBIENT CANVAS & FILM GRAIN ─── */}
      <CosmicCanvas active={false} />
      <FilmGrain />

      {/* ── CENTERPIECE: Logo → Countdown → Launch Button ─── */}
      <div className="relative z-10 flex-1 flex flex-col items-center justify-center gap-0 px-4 animate-fade-up">

        {/* ── OFFICIAL ZIGGO LOGO ─── */}
        <div className="relative flex flex-col items-center justify-center -mb-3 sm:-mb-5 md:-mb-6">
          {/* Deep Royal Sapphire & Gold Radiant Backlight */}
          <div
            className="absolute w-[450px] h-[220px] sm:w-[650px] sm:h-[300px] rounded-full blur-[90px] opacity-50 pointer-events-none animate-pulse-glow"
            style={{
              background: 'radial-gradient(circle, rgba(59, 130, 246, 0.65) 0%, rgba(245, 158, 11, 0.22) 50%, transparent 75%)',
            }}
            aria-hidden="true"
          />

          {/* Clean ambient core glow */}
          <div
            className="absolute w-[300px] h-[150px] rounded-full blur-[55px] opacity-65 pointer-events-none"
            style={{
              background: 'radial-gradient(circle, rgba(96, 165, 250, 0.55) 0%, transparent 70%)',
            }}
            aria-hidden="true"
          />

          <Image
            src="/logo-light.png"
            alt="Ziggo — Sri Lanka's Flagship Super App"
            width={600}
            height={210}
            className="relative z-10 w-48 sm:w-64 md:w-80 lg:w-[380px] h-auto object-contain drop-shadow-[0_8px_40px_rgba(59,130,246,0.7)] hover:scale-105 transition-transform duration-500 animate-float"
            priority
          />
        </div>

        {/* ── PREMIUM COUNTDOWN ─── */}
        <div className="w-full max-w-2xl">
          <Countdown />
        </div>

        {/* ── STAGE LAUNCH BUTTON ─── */}

        <div className="mt-16 sm:mt-20 md:mt-24 relative flex items-center justify-center">
          {/* Multi-Layered Radiant Ambient Glow */}
          <div
            className="absolute -inset-6 rounded-full blur-[35px] opacity-70 pointer-events-none animate-pulse-glow"
            style={{
              background: 'radial-gradient(ellipse at center, rgba(245, 158, 11, 0.45) 0%, rgba(59, 130, 246, 0.6) 45%, transparent 75%)',
            }}
            aria-hidden="true"
          />

          {/* Concentric Soft Radar Pulse Wave */}
          <div
            className="absolute -inset-2 rounded-full border border-amber-400/30 opacity-40 pointer-events-none animate-ping"
            style={{ animationDuration: '3.5s' }}
            aria-hidden="true"
          />

          <MagneticButton strength={0.4}>
            <button
              onClick={triggerReveal}
              className="relative group overflow-hidden px-12 sm:px-16 py-4 sm:py-5 rounded-full border-2 border-amber-300/60 hover:border-amber-200 transition-all duration-500 hover:scale-105 active:scale-95 shadow-[0_15px_40px_rgba(0,0,0,0.8),0_0_50px_rgba(245,158,11,0.35),0_0_80px_rgba(59,130,246,0.3),inset_0_1px_2px_rgba(255,255,255,0.6)]"
              style={{
                background: 'linear-gradient(180deg, rgba(255, 255, 255, 0.16) 0%, rgba(30, 58, 138, 0.75) 40%, rgba(5, 10, 25, 0.95) 100%)',
                backdropFilter: 'blur(28px)',
              }}
              data-cursor="LAUNCH"
              aria-label="Launch Ziggo"
            >
              {/* Upper Convex Glass Specular Reflection Highlight */}
              <div
                className="absolute inset-x-3 top-1 h-3.5 rounded-full bg-gradient-to-b from-white/40 via-white/10 to-transparent pointer-events-none"
                aria-hidden="true"
              />

              {/* Shimmering Dynamic Light Sweep */}
              <div
                className="absolute inset-0 -translate-x-full group-hover:translate-x-full transition-transform duration-1000 bg-gradient-to-r from-transparent via-white/30 to-transparent pointer-events-none"
                aria-hidden="true"
              />

              {/* Button Content - Perfectly Optically Centered */}
              <div className="relative z-10 flex items-center justify-center gap-3 sm:gap-3.5 select-none pl-1">
                {/* 24K Gold & Diamond White Metallic Title */}
                <span
                  className="font-['Outfit'] font-black text-base sm:text-lg md:text-xl tracking-[0.2em] uppercase text-white drop-shadow-[0_2px_12px_rgba(0,0,0,0.8)]"
                  style={{
                    background: 'linear-gradient(180deg, #FFFFFF 0%, #FFFBEB 25%, #FDE68A 55%, #F59E0B 85%, #D97706 100%)',
                    WebkitBackgroundClip: 'text',
                    WebkitTextFillColor: 'transparent',
                    filter: 'drop-shadow(0 0 16px rgba(245, 158, 11, 0.45))',
                  }}
                >
                  Launch
                </span>

                {/* 3D Hyper-Attractive Luxury Aerospace Rocket */}
                <div className="relative flex items-center justify-center w-8 h-8 sm:w-9 sm:h-9 group-hover:scale-110 group-hover:translate-x-1 group-hover:-translate-y-1 transition-all duration-300">
                  <svg
                    viewBox="0 0 48 48"
                    fill="none"
                    xmlns="http://www.w3.org/2000/svg"
                    className="w-full h-full drop-shadow-[0_0_16px_rgba(251,191,36,0.95)]"
                  >
                    <defs>
                      {/* 3D Pearl White Titanium Hull */}
                      <linearGradient id="hull3D" x1="10" y1="10" x2="38" y2="38" gradientUnits="userSpaceOnUse">
                        <stop offset="0%" stopColor="#FFFFFF" />
                        <stop offset="35%" stopColor="#F1F5F9" />
                        <stop offset="65%" stopColor="#CBD5E1" />
                        <stop offset="100%" stopColor="#64748B" />
                      </linearGradient>

                      {/* Glossy Scarlet Nose Cap */}
                      <linearGradient id="noseCap" x1="30" y1="4" x2="44" y2="18" gradientUnits="userSpaceOnUse">
                        <stop offset="0%" stopColor="#FF4D4D" />
                        <stop offset="45%" stopColor="#E11D48" />
                        <stop offset="100%" stopColor="#881337" />
                      </linearGradient>

                      {/* Electric Blue Swept Wings */}
                      <linearGradient id="deltaWing" x1="12" y1="12" x2="36" y2="36" gradientUnits="userSpaceOnUse">
                        <stop offset="0%" stopColor="#38BDF8" />
                        <stop offset="50%" stopColor="#2563EB" />
                        <stop offset="100%" stopColor="#1E3A8A" />
                      </linearGradient>

                      {/* Dynamic Multistage Plasma Thruster */}
                      <radialGradient id="plasmaCore" cx="12" cy="36" r="14" gradientUnits="userSpaceOnUse">
                        <stop offset="0%" stopColor="#FFFFFF" />
                        <stop offset="25%" stopColor="#67E8F9" />
                        <stop offset="55%" stopColor="#FBBF24" />
                        <stop offset="80%" stopColor="#F97316" />
                        <stop offset="100%" stopColor="rgba(239, 68, 68, 0)" />
                      </radialGradient>
                    </defs>

                    {/* Outer Plasma Flame Glow Cone */}
                    <path
                      d="M16 32 C12 36 6 44 2 46 C5 41 12 34 16 32 Z"
                      fill="url(#plasmaCore)"
                      className="animate-pulse"
                      filter="drop-shadow(0 0 8px #F59E0B)"
                    />
                    <path
                      d="M17 31 C13.5 35 8 42 4 44 C6.5 40 13 33.5 17 31 Z"
                      fill="#FFFFFF"
                      opacity="0.9"
                    />

                    {/* Left Delta Wing */}
                    <path
                      d="M11 29 C9 22 13 18 18 18 L15 34 L11 29 Z"
                      fill="url(#deltaWing)"
                      stroke="#7DD3FC"
                      strokeWidth="0.8"
                    />

                    {/* Right Delta Wing */}
                    <path
                      d="M29 11 C22 9 18 13 18 18 L34 15 L29 11 Z"
                      fill="url(#deltaWing)"
                      stroke="#7DD3FC"
                      strokeWidth="0.8"
                    />

                    {/* Central Aerodynamic Fuselage with 3D Curvature */}
                    <path
                      d="M38 10 C33 15 23 19 14 28 C12.5 29.5 11.2 32.5 10 34.5 L13.5 38 C15.5 36.8 18.5 35.5 20 34 C29 25 33 15 38 10 Z"
                      fill="url(#hull3D)"
                      stroke="#FFFFFF"
                      strokeWidth="1.2"
                    />

                    {/* Longitudinal Specular Chrome Highlight Spine */}
                    <path
                      d="M37 11 C32 16 23 20 15 28 C14 29 13 31 12 33 L14 35 C15.5 33.8 17.5 32.5 19 31 C27 23 31 15 37 11 Z"
                      fill="#FFFFFF"
                      opacity="0.4"
                    />

                    {/* Vivid Aerodynamic Nose Cone */}
                    <path
                      d="M38 10 C35.5 12.5 30.5 14.8 27.5 16.8 L31.2 20.5 C33.2 17.5 35.5 12.5 38 10 Z"
                      fill="url(#noseCap)"
                      stroke="#FECDD3"
                      strokeWidth="0.6"
                    />

                    {/* Illuminated Cyan Aerospace Cockpit Porthole */}
                    <circle cx="25.5" cy="22.5" r="3.6" fill="#0284C7" stroke="#BAE6FD" strokeWidth="1.2" />
                    <circle cx="24.5" cy="21.5" r="1.3" fill="#FFFFFF" opacity="0.95" />

                    {/* Titanium Engine Exhaust Bell */}
                    <path d="M12 36.5 L14.5 39 L10.5 43 L8 40.5 L12 36.5 Z" fill="#1E293B" stroke="#64748B" strokeWidth="0.75" />
                  </svg>
                </div>
              </div>
            </button>


          </MagneticButton>
        </div>
      </div>


      <RegistrationModal isOpen={isModalOpen} onClose={() => setIsModalOpen(false)} />
    </section>
  );
}
