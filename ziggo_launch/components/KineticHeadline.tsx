'use client';

import { useEffect, useRef } from 'react';
import gsap from 'gsap';
import SplitType from 'split-type';

interface KineticHeadlineProps {
  prefix?: string;
  highlight?: string;
}

export default function KineticHeadline({
  prefix = 'The Wait is Over.',
  highlight = 'Ziggo Arrives.',
}: KineticHeadlineProps) {
  const containerRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    if (!containerRef.current) return;

    // Split text into words and characters
    const split = new SplitType(containerRef.current, {
      types: 'words,chars',
      tagName: 'span',
    });

    if (split.chars && split.chars.length > 0) {
      gsap.fromTo(
        split.chars,
        {
          opacity: 0,
          y: 40,
          rotateX: -45,
          filter: 'blur(8px)',
        },
        {
          opacity: 1,
          y: 0,
          rotateX: 0,
          filter: 'blur(0px)',
          duration: 1.1,
          stagger: 0.025,
          ease: 'power4.out',
          delay: 0.3,
        }
      );
    }

    return () => {
      split.revert();
    };
  }, [prefix, highlight]);

  return (
    <h1
      ref={containerRef}
      className="font-['Outfit'] font-black leading-[1.05] tracking-tight text-white select-none"
      style={{
        fontSize: 'clamp(1.7rem, 3.8vw, 3.4rem)',
        textShadow: '0 0 50px rgba(59, 130, 246, 0.45)',
        perspective: '1000px',
      }}
    >
      <span className="block text-white/95 drop-shadow-md">{prefix}</span>
      <span
        className="block animate-text-shimmer"
        style={{
          background: 'linear-gradient(90deg, #FFFFFF 0%, #60A5FA 25%, #F59E0B 50%, #FDE68A 75%, #FFFFFF 100%)',
          WebkitBackgroundClip: 'text',
          backgroundClip: 'text',
          WebkitTextFillColor: 'transparent',
          filter: 'drop-shadow(0 0 35px rgba(245, 158, 11, 0.45)) drop-shadow(0 0 65px rgba(96, 165, 250, 0.35))',
        }}
      >
        {highlight}
      </span>
    </h1>
  );
}
