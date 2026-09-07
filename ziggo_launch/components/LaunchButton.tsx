'use client';

import { useState } from 'react';
import LaunchReveal from './LaunchReveal';

export default function LaunchButton() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{ sent: number; failed: number; skipped: number } | null>(null);
  const [showReveal, setShowReveal] = useState(false);

  // Directly trigger push notification to all registered people and launch celebration
  async function handleLaunchClick() {
    setLoading(true);
    setShowReveal(true);

    try {
      // Optional: Request browser notification permission if not yet granted
      if (typeof window !== 'undefined' && 'Notification' in window && Notification.permission === 'default') {
        try {
          await Notification.requestPermission();
        } catch { /* ignore */ }
      }

      const res = await fetch('/api/launch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          adminToken: 'ziggo_admin_dev_token_change_in_production'
        }),
      });

      const data = await res.json();
      if (res.ok) {
        setResult({ sent: data.sent ?? 0, failed: data.failed ?? 0, skipped: data.skipped ?? 0 });
      }
    } catch (err) {
      console.error('Launch trigger error:', err);
    } finally {
      setLoading(false);
    }
  }

  function handleClose() {
    setShowReveal(false);
  }

  return (
    <>
      {/* Full screen celebration + notification confirmation */}
      {showReveal && (
        <LaunchReveal onClose={handleClose} result={result} />
      )}

      {/* Main button */}
      <button
        onClick={handleLaunchClick}
        disabled={loading}
        className="btn-cta disabled:opacity-60 disabled:cursor-not-allowed disabled:transform-none"
        aria-label="Send launch notification to all registered users"
      >
        {loading ? (
          <>
            <svg className="w-5 h-5 animate-spin" fill="none" viewBox="0 0 24 24" aria-hidden="true">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
            </svg>
            <span>Launching &amp; Notifying…</span>
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
    </>
  );
}
