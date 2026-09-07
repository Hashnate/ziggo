import { NextRequest, NextResponse } from 'next/server';
import { getPool, ensureSubscribersTable } from '@/lib/db';

let initialized = false;
async function init() {
  if (!initialized) { await ensureSubscribersTable(); initialized = true; }
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const adminToken = searchParams.get('adminToken') ?? '';

  if (!process.env.LAUNCH_ADMIN_TOKEN || adminToken !== process.env.LAUNCH_ADMIN_TOKEN) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    await init();
    const db = getPool();
    const result = await db.query('SELECT COUNT(*) FROM launch_subscribers');
    const count = parseInt(result.rows[0].count, 10);
    return NextResponse.json({ count });
  } catch {
    return NextResponse.json({ count: 0 });
  }
}
