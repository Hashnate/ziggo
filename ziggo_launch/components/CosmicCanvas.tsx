'use client';

import { useEffect, useRef } from 'react';

interface CanvasProps {
  active: boolean;
}

export default function CosmicCanvas({ active }: CanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animationId: number;
    let width = (canvas.width = window.innerWidth);
    let height = (canvas.height = window.innerHeight);

    const handleResize = () => {
      if (!canvas) return;
      width = canvas.width = window.innerWidth;
      height = canvas.height = window.innerHeight;
    };
    window.addEventListener('resize', handleResize);

    // Mouse coordinates with spring lerp for silky smooth interactive parallax
    let mouseX = width / 2;
    let mouseY = height / 2;
    let targetMouseX = mouseX;
    let targetMouseY = mouseY;

    const handleMouseMove = (e: MouseEvent) => {
      targetMouseX = e.clientX;
      targetMouseY = e.clientY;
    };
    window.addEventListener('mousemove', handleMouseMove);

    // ── 1. ATMOSPHERIC NEBULA ORBS (Soft volumetric fluid lights) ───────────
    const nebulaOrbs = [
      {
        xRatio: 0.2,
        yRatio: 0.3,
        radiusRatio: 0.45,
        colorInner: 'rgba(37, 99, 235, 0.28)', // Royal Sapphire
        colorOuter: 'rgba(3, 7, 18, 0)',
        speedX: 0.0004,
        speedY: 0.0003,
        phase: 0,
      },
      {
        xRatio: 0.8,
        yRatio: 0.4,
        radiusRatio: 0.4,
        colorInner: 'rgba(245, 158, 11, 0.16)', // Champagne Gold
        colorOuter: 'rgba(3, 7, 18, 0)',
        speedX: -0.0003,
        speedY: 0.0004,
        phase: Math.PI / 3,
      },
      {
        xRatio: 0.5,
        yRatio: 0.75,
        radiusRatio: 0.5,
        colorInner: 'rgba(79, 70, 229, 0.22)', // Indigo Glow
        colorOuter: 'rgba(3, 7, 18, 0)',
        speedX: 0.00025,
        speedY: -0.00035,
        phase: Math.PI * 0.7,
      },
      {
        xRatio: 0.5,
        yRatio: 0.2,
        radiusRatio: 0.35,
        colorInner: 'rgba(6, 182, 212, 0.15)', // Ice Cyan
        colorOuter: 'rgba(3, 7, 18, 0)',
        speedX: -0.0002,
        speedY: 0.00025,
        phase: Math.PI * 1.2,
      },
    ];

    // ── 2. MULTI-TIER STARDUST PARTICLES & CONSTELLATION NETWORK ───────────
    interface Particle {
      x: number;
      y: number;
      baseX: number;
      baseY: number;
      size: number;
      speedY: number;
      speedX: number;
      alpha: number;
      baseAlpha: number;
      color: string;
      glow: number;
      tier: 'bg-bokeh' | 'mid-star' | 'fg-ember';
      phase: number;
    }

    const particles: Particle[] = [];
    const colorPalette = [
      '#60A5FA', // Azure bright
      '#93C5FD', // Ice blue
      '#F59E0B', // 24K Gold
      '#FDE68A', // Champagne
      '#FFFFFF', // Pure diamond
      '#38BDF8', // Cyan
    ];

    const particleCount = Math.min(120, Math.floor(width / 16));

    for (let i = 0; i < particleCount; i++) {
      const isBokeh = Math.random() < 0.12;
      const isEmber = Math.random() > 0.75;
      const tier: 'bg-bokeh' | 'mid-star' | 'fg-ember' = isBokeh
        ? 'bg-bokeh'
        : isEmber
        ? 'fg-ember'
        : 'mid-star';

      const size = isBokeh
        ? Math.random() * 18 + 12
        : isEmber
        ? Math.random() * 2.2 + 1.2
        : Math.random() * 1.5 + 0.6;

      const alpha = isBokeh
        ? Math.random() * 0.07 + 0.03
        : isEmber
        ? Math.random() * 0.65 + 0.35
        : Math.random() * 0.45 + 0.15;

      const px = Math.random() * width;
      const py = Math.random() * height;

      particles.push({
        x: px,
        y: py,
        baseX: px,
        baseY: py,
        size,
        speedY: isBokeh ? Math.random() * 0.15 + 0.05 : Math.random() * 0.4 + 0.15,
        speedX: (Math.random() - 0.5) * 0.15,
        alpha,
        baseAlpha: alpha,
        color: colorPalette[Math.floor(Math.random() * colorPalette.length)],
        glow: isBokeh ? 0 : isEmber ? Math.random() * 14 + 6 : Math.random() * 6 + 2,
        tier,
        phase: Math.random() * Math.PI * 2,
      });
    }

    // ── 3. LAUNCH FIREWORKS & GOLDEN BURSTS ─────────────────────────────────
    interface Firework {
      x: number;
      y: number;
      vx: number;
      vy: number;
      color: string;
      alpha: number;
      size: number;
      decay: number;
    }
    const fireworks: Firework[] = [];

    function spawnBurst(x: number, y: number) {
      const burstColor = colorPalette[Math.floor(Math.random() * colorPalette.length)];
      const count = 60;
      for (let i = 0; i < count; i++) {
        const angle = Math.random() * Math.PI * 2;
        const speed = Math.random() * 6.5 + 1.5;
        fireworks.push({
          x,
          y,
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed,
          color: burstColor,
          alpha: 1,
          size: Math.random() * 2.5 + 1,
          decay: Math.random() * 0.016 + 0.009,
        });
      }
    }

    // ── 4. RENDER LOOP ─────────────────────────────────────────────────────
    let time = 0;
    let frameCount = 0;

    const render = () => {
      time += 0.01;
      frameCount++;

      // Smooth mouse lerp
      mouseX += (targetMouseX - mouseX) * 0.05;
      mouseY += (targetMouseY - mouseY) * 0.05;

      ctx.clearRect(0, 0, width, height);

      // A. Deep Obsidian Base
      ctx.fillStyle = '#030712';
      ctx.fillRect(0, 0, width, height);

      // B. Render Atmospheric Nebula Fluid Orbs
      ctx.save();
      for (const orb of nebulaOrbs) {
        const ox =
          width * orb.xRatio +
          Math.sin(time * orb.speedX * 1000 + orb.phase) * (width * 0.12) +
          (mouseX - width / 2) * 0.04;
        const oy =
          height * orb.yRatio +
          Math.cos(time * orb.speedY * 1000 + orb.phase) * (height * 0.1) +
          (mouseY - height / 2) * 0.04;
        const r = Math.max(width, height) * orb.radiusRatio;

        const grad = ctx.createRadialGradient(ox, oy, 0, ox, oy, r);
        grad.addColorStop(0, orb.colorInner);
        grad.addColorStop(0.5, orb.colorInner.replace(/[\d\.]+\)$/, '0.08)'));
        grad.addColorStop(1, orb.colorOuter);

        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.arc(ox, oy, r, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();

      // C. Render Delicate Interactive Constellation Filaments
      ctx.save();
      const maxConnectDist = 110;
      for (let i = 0; i < particles.length; i++) {
        if (particles[i].tier === 'bg-bokeh') continue;
        for (let j = i + 1; j < particles.length; j++) {
          if (particles[j].tier === 'bg-bokeh') continue;
          const dx = particles[i].x - particles[j].x;
          const dy = particles[i].y - particles[j].y;
          const dist = Math.sqrt(dx * dx + dy * dy);

          if (dist < maxConnectDist) {
            const lineAlpha = (1 - dist / maxConnectDist) * 0.12;
            ctx.strokeStyle = `rgba(147, 197, 253, ${lineAlpha})`;
            ctx.lineWidth = 0.6;
            ctx.beginPath();
            ctx.moveTo(particles[i].x, particles[i].y);
            ctx.lineTo(particles[j].x, particles[j].y);
            ctx.stroke();
          }
        }
      }
      ctx.restore();

      // D. Render Stardust, Golden Embers & Bokeh Orbs
      for (const p of particles) {
        // Upward floating physics
        p.y -= active ? p.speedY * 4 : p.speedY;
        p.x += p.speedX + Math.sin(time + p.phase) * 0.15;

        // Interactive subtle repulsion from cursor
        const mdx = p.x - mouseX;
        const mdy = p.y - mouseY;
        const mDist = Math.sqrt(mdx * mdx + mdy * mdy);
        if (mDist < 120) {
          const push = (1 - mDist / 120) * 0.8;
          p.x += (mdx / mDist) * push;
          p.y += (mdy / mDist) * push;
        }

        // Loop boundaries smoothly
        if (p.y < -30) {
          p.y = height + 30;
          p.x = Math.random() * width;
        }
        if (p.x < -30) p.x = width + 30;
        if (p.x > width + 30) p.x = -30;

        // Twinkle sinusoidal pulse
        const twinkle = 0.7 + 0.3 * Math.sin(time * 2.5 + p.phase);
        const curAlpha = p.baseAlpha * twinkle;

        ctx.save();
        if (p.tier === 'bg-bokeh') {
          // Large soft out-of-focus background bokeh
          const bGrad = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.size);
          bGrad.addColorStop(0, p.color);
          bGrad.addColorStop(1, 'transparent');
          ctx.fillStyle = bGrad;
          ctx.globalAlpha = curAlpha;
          ctx.beginPath();
          ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
          ctx.fill();
        } else {
          // Sharp glowing stardust / ember
          ctx.globalAlpha = Math.max(0.08, Math.min(1, curAlpha));
          ctx.fillStyle = p.color;
          if (p.glow > 0) {
            ctx.shadowColor = p.color;
            ctx.shadowBlur = p.glow;
          }
          ctx.beginPath();
          ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
          ctx.fill();
        }
        ctx.restore();
      }

      // E. Launch Fireworks (when launched)
      if (active) {
        if (frameCount % 24 === 0) {
          spawnBurst(
            Math.random() * width * 0.8 + width * 0.1,
            Math.random() * height * 0.5 + height * 0.15
          );
        }

        for (let i = fireworks.length - 1; i >= 0; i--) {
          const f = fireworks[i];
          f.x += f.vx;
          f.y += f.vy;
          f.vy += 0.08; // gravity
          f.alpha -= f.decay;

          if (f.alpha <= 0) {
            fireworks.splice(i, 1);
            continue;
          }

          ctx.save();
          ctx.globalAlpha = Math.max(0, f.alpha);
          ctx.shadowColor = f.color;
          ctx.shadowBlur = 12;
          ctx.fillStyle = f.color;
          ctx.beginPath();
          ctx.arc(f.x, f.y, f.size, 0, Math.PI * 2);
          ctx.fill();
          ctx.restore();
        }
      }

      // F. Cinematic Outer Vignette
      const vGrad = ctx.createRadialGradient(
        width / 2,
        height / 2,
        Math.min(width, height) * 0.35,
        width / 2,
        height / 2,
        Math.max(width, height) * 0.75
      );
      vGrad.addColorStop(0, 'rgba(0, 0, 0, 0)');
      vGrad.addColorStop(1, 'rgba(2, 6, 23, 0.65)');
      ctx.fillStyle = vGrad;
      ctx.fillRect(0, 0, width, height);

      animationId = requestAnimationFrame(render);
    };

    render();

    return () => {
      cancelAnimationFrame(animationId);
      window.removeEventListener('resize', handleResize);
      window.removeEventListener('mousemove', handleMouseMove);
    };
  }, [active]);

  return (
    <canvas
      ref={canvasRef}
      className="absolute inset-0 pointer-events-none z-0"
      style={{ width: '100%', height: '100%' }}
    />
  );
}
