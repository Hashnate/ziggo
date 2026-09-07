'use client';

import { useEffect, useRef, useState } from 'react';
import Image from 'next/image';
import { playCelebrationAudio, playCardClickAudio } from '@/lib/audio';

const ZIGGO_SERVICES = [
  {
    name: 'Rides',
    tag: 'Fast Travel',
    color: '#38BDF8',
    glowColor: 'rgba(56, 189, 248, 0.8)',
    image: '/service-rides-user-official.jpg?v=2',
  },
  {
    name: 'Food',
    tag: 'Fresh Delivery',
    color: '#FB923C',
    glowColor: 'rgba(251, 146, 60, 0.6)',
    image: '/service-food.jpg?v=3',
  },
  {
    name: 'Mart',
    tag: 'Daily Essentials',
    color: '#34D399',
    glowColor: 'rgba(52, 211, 153, 0.6)',
    image: '/service-mart.jpg?v=3',
  },
  {
    name: 'Trucks',
    tag: 'Heavy Load',
    color: '#F59E0B',
    glowColor: 'rgba(245, 158, 11, 0.6)',
    image: '/service-trucks-user-official.jpg',
  },
  {
    name: 'Rental',
    tag: 'Vehicle Hire',
    color: '#A78BFA',
    glowColor: 'rgba(167, 139, 250, 0.6)',
    image: '/service-rental-user-official.jpg',
  },
  {
    name: 'Events',
    tag: 'VIP Tickets',
    color: '#F472B6',
    glowColor: 'rgba(244, 114, 182, 0.6)',
    image: '/service-events.jpg?v=3',
  },
];




export default function CinematicLaunch({ onComplete }: { onComplete?: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [activeCardIndex, setActiveCardIndex] = useState<number>(0);
  const [isHovered, setIsHovered] = useState<boolean>(false);

  // Auto-cycle through the 6 service cards one by one showing each in big highlighted size
  useEffect(() => {
    if (isHovered) return;
    const interval = setInterval(() => {
      setActiveCardIndex((prev) => (prev + 1) % ZIGGO_SERVICES.length);
    }, 2200);
    return () => clearInterval(interval);
  }, [isHovered]);

  useEffect(() => {
    playCelebrationAudio();

    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animId: number;
    let width = (canvas.width = window.innerWidth);
    let height = (canvas.height = window.innerHeight);

    const handleResize = () => {
      if (!canvas) return;
      width = canvas.width = window.innerWidth;
      height = canvas.height = window.innerHeight;
    };
    window.addEventListener('resize', handleResize);

    // ── 1. VIP Event Starlight & Golden Embers Engine ─────────
    interface DustParticle {
      x: number;
      y: number;
      size: number;
      speedY: number;
      speedX: number;
      alpha: number;
      color: string;
      glow: number;
    }

    const particles: DustParticle[] = [];
    const goldPalette = ['#E5C97E', '#C9A961', '#93C5FD', '#FFFFFF', '#FCD34D'];

    for (let i = 0; i < 90; i++) {
      particles.push({
        x: Math.random() * width,
        y: Math.random() * height,
        size: Math.random() * 2.5 + 0.8,
        speedY: Math.random() * 0.35 + 0.1,
        speedX: (Math.random() - 0.5) * 0.15,
        alpha: Math.random() * 0.5 + 0.25,
        color: goldPalette[Math.floor(Math.random() * goldPalette.length)],
        glow: Math.random() * 8 + 4,
      });
    }

    // Opening VIP Celebration Streamers
    import('canvas-confetti').then((mod) => {
      const confetti = mod.default;
      confetti({
        particleCount: 120,
        spread: 120,
        origin: { x: 0.5, y: 0.4 },
        colors: ['#C9A961', '#E5C97E', '#93C5FD', '#FFFFFF', '#3B82F6'],
        startVelocity: 50,
        gravity: 0.65,
        ticks: 400,
      });
    }).catch(() => {});

    let time = 0;
    const cx = width / 2;

    const render = () => {
      time += 0.016;
      ctx.clearRect(0, 0, width, height);

      // Render Stardust Embers
      for (const p of particles) {
        p.y -= p.speedY;
        p.x += p.speedX;

        if (p.y < 0) {
          p.y = height;
          p.x = Math.random() * width;
        }

        ctx.save();
        ctx.shadowColor = p.color;
        ctx.shadowBlur = p.glow;
        ctx.fillStyle = p.color;
        ctx.globalAlpha = p.alpha;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
      }

      animId = requestAnimationFrame(render);
    };

    render();

    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener('resize', handleResize);
    };
  }, []);



  return (
    <div
      className="fixed inset-0 z-50 flex flex-col items-center justify-center p-4 overflow-hidden select-none bg-[#060B18]"
      style={{
        backgroundColor: '#060B18',
      }}
    >
      {/* Top right close button */}
      {onComplete && (
        <button
          onClick={onComplete}
          className="absolute top-4 sm:top-6 right-4 sm:right-6 z-50 p-2.5 rounded-full bg-white/10 hover:bg-white/20 text-white/70 hover:text-white border border-white/15 transition-all backdrop-blur-md"
          aria-label="Close celebration"
        >
          <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      )}

      {/* ── 1. Background Starlight & God Rays Canvas ──────────── */}
      <canvas ref={canvasRef} className="absolute inset-0 w-full h-full pointer-events-none z-0" />

      {/* ── 2. Deep Royal Blue & Amber Aura ────────────────────── */}
      <div className="absolute inset-0 pointer-events-none overflow-hidden" aria-hidden="true">
        <div
          className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[700px] h-[700px] md:w-[1000px] md:h-[1000px] rounded-full blur-[140px] opacity-40 animate-pulse-glow"
          style={{
            background: 'radial-gradient(circle, rgba(59, 130, 246, 0.4) 0%, rgba(201, 169, 97, 0.2) 50%, transparent 75%)',
          }}
        />
      </div>

      {/* ── 3. The Grand VIP Stage Centerpiece (NO BOXES) ───────── */}
      <div className="relative z-10 flex flex-col items-center justify-center text-center max-w-5xl w-full gap-5 sm:gap-7 md:gap-9 animate-scale-pop">

        {/* ── Floating Logo ──────────────── */}
        <div className="relative flex flex-col items-center gap-2 sm:gap-3">
          {/* Floating Pure White Logo */}

          <div className="relative z-10 flex flex-col items-center animate-float">
            <Image
              src="/logo-light.png"
              alt="Ziggo Logo"
              width={320}
              height={110}
              className="w-44 sm:w-56 md:w-72 h-auto object-contain drop-shadow-[0_10px_45px_rgba(59,130,246,0.7)]"
              priority
            />
          </div>

          {/* Master Ultra-Crisp Floating Headline */}
          <div className="relative z-10 flex flex-col items-center gap-2 sm:gap-3 -mt-2 sm:-mt-4 px-4">
            <div className="relative flex items-center justify-center gap-3 sm:gap-6 flex-wrap">
              <h1
                className="font-['Outfit'] font-black tracking-normal select-none flex items-center gap-3 sm:gap-4 flex-wrap justify-center text-white"
                style={{
                  fontSize: 'clamp(2.4rem, 7.5vw, 5.2rem)',
                  lineHeight: 1.1,
                  textShadow: '0 4px 30px rgba(0, 0, 0, 0.95), 0 0 40px rgba(245, 158, 11, 0.65)',
                }}
              >
                <span>Ziggo</span>
                <span
                  style={{
                    color: '#FBBF24',
                    textShadow: '0 4px 30px rgba(0, 0, 0, 0.95), 0 0 50px rgba(245, 158, 11, 0.9), 0 0 90px rgba(245, 158, 11, 0.5)',
                  }}
                >
                  is Live
                </span>
              </h1>

              {/* 3D High-Definition Aerospace Rocket Craft */}
              <div className="relative flex items-center justify-center w-12 h-12 sm:w-16 sm:h-16 md:w-20 md:h-20 animate-bounce" style={{ animationDuration: '2.5s' }}>
                <svg
                  viewBox="0 0 48 48"
                  fill="none"
                  xmlns="http://www.w3.org/2000/svg"
                  className="w-full h-full drop-shadow-[0_0_25px_rgba(251,191,36,1)]"
                >
                  <defs>
                    <linearGradient id="liveHullV2" x1="10" y1="10" x2="38" y2="38" gradientUnits="userSpaceOnUse">
                      <stop offset="0%" stopColor="#FFFFFF" />
                      <stop offset="30%" stopColor="#F8FAFC" />
                      <stop offset="65%" stopColor="#CBD5E1" />
                      <stop offset="100%" stopColor="#475569" />
                    </linearGradient>
                    <linearGradient id="liveNoseV2" x1="30" y1="4" x2="44" y2="18" gradientUnits="userSpaceOnUse">
                      <stop offset="0%" stopColor="#FF3B30" />
                      <stop offset="60%" stopColor="#E11D48" />
                      <stop offset="100%" stopColor="#9F1239" />
                    </linearGradient>
                    <linearGradient id="liveWingV2" x1="12" y1="12" x2="36" y2="36" gradientUnits="userSpaceOnUse">
                      <stop offset="0%" stopColor="#38BDF8" />
                      <stop offset="50%" stopColor="#2563EB" />
                      <stop offset="100%" stopColor="#1E3A8A" />
                    </linearGradient>
                    <radialGradient id="livePlasmaV2" cx="12" cy="36" r="14" gradientUnits="userSpaceOnUse">
                      <stop offset="0%" stopColor="#FFFFFF" />
                      <stop offset="25%" stopColor="#67E8F9" />
                      <stop offset="55%" stopColor="#FBBF24" />
                      <stop offset="80%" stopColor="#F97316" />
                      <stop offset="100%" stopColor="rgba(239, 68, 68, 0)" />
                    </radialGradient>
                  </defs>

                  {/* High-Velocity Plasma Flame Plume */}
                  <path
                    d="M16 32 C12 36 6 44 2 46 C5 41 12 34 16 32 Z"
                    fill="url(#livePlasmaV2)"
                    className="animate-pulse"
                    filter="drop-shadow(0 0 12px #F59E0B)"
                  />
                  <path
                    d="M17 31 C13.5 35 8 42 4 44 C6.5 40 13 33.5 17 31 Z"
                    fill="#FFFFFF"
                    opacity="0.95"
                  />

                  {/* Left Delta Wing */}
                  <path
                    d="M11 29 C9 22 13 18 18 18 L15 34 L11 29 Z"
                    fill="url(#liveWingV2)"
                    stroke="#7DD3FC"
                    strokeWidth="1.2"
                  />

                  {/* Right Delta Wing */}
                  <path
                    d="M29 11 C22 9 18 13 18 18 L34 15 L29 11 Z"
                    fill="url(#liveWingV2)"
                    stroke="#7DD3FC"
                    strokeWidth="1.2"
                  />

                  {/* Central Pure Titanium Fuselage */}
                  <path
                    d="M38 10 C33 15 23 19 14 28 C12.5 29.5 11.2 32.5 10 34.5 L13.5 38 C15.5 36.8 18.5 35.5 20 34 C29 25 33 15 38 10 Z"
                    fill="url(#liveHullV2)"
                    stroke="#FFFFFF"
                    strokeWidth="1.6"
                  />

                  {/* Specular Chrome Reflection Spine */}
                  <path
                    d="M37 11 C32 16 23 20 15 28 C14 29 13 31 12 33 L14 35 C15.5 33.8 17.5 32.5 19 31 C27 23 31 15 37 11 Z"
                    fill="#FFFFFF"
                    opacity="0.6"
                  />

                  {/* Scarlet Aerodynamic Nose Cone */}
                  <path
                    d="M38 10 C35.5 12.5 30.5 14.8 27.5 16.8 L31.2 20.5 C33.2 17.5 35.5 12.5 38 10 Z"
                    fill="url(#liveNoseV2)"
                    stroke="#FECDD3"
                    strokeWidth="0.8"
                  />

                  {/* Illuminated Cockpit Porthole */}
                  <circle cx="25.5" cy="22.5" r="4" fill="#0284C7" stroke="#BAE6FD" strokeWidth="1.5" />
                  <circle cx="24.2" cy="21.2" r="1.5" fill="#FFFFFF" opacity="0.95" />

                  {/* Exhaust Nozzle */}
                  <path d="M12 36.5 L14.5 39 L10.5 43 L8 40.5 L12 36.5 Z" fill="#0F172A" stroke="#94A3B8" strokeWidth="1" />
                </svg>
              </div>
            </div>

            {/* Subtitle Badge */}
            <p className="text-white/90 font-['DM_Sans'] text-xs sm:text-base md:text-lg font-medium tracking-wide max-w-xl mx-auto drop-shadow-[0_2px_12px_rgba(0,0,0,0.95)] mt-2 sm:mt-3">
              Sri Lanka&apos;s Flagship All-In-One Super App is officially launched nationwide
            </p>
          </div>
        </div>

        {/* ── 4. Symmetrical Grand Row of 6 Super-App Service Cards ─── */}
        <div
          className="flex flex-nowrap items-center justify-start sm:justify-center gap-2 sm:gap-3 md:gap-4 max-w-full overflow-x-auto no-scrollbar px-3 sm:px-4 py-2 sm:py-3 z-10 mt-1 sm:mt-2"
          onMouseEnter={() => setIsHovered(true)}
          onMouseLeave={() => setIsHovered(false)}
        >
          {ZIGGO_SERVICES.map((service, idx) => {
            const isActive = idx === activeCardIndex;
            return (
              <div
                key={service.name}
                onClick={() => {
                  setActiveCardIndex(idx);
                  playCardClickAudio();
                }}
                onMouseEnter={() => setActiveCardIndex(idx)}
                className={`relative flex-shrink-0 cursor-pointer group flex flex-col items-center w-[88px] sm:w-[110px] md:w-[124px] lg:w-[136px] rounded-2xl overflow-hidden bg-[#0A1226]/85 backdrop-blur-md transition-all duration-500 ${
                  isActive
                    ? 'scale-110 sm:scale-120 -translate-y-1.5 sm:-translate-y-2.5 z-30 ring-2 ring-white/50'
                    : 'scale-95 sm:scale-100 opacity-80 hover:opacity-100 hover:scale-105 hover:-translate-y-1 hover:z-30'
                }`}
                style={{
                  animation: 'fade-up 0.8s cubic-bezier(0.34,1.56,0.64,1) both',
                  animationDelay: `${idx * 80}ms`,
                  boxShadow: isActive
                    ? `0 20px 45px -5px ${service.glowColor}, 0 0 25px ${service.color}`
                    : '0 10px 30px rgba(0,0,0,0.8)',
                  borderColor: isActive ? service.color : 'rgba(255, 255, 255, 0.15)',
                }}
              >
                {/* Photo Banner with Zoom */}
                <div className="relative w-full h-18 sm:h-24 md:h-28 overflow-hidden">
                  <Image
                    src={service.image}
                    alt={service.name}
                    width={200}
                    height={150}
                    unoptimized
                    className={`w-full h-full object-cover transition-transform duration-700 ${
                      isActive ? 'scale-115 brightness-105' : 'group-hover:scale-115'
                    }`}
                  />

                  {/* Top Subtle Dark Shadow */}
                  <div className="absolute top-0 inset-x-0 h-6 bg-gradient-to-b from-[#0A1226]/80 via-[#0A1226]/20 to-transparent pointer-events-none z-10" />

                  {/* Gradient Shading from Image into Dark Card Base */}
                  <div className="absolute inset-0 bg-gradient-to-t from-[#0A1226] via-[#0A1226]/30 to-transparent" />

                  {/* Top Glowing Color Accent Bar */}
                  <div
                    className="absolute top-0 inset-x-0 h-[3.5px] z-20 transition-all duration-500"
                    style={{
                      backgroundColor: service.color,
                      boxShadow: isActive
                        ? `0 0 16px 3px ${service.color}, 0 2px 8px ${service.color}`
                        : `0 0 10px 1px ${service.color}`,
                    }}
                  />
                </div>

                {/* Service Titles */}
                <div className="relative z-10 flex flex-col items-center text-center p-2 pt-1 w-full">
                  <span className={`font-['Outfit'] font-black text-white text-xs sm:text-sm md:text-base tracking-wide transition-colors duration-300 ${
                    isActive ? 'text-white drop-shadow-[0_0_12px_rgba(255,255,255,0.8)]' : ''
                  }`}>
                    {service.name}
                  </span>
                  <span
                    className="font-['DM_Sans'] font-semibold text-[10px] sm:text-xs md:text-[13px] tracking-wide"
                    style={{ color: service.color }}
                  >
                    {service.tag}
                  </span>
                </div>
              </div>
            );
          })}
        </div>

        {/* ── 5. Master CTA: Explore Ziggo App ─── */}
        <div className="relative z-10 flex items-center justify-center mt-2 sm:mt-3 md:mt-4 animate-fade-up">
          <a
            href={process.env.NEXT_PUBLIC_APP_LINK ?? 'https://ziggo.app'}
            target="_blank"
            rel="noopener noreferrer"
            className="group relative overflow-hidden inline-flex items-center justify-center gap-2.5 sm:gap-3 px-8 sm:px-12 py-3 sm:py-3.5 rounded-full border border-amber-300/60 hover:border-amber-200 transition-all duration-300 hover:scale-105 active:scale-95 shadow-[0_12px_35px_rgba(0,0,0,0.8),0_0_40px_rgba(245,158,11,0.35),0_0_60px_rgba(59,130,246,0.25)]"
            style={{
              background: 'linear-gradient(180deg, rgba(255, 255, 255, 0.18) 0%, rgba(30, 58, 138, 0.85) 45%, rgba(6, 11, 24, 0.95) 100%)',
              backdropFilter: 'blur(28px)',
            }}
          >
            {/* Upper Convex Glass Specular Reflection Highlight */}
            <div
              className="absolute inset-x-3 top-1 h-3 rounded-full bg-gradient-to-b from-white/35 via-white/10 to-transparent pointer-events-none"
              aria-hidden="true"
            />

            {/* Dynamic Light Sweep */}
            <div
              className="absolute inset-0 -translate-x-full group-hover:translate-x-full transition-transform duration-1000 bg-gradient-to-r from-transparent via-white/25 to-transparent pointer-events-none"
              aria-hidden="true"
            />

            <span
              className="font-['Outfit'] font-black text-sm sm:text-base md:text-lg tracking-[0.15em] uppercase text-white"
              style={{
                background: 'linear-gradient(180deg, #FFFFFF 0%, #FFFBEB 25%, #FDE68A 55%, #F59E0B 85%, #D97706 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
                filter: 'drop-shadow(0 0 14px rgba(245, 158, 11, 0.45))',
              }}
            >
              Explore Ziggo App
            </span>

            <svg
              className="w-4 h-4 sm:w-5 sm:h-5 text-amber-300 group-hover:translate-x-1 transition-transform duration-300"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              strokeWidth={2.5}
            >
              <path strokeLinecap="round" strokeLinejoin="round" d="M14 5l7 7m0 0l-7 7m7-7H3" />
            </svg>
          </a>
        </div>

      </div>
    </div>
  );
}
