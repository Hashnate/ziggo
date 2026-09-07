// Synthesizes ambient stage suspense sound & celebratory launch chime using Web Audio API

let suspenseOsc: OscillatorNode | null = null;
let suspenseGain: GainNode | null = null;
let suspenseInterval: ReturnType<typeof setInterval> | null = null;

export function toggleSuspenseAudio(enable: boolean): boolean {
  try {
    const AudioContextClass = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    if (!AudioContextClass) return false;

    if (!enable) {
      if (suspenseInterval) clearInterval(suspenseInterval);
      if (suspenseGain) {
        suspenseGain.gain.linearRampToValueAtTime(0.0001, (suspenseGain.context.currentTime || 0) + 0.5);
      }
      setTimeout(() => {
        try {
          suspenseOsc?.stop();
          suspenseOsc?.disconnect();
        } catch {}
        suspenseOsc = null;
        suspenseGain = null;
      }, 600);
      return false;
    }

    const ctx = new AudioContextClass();
    if (ctx.state === 'suspended') ctx.resume();

    // Deep cinematic sub-bass drone
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    const filter = ctx.createBiquadFilter();

    osc.type = 'sine';
    osc.frequency.setValueAtTime(55, ctx.currentTime); // 55Hz (A1) sub-bass

    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(140, ctx.currentTime);

    gain.gain.setValueAtTime(0.001, ctx.currentTime);
    gain.gain.linearRampToValueAtTime(0.12, ctx.currentTime + 2);

    osc.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    osc.start();

    suspenseOsc = osc;
    suspenseGain = gain;

    // Heartbeat suspense thud every 1.5s
    suspenseInterval = setInterval(() => {
      try {
        if (!ctx || ctx.state !== 'running') return;
        const kickOsc = ctx.createOscillator();
        const kickGain = ctx.createGain();
        kickOsc.type = 'sine';
        kickOsc.frequency.setValueAtTime(90, ctx.currentTime);
        kickOsc.frequency.exponentialRampToValueAtTime(35, ctx.currentTime + 0.18);

        kickGain.gain.setValueAtTime(0.2, ctx.currentTime);
        kickGain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.25);

        kickOsc.connect(kickGain);
        kickGain.connect(ctx.destination);
        kickOsc.start();
        kickOsc.stop(ctx.currentTime + 0.28);
      } catch {}
    }, 1500);

    return true;
  } catch {
    return false;
  }
}

// Pre-instantiated and preloaded audio objects for zero-latency instant playback
let celebrationAudio: HTMLAudioElement | null = null;
let clickAudio: HTMLAudioElement | null = null;
let lastCelebrationPlayTime = 0;

if (typeof window !== 'undefined') {
  try {
    celebrationAudio = new Audio('/sounds/celebration-premium.wav');
    celebrationAudio.preload = 'auto';
    celebrationAudio.volume = 0.95;

    clickAudio = new Audio('/sounds/click-premium.wav');
    clickAudio.preload = 'auto';
    clickAudio.volume = 0.50;
  } catch {}
}

export function playCelebrationAudio() {
  try {
    // Prevent double-trigger echo / stutter if triggered within 2.5 seconds
    const now = Date.now();
    if (now - lastCelebrationPlayTime < 2500) return;
    lastCelebrationPlayTime = now;

    // Immediately stop any suspense drone
    toggleSuspenseAudio(false);

    if (!celebrationAudio && typeof window !== 'undefined') {
      celebrationAudio = new Audio('/sounds/celebration-premium.wav');
      celebrationAudio.volume = 0.95;
    }

    if (celebrationAudio) {
      celebrationAudio.currentTime = 0;
      celebrationAudio.play().catch(() => {
        // Fallback for browsers requiring gesture
      });
    }
  } catch {}
}

export function playCardClickAudio() {
  try {
    if (!clickAudio && typeof window !== 'undefined') {
      clickAudio = new Audio('/sounds/click-premium.wav');
      clickAudio.volume = 0.50;
    }
    if (clickAudio) {
      clickAudio.currentTime = 0;
      clickAudio.play().catch(() => {});
    }
  } catch {}
}

