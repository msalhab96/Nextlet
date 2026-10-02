import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createPgDatabase, type Database } from '../src/db.js';
import { migrate } from '../src/migrate.js';
import { seed } from '../src/seed.js';

const url = process.env.TEST_DATABASE_URL;

describe.skipIf(!url)('demo seed', () => {
  const schema = `nextlet_seed_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
  let admin: Database;
  let db: Database;

  beforeAll(async () => {
    admin = createPgDatabase(url!);
    await admin.query(`CREATE SCHEMA ${schema}`);
    db = createPgDatabase(url!, { searchPath: schema });
    await migrate(db, () => undefined);
  });

  afterAll(async () => {
    await db?.close();
    await admin?.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await admin?.close();
  });

  it('loads a week of sample tasks exactly once', async () => {
    const today = '2026-10-01';
    await seed(db, { demo: true, log: () => undefined, today });
    await seed(db, { demo: true, log: () => undefined, today });

    const { rows } = await db.query<{ open: number; done: number; inbox: number; carried: number }>(`
      SELECT count(*) FILTER (WHERE completed_at IS NULL)::int AS open,
             count(*) FILTER (WHERE completed_at IS NOT NULL)::int AS done,
             count(*) FILTER (WHERE completed_at IS NULL AND day IS NULL)::int AS inbox,
             count(*) FILTER (WHERE completed_at IS NULL AND day < '${today}')::int AS carried
      FROM tasks`);
    expect(rows[0]).toEqual({ open: 17, done: 8, inbox: 3, carried: 1 });

    const done = await db.query<{ completed_at: Date }>('SELECT completed_at FROM tasks WHERE completed_at IS NOT NULL');
    for (const row of done.rows) expect(row.completed_at.getTime()).toBeLessThanOrEqual(Date.now());
  });
});
