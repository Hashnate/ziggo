'use client';

import { useState } from 'react';
import StateA from '@/components/StateA';
import CinematicLaunch from '@/components/CinematicLaunch';

export default function HomePage() {
  const [isLaunched, setIsLaunched] = useState(false);

  return (
    <main className="relative w-screen h-screen overflow-hidden bg-[#03061A]">
      {isLaunched ? (
        <CinematicLaunch onComplete={() => setIsLaunched(false)} />
      ) : (
        <StateA onLaunched={() => setIsLaunched(true)} />
      )}
    </main>
  );
}


