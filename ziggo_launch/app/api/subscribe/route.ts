import { NextRequest, NextResponse } from 'next/server';
import { getPool, ensureSubscribersTable } from '@/lib/db';

let initialized = false;
async function init() {
  if (!initialized) { await ensureSubscribersTable(); initialized = true; }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { fullName, email, phone, pushSubscription } = body as {
      fullName?: string;
      email?: string;
      phone?: string;
      pushSubscription?: object | null;
    };

    // Basic validation
    if (!fullName?.trim() || !email?.trim() || !phone?.trim()) {
      return NextResponse.json({ error: 'Name, email and phone are required.' }, { status: 400 });
    }
    const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRe.test(email.trim())) {
      return NextResponse.json({ error: 'Invalid email address.' }, { status: 400 });
    }
    // Sri Lanka phone — +94 XXXXXXXXX or 07XXXXXXXX (9–12 digits after stripping)
    const phoneClean = phone.trim().replace(/[\s\-()]/g, '');
    const phoneRe = /^(\+94|0094|0)[0-9]{9}$/;
    if (!phoneRe.test(phoneClean)) {
      return NextResponse.json({ error: 'Enter a valid Sri Lanka phone number.' }, { status: 400 });
    }

    await init();
    const db = getPool();

    const pushEnabled = !!pushSubscription;
    const pushJson = pushSubscription ? JSON.stringify(pushSubscription) : null;

    // Upsert — on duplicate email: update name, phone, and push subscription
    await db.query(
      `INSERT INTO launch_subscribers
         (full_name, email, phone, push_subscription, push_enabled)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (email) DO UPDATE
         SET full_name         = EXCLUDED.full_name,
             phone             = EXCLUDED.phone,
             push_subscription = EXCLUDED.push_subscription,
             push_enabled      = EXCLUDED.push_enabled;`,
      [fullName.trim(), email.trim().toLowerCase(), phoneClean, pushJson, pushEnabled]
    );

    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('[subscribe] error:', err);
    return NextResponse.json({ error: 'Could not save. Please try again.' }, { status: 500 });
  }
}
