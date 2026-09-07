'use client';

import { useState, useRef } from 'react';
import { requestPushSubscription } from '@/lib/push-client';

type Step = 'idle' | 'submitting' | 'push-prompt' | 'success' | 'error';

interface FormData {
  fullName: string;
  email: string;
  phone: string;
}

interface Props {
  onSuccess?: () => void;
}

export default function RegistrationForm({ onSuccess }: Props = {}) {
  const [form, setForm] = useState<FormData>({ fullName: '', email: '', phone: '' });
  const [enablePush, setEnablePush] = useState<boolean>(true);
  const [errors, setErrors] = useState<Partial<FormData>>({});
  const [step, setStep] = useState<Step>('idle');
  const [errorMsg, setErrorMsg] = useState('');
  const formRef = useRef<HTMLFormElement>(null);

  function validate(): boolean {
    const e: Partial<FormData> = {};
    if (!form.fullName.trim()) e.fullName = 'Please enter your full name.';
    if (!form.email.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email))
      e.email = 'Enter a valid email address.';
    const ph = form.phone.trim().replace(/[\s\-()]/g, '');
    if (!/^(\+94|0094|0)[0-9]{9}$/.test(ph))
      e.phone = 'Enter a valid Sri Lanka number (e.g. 071 234 5678).';
    setErrors(e);
    return Object.keys(e).length === 0;
  }

  async function submit(pushSubscription: PushSubscription | null) {
    setStep('submitting');
    try {
      const res = await fetch('/api/subscribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fullName: form.fullName.trim(),
          email: form.email.trim().toLowerCase(),
          phone: form.phone.trim().replace(/[\s\-()]/g, ''),
          pushSubscription: pushSubscription?.toJSON() ?? null,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Unknown error');
      if (onSuccess) {
        onSuccess();
      } else {
        setStep('success');
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Something went wrong. Please try again.');
      setStep('error');
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!validate()) return;

    setStep('push-prompt');
    let pushSub: PushSubscription | null = null;

    if (enablePush) {
      pushSub = await requestPushSubscription();
    }

    await submit(pushSub);
  }

  function handleChange(e: React.ChangeEvent<HTMLInputElement>) {
    const { name, value } = e.target;
    setForm((f) => ({ ...f, [name]: value }));
    if (errors[name as keyof FormData]) {
      setErrors((er) => ({ ...er, [name]: undefined }));
    }
  }

  // ── Success State ────────────────────────────────────────────
  if (step === 'success') {
    return (
      <div className="flex flex-col items-center gap-5 py-4 animate-scale-pop text-center">
        <div className="w-20 h-20 rounded-full flex items-center justify-center text-4xl"
          style={{ background: 'linear-gradient(135deg, rgba(59,130,246,0.25) 0%, rgba(30,58,138,0.35) 100%)', border: '1px solid rgba(96,165,250,0.3)' }}>
          🎉
        </div>
        <h3 className="font-['Outfit'] font-bold text-white text-2xl">You&apos;re on the list!</h3>
        <p className="text-white/55 font-['DM_Sans'] text-sm leading-relaxed max-w-xs">
          We&apos;ll ping you the second Ziggo goes live. Get ready — it&apos;s going to be epic.{' '}
          <span role="img" aria-label="rocket">🚀</span>
        </p>
        <div className="flex items-center gap-2 px-4 py-2 rounded-full glass text-brand-glow text-xs font-semibold font-['DM_Sans']">
          <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
          Launch notification enabled
        </div>
      </div>
    );
  }

  // ── Form ─────────────────────────────────────────────────────
  const isLoading = step === 'submitting' || step === 'push-prompt';

  return (
    <form
      ref={formRef}
      onSubmit={handleSubmit}
      noValidate
      className="flex flex-col gap-5 w-full"
      aria-label="Ziggo launch waitlist registration"
    >
      {/* Full Name */}
      <Field
        id="fullName"
        name="fullName"
        label="Full Name"
        type="text"
        placeholder="Ashan Perera"
        value={form.fullName}
        error={errors.fullName}
        onChange={handleChange}
        autoComplete="name"
        disabled={isLoading}
      />

      {/* Email */}
      <Field
        id="email"
        name="email"
        label="Email Address"
        type="email"
        placeholder="ashan@email.com"
        value={form.email}
        error={errors.email}
        onChange={handleChange}
        autoComplete="email"
        disabled={isLoading}
      />

      {/* Phone */}
      <div className="flex flex-col gap-1.5">
        <label
          htmlFor="phone"
          className="text-xs font-semibold text-white/60 font-['DM_Sans'] tracking-wide"
        >
          Phone Number
        </label>
        <div className="relative">
          <span className="absolute left-4 top-1/2 -translate-y-1/2 text-white/40 text-sm font-['DM_Sans'] select-none pointer-events-none">
            🇱🇰 +94
          </span>
          <input
            id="phone"
            name="phone"
            type="tel"
            placeholder="71 234 5678"
            value={form.phone}
            onChange={handleChange}
            autoComplete="tel"
            disabled={isLoading}
            aria-invalid={!!errors.phone}
            aria-describedby={errors.phone ? 'phone-error' : undefined}
            className={`w-full pl-20 pr-4 py-3.5 rounded-xl bg-white/[0.07] border text-white text-sm font-['DM_Sans'] placeholder-white/25 outline-none transition-all duration-200 focus:bg-white/[0.10] focus:border-brand-bright/60 focus:ring-2 focus:ring-brand-bright/20 disabled:opacity-50 ${errors.phone ? 'border-red-400/60' : 'border-white/10'}`}
          />
        </div>
        {errors.phone && (
          <p id="phone-error" className="text-red-400 text-xs font-['DM_Sans'] mt-0.5" role="alert">
            {errors.phone}
          </p>
        )}
      </div>

      {/* 1-Click Instant Push Alert Toggle */}
      <div
        onClick={() => setEnablePush(!enablePush)}
        className={`flex items-start gap-3 p-3.5 rounded-2xl cursor-pointer transition-all duration-300 border ${
          enablePush
            ? 'bg-blue-950/40 border-amber-400/40 shadow-[0_0_20px_rgba(245,158,11,0.15)]'
            : 'bg-white/[0.04] border-white/10 opacity-70'
        }`}
      >
        <div className={`mt-0.5 w-5 h-5 rounded-lg flex items-center justify-center transition-colors ${
          enablePush ? 'bg-amber-400 text-black font-black text-xs' : 'border border-white/30'
        }`}>
          {enablePush ? '✓' : ''}
        </div>
        <div className="flex flex-col gap-0.5 select-none">
          <span className="text-xs font-['Outfit'] font-bold text-white flex items-center gap-1.5">
            <span>🚀 Enable 1-Click Launch Alert</span>
          </span>
          <span className="text-[11px] font-['DM_Sans'] text-white/60 leading-tight">
            Native push notification sent directly to your phone & PC when Ziggo goes live.
          </span>
        </div>
      </div>

      {/* Submit */}
      <button
        type="submit"
        disabled={isLoading}
        className="btn-cta w-full justify-center disabled:opacity-60 disabled:cursor-not-allowed disabled:transform-none"
        aria-busy={isLoading}
      >
        {isLoading ? (
          <>
            <Spinner />
            {step === 'push-prompt' ? 'Setting up notifications…' : 'Saving your spot…'}
          </>
        ) : (
          <>
            <span>Notify Me at Launch</span>
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5} aria-hidden="true">
              <path strokeLinecap="round" strokeLinejoin="round" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
            </svg>
          </>
        )}
      </button>

      {/* Error state */}
      {step === 'error' && (
        <div className="flex items-start gap-3 p-3 rounded-xl bg-red-500/10 border border-red-400/20" role="alert">
          <span className="text-red-400 text-lg flex-shrink-0">⚠️</span>
          <div className="flex flex-col gap-1">
            <p className="text-red-300 text-sm font-['DM_Sans']">{errorMsg}</p>
            <button
              type="button"
              onClick={() => setStep('idle')}
              className="text-xs text-red-400/70 underline underline-offset-2 hover:text-red-300 text-left font-['DM_Sans']"
            >
              Try again
            </button>
          </div>
        </div>
      )}
    </form>
  );
}

// ── Sub-components ───────────────────────────────────────────

function Field({
  id, name, label, type, placeholder, value, error, onChange, autoComplete, disabled,
}: {
  id: string; name: string; label: string; type: string; placeholder: string;
  value: string; error?: string; onChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
  autoComplete?: string; disabled?: boolean;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-xs font-semibold text-white/60 font-['DM_Sans'] tracking-wide">
        {label}
      </label>
      <input
        id={id}
        name={name}
        type={type}
        placeholder={placeholder}
        value={value}
        onChange={onChange}
        autoComplete={autoComplete}
        disabled={disabled}
        aria-invalid={!!error}
        aria-describedby={error ? `${id}-error` : undefined}
        className={`w-full px-4 py-3.5 rounded-xl bg-white/[0.07] border text-white text-sm font-['DM_Sans'] placeholder-white/25 outline-none transition-all duration-200 focus:bg-white/[0.10] focus:border-brand-bright/60 focus:ring-2 focus:ring-brand-bright/20 disabled:opacity-50 ${error ? 'border-red-400/60' : 'border-white/10'}`}
      />
      {error && (
        <p id={`${id}-error`} className="text-red-400 text-xs font-['DM_Sans'] mt-0.5" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

function Spinner() {
  return (
    <svg className="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24" aria-hidden="true">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
    </svg>
  );
}
