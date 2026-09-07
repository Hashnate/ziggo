'use client';

import { useState } from 'react';
import RegistrationForm from './RegistrationForm';

interface Props {
  isOpen: boolean;
  onClose: () => void;
}

export default function RegistrationModal({ isOpen, onClose }: Props) {
  const [success, setSuccess] = useState(false);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Register for launch notification"
    >
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/70 backdrop-blur-sm"
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Modal card */}
      <div
        className="relative z-10 w-full max-w-md animate-scale-pop"
        style={{ boxShadow: '0 32px 80px rgba(0,0,0,0.6)' }}
      >
        <div
          className="glass rounded-3xl p-7 md:p-9 flex flex-col gap-5"
          style={{ border: '1px solid rgba(255,255,255,0.12)' }}
        >
          {/* Close button */}
          <button
            onClick={onClose}
            className="absolute top-4 right-4 w-9 h-9 rounded-full glass flex items-center justify-center text-white/50 hover:text-white transition-colors"
            aria-label="Close"
          >
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>

          {!success ? (
            <>
              {/* Header */}
              <div className="text-center flex flex-col gap-2 pr-4">
                <span className="text-3xl" aria-hidden="true">🔔</span>
                <h2
                  className="font-['Outfit'] font-black text-white leading-tight"
                  style={{ fontSize: 'clamp(1.4rem, 3.5vw, 1.9rem)', letterSpacing: '-0.025em' }}
                >
                  Get Notified at Launch
                </h2>
                <p className="text-white/50 font-['DM_Sans'] text-sm leading-relaxed">
                  We&apos;ll send you a push notification the instant Ziggo goes live.
                </p>
              </div>

              {/* Divider */}
              <div className="h-px bg-white/[0.07]" aria-hidden="true" />

              {/* Form — reuse existing component, pass onSuccess */}
              <RegistrationForm onSuccess={() => setSuccess(true)} />

              <p className="text-center text-white/20 text-xs font-['DM_Sans']">
                No spam — one notification only. 🔒
              </p>
            </>
          ) : (
            /* Success state */
            <div className="flex flex-col items-center gap-5 py-4 text-center animate-scale-pop">
              <div
                className="w-20 h-20 rounded-full flex items-center justify-center text-4xl"
                style={{
                  background: 'linear-gradient(135deg, rgba(59,130,246,0.25) 0%, rgba(30,58,138,0.35) 100%)',
                  border: '1px solid rgba(96,165,250,0.3)',
                }}
              >
                🎉
              </div>
              <h3 className="font-['Outfit'] font-bold text-white text-2xl">You&apos;re on the list!</h3>
              <p className="text-white/55 font-['DM_Sans'] text-sm leading-relaxed max-w-xs">
                We&apos;ll ping you the second Ziggo goes live. Get ready — it&apos;s going to be epic! 🚀
              </p>
              <div className="flex items-center gap-2 px-4 py-2 rounded-full glass text-brand-glow text-xs font-semibold font-['DM_Sans']">
                <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
                Launch notification enabled
              </div>
              <button
                onClick={onClose}
                className="btn-cta px-8"
              >
                Got it 🚀
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
