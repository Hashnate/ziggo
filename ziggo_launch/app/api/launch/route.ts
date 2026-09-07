import { NextRequest, NextResponse } from 'next/server';
import webpush from 'web-push';
import { getPool, ensureSubscribersTable, setLaunched } from '@/lib/db';


let initialized = false;
async function init() {
  if (!initialized) { await ensureSubscribersTable(); initialized = true; }
}

function configureWebPush() {
  const { VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT } = process.env;
  if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY || !VAPID_SUBJECT) {
    throw new Error('VAPID environment variables are not configured.');
  }
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { adminToken } = body as { adminToken?: string };

    // Auth check
    const expected = process.env.LAUNCH_ADMIN_TOKEN;
    if (!expected || adminToken !== expected) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    // Configure VAPID (skip if not set — Web Push won't work but FCM might)
    let webPushConfigured = false;
    try {
      configureWebPush();
      webPushConfigured = true;
    } catch (err) {
      console.warn('[launch] Web Push not configured:', (err as Error).message);
    }

    await init();
    const db = getPool();

    // ── Flip global launch state (idempotent — won't double-flip) ──
    await setLaunched();
    // Note: we continue regardless of whether this was the first flip
    // so the push fan-out always runs even if the admin retries.

    const appLink = process.env.NEXT_PUBLIC_APP_LINK ?? 'https://ziggo.app';

    // Load all subscribers with push enabled and not yet notified
    const { rows: subscribers } = await db.query(`
      SELECT id, push_subscription FROM launch_subscribers
      WHERE push_enabled = true AND notified = false
    `);

    let sent = 0;
    let failed = 0;

    // Idempotency: count already-notified
    const { rows: skippedRows } = await db.query(
      'SELECT COUNT(*) FROM launch_subscribers WHERE notified = true'
    );
    const skipped = parseInt(skippedRows[0].count, 10);

    // Fan-out Web Push
    const deadIds: string[] = [];

    if (webPushConfigured) {
      const payload = JSON.stringify({
        title: '🚀 Ziggo is Officially LIVE!',
        body: "Sri Lanka's flagship super-app is live. Tap to open Rides, Food, Trucks & Mart now.",
        url: appLink,
        image: '/service-rides-user-official.jpg',
        icon: '/logo-light.png',
      });

      const results = await Promise.allSettled(
        subscribers.map(async (row) => {
          try {
            await webpush.sendNotification(row.push_subscription, payload);
            // Mark notified
            await db.query(
              'UPDATE launch_subscribers SET notified = true WHERE id = $1',
              [row.id]
            );
            sent++;
          } catch (err: unknown) {
            const statusCode = (err as { statusCode?: number }).statusCode;
            // 410 Gone / 404 Not Found = expired subscription, clean up
            if (statusCode === 410 || statusCode === 404) {
              deadIds.push(row.id);
            } else {
              console.error('[launch] push failed for', row.id, err);
            }
            failed++;
          }
        })
      );
      void results; // allSettled never rejects
    } else {
      // VAPID not configured — just mark all as skipped rather than failing
      console.warn('[launch] Skipping Web Push — VAPID not configured.');
    }

    // Clean up dead/expired subscriptions
    if (deadIds.length > 0) {
      await db.query(
        `DELETE FROM launch_subscribers WHERE id = ANY($1::uuid[])`,
        [deadIds]
      );
      console.log(`[launch] Cleaned up ${deadIds.length} expired subscriptions.`);
    }

    // Optional: FCM fan-out for existing app users
    const fcmServerKey = process.env.FCM_SERVER_KEY;
    if (fcmServerKey) {
      try {
        const fcmRes = await fetch('https://fcm.googleapis.com/fcm/send', {
          method: 'POST',
          headers: {
            Authorization: `key=${fcmServerKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            to: '/topics/all',
            notification: {
              title: 'Ziggo is now LIVE! 🚀',
              body: "The super-app you've been waiting for is here. Tap to open Ziggo.",
              click_action: appLink,
              icon: '/logo-light.png',
            },
            data: { url: appLink },
          }),
        });
        const fcmData = await fcmRes.json();
        console.log('[launch] FCM result:', fcmData);
      } catch (err) {
        console.error('[launch] FCM error:', err);
      }
    }

    return NextResponse.json({
      success: true,
      sent,
      failed,
      skipped,
      deadCleaned: deadIds.length,
    });
  } catch (err) {
    console.error('[launch] fatal error:', err);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
