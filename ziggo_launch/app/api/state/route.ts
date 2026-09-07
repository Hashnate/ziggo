import { NextResponse } from 'next/server';
import { getLaunchState } from '@/lib/db';

// Cache for a maximum of 3 seconds so we don't hammer the DB
export const revalidate = 3;

export async function GET() {
  try {
    const { launched, launchedAt } = await getLaunchState();
    return NextResponse.json(
      { launched, launchedAt },
      {
        status: 200,
        headers: {
          // Allow browser to cache for 3s, then re-validate
          'Cache-Control': 'public, max-age=3, stale-while-revalidate=3',
        },
      }
    );
  } catch (err) {
    console.error('[api/state] error:', err);
    // On DB failure, default to not-launched so the page still renders
    return NextResponse.json({ launched: false, launchedAt: null }, { status: 200 });
  }
}
