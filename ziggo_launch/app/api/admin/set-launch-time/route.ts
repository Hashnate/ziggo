import { NextRequest, NextResponse } from 'next/server';
import { getPool, ensureSchema } from '@/lib/db';

let schemaInitialized = false;

async function initSchema() {
  if (!schemaInitialized) {
    await ensureSchema();
    schemaInitialized = true;
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { launchAt, adminToken } = body as {
      launchAt?: string;
      adminToken?: string;
    };

    // Auth check
    const expectedToken = process.env.LAUNCH_ADMIN_TOKEN;
    if (!expectedToken || adminToken !== expectedToken) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    // Validate launchAt
    if (!launchAt || isNaN(Date.parse(launchAt))) {
      return NextResponse.json(
        { error: 'Invalid launchAt datetime string' },
        { status: 400 }
      );
    }

    await initSchema();
    const db = getPool();
    await db.query(
      `INSERT INTO app_config (key, value, updated_at)
       VALUES ('launch_datetime', $1, now())
       ON CONFLICT (key) DO UPDATE
         SET value = EXCLUDED.value,
             updated_at = now();`,
      [launchAt]
    );

    return NextResponse.json({ success: true, launchAt });
  } catch (err) {
    console.error('[set-launch-time] error:', err);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
