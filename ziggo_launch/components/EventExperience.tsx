'use client';

import { useEffect, useRef } from 'react';
import Image from 'next/image';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

export default function EventExperience() {
  const containerRef = useRef<HTMLDivElement>(null);
  const imageCardRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    gsap.registerPlugin(ScrollTrigger);

    if (!containerRef.current) return;

    if (imageCardRef.current) {
      gsap.fromTo(
        imageCardRef.current,
        {
          opacity: 0,
          scale: 0.9,
          y: 40,
        },
        {
          opacity: 1,
          scale: 1,
          y: 0,
          duration: 1.2,
          ease: 'power3.out',
          scrollTrigger: {
            trigger: imageCardRef.current,
            start: 'top 75%',
          },
        }
      );
    }
  }, []);

  return (
    <section
      ref={containerRef}
      className="relative py-20 sm:py-28 px-4 overflow-hidden border-t border-white/[0.06]"
      aria-label="Event Experience"
    >
      {/* Background Volumetric Beam */}
      <div
        className="absolute top-1/3 right-0 w-[500px] h-[500px] rounded-full blur-[140px] opacity-20 pointer-events-none"
        style={{
          background: 'radial-gradient(circle, rgba(59, 130, 246, 0.4) 0%, rgba(245, 158, 11, 0.2) 60%, transparent 80%)',
        }}
        aria-hidden="true"
      />

      <div className="max-w-6xl mx-auto flex flex-col gap-20 sm:gap-28">
        {/* Feature 1: The Super App 3D Visual Masterpiece */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-10 lg:gap-14 items-center">
          <div className="flex flex-col gap-5 text-left">
            <span className="inline-flex items-center gap-2 px-3.5 py-1 rounded-full bg-blue-500/10 border border-blue-400/30 text-[11px] font-bold tracking-[0.2em] uppercase text-blue-300 w-fit">
              <span className="w-1.5 h-1.5 rounded-full bg-blue-400 animate-pulse" />
              Next-Gen Ecosystem
            </span>

            <h2
              className="font-['Outfit'] font-black text-white tracking-tight leading-tight"
              style={{ fontSize: 'clamp(2.2rem, 5vw, 3.8rem)' }}
            >
              One Tap.{' '}
              <span
                className="animate-text-shimmer"
                style={{
                  background: 'linear-gradient(90deg, #60A5FA 0%, #FFFFFF 40%, #F59E0B 100%)',
                  WebkitBackgroundClip: 'text',
                  backgroundClip: 'text',
                  WebkitTextFillColor: 'transparent',
                }}
              >
                Infinite Superpowers.
              </span>
            </h2>

            <p className="font-['DM_Sans'] text-white/70 text-sm sm:text-base leading-relaxed">
              Ziggo bridges every daily essential into a single, high-speed ecosystem. From swift ride booking and gourmet meal delivery to nationwide logistics and exclusive VIP concert passes — everything works seamlessly under one roof.
            </p>

            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 pt-2">
              <div className="service-hud-card p-3 text-center">
                <span className="font-['Outfit'] font-black text-xl text-blue-300">0.8s</span>
                <span className="font-['DM_Sans'] text-[10px] text-white/50 block uppercase tracking-wider mt-0.5">Average Match</span>
              </div>
              <div className="service-hud-card p-3 text-center">
                <span className="font-['Outfit'] font-black text-xl text-amber-300">24/7</span>
                <span className="font-['DM_Sans'] text-[10px] text-white/50 block uppercase tracking-wider mt-0.5">Islandwide Support</span>
              </div>
              <div className="service-hud-card p-3 text-center col-span-2 sm:col-span-1">
                <span className="font-['Outfit'] font-black text-xl text-emerald-300">100%</span>
                <span className="font-['DM_Sans'] text-[10px] text-white/50 block uppercase tracking-wider mt-0.5">Verified Fleet</span>
              </div>
            </div>
          </div>

          {/* 3D Colorful Super App Artwork Showcase */}
          <div
            ref={imageCardRef}
            className="relative rounded-3xl overflow-hidden border border-white/15 shadow-[0_25px_60px_rgba(0,0,0,0.8),0_0_50px_rgba(59,130,246,0.2)] group"
          >
            {/* Top Shine */}
            <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-white/50 to-transparent z-10" />

            <Image
              src="/hero-superapp-3d.jpg"
              alt="Ziggo 3D Super App Ecosystem"
              width={1280}
              height={720}
              className="w-full h-auto object-cover transform transition-transform duration-700 group-hover:scale-105"
            />

            {/* Glowing Corner Badge */}
            <div className="absolute bottom-4 right-4 z-10 px-3.5 py-1.5 rounded-full bg-black/60 border border-white/20 backdrop-blur-md text-[11px] font-bold text-amber-300 flex items-center gap-1.5 shadow-lg">
              <span>✨</span>
              <span>All-In-One Flagship Experience</span>
            </div>
          </div>
        </div>

        {/* Feature 2: Nationwide Islandwide Rollout */}
        <div className="service-hud-card p-8 sm:p-12 relative overflow-hidden text-center flex flex-col items-center">
          <span className="text-[11px] font-extrabold uppercase px-4 py-1.5 rounded-full bg-amber-400/15 border border-amber-400/30 text-amber-300 tracking-[0.2em] mb-4">
            Phase 1 Nationwide Ignition
          </span>

          <h3 className="font-['Outfit'] font-black text-2xl sm:text-4xl text-white mb-3">
            Launching Simultaneously Across Sri Lanka
          </h3>

          <p className="font-['DM_Sans'] text-white/60 text-sm sm:text-base max-w-xl mb-8">
            Starting from the heart of Colombo, expanding instantly to Kandy, Galle, Negombo, and nationwide transit corridors on launch night.
          </p>

          <div className="flex flex-wrap items-center justify-center gap-3 sm:gap-6">
            {['Colombo Central', 'Kandy Metro', 'Galle Fort', 'Negombo Coastal', 'Kurunegala', 'Jaffna Express'].map((city) => (
              <span
                key={city}
                className="px-4 py-2 rounded-full glass border border-white/10 text-xs sm:text-sm font-semibold text-white/80 hover:border-amber-400/50 hover:text-amber-200 transition-colors cursor-default"
              >
                📍 {city}
              </span>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
