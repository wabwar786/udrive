export const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL ??
  'https://udrive-api-production.up.railway.app';

export type AdminUser = {
  id?: string;
  fullName: string;
  phoneNumber?: string;
  roles: string[];
};

export type AdminSession = {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt?: string;
  user: AdminUser;
};

type Envelope<T> = {
  success: boolean;
  data: T;
  message?: string;
};

const KEY = 'udrive-admin-session-v10';

export function readSession(): AdminSession | null {
  if (typeof window === 'undefined') return null;

  try {
    return JSON.parse(localStorage.getItem(KEY) ?? 'null');
  } catch {
    return null;
  }
}

export function saveSession(value: AdminSession | null) {
  if (typeof window === 'undefined') return;

  if (value) {
    localStorage.setItem(KEY, JSON.stringify(value));
  } else {
    localStorage.removeItem(KEY);
  }
}

async function refresh(session: AdminSession) {
  const response = await fetch(`${API_BASE}/api/v1/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      refreshToken: session.refreshToken,
      deviceId: 'udrive-admin-v10',
      deviceName: 'uDrive Operations Portal',
    }),
  });

  const body = await response.json().catch(() => ({}));

  if (!response.ok || !body.data) {
    saveSession(null);
    throw new Error(body.message ?? body.detail ?? 'Session expired.');
  }

  saveSession(body.data);
  return body.data as AdminSession;
}

async function runAuthorized(
  path: string,
  init: RequestInit = {},
  accept = 'application/json',
) {
  let session = readSession();

  const run = (token?: string) =>
    fetch(`${API_BASE}${path}`, {
      ...init,
      headers: {
        Accept: accept,
        ...(init.body && !(init.body instanceof FormData)
          ? { 'Content-Type': 'application/json' }
          : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init.headers,
      },
    });

  let response = await run(session?.accessToken);

  if (response.status === 401 && session?.refreshToken) {
    session = await refresh(session);
    response = await run(session.accessToken);
  }

  return response;
}

export async function apiFetch<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await runAuthorized(path, init);
  const body = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new Error(
      body.message ??
        body.detail ??
        `Request failed (${response.status}).`,
    );
  }

  return (body as Envelope<T>).data;
}

export async function apiProtectedFile(
  path: string,
): Promise<{ objectUrl: string; contentType: string }> {
  const response = await runAuthorized(
    path,
    {},
    'image/avif,image/webp,image/png,image/jpeg,application/pdf,*/*',
  );

  if (!response.ok) {
    const body = await response.clone().json().catch(() => ({}));
    throw new Error(
      body.message ??
        body.detail ??
        `Document could not be loaded (${response.status}).`,
    );
  }

  const blob = await response.blob();

  return {
    objectUrl: URL.createObjectURL(blob),
    contentType:
      blob.type ||
      response.headers.get('content-type') ||
      'application/octet-stream',
  };
}

export async function login(phoneNumber: string, code: string) {
  const response = await fetch(`${API_BASE}/api/v1/auth/otp/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      phoneNumber,
      code,
      fullName: 'uDrive Admin',
      language: 'en',
      deviceId: 'udrive-admin-v10',
      deviceName: 'uDrive Operations Portal',
    }),
  });

  const body = await response.json();

  if (!response.ok) {
    throw new Error(body.message ?? 'Login failed.');
  }

  const session = body.data as AdminSession;

  if (
    !session.user.roles.some((role) =>
      [
        'Admin',
        'Operations',
        'VerificationOfficer',
        'SupportAgent',
        'FinanceOfficer',
        'SafetyOfficer',
        'TourismManager',
      ].includes(role),
    )
  ) {
    throw new Error('This account has no Admin permission.');
  }

  saveSession(session);
  return session;
}

export async function requestOtp(phoneNumber: string) {
  const response = await fetch(`${API_BASE}/api/v1/auth/otp/request`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phoneNumber, purpose: 'login' }),
  });

  const body = await response.json();

  if (!response.ok) {
    throw new Error(body.message ?? 'OTP request failed.');
  }

  return body.data;
}

export function money(value: unknown) {
  return new Intl.NumberFormat('en-PK', {
    style: 'currency',
    currency: 'PKR',
    maximumFractionDigits: 0,
  }).format(Number(value ?? 0));
}

export function when(value: unknown) {
  if (!value) return '—';

  return new Intl.DateTimeFormat('en-GB', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(String(value)));
}
