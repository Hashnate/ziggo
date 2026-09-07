import { NextRequest, NextResponse } from 'next/server';
import webpush from 'web-push';
import { getPool } from '@/lib/db';

function configureWebPush() {
  const { VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT } = process.env;
  if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY || !VAPID_SUBJECT) {
    throw new Error('VAPID environment variables are not configured.');
  }
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}));
    const testPhone = body.phone || '0768049250';
    const cleanPhone = testPhone.trim().replace(/[\s\-()]/g, '');

    let webPushConfigured = false;
    try {
      configureWebPush();
      webPushConfigured = true;
    } catch (err) {
      console.warn('[test-push] Web Push not configured:', (err as Error).message);
    }

    const appLink = process.env.NEXT_PUBLIC_APP_LINK ?? 'https://ziggo.app';
    const payload = JSON.stringify({
      title: '🚀 Ziggo is Officially LIVE!',
      body: "Sri Lanka's flagship super-app is live. Tap to open Rides, Food, Trucks & Mart now.",
      url: appLink,
      image: '/service-rides-user-official.jpg',
      icon: '/logo-light.png',
      badge: '/logo-light.png',
    });

    let webPushSent = 0;
    let fcmSent = false;

    // 1. Try sending via Web Push to subscribers matching test phone or all active subscriptions
    if (webPushConfigured) {
      try {
        const db = getPool();
        const { rows: subscribers } = await db.query(`
          SELECT id, push_subscription FROM launch_subscribers
          WHERE push_enabled = true AND (phone LIKE $1 OR phone = $2)
        `, [`%${cleanPhone.slice(-9)}%`, cleanPhone]);

        if (subscribers.length > 0) {
          for (const row of subscribers) {
            try {
              if (row.push_subscription) {
                await webpush.sendNotification(row.push_subscription, payload);
                webPushSent++;
              }
            } catch (e) {
              console.warn('[test-push] subscription push failed:', e);
            }
          }
        }
      } catch (dbErr) {
        console.warn('[test-push] DB query skipped:', dbErr);
      }
    }

    // 2. Call backend FCM test-push for the exact target mobile number ONLY
    try {
      const backendRes = await fetch('http://127.0.0.1:8030/api/v1/public/test-push', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          phone: cleanPhone,
          title: '🚀 Ziggo is Officially LIVE!',
          body: "Sri Lanka's flagship super-app is live. Tap to open Rides, Food, Trucks & Mart now.",
        }),
      });
      if (backendRes.ok) {
        const backendData = await backendRes.json();
        fcmSent = backendData.sent_count > 0;
      }
    } catch (err) {
      console.warn('[test-push] Backend FCM call failed:', err);
    }

    return NextResponse.json({
      success: true,
      phone: testPhone,
      webPushSent,
      fcmSent,
      message: `Test notification sent successfully for ${testPhone}!`,
      notification: {
        title: '🚀 Ziggo is Officially LIVE!',
        body: "Sri Lanka's flagship super-app is live. Tap to open Rides, Food, Trucks & Mart now.",
      },
    });
  } catch (err) {
    console.error('[test-push] fatal error:', err);
    return NextResponse.json({ error: 'Internal test push error' }, { status: 500 });
  }
}
