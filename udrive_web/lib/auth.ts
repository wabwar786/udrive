import { api, ApiError } from './api';

/**
 * WhatsApp-OTP sign-in, the same as the UDrive app.
 *
 * - Tokens live in sessionStorage: they survive a page change or reload in
 *   this tab, and are gone when the tab or browser closes. Never a cookie,
 *   never localStorage.
 * - The 15-minute access token is renewed with the refresh token when it is
 *   about to run out (POST /api/v1/auth/refresh rotates both).
 * - 30 minutes without using the site signs out, and the refresh token is
 *   revoked on the server (POST /api/v1/auth/logout).
 */
type Session = {
  access: string;
  accessExp: number;
  refresh: string;
  phone: string;
  name: string;
  last: number;
};

const KEY = 'ud.session';
const IDLE_MS = 30 * 60 * 1000;
const DEVICE = { deviceId: 'udrive-website', deviceName: 'UDrive website' };
type Tokens = { accessToken: string; accessTokenExpiresAt: string; refreshToken: string; user?: { fullName?: string; phoneNumber?: string } };

let memory: Session | null = null;
let refreshing: Promise<Session | null> | null = null;

function read(): Session | null {
  if (memory) return memory;
  try {
    const raw = typeof window !== 'undefined' ? window.sessionStorage.getItem(KEY) : null;
    memory = raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    memory = null;
  }
  return memory;
}

/** `notify`: tell listeners (header, pages) — only when who is signed in changes. */
function write(s: Session | null, notify = true) {
  memory = s;
  try {
    if (s) window.sessionStorage.setItem(KEY, JSON.stringify(s));
    else window.sessionStorage.removeItem(KEY);
  } catch {
    /* private mode: memory only */
  }
  if (notify && typeof window !== 'undefined') window.dispatchEvent(new Event('ud-auth'));
}

const fromTokens = (t: Tokens, phone: string, name: string): Session => ({
  access: t.accessToken,
  accessExp: Date.parse(t.accessTokenExpiresAt) || Date.now() + 14 * 60 * 1000,
  refresh: t.refreshToken,
  phone: t.user?.phoneNumber || phone,
  name: (t.user?.fullName && !t.user.fullName.startsWith('uDrive User') ? t.user.fullName : name) || '',
  last: Date.now(),
});

/** Who is signed in, or null. Also ends an idle session. */
export function session(): { phone: string; name: string } | null {
  const s = read();
  if (!s) return null;
  if (Date.now() - s.last > IDLE_MS) {
    void signOut();
    return null;
  }
  return { phone: s.phone, name: s.name };
}

export const signedInPhone = () => session()?.phone ?? null;
export const currentToken = () => (session() ? read()?.access ?? null : null);

export async function requestCode(phone: string): Promise<number> {
  const data = await api<{ retryAfterSeconds?: number }>('/api/v1/auth/otp/request', {
    method: 'POST',
    body: JSON.stringify({ phoneNumber: phone, purpose: 'login' }),
  });
  return data?.retryAfterSeconds ?? 45;
}

export async function verifyCode(phone: string, code: string, fullName: string): Promise<string> {
  const data = await api<Tokens>('/api/v1/auth/otp/verify', {
    method: 'POST',
    body: JSON.stringify({ phoneNumber: phone, code: code.trim(), fullName: fullName.trim() || null, language: 'en', ...DEVICE }),
  });
  write(fromTokens(data, phone, fullName.trim()));
  return data.accessToken;
}

async function renew(): Promise<Session | null> {
  const s = read();
  if (!s) return null;
  refreshing ??= api<Tokens>('/api/v1/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({ refreshToken: s.refresh, ...DEVICE }),
  })
    .then((t) => {
      const next = { ...fromTokens(t, s.phone, s.name), last: s.last };
      write(next, false);
      return next;
    })
    .catch(() => {
      write(null);
      return null;
    })
    .finally(() => {
      refreshing = null;
    });
  return refreshing;
}

/** Calls the API as the signed-in user; renews the token when needed. */
export async function authApi<T>(path: string, init: RequestInit = {}): Promise<T> {
  if (!session()) throw new ApiError('Please log in again.', 401, 'signed_out');
  let s = read()!;
  s.last = Date.now();
  write(s, false);
  if (s.accessExp - Date.now() < 60_000) {
    const next = await renew();
    if (!next) throw new ApiError('Session ended. Please log in again.', 401, 'signed_out');
    s = next;
  }
  try {
    return await api<T>(path, { ...init, token: s.access });
  } catch (e) {
    if (e instanceof ApiError && e.status === 401) {
      const again = await renew();
      if (!again) throw new ApiError('Session ended. Please log in again.', 401, 'signed_out');
      return api<T>(path, { ...init, token: again.access });
    }
    throw e;
  }
}

export async function signOut() {
  const s = read();
  write(null);
  if (s) {
    await api('/api/v1/auth/logout', { method: 'POST', body: JSON.stringify({ refreshToken: s.refresh }), token: s.access }).catch(() => undefined);
  }
}

/** Re-renders a component when someone signs in or out (any tab section). */
export function onAuthChange(fn: () => void): () => void {
  window.addEventListener('ud-auth', fn);
  return () => window.removeEventListener('ud-auth', fn);
}
