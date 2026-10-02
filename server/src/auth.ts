import { createHash, createHmac, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

// Optional single-password protection. When NEXTLET_PASSWORD is empty, Nextlet is
// open (fine on 127.0.0.1). When it is set, every API call needs a session token,
// sent either as the nextlet_session cookie (web app) or a Bearer header (Mac app).
//
// Tokens are stateless and signed: "v1.<expires>.<nonce>.<signature>". The signing
// key is derived from the password (and SESSION_SECRET, when given), so changing
// the password signs everyone out.

export const SESSION_COOKIE = 'nextlet_session';
const TOKEN_VERSION = 'v1';

const sha256 = (value: string) => createHash('sha256').update(value, 'utf8').digest();

export interface AuthOptions {
  password: string;
  secret?: string;
  sessionDays?: number;
}

export class Auth {
  readonly required: boolean;
  readonly sessionSeconds: number;
  private readonly key: Buffer;
  private readonly passwordDigest: Buffer;

  constructor({ password, secret = '', sessionDays = 30 }: AuthOptions) {
    this.required = password.length > 0;
    this.sessionSeconds = Math.round(sessionDays * 86_400);
    this.passwordDigest = sha256(password);
    this.key = secret ? sha256(`${secret}\u0000${password}`) : scryptSync(password, 'nextlet-session-key-v1', 32);
  }

  checkPassword(candidate: string): boolean {
    return timingSafeEqual(sha256(candidate), this.passwordDigest);
  }

  issue(now = Date.now()): { token: string; expiresAt: string } {
    const expires = Math.floor(now / 1000) + this.sessionSeconds;
    const payload = `${TOKEN_VERSION}.${expires}.${randomBytes(12).toString('base64url')}`;
    return { token: `${payload}.${this.sign(payload)}`, expiresAt: new Date(expires * 1000).toISOString() };
  }

  verify(token: string | undefined | null, now = Date.now()): boolean {
    if (!token) return false;
    const parts = token.split('.');
    if (parts.length !== 4 || parts[0] !== TOKEN_VERSION) return false;
    const expires = Number(parts[1]);
    if (!Number.isInteger(expires) || expires * 1000 <= now) return false;
    const expected = Buffer.from(this.sign(parts.slice(0, 3).join('.')));
    const actual = Buffer.from(parts[3]!);
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  }

  private sign(payload: string): string {
    return createHmac('sha256', this.key).update(payload).digest('base64url');
  }
}

/** Counts failed sign-ins per client, so the password can't be guessed quickly. */
export class LoginThrottle {
  private readonly failures = new Map<string, { count: number; resetAt: number }>();

  constructor(
    private readonly limit = 10,
    private readonly windowMs = 5 * 60_000,
  ) {}

  /** Seconds to wait before trying again, or 0 when the client may try now. */
  retryAfter(client: string, now = Date.now()): number {
    const entry = this.failures.get(client);
    if (!entry || entry.resetAt <= now) return 0;
    return entry.count >= this.limit ? Math.ceil((entry.resetAt - now) / 1000) : 0;
  }

  fail(client: string, now = Date.now()) {
    const entry = this.failures.get(client);
    if (!entry || entry.resetAt <= now) this.failures.set(client, { count: 1, resetAt: now + this.windowMs });
    else entry.count += 1;
    if (this.failures.size > 10_000) {
      for (const [key, value] of this.failures) if (value.resetAt <= now) this.failures.delete(key);
    }
  }

  succeed(client: string) {
    this.failures.delete(client);
  }
}

export function readCookie(header: string | undefined, name: string): string | undefined {
  if (!header) return undefined;
  for (const part of header.split(';')) {
    const index = part.indexOf('=');
    if (index === -1) continue;
    if (part.slice(0, index).trim() === name) {
      try {
        return decodeURIComponent(part.slice(index + 1).trim());
      } catch {
        return undefined;
      }
    }
  }
  return undefined;
}

export function sessionCookie(value: string, options: { maxAgeSeconds: number; secure: boolean }): string {
  const attributes = [`${SESSION_COOKIE}=${encodeURIComponent(value)}`, 'Path=/', 'HttpOnly', 'SameSite=Strict', `Max-Age=${options.maxAgeSeconds}`];
  if (options.secure) attributes.push('Secure');
  return attributes.join('; ');
}
