import { describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { Auth, LoginThrottle, readCookie } from '../src/auth.js';
import type { Database } from '../src/db.js';

// The auth layer sits in front of every route, so a database that answers every
// query with no rows is enough to exercise it.
const emptyDb: Database = {
  query: async () => ({ rows: [], rowCount: 0 }),
  transaction: async (work) => work({ query: async () => ({ rows: [], rowCount: 0 }) }),
  close: async () => undefined,
};

const PASSWORD = 'correct horse battery staple';

function protectedApp() {
  return buildApp({ db: emptyDb, auth: new Auth({ password: PASSWORD }), logger: false });
}

describe('sessions', () => {
  it('issues tokens that verify until they expire', () => {
    const auth = new Auth({ password: PASSWORD, sessionDays: 1 });
    const now = Date.UTC(2026, 9, 1);
    const { token } = auth.issue(now);
    expect(auth.verify(token, now)).toBe(true);
    expect(auth.verify(token, now + 2 * 86_400_000)).toBe(false);
    expect(auth.verify(`${token}x`, now)).toBe(false);
    expect(auth.verify('v1.1.2.3', now)).toBe(false);
    expect(auth.verify(undefined, now)).toBe(false);
  });

  it('signs everyone out when the password changes', () => {
    const { token } = new Auth({ password: 'old' }).issue();
    expect(new Auth({ password: 'new' }).verify(token)).toBe(false);
    const withSecret = new Auth({ password: 'old', secret: 's3cret' }).issue().token;
    expect(new Auth({ password: 'new', secret: 's3cret' }).verify(withSecret)).toBe(false);
    expect(new Auth({ password: 'old', secret: 's3cret' }).verify(withSecret)).toBe(true);
  });

  it('throttles repeated failures', () => {
    const throttle = new LoginThrottle(3, 60_000);
    const now = 1_000_000;
    for (let i = 0; i < 3; i++) throttle.fail('1.2.3.4', now);
    expect(throttle.retryAfter('1.2.3.4', now)).toBe(60);
    expect(throttle.retryAfter('5.6.7.8', now)).toBe(0);
    expect(throttle.retryAfter('1.2.3.4', now + 61_000)).toBe(0);
  });

  it('reads cookies', () => {
    expect(readCookie('a=1; nextlet_session=abc%2Edef; b=2', 'nextlet_session')).toBe('abc.def');
    expect(readCookie(undefined, 'nextlet_session')).toBeUndefined();
  });
});

describe('password protection', () => {
  it('stays open when no password is set', async () => {
    const app = buildApp({ db: emptyDb, logger: false });
    expect((await app.inject({ url: '/api/projects' })).statusCode).toBe(200);
    expect((await app.inject({ url: '/api/auth/status' })).json()).toEqual({ required: false, authenticated: true });
    await app.close();
  });

  it('locks the API until you sign in', async () => {
    const app = protectedApp();
    const locked = await app.inject({ url: '/api/tasks?status=open' });
    expect(locked.statusCode).toBe(401);
    expect(locked.json().error).toBe('unauthorized');
    expect((await app.inject({ url: '/api/health' })).statusCode).toBe(200);
    expect((await app.inject({ url: '/api/auth/status' })).json()).toEqual({ required: true, authenticated: false });

    const wrong = await app.inject({ method: 'POST', url: '/api/auth/login', payload: { password: 'nope' } });
    expect(wrong.statusCode).toBe(401);
    expect(wrong.json().error).toBe('invalid_password');

    const right = await app.inject({ method: 'POST', url: '/api/auth/login', payload: { password: PASSWORD } });
    expect(right.statusCode).toBe(200);
    const { token } = right.json();
    const cookie = String(right.headers['set-cookie']);
    expect(cookie).toContain('nextlet_session=');
    expect(cookie).toContain('HttpOnly');
    expect(cookie).toContain('SameSite=Strict');

    // The web app sends the cookie, the Mac app a Bearer token.
    const viaCookie = await app.inject({ url: '/api/projects', headers: { cookie: cookie.split(';')[0]! } });
    expect(viaCookie.statusCode).toBe(200);
    const viaBearer = await app.inject({ url: '/api/projects', headers: { authorization: `Bearer ${token}` } });
    expect(viaBearer.statusCode).toBe(200);
    expect((await app.inject({ url: '/api/auth/status', headers: { authorization: `Bearer ${token}` } })).json().authenticated).toBe(true);

    const logout = await app.inject({ method: 'POST', url: '/api/auth/logout' });
    expect(logout.statusCode).toBe(204);
    expect(String(logout.headers['set-cookie'])).toContain('Max-Age=0');
    await app.close();
  });

  it('refuses to keep guessing after ten wrong passwords', async () => {
    const app = protectedApp();
    for (let i = 0; i < 10; i++) {
      await app.inject({ method: 'POST', url: '/api/auth/login', payload: { password: `guess ${i}` } });
    }
    const blocked = await app.inject({ method: 'POST', url: '/api/auth/login', payload: { password: PASSWORD } });
    expect(blocked.statusCode).toBe(429);
    expect(blocked.headers['retry-after']).toBeDefined();
    await app.close();
  });
});
