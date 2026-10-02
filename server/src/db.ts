import pg from 'pg';

// DATE columns stay plain 'YYYY-MM-DD' strings. A task belongs to a day, not an
// instant, so converting them to JavaScript Dates would only invite timezone bugs.
pg.types.setTypeParser(pg.types.builtins.DATE, (value) => value);

export interface QueryResult<Row> {
  rows: Row[];
  rowCount: number | null;
}

export interface Queryable {
  query<Row extends object = Record<string, unknown>>(text: string, params?: unknown[]): Promise<QueryResult<Row>>;
}

export interface Database extends Queryable {
  transaction<T>(work: (tx: Queryable) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

export interface DatabaseOptions {
  /** Schema to use instead of public. The API tests use this to stay isolated. */
  searchPath?: string;
}

export function createPgDatabase(connectionString: string, options: DatabaseOptions = {}): Database {
  const pool = new pg.Pool({
    connectionString,
    max: 10,
    ...(options.searchPath ? { options: `-c search_path=${options.searchPath}` } : {}),
  });

  return {
    async query<Row extends object>(text: string, params: unknown[] = []) {
      const result = await pool.query(text, params);
      return { rows: result.rows as Row[], rowCount: result.rowCount };
    },

    async transaction<T>(work: (tx: Queryable) => Promise<T>) {
      const client = await pool.connect();
      const tx: Queryable = {
        async query<Row extends object>(text: string, params: unknown[] = []) {
          const result = await client.query(text, params);
          return { rows: result.rows as Row[], rowCount: result.rowCount };
        },
      };
      try {
        await client.query('BEGIN');
        const result = await work(tx);
        await client.query('COMMIT');
        return result;
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    close: () => pool.end(),
  };
}

export async function waitForDatabase(db: Database, log: (message: string) => void, attempts = 30): Promise<void> {
  for (let attempt = 1; ; attempt++) {
    try {
      await db.query('SELECT 1');
      return;
    } catch (error) {
      if (attempt >= attempts) throw error;
      log(`database not ready yet (attempt ${attempt}/${attempts}), retrying in 1s`);
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }
}
