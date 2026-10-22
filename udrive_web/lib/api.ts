import { API_URL } from './config';

/** The API's JSON envelope: { success, data, message }. */
type Envelope<T> = { success?: boolean; data?: T; message?: string; error?: string };

export class ApiError extends Error {
  constructor(message: string, public status: number, public code?: string) {
    super(message);
  }
}

/** Calls the UDrive API from the browser. Throws ApiError with the server's own message. */
export async function api<T>(path: string, init: RequestInit & { token?: string } = {}): Promise<T> {
  if (!API_URL) throw new ApiError('Website is not connected to the UDrive API yet.', 0);
  const headers = new Headers(init.headers);
  headers.set('Accept', 'application/json');
  if (init.body && !(init.body instanceof FormData)) headers.set('Content-Type', 'application/json');
  if (init.token) headers.set('Authorization', `Bearer ${init.token}`);

  let response: Response;
  try {
    response = await fetch(`${API_URL}${path}`, { ...init, headers, credentials: 'omit', cache: 'no-store' });
  } catch {
    throw new ApiError('Internet connection problem. Please try again.', 0);
  }

  const body = (await response.json().catch(() => ({}))) as Envelope<T>;
  if (!response.ok) {
    const message =
      response.status === 429
        ? 'Too many tries. Please wait a minute and try again.'
        : body.message || 'Something went wrong. Please try again.';
    throw new ApiError(message, response.status, body.error);
  }
  return body.data as T;
}

/**
 * Build-time fetch for the static HTML (what Google reads).
 * Never fails the build: no API, a timeout or an error gives the fallback,
 * and the page then loads live data in the browser as usual.
 */
export async function atBuild<T>(path: string, fallback: T): Promise<T> {
  if (!API_URL) return fallback;
  try {
    const response = await fetch(`${API_URL}${path}`, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(10000),
      // force-cache: this runs only while building. 'no-store' would make
      // Next treat the page as dynamic, which a static export cannot be.
      cache: 'force-cache',
    });
    if (!response.ok) return fallback;
    const body = (await response.json()) as Envelope<T>;
    return (body.data ?? fallback) as T;
  } catch {
    return fallback;
  }
}

/** Turns an API image path into a full URL; anything that is not ours or https is dropped. */
export function img(url: string | null | undefined): string | null {
  if (!url) return null;
  if (url.startsWith('/api/')) return API_URL ? `${API_URL}${url}` : null;
  if (url.startsWith('https://')) return url;
  return null;
}
