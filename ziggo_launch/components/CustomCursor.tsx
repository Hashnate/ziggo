'use client';

import { useEffect, useRef, useState } from 'react';

export default function CustomCursor() {
  const dotRef = useRef<HTMLDivElement>(null);
  const ringRef = useRef<HTMLDivElement>(null);
  const [isPointer, setIsPointer] = useState(false);
  const [cursorLabel, setCursorLabel] = useState('');
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    // Only enable on desktop pointer devices
    if (window.matchMedia('(pointer: coarse)').matches) return;

    let mouseX = window.innerWidth / 2;
    let mouseY = window.innerHeight / 2;
    let ringX = mouseX;
    let ringY = mouseY;
    let animId: number;

    const onMouseMove = (e: MouseEvent) => {
      mouseX = e.clientX;
      mouseY = e.clientY;
      if (!isVisible) setIsVisible(true);

      if (dotRef.current) {
        dotRef.current.style.transform = `translate3d(${mouseX}px, ${mouseY}px, 0)`;
      }

      // Check hovered element
      const target = e.target as HTMLElement | null;
      const interactive = target?.closest('button, a, input, [data-cursor], .cursor-pointer');
      if (interactive) {
        setIsPointer(true);
        const label = interactive.getAttribute('data-cursor') || '';
        setCursorLabel(label);
      } else {
        setIsPointer(false);
        setCursorLabel('');
      }
    };

    const onMouseLeave = () => setIsVisible(false);
    const onMouseEnter = () => setIsVisible(true);

    window.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseleave', onMouseLeave);
    document.addEventListener('mouseenter', onMouseEnter);

    // Smooth inertia for trailing ring
    const render = () => {
      ringX += (mouseX - ringX) * 0.15;
      ringY += (mouseY - ringY) * 0.15;

      if (ringRef.current) {
        ringRef.current.style.transform = `translate3d(${ringX}px, ${ringY}px, 0)`;
      }

      animId = requestAnimationFrame(render);
    };

    render();

    return () => {
      window.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseleave', onMouseLeave);
      document.removeEventListener('mouseenter', onMouseEnter);
      cancelAnimationFrame(animId);
    };
  }, [isVisible]);

  if (!isVisible) return null;

  return (
    <div className="pointer-events-none fixed inset-0 z-[999] overflow-hidden" aria-hidden="true">
      {/* Precision Center Dot */}
      <div
        ref={dotRef}
        className="fixed -top-1 -left-1 w-2 h-2 rounded-full bg-amber-300 shadow-[0_0_8px_#F59E0B] will-change-transform"
      />

      {/* Trailing Fluid Luxury Ring */}
      <div
        ref={ringRef}
        className={`fixed flex items-center justify-center rounded-full border border-amber-400/50 backdrop-blur-[1px] transition-[width,height,background-color,border-color] duration-200 ease-out will-change-transform ${
          isPointer
            ? 'w-14 h-14 -top-7 -left-7 bg-amber-400/10 border-amber-300 shadow-[0_0_20px_rgba(245,158,11,0.3)]'
            : 'w-8 h-8 -top-4 -left-4 bg-transparent border-white/30'
        }`}
      >
        {cursorLabel && (
          <span className="font-['DM_Sans'] text-[9px] font-extrabold text-amber-300 tracking-wider uppercase select-none">
            {cursorLabel}
          </span>
        )}
      </div>
    </div>
  );
}
