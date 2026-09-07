import { Pool } from 'pg';

// Shared Postgres pool — used by all API routes.
// Lazy-initialized so it doesn't blow up during static builds.
let pool: Pool | null = null;

export function getPool(): Pool {
  if (!pool) {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL environment variable is not set');
    }
    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 10,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000,
    });
    pool.on('error', (err) => {
      console.error('[pg pool] Unexpected error on idle client:', err);
    });
  }
  return pool;
}


/**
 * Run the app_config migration on first startup.
 * Called from the first API route that touches the DB.
 */
export async function ensureSchema(): Promise<void> {
  const db = getPool();
  await db.query(`
    CREATE TABLE IF NOT EXISTS app_config (
      key        TEXT PRIMARY KEY,
      value      TEXT NOT NULL,
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);
  // Seed default launch datetime only if not already set
  const defaultLaunchAt =
    process.env.NEXT_PUBLIC_LAUNCH_DATETIME ?? '2026-09-06T16:30:00+05:30';
  await db.query(
    `INSERT INTO app_config (key, value)
     VALUES ('launch_datetime', $1)
     ON CONFLICT (key) DO NOTHING;`,
    [defaultLaunchAt]
  );
}

/**
 * Create the launch_subscribers table if it doesn't exist.
 */
export async function ensureSubscribersTable(): Promise<void> {
  const db = getPool();
  await db.query(`
    CREATE TABLE IF NOT EXISTS launch_subscribers (
      id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      full_name         TEXT NOT NULL,
      email             TEXT UNIQUE NOT NULL,
      phone             TEXT NOT NULL,
      push_subscription JSONB,
      push_enabled      BOOLEAN NOT NULL DEFAULT false,
      notified          BOOLEAN NOT NULL DEFAULT false,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
}

/**
 * Create and seed the global launch_state table.
 * Single row: launched=false until the admin fires the event.
 */
export async function ensureLaunchState(): Promise<void> {
  const db = getPool();
  await db.query(`
    CREATE TABLE IF NOT EXISTS launch_state (
      id          INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
      launched    BOOLEAN NOT NULL DEFAULT false,
      launched_at TIMESTAMPTZ
    );
  `);
  // Seed a single row if not present
  await db.query(`
    INSERT INTO launch_state (id, launched)
    VALUES (1, false)
    ON CONFLICT (id) DO NOTHING;
  `);
}

/**
 * Get current global launch state.
 */
export async function getLaunchState(): Promise<{ launched: boolean; launchedAt: string | null }> {
  const db = getPool();
  await ensureLaunchState();
  const { rows } = await db.query<{ launched: boolean; launched_at: string | null }>(
    'SELECT launched, launched_at FROM launch_state WHERE id = 1'
  );
  if (rows.length === 0) return { launched: false, launchedAt: null };
  return { launched: rows[0].launched, launchedAt: rows[0].launched_at ?? null };
}

/**
 * Atomically flip the launched flag to true (idempotent).
 * Returns true if this call actually flipped it (first time).
 */
export async function setLaunched(): Promise<boolean> {
  const db = getPool();
  await ensureLaunchState();
  const { rowCount } = await db.query(`
    UPDATE launch_state
    SET launched = true, launched_at = now()
    WHERE id = 1 AND launched = false
  `);
  return (rowCount ?? 0) > 0;
}

