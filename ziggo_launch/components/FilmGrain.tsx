'use client';

import { useEffect, useState } from 'react';

export default function FilmGrain() {
  const [patternUrl, setPatternUrl] = useState<string | null>(null);

  useEffect(() => {
    // Generate a subtle 128x128 monochrome film grain pattern once
    const canvas = document.createElement('canvas');
    canvas.width = 128;
    canvas.height = 128;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const imgData = ctx.createImageData(128, 128);
    const data = imgData.data;
    for (let i = 0; i < data.length; i += 4) {
      const v = Math.random() * 255;
      data[i] = v;     // R
      data[i + 1] = v; // G
      data[i + 2] = v; // B
      data[i + 3] = Math.random() * 32 + 10; // Subtle alpha
    }
    ctx.putImageData(imgData, 0, 0);
    setPatternUrl(canvas.toDataURL());
  }, []);

  if (!patternUrl) return null;

  return (
    <div
      className="pointer-events-none fixed inset-0 z-50 opacity-[0.038] mix-blend-overlay"
      style={{
        backgroundImage: `url(${patternUrl})`,
        backgroundRepeat: 'repeat',
        backgroundSize: '128px 128px',
      }}
      aria-hidden="true"
    />
  );
}
