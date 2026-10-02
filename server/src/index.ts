import { buildApp } from './app.js';
import { Auth } from './auth.js';
import { config } from './config.js';
import { createPgDatabase, waitForDatabase } from './db.js';
import { migrate } from './migrate.js';
import { seed } from './seed.js';

const db = createPgDatabase(config.databaseUrl);
const auth = new Auth({ password: config.password, secret: config.sessionSecret });
const app = buildApp({ db, auth, logger: { level: config.logLevel } });
const log = (message: string) => app.log.info(message);

try {
  await waitForDatabase(db, log);
  await migrate(db, log);
  await seed(db, { demo: config.seedDemo, log });
  await app.listen({ port: config.port, host: config.host });
  log(auth.required ? 'password protection is on' : 'password protection is off (set NEXTLET_PASSWORD to turn it on)');
} catch (error) {
  app.log.error(error, 'Nextlet API failed to start');
  await db.close().catch(() => undefined);
  process.exit(1);
}

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, async () => {
    app.log.info(`received ${signal}, shutting down`);
    await app.close();
    await db.close();
    process.exit(0);
  });
}
