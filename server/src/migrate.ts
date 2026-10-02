import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Database } from './db.js';

const MIGRATIONS_DIR = fileURLToPath(new URL('../migrations/', import.meta.url));
const MIGRATION_LOCK = 727_001;

/** Applies every migrations/*.sql file that has not run yet, in filename order. */
export async function migrate(db: Database, log: (message: string) => void): Promise<void> {
  const files = (await readdir(MIGRATIONS_DIR)).filter((file) => file.endsWith('.sql')).sort();

  await db.transaction(async (tx) => {
    // Two API containers starting at once must not run the same migration twice.
    await tx.query('SELECT pg_advisory_xact_lock($1)', [MIGRATION_LOCK]);
    await tx.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version text PRIMARY KEY,
        applied_at timestamptz NOT NULL DEFAULT now()
      )
    `);
    const { rows } = await tx.query<{ version: string }>('SELECT version FROM schema_migrations');
    const applied = new Set(rows.map((row) => row.version));

    for (const file of files) {
      if (applied.has(file)) continue;
      const sql = await readFile(path.join(MIGRATIONS_DIR, file), 'utf8');
      await tx.query(sql);
      await tx.query('INSERT INTO schema_migrations (version) VALUES ($1)', [file]);
      log(`applied migration ${file}`);
    }
  });
}
