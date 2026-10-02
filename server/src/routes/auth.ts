import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { Auth, LoginThrottle, SESSION_COOKIE, readCookie, sessionCookie } from '../auth.js';
import { HttpError } from '../http.js';

const loginBody = z.strictObject({ password: z.string().max(1000) });

const OPEN_ROUTES = new Set(['/api/health', '/api/auth/status', '/api/auth/login', '/api/auth/logout']);

export function sessionToken(request: FastifyRequest): string | undefined {
  const header = request.headers.authorization;
  if (header?.startsWith('Bearer ')) return header.slice('Bearer '.length).trim();
  return readCookie(request.headers.cookie, SESSION_COOKIE);
}

export function registerAuth(app: FastifyInstance, auth: Auth, throttle = new LoginThrottle()) {
  app.addHook('onRequest', async (request) => {
    if (!auth.required) return;
    const route = request.routeOptions.url;
    if (route && OPEN_ROUTES.has(route)) return;
    if (!auth.verify(sessionToken(request))) {
      throw new HttpError(401, 'unauthorized', 'Sign in to Nextlet to continue');
    }
  });

  app.get('/auth/status', async (request) => ({
    required: auth.required,
    authenticated: !auth.required || auth.verify(sessionToken(request)),
  }));

  app.post('/auth/login', async (request, reply) => {
    const { password } = loginBody.parse(request.body);
    if (!auth.required) return { ok: true, token: null, expiresAt: null };

    const client = request.ip;
    const wait = throttle.retryAfter(client);
    if (wait > 0) {
      reply.header('retry-after', String(wait));
      throw new HttpError(429, 'too_many_attempts', `Too many attempts. Try again in ${Math.ceil(wait / 60)} min.`);
    }
    if (!auth.checkPassword(password)) {
      throttle.fail(client);
      throw new HttpError(401, 'invalid_password', 'That password isn’t right');
    }

    throttle.succeed(client);
    const session = auth.issue();
    reply.header('set-cookie', sessionCookie(session.token, { maxAgeSeconds: auth.sessionSeconds, secure: request.protocol === 'https' }));
    return { ok: true, token: session.token, expiresAt: session.expiresAt };
  });

  app.post('/auth/logout', async (request, reply) => {
    reply.header('set-cookie', sessionCookie('', { maxAgeSeconds: 0, secure: request.protocol === 'https' }));
    return reply.status(204).send();
  });
}
