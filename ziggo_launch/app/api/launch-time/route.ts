import { NextResponse } from 'next/server';
import { getPool, ensureSchema } from '@/lib/db';

let schemaInitialized = false;

async function initSchema() {
  if (!schemaInitialized) {
    await ensureSchema();
    schemaInitialized = true;
  }
}

export async function GET() {
  // Fallback if DATABASE_URL is not configured
  const fallback =
    process.env.NEXT_PUBLIC_LAUNCH_DATETIME ?? '2026-09-06T16:30:00+05:30';

  try {
    await initSchema();
    const db = getPool();
    const result = await db.query(
      `SELECT value FROM app_config WHERE key = 'launch_datetime' LIMIT 1`
    );
    const launchAt =
      result.rows.length > 0 ? result.rows[0].value : fallback;
    return NextResponse.json({ launchAt });
  } catch {
    // DB unavailable — fall back to env var
    return NextResponse.json({ launchAt: fallback });
  }
}
