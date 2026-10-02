import Fastify, { type FastifyServerOptions } from 'fastify';
import { Auth } from './auth.js';
import type { Database } from './db.js';
import { errorHandler } from './http.js';
import { registerAuth } from './routes/auth.js';
import { registerProjectRoutes } from './routes/projects.js';
import { registerTaskRoutes } from './routes/tasks.js';

export interface AppOptions {
  db: Database;
  auth?: Auth;
  logger?: FastifyServerOptions['logger'];
}

export function buildApp({ db, auth = new Auth({ password: '' }), logger = true }: AppOptions) {
  const app = Fastify({ logger, trustProxy: true, bodyLimit: 1024 * 1024 });

  app.setErrorHandler(errorHandler);
  app.setNotFoundHandler((request, reply) =>
    reply.status(404).send({ error: 'not_found', message: `No route for ${request.method} ${request.url}` }),
  );

  app.register(
    async (api) => {
      registerAuth(api, auth);
      api.get('/health', async () => {
        await db.query('SELECT 1');
        return { ok: true };
      });
      registerProjectRoutes(api, db);
      registerTaskRoutes(api, db);
    },
    { prefix: '/api' },
  );

  return app;
}
