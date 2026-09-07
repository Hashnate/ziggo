'use client';

import { useEffect, useRef, useState, useCallback } from 'react';

interface TimeLeft {
  days: number;
  hours: number;
  minutes: number;
  seconds: number;
}

function calcTimeLeft(targetDate: Date): TimeLeft {
  const diff = Math.max(0, targetDate.getTime() - Date.now());
  return {
    days: Math.floor(diff / (1000 * 60 * 60 * 24)),
    hours: Math.floor((diff / (1000 * 60 * 60)) % 24),
    minutes: Math.floor((diff / (1000 * 60)) % 60),
    seconds: Math.floor((diff / 1000) % 60),
  };
}

function CountdownUnit({
  value,
  label,
  delay,
  accentColor = '#60A5FA',
}: {
  value: number;
  label: string;
  delay: string;
  accentColor?: string;
}) {
  const formatted = String(value).padStart(2, '0');
  const [prevVal, setPrevVal] = useState(formatted);
  const [animKey, setAnimKey] = useState(0);

  useEffect(() => {
    if (formatted !== prevVal) {
      setAnimKey((k) => k + 1);
      setPrevVal(formatted);
    }
  }, [formatted, prevVal]);

  return (
    <div
      className="stage-countdown-card px-3 py-3 sm:px-4 sm:py-4 min-w-[66px] sm:min-w-[88px] text-center flex flex-col items-center justify-center animate-fade-up group"
      style={{ animationDelay: delay }}
    >
      {/* Digits Display */}

      <span
        key={animKey}
        className="font-['Outfit'] font-black tracking-tight leading-none text-white animate-digit-flip block select-none"
        style={{
          fontSize: 'clamp(1.6rem, 3.2vw, 2.8rem)',
          background: 'linear-gradient(180deg, #FFFFFF 0%, #E2E8F0 55%, #94A3B8 100%)',
          WebkitBackgroundClip: 'text',
          backgroundClip: 'text',
          WebkitTextFillColor: 'transparent',
          filter: `drop-shadow(0 0 25px ${accentColor}66)`,
        }}
        aria-live="polite"
        aria-atomic="true"
      >
        {formatted}
      </span>

      {/* Label with micro dot */}
      <div className="flex items-center gap-1 mt-1.5 sm:mt-2">
        <span
          className="w-1.5 h-1.5 rounded-full transition-transform group-hover:scale-125"
          style={{ backgroundColor: accentColor, boxShadow: `0 0 8px ${accentColor}` }}
          aria-hidden="true"
        />
        <span
          className="font-['DM_Sans'] text-[10px] sm:text-xs font-bold tracking-[0.22em] uppercase text-white/70 group-hover:text-white transition-colors"
        >
          {label}
        </span>
      </div>
    </div>
  );
}

export default function Countdown() {
  const FALLBACK =
    process.env.NEXT_PUBLIC_LAUNCH_DATETIME ?? '2026-09-06T16:30:00+05:30';

  const [launchAt, setLaunchAt] = useState<Date>(() => new Date(FALLBACK));
  const [timeLeft, setTimeLeft] = useState<TimeLeft>(() => calcTimeLeft(new Date(FALLBACK)));
  const [isLive, setIsLive] = useState(false);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Fetch launch datetime from API
  const fetchLaunchTime = useCallback(async () => {
    try {
      const res = await fetch('/api/launch-time', { cache: 'no-store' });
      if (res.ok) {
        const data = await res.json();
        if (data.launchAt) {
          setLaunchAt(new Date(data.launchAt));
        }
      }
    } catch {
      // Network error — keep current value
    }
  }, []);

  useEffect(() => {
    fetchLaunchTime();
    pollRef.current = setInterval(fetchLaunchTime, 60_000);
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, [fetchLaunchTime]);

  // Tick every second
  useEffect(() => {
    const tick = () => {
      const tl = calcTimeLeft(launchAt);
      setTimeLeft(tl);
      if (
        tl.days === 0 &&
        tl.hours === 0 &&
        tl.minutes === 0 &&
        tl.seconds === 0
      ) {
        setIsLive(true);
      }
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [launchAt]);

  if (isLive) {
    return (
      <div className="flex flex-col items-center gap-4 animate-scale-pop">
        <div className="text-6xl md:text-8xl font-['Outfit'] font-black text-white drop-shadow-[0_0_50px_rgba(245,158,11,0.6)]">
          🚀
        </div>
        <p className="text-3xl md:text-5xl font-['Outfit'] font-black text-transparent bg-clip-text bg-gradient-to-r from-amber-300 via-white to-blue-400 text-center tracking-tight">
          ZIGGO IS OFFICIALLY LIVE!
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center gap-6 sm:gap-7 md:gap-8">
      {/* Chronometer Stage Status Pill — High Visibility & Ultra-Crisp Neon */}
      <div className="relative group flex items-center gap-2.5 px-6 py-2 rounded-full bg-[#0A1633]/90 backdrop-blur-xl border-2 border-amber-400/60 shadow-[0_0_25px_rgba(245,158,11,0.4),0_0_50px_rgba(59,130,246,0.3),inset_0_1px_2px_rgba(255,255,255,0.4)] hover:border-amber-300 transition-all duration-300 hover:scale-105">
        {/* Pulsating Amber Beacon */}
        <span className="relative flex h-2.5 w-2.5 items-center justify-center">
          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75" />
          <span className="relative inline-flex rounded-full h-2 w-2 bg-amber-300 shadow-[0_0_8px_#F59E0B]" />
        </span>

        <span className="font-['Outfit'] font-black uppercase text-xs sm:text-sm tracking-[0.2em] text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.9)]">
          <span className="text-amber-300 drop-shadow-[0_0_10px_rgba(245,158,11,0.8)]">Grand Launch</span> Countdown
        </span>
      </div>

      {/* Main Chronometer Cards */}
      <div
        className="flex items-center gap-3 sm:gap-4 md:gap-6"
        role="timer"
        aria-label="Countdown to Ziggo launch"
      >
        <CountdownUnit value={timeLeft.days} label="Days" delay="0ms" accentColor="#60A5FA" />
        <Separator />
        <CountdownUnit value={timeLeft.hours} label="Hours" delay="60ms" accentColor="#38BDF8" />
        <Separator />
        <CountdownUnit value={timeLeft.minutes} label="Minutes" delay="120ms" accentColor="#F59E0B" />
        <Separator />
        <CountdownUnit value={timeLeft.seconds} label="Seconds" delay="180ms" accentColor="#EC4899" />
      </div>
    </div>
  );
}



function Separator() {
  return (
    <div className="flex flex-col gap-2 mb-4 select-none" aria-hidden="true">
      <div className="w-1.5 h-1.5 sm:w-2 sm:h-2 rounded-full bg-blue-400 shadow-[0_0_10px_#60A5FA] animate-pulse" />
      <div className="w-1.5 h-1.5 sm:w-2 sm:h-2 rounded-full bg-amber-400 shadow-[0_0_10px_#F59E0B] animate-pulse" />
    </div>
  );
}

