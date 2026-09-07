'use client';

import { useState, useEffect } from 'react';
import Image from 'next/image';
import Countdown from './Countdown';
import CosmicCanvas from './CosmicCanvas';
import CinematicLaunch from './CinematicLaunch';
import StageServicePills from './StageServicePills';
import RegistrationModal from './RegistrationModal';
import KineticHeadline from './KineticHeadline';
import MagneticButton from './MagneticButton';
import { playCelebrationAudio, toggleSuspenseAudio } from '@/lib/audio';

export default function Hero() {
  const [isLaunched, setIsLaunched] = useState(false);
  const [loading, setLoading] = useState(false);
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
    } catch { /* browser may block */ }
  };

  const handleToggleAudio = () => {
    const next = !isAudioActive;
    const ok = toggleSuspenseAudio(next);
    if (ok !== false) setIsAudioActive(next);
  };

  async function handleLaunch() {
    setLoading(true);
    setIsAudioActive(false);
    playCelebrationAudio();
    setIsLaunched(true);
    try {
      await fetch('/api/launch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ adminToken: 'ziggo_admin_dev_token_change_in_production' }),
      });
    } catch (err) {
      console.error('Launch dispatch error:', err);
    } finally {
      setLoading(false);
    }
  }

  return (
    <section
      className="relative w-screen h-screen flex flex-col overflow-hidden select-none"
      aria-label="Ziggo Grand Launch Stage"
    >
      {isLaunched ? (
        <CinematicLaunch />
      ) : (
        <>
          {/* ── ATMOSPHERE ──────────────────────────────────────────── */}
          <CosmicCanvas active={false} />

          {/* Background gradients */}
          <div
            className="absolute inset-0 z-0 pointer-events-none"
            style={{
              background: `
                radial-gradient(ellipse 90% 55% at 68% 52%, rgba(37,99,235,0.28) 0%, transparent 62%),
                radial-gradient(ellipse 55% 65% at 18% 45%, rgba(30,58,138,0.38) 0%, transparent 60%),
                radial-gradient(ellipse 40% 50% at 82% 85%, rgba(245,158,11,0.13) 0%, transparent 55%),
                linear-gradient(160deg, #04081A 0%, #050B1C 50%, #030712 100%)
              `,
            }}
            aria-hidden="true"
          />

          {/* Subtle grid */}
          <div
            className="absolute inset-0 z-0 pointer-events-none opacity-[0.032]"
            style={{
              backgroundImage: 'linear-gradient(rgba(255,255,255,0.9) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.9) 1px, transparent 1px)',
              backgroundSize: '80px 80px',
            }}
            aria-hidden="true"
          />

          {/* Stage beams */}
          <div className="absolute top-0 left-[8%] w-[38vw] h-[65vh] z-0 pointer-events-none opacity-25 animate-stage-beam-left" style={{ background: 'radial-gradient(ellipse at top, rgba(59,130,246,0.55) 0%, transparent 70%)', filter: 'blur(75px)' }} aria-hidden="true" />
          <div className="absolute top-0 right-[8%] w-[38vw] h-[65vh] z-0 pointer-events-none opacity-22 animate-stage-beam-right" style={{ background: 'radial-gradient(ellipse at top, rgba(245,158,11,0.5) 0%, transparent 70%)', filter: 'blur(75px)' }} aria-hidden="true" />

          {/* ── TOP CONTROL BAR ─────────────────────────────────────── */}
          <header className="relative z-30 w-full flex items-center justify-between px-6 sm:px-10 py-3 border-b border-white/[0.05] bg-black/20 backdrop-blur-xl flex-none">
            {/* Live dot */}
            <div className="flex items-center gap-2.5 px-3.5 py-1.5 rounded-full bg-white/[0.05] border border-white/10">
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-80" />
                <span className="relative inline-flex rounded-full h-2 w-2 bg-red-500 shadow-[0_0_8px_#EF4444]" />
              </span>
              <span className="font-['Outfit'] font-bold text-[10px] sm:text-xs text-white tracking-widest uppercase">Official Launch Ceremony</span>
              <span className="hidden sm:inline text-white/20 text-xs">•</span>
              <span className="hidden sm:inline font-['DM_Sans'] text-[11px] text-white/50">Colombo Stage · Sept 6, 2026</span>
            </div>

            {/* Controls */}
            <div className="flex items-center gap-2">
              <button
                onClick={handleToggleAudio}
                className={`px-3 py-1.5 rounded-full text-[11px] font-semibold flex items-center gap-1.5 transition-all border ${isAudioActive ? 'bg-amber-500/15 text-amber-300 border-amber-400/40 shadow-[0_0_12px_rgba(245,158,11,0.25)]' : 'bg-white/[0.04] text-white/55 border-white/[0.08] hover:text-white hover:bg-white/10'}`}
                aria-label="Toggle Audio"
              >
                {isAudioActive ? '🔊' : '🔇'}
                <span className="hidden sm:inline">{isAudioActive ? 'Audio On' : 'Stage Audio'}</span>
              </button>
              <button
                onClick={toggleFullscreen}
                className="px-3 py-1.5 rounded-full text-[11px] font-semibold flex items-center gap-1.5 bg-white/[0.04] text-white/55 border border-white/[0.08] hover:text-white hover:bg-white/10 transition-all"
                aria-label="Fullscreen"
              >
                {isFullscreen ? '⤦' : '⛶'}
                <span className="hidden sm:inline">{isFullscreen ? 'Exit' : 'Big Screen'}</span>
              </button>
              <button
                onClick={handleLaunch}
                disabled={loading}
                className="px-4 py-1.5 rounded-full text-[11px] font-['Outfit'] font-bold flex items-center gap-1.5 bg-gradient-to-r from-blue-600 to-indigo-600 text-white border border-blue-400/30 hover:brightness-125 shadow-[0_0_20px_rgba(59,130,246,0.5)] transition-all"
              >
                🚀 <span>Ignite</span>
              </button>
            </div>
          </header>

          {/* ── MAIN STAGE SPLIT ────────────────────────────────────── */}
          <div className="relative z-10 flex-1 flex flex-row items-stretch min-h-0 overflow-hidden">

            {/* ════════ LEFT PANEL ════════ */}
            <div className="flex flex-col justify-center px-8 sm:px-12 lg:px-16 py-4 gap-3 sm:gap-4 w-full lg:w-[52%] xl:w-[50%] flex-none animate-fade-up">

              {/* ── LOGO — The Hero of the Page ───────────────────── */}
              <div className="relative flex-none">
                {/* Halo glow behind logo */}
                <div
                  className="absolute -inset-4 rounded-3xl blur-3xl opacity-60 pointer-events-none"
                  style={{ background: 'radial-gradient(ellipse, rgba(59,130,246,0.55) 0%, rgba(245,158,11,0.2) 55%, transparent 75%)' }}
                  aria-hidden="true"
                />
                <Image
                  src="/logo-light.png"
                  alt="Ziggo — Sri Lanka's Super App"
                  width={340}
                  height={120}
                  className="relative z-10 h-14 sm:h-16 md:h-18 w-auto object-contain drop-shadow-[0_4px_28px_rgba(59,130,246,0.75)]"
                  priority
                />
              </div>

              {/* Invitation badge */}
              <div className="flex-none">
                <span className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-amber-400/[0.08] border border-amber-400/30 text-[10px] sm:text-xs font-bold tracking-[0.2em] uppercase text-amber-200/90 shadow-[0_0_18px_rgba(245,158,11,0.15)]">
                  <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />
                  Colombo, Sri Lanka · Sept 6, 2026 · By Invitation Only
                </span>
              </div>

              {/* Kinetic Headline */}
              <div className="flex-none">
                <KineticHeadline prefix="The Wait is Over." highlight="Ziggo Arrives." />
              </div>

              {/* Subtitle */}
              <p className="flex-none font-['DM_Sans'] text-white/60 text-sm leading-relaxed max-w-md">
                Sri Lanka's all-in-one platform for{' '}
                <span className="text-white/90 font-semibold">rides, food, groceries, trucks, rentals & events</span>.
              </p>

              {/* Countdown */}
              <div className="flex-none">
                <Countdown />
              </div>

              {/* Service Pills */}
              <div className="flex-none">
                <StageServicePills />
              </div>

              {/* CTAs */}
              <div className="flex-none flex items-center gap-3 flex-wrap">
                <MagneticButton strength={0.3}>
                  <button
                    id="rsvp-btn"
                    onClick={() => setIsModalOpen(true)}
                    className="btn-cta"
                    data-cursor="RSVP"
                    aria-label="Reserve your spot"
                  >
                    <span>Reserve Your Spot</span>
                    <svg className="w-4 h-4 animate-pulse text-amber-300" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                    </svg>
                  </button>
                </MagneticButton>

                <MagneticButton strength={0.3}>
                  <button
                    id="ignite-btn"
                    onClick={handleLaunch}
                    disabled={loading}
                    className="btn-stage-vip"
                    data-cursor="IGNITE"
                    aria-label="Ignite the launch"
                  >
                    {loading ? (
                      <>
                        <svg className="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                        </svg>
                        Igniting…
                      </>
                    ) : (
                      <span>Ignite Launch 🚀</span>
                    )}
                  </button>
                </MagneticButton>
              </div>

              {/* Social proof */}
              <div className="flex-none flex flex-wrap items-center gap-4 text-[11px] text-white/35 font-['DM_Sans']">
                <span className="flex items-center gap-1.5"><span className="text-amber-400">⚡</span><strong className="text-white/60">18,400+</strong> Early Access</span>
                <span className="text-white/10">|</span>
                <span className="flex items-center gap-1.5"><span className="text-emerald-400">✓</span><strong className="text-white/60">4,200+</strong> Merchants</span>
                <span className="text-white/10">|</span>
                <span className="flex items-center gap-1.5"><span className="text-blue-400">🛡️</span> Central Bank Approved</span>
              </div>
            </div>

            {/* ════════ RIGHT PANEL — 3D Visual ════════ */}
            <div className="hidden lg:flex flex-col items-center justify-center flex-1 pr-8 xl:pr-14 py-5 relative">
              {/* Radial glow behind card */}
              <div
                className="absolute inset-8 rounded-[3rem] blur-[100px] opacity-35 pointer-events-none"
                style={{ background: 'radial-gradient(ellipse, rgba(59,130,246,0.6) 0%, rgba(245,158,11,0.35) 55%, transparent 80%)' }}
                aria-hidden="true"
              />

              <div
                className="relative w-full max-w-[560px] rounded-[2rem] overflow-hidden border border-white/[0.12] shadow-[0_40px_100px_rgba(0,0,0,0.85),_0_0_60px_rgba(59,130,246,0.2)] group"
                style={{ animationDelay: '0.15s' }}
              >
                {/* Top glint line */}
                <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-white/60 to-transparent z-10" />

                <Image
                  src="/hero-superapp-3d.jpg"
                  alt="Ziggo Super App 3D Ecosystem — Rides, Food, Mart, Trucks, Rental & Events"
                  width={1280}
                  height={780}
                  className="w-full h-auto object-cover transform transition-transform duration-700 group-hover:scale-[1.04]"
                  priority
                />

                {/* Bottom fade blend */}
                <div
                  className="absolute inset-0 pointer-events-none"
                  style={{ background: 'linear-gradient(to bottom, transparent 55%, rgba(3,7,18,0.65) 100%)' }}
                />

                {/* Floating badge */}
                <div className="absolute bottom-4 left-4 z-10 flex items-center gap-2 px-3.5 py-2 rounded-full bg-black/65 border border-white/15 backdrop-blur-lg shadow-xl">
                  <span className="text-amber-400 text-sm">✨</span>
                  <span className="font-['DM_Sans'] text-xs font-bold text-white/90">Sri Lanka's Flagship Super App</span>
                </div>

                {/* Top-right app badge */}
                <div className="absolute top-4 right-4 z-10 flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-blue-600/70 border border-blue-400/40 backdrop-blur-md shadow-lg">
                  <span className="w-1.5 h-1.5 rounded-full bg-blue-300 animate-pulse" />
                  <span className="font-['DM_Sans'] text-[10px] font-bold text-blue-100 uppercase tracking-wider">All-in-One Platform</span>
                </div>
              </div>

              {/* Stat strip */}
              <div className="flex items-center justify-center gap-8 mt-5">
                {[
                  { val: '6', label: 'Core Services', color: '#60A5FA' },
                  { val: '0.8s', label: 'Avg Match', color: '#F59E0B' },
                  { val: '24/7', label: 'Support', color: '#34D399' },
                  { val: '100%', label: 'Verified Fleet', color: '#C084FC' },
                ].map((s) => (
                  <div key={s.label} className="flex flex-col items-center gap-0.5">
                    <span
                      className="font-['Outfit'] font-black text-2xl leading-none"
                      style={{ color: s.color, textShadow: `0 0 18px ${s.color}88` }}
                    >
                      {s.val}
                    </span>
                    <span className="font-['DM_Sans'] text-[10px] text-white/40 uppercase tracking-wider">{s.label}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* ── BOTTOM FOOTER ───────────────────────────────────────── */}
          <footer className="relative z-20 flex-none w-full px-6 sm:px-10 py-2.5 border-t border-white/[0.05] bg-black/15 backdrop-blur-xl flex items-center justify-between">
            {/* Ziggo wordmark on mobile where right panel is hidden */}
            <div className="flex items-center gap-2">
              <Image src="/logo-light.png" alt="Ziggo" width={80} height={28} className="h-5 w-auto object-contain opacity-40" />
              <span className="text-[10px] text-white/25 font-['DM_Sans']">© {new Date().getFullYear()} Ziggo Technologies (Pvt) Ltd</span>
            </div>
            <p className="text-[10px] text-white/25 font-['DM_Sans'] hidden sm:block">Sri Lanka 🇱🇰 · Nationwide Rollout</p>
            <p className="text-[10px] text-white/25 font-['DM_Sans']">Sept 6, 2026</p>
          </footer>

          <RegistrationModal isOpen={isModalOpen} onClose={() => setIsModalOpen(false)} />
        </>
      )}
    </section>
  );
}
