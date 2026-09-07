'use client';

import { useState, useEffect, useCallback } from 'react';
import Image from 'next/image';
import LaunchReveal from '@/components/LaunchReveal';

// ── Helpers ──────────────────────────────────────────────────
function toLocalDatetimeValue(isoString: string): string {
  try {
    const d = new Date(isoString);
    // Format as "YYYY-MM-DDTHH:MM" in local time (Sri Lanka = UTC+5:30)
    // We use Sri Lanka timezone offset for display
    const opts: Intl.DateTimeFormatOptions = {
      timeZone: 'Asia/Colombo',
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hour12: false,
    };
    const parts = new Intl.DateTimeFormat('en-CA', opts).formatToParts(d);
    const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
    return `${get('year')}-${get('month')}-${get('day')}T${get('hour')}:${get('minute')}`;
  } catch { return ''; }
}

function toLKAIso(localValue: string): string {
  // localValue is "YYYY-MM-DDTHH:MM" interpreted as Asia/Colombo
  return `${localValue}:00+05:30`;
}

// ── Main Component ────────────────────────────────────────────
export default function LaunchControlPage() {
  const DEFAULT_TOKEN_PLACEHOLDER = 'Enter admin token…';
  const DEFAULT_LAUNCH_ISO = '2026-09-06T16:30:00+05:30';

  const [token, setToken] = useState('');
  const [authed, setAuthed] = useState(false);
  const [authError, setAuthError] = useState('');
  const [authLoading, setAuthLoading] = useState(false);

  // Dashboard state
  const [currentLaunch, setCurrentLaunch] = useState('');
  const [newDatetime, setNewDatetime] = useState('');
  const [updateStatus, setUpdateStatus] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');
  const [subscriberCount, setSubscriberCount] = useState<number | null>(null);

  // Launch state
  const [showConfirm, setShowConfirm] = useState(false);
  const [launching, setLaunching] = useState(false);
  const [launchResult, setLaunchResult] = useState<{ sent: number; failed: number; skipped: number } | null>(null);
  const [launchError, setLaunchError] = useState('');
  const [showReveal, setShowReveal] = useState(false);

  // Fetch current launch time + subscriber count
  const fetchDashboard = useCallback(async () => {
    try {
      const [ltRes, subRes] = await Promise.all([
        fetch('/api/launch-time'),
        fetch(`/api/admin/subscribers?adminToken=${encodeURIComponent(token)}`),
      ]);
      if (ltRes.ok) {
        const { launchAt } = await ltRes.json();
        setCurrentLaunch(launchAt);
        setNewDatetime(toLocalDatetimeValue(launchAt));
      }
      if (subRes.ok) {
        const { count } = await subRes.json();
        setSubscriberCount(count);
      }
    } catch { /* ignore */ }
  }, [token]);

  // Auth check — validate token against the server
  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    if (!token.trim()) { setAuthError('Please enter the admin token.'); return; }
    setAuthLoading(true);
    setAuthError('');
    try {
      const res = await fetch('/api/admin/set-launch-time', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        // Send current value so it's a no-op if correct
        body: JSON.stringify({ adminToken: token, launchAt: DEFAULT_LAUNCH_ISO }),
      });
      if (res.status === 401) {
        setAuthError('Invalid admin token. Please try again.');
      } else {
        setAuthed(true);
      }
    } catch {
      setAuthError('Network error. Please try again.');
    } finally {
      setAuthLoading(false);
    }
  }

  useEffect(() => {
    if (authed) fetchDashboard();
  }, [authed, fetchDashboard]);

  // Update launch datetime
  async function handleUpdateTime() {
    if (!newDatetime) return;
    setUpdateStatus('saving');
    try {
      const iso = toLKAIso(newDatetime);
      const res = await fetch('/api/admin/set-launch-time', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ adminToken: token, launchAt: iso }),
      });
      if (!res.ok) throw new Error();
      const { launchAt } = await res.json();
      setCurrentLaunch(launchAt);
      setUpdateStatus('saved');
      setTimeout(() => setUpdateStatus('idle'), 2500);
    } catch {
      setUpdateStatus('error');
      setTimeout(() => setUpdateStatus('idle'), 3000);
    }
  }

  function handleResetToDefault() {
    setNewDatetime(toLocalDatetimeValue(DEFAULT_LAUNCH_ISO));
  }

  // Fire the launch!
  async function handleLaunch() {
    setShowConfirm(false);
    setLaunching(true);
    setLaunchError('');
    // Trigger confetti immediately for instant feedback
    setShowReveal(true);
    try {
      const res = await fetch('/api/launch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ adminToken: token }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Launch failed');
      setLaunchResult({ sent: data.sent, failed: data.failed, skipped: data.skipped });
    } catch (err: unknown) {
      setLaunchError(err instanceof Error ? err.message : 'Launch failed');
      setShowReveal(false);
    } finally {
      setLaunching(false);
    }
  }

  // ── Login Screen ──────────────────────────────────────────
  if (!authed) {
    return (
      <div className="min-h-screen bg-[#0A0F1F] flex items-center justify-center px-4">
        <div className="w-full max-w-sm">
          <div
            className="glass rounded-3xl p-8 flex flex-col gap-6"
            style={{ boxShadow: '0 24px 64px rgba(0,0,0,0.5)' }}
          >
            <div className="text-center flex flex-col gap-2">
              <Image src="/logo-light.png" alt="Ziggo" width={100} height={36}
                className="w-24 h-auto mx-auto object-contain mb-2" />
              <h1 className="font-['Outfit'] font-black text-white text-xl">Launch Control</h1>
              <p className="text-white/40 text-xs font-['DM_Sans']">Admin access only</p>
            </div>

            <form onSubmit={handleLogin} className="flex flex-col gap-4" aria-label="Admin login">
              <div className="flex flex-col gap-1.5">
                <label htmlFor="admin-token" className="text-xs font-semibold text-white/50 font-['DM_Sans'] tracking-wide">
                  Admin Token
                </label>
                <input
                  id="admin-token"
                  type="password"
                  placeholder={DEFAULT_TOKEN_PLACEHOLDER}
                  value={token}
                  onChange={(e) => { setToken(e.target.value); setAuthError(''); }}
                  className="w-full px-4 py-3.5 rounded-xl bg-white/[0.07] border border-white/10 text-white text-sm font-['DM_Sans'] placeholder-white/20 outline-none focus:border-brand-bright/60 focus:ring-2 focus:ring-brand-bright/20 transition-all"
                  aria-label="Admin token"
                />
                {authError && <p className="text-red-400 text-xs font-['DM_Sans']" role="alert">{authError}</p>}
              </div>
              <button type="submit" disabled={authLoading} className="btn-cta w-full justify-center disabled:opacity-60">
                {authLoading ? 'Verifying…' : 'Enter Launch Control →'}
              </button>
            </form>
          </div>
        </div>
      </div>
    );
  }

  // ── Dashboard ─────────────────────────────────────────────
  const formattedCurrent = currentLaunch
    ? new Date(currentLaunch).toLocaleString('en-LK', {
        timeZone: 'Asia/Colombo',
        weekday: 'long', year: 'numeric', month: 'long',
        day: 'numeric', hour: '2-digit', minute: '2-digit',
      })
    : '—';

  return (
    <>
      {showReveal && <LaunchReveal onClose={() => setShowReveal(false)} result={launchResult} />}

      <div className="min-h-screen bg-[#0A0F1F] px-4 py-10">
        <div className="max-w-2xl mx-auto flex flex-col gap-6">

          {/* Header */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <Image src="/logo-light.png" alt="Ziggo" width={80} height={28} className="w-20 h-auto object-contain" />
              <span className="glass px-3 py-1 rounded-full text-xs font-semibold text-brand-glow font-['DM_Sans']">
                Launch Control
              </span>
            </div>
            <button onClick={() => setAuthed(false)}
              className="text-xs text-white/30 hover:text-white/60 font-['DM_Sans'] transition-colors">
              Sign out
            </button>
          </div>

          {/* Stats */}
          <div className="grid grid-cols-2 gap-4">
            <StatCard label="Registered" value={subscriberCount !== null ? String(subscriberCount) : '—'} icon="👥" />
            <StatCard
              label="Launch Target"
              value={currentLaunch ? new Date(currentLaunch).toLocaleDateString('en-LK', {
                timeZone: 'Asia/Colombo', month: 'short', day: 'numeric',
              }) : '—'}
              icon="📅"
            />
          </div>

          {/* Update Launch Time */}
          <div className="glass rounded-2xl p-6 flex flex-col gap-4">
            <div className="flex flex-col gap-1">
              <h2 className="font-['Outfit'] font-bold text-white text-lg">🗓️ Launch Date & Time</h2>
              <p className="text-white/40 text-xs font-['DM_Sans']">Current: {formattedCurrent} (Sri Lanka Time)</p>
            </div>

            <div className="flex flex-col gap-2">
              <label htmlFor="launch-datetime" className="text-xs font-semibold text-white/50 font-['DM_Sans'] tracking-wide">
                New date & time (Sri Lanka Time, UTC+5:30)
              </label>
              <input
                id="launch-datetime"
                type="datetime-local"
                value={newDatetime}
                onChange={(e) => setNewDatetime(e.target.value)}
                className="w-full px-4 py-3 rounded-xl bg-white/[0.07] border border-white/10 text-white text-sm font-['DM_Sans'] outline-none focus:border-brand-bright/60 focus:ring-2 focus:ring-brand-bright/20 transition-all"
                style={{ colorScheme: 'dark' }}
              />
            </div>

            <div className="flex gap-3">
              <button
                onClick={handleUpdateTime}
                disabled={updateStatus === 'saving'}
                className="flex-1 btn-cta justify-center py-3 text-sm disabled:opacity-60"
              >
                {updateStatus === 'saving' ? 'Saving…' :
                  updateStatus === 'saved' ? '✓ Saved!' :
                  updateStatus === 'error' ? '✗ Error — retry' :
                  'Update Launch Time'}
              </button>
              <button
                onClick={handleResetToDefault}
                className="px-4 py-3 rounded-xl glass text-white/50 hover:text-white text-sm font-['DM_Sans'] transition-colors border border-white/10 hover:border-white/20"
              >
                Reset
              </button>
            </div>

            <p className="text-white/25 text-xs font-['DM_Sans']">
              💡 The public countdown updates automatically within 60 seconds. No redeploy needed.
            </p>
          </div>

          {/* Launch Button */}
          <div className="glass rounded-2xl p-6 flex flex-col gap-4 border border-red-500/10">
            <div className="flex flex-col gap-1">
              <h2 className="font-['Outfit'] font-bold text-white text-lg">🚀 Fire the Launch</h2>
              <p className="text-white/40 text-xs font-['DM_Sans']">
                Sends a Web Push notification to all {subscriberCount ?? '…'} registered subscribers. This cannot be undone.
              </p>
            </div>

            {launchResult && (
              <div className="p-4 rounded-xl bg-green-500/10 border border-green-400/20 flex flex-col gap-1">
                <p className="text-green-300 font-semibold font-['Outfit'] text-sm">🎉 Launch notification sent!</p>
                <p className="text-white/50 text-xs font-['DM_Sans']">
                  Sent: {launchResult.sent} · Failed: {launchResult.failed} · Skipped (already notified): {launchResult.skipped}
                </p>
              </div>
            )}

            {launchError && (
              <div className="p-3 rounded-xl bg-red-500/10 border border-red-400/20">
                <p className="text-red-300 text-sm font-['DM_Sans']">⚠️ {launchError}</p>
              </div>
            )}

            {!showConfirm ? (
              <button
                onClick={() => setShowConfirm(true)}
                disabled={launching || !!launchResult}
                className="w-full py-4 rounded-2xl font-['Outfit'] font-black text-white text-lg tracking-wide transition-all duration-200 hover:scale-[1.02] hover:shadow-2xl active:scale-[0.99] disabled:opacity-40 disabled:cursor-not-allowed disabled:transform-none"
                style={{
                  background: 'linear-gradient(135deg, #EF4444 0%, #DC2626 100%)',
                  boxShadow: '0 16px 40px -10px rgba(239,68,68,0.45)',
                }}
              >
                {launchResult ? '✓ Launch Fired' : '🚀 FIRE THE LAUNCH'}
              </button>
            ) : (
              <div className="flex flex-col gap-3 p-4 rounded-2xl border border-red-400/30 bg-red-500/10 animate-scale-pop">
                <p className="text-white font-['Outfit'] font-bold text-center">
                  ⚠️ Fire the launch?
                </p>
                <p className="text-white/50 text-xs font-['DM_Sans'] text-center">
                  This will send a push notification to ALL registered subscribers and cannot be undone.
                </p>
                <div className="flex gap-3">
                  <button
                    onClick={() => setShowConfirm(false)}
                    className="flex-1 py-3 rounded-xl glass text-white/60 hover:text-white font-['DM_Sans'] text-sm transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleLaunch}
                    disabled={launching}
                    className="flex-1 py-3 rounded-xl font-['Outfit'] font-bold text-white text-sm transition-all hover:opacity-90 disabled:opacity-50"
                    style={{ background: 'linear-gradient(135deg, #EF4444 0%, #DC2626 100%)' }}
                  >
                    {launching ? 'Firing…' : '🚀 Yes, fire it!'}
                  </button>
                </div>
              </div>
            )}
          </div>

          <p className="text-center text-white/20 text-xs font-['DM_Sans']">
            Ziggo Launch Control · Admin only · {new Date().getFullYear()}
          </p>
        </div>
      </div>
    </>
  );
}

function StatCard({ label, value, icon }: { label: string; value: string; icon: string }) {
  return (
    <div className="glass rounded-2xl p-5 flex flex-col gap-1">
      <span className="text-2xl" aria-hidden="true">{icon}</span>
      <span className="font-['Outfit'] font-black text-white text-2xl">{value}</span>
      <span className="text-white/40 text-xs font-['DM_Sans']">{label}</span>
    </div>
  );
}
