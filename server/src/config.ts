export const config = {
  port: Number(process.env.PORT ?? 3000),
  host: process.env.HOST ?? '0.0.0.0',
  databaseUrl: process.env.DATABASE_URL ?? 'postgres://nextlet:nextlet@localhost:5432/nextlet',
  seedDemo: process.env.SEED_DEMO === 'true',
  logLevel: process.env.LOG_LEVEL ?? 'info',
  /** Leave empty for no sign-in (fine when Nextlet only listens on 127.0.0.1). */
  password: process.env.NEXTLET_PASSWORD ?? '',
  /** Optional extra secret mixed into session signatures. */
  sessionSecret: process.env.SESSION_SECRET ?? '',
};
