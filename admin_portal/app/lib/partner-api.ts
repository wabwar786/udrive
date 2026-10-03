/**
 * The partner portal's own session and fetch helper.
 *
 * Deliberately separate from `admin-api.ts`, and the reason is the storage key:
 * a partner signing in must not overwrite an admin's session in the same
 * browser, and an admin's token must never be sent to a partner route. Sharing
 * one key would do both, and the bug would only show up on the one machine where
 * somebody uses both — the office laptop.
 *
 * Nothing in here sends a partner id. Every partner route resolves the partner
 * from the token server-side, so there is no identifier in any URL for somebody
 * to change. That is the security model; this file simply has nothing to leak.
 */

export const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL ??
  'https://udrive-api-production.up.railway.app';

const KEY = 'udrive-partner-session-v1';
const DEVICE_ID = 'udrive-partner-portal';
const DEVICE_NAME = 'UDrive Partner Portal';

export type PartnerSession = {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt?: string;
  user: { id?: string; fullName: string; phoneNumber?: string; roles: string[] };
};

type Envelope<T> = { success: boolean; data: T; message?: string };

export function readPartnerSession(): PartnerSession | null {
  if (typeof window === 'undefined') return null;
  try {
    return JSON.parse(localStorage.getItem(KEY) ?? 'null');
  } catch {
    return null;
  }
}

export function savePartnerSession(value: PartnerSession | null) {
  if (typeof window === 'undefined') return;
  if (value) localStorage.setItem(KEY, JSON.stringify(value));
  else localStorage.removeItem(KEY);
}

function friendly(status: number, body: Record<string, unknown>): string {
  const message = typeof body.message === 'string' ? body.message : '';
  const usable =
    message && !/traceid|request could not be completed/i.test(message)
      ? message
      : '';

  if (status === 401) return 'Your session has expired. Please sign in again.';
  // The API says "This account is not a UDrive partner" here, and that sentence
  // is the whole answer — a generic "no permission" would send somebody to ring
  // support about a working account.
  if (status === 403) return usable || 'This account is not a UDrive partner.';
  if (status === 404) return usable || 'That is not ready yet.';
  if (status === 409) return usable || 'That has already been done.';
  if (status >= 500) return 'The server is busy. Please try again in a moment.';
  return usable || 'That did not work. Please try again.';
}

async function refresh(session: PartnerSession) {
  const response = await fetch(`${API_BASE}/api/v1/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      refreshToken: session.refreshToken,
      deviceId: DEVICE_ID,
      deviceName: DEVICE_NAME,
    }),
  });

  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.data) {
    savePartnerSession(null);
    throw new Error('Session expired.');
  }

  savePartnerSession(body.data);
  return body.data as PartnerSession;
}

function signOutAndReturn() {
  if (typeof window === 'undefined') return;
  savePartnerSession(null);
  if (window.location.pathname !== '/partner/login') {
    window.location.replace('/partner/login');
  }
}

async function run(path: string, init: RequestInit = {}) {
  let session = readPartnerSession();

  const send = (token?: string) =>
    fetch(new URL(path, API_BASE).toString(), {
      ...init,
      cache: 'no-store',
      headers: {
        Accept: 'application/json',
        // FormData has to set its own content type so the browser can add the
        // multipart boundary. Setting it by hand here breaks the signing upload.
        ...(init.body && !(init.body instanceof FormData)
          ? { 'Content-Type': 'application/json' }
          : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init.headers,
      },
    });

  let response = await send(session?.accessToken);

  if (response.status === 401) {
    if (session?.refreshToken) {
      try {
        session = await refresh(session);
        response = await send(session.accessToken);
      } catch {
        signOutAndReturn();
      }
    } else {
      signOutAndReturn();
    }
  }

  return response;
}

export async function partnerFetch<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await run(path, init);
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(friendly(response.status, body as Record<string, unknown>));
  }
  return (body as Envelope<T>).data;
}

export async function requestPartnerOtp(phoneNumber: string) {
  const response = await fetch(`${API_BASE}/api/v1/auth/otp/request`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phoneNumber, purpose: 'login' }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.message ?? 'We could not send the code. Try again.');
  }
  return body.data;
}

export async function verifyPartnerOtp(phoneNumber: string, code: string) {
  const response = await fetch(`${API_BASE}/api/v1/auth/otp/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      phoneNumber,
      code,
      deviceId: DEVICE_ID,
      deviceName: DEVICE_NAME,
    }),
  });

  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.data) {
    throw new Error(body.message ?? 'That code did not work.');
  }

  savePartnerSession(body.data as PartnerSession);
  return body.data as PartnerSession;
}

/**
 * Sends the signature: the photograph, the video, and what the browser is.
 *
 * The server supplies the time, the IP and the phone number itself, so none of
 * those are sent from here — a client-supplied timestamp on a signature is worth
 * nothing.
 */
export async function signContract(
  selfie: Blob,
  video: Blob,
  deviceInfo: string,
) {
  const body = new FormData();
  body.append('selfie', selfie, 'selfie.jpg');
  body.append(
    'video',
    video,
    video.type.includes('mp4') ? 'signature.mp4' : 'signature.webm',
  );
  body.append('deviceInfo', deviceInfo);

  const response = await run('/api/v1/partner/contract/sign', {
    method: 'POST',
    body,
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(friendly(response.status, payload as Record<string, unknown>));
  }
  return (payload as Envelope<{ reference: string }>).data;
}

export function money(value: unknown) {
  return new Intl.NumberFormat('en-PK', {
    style: 'currency',
    currency: 'PKR',
    maximumFractionDigits: 0,
  }).format(Number(value ?? 0));
}

export function monthName(value: unknown) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('en-GB', {
    month: 'long',
    year: 'numeric',
  }).format(new Date(String(value)));
}

export function when(value: unknown) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('en-GB', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(String(value)));
}
