import { api } from './api';

/**
 * WhatsApp-OTP sign-in for bookings and hotel registration.
 *
 * Uses the app's own /api/v1/auth/otp endpoints. The access token lives in
 * memory only (never localStorage or a cookie), so closing the tab signs out
 * and nothing is left behind on a shared computer.
 */
let token: string | null = null;
let tokenPhone: string | null = null;

export const currentToken = () => token;
export const signedInPhone = () => tokenPhone;

export async function requestCode(phone: string): Promise<number> {
  const data = await api<{ retryAfterSeconds?: number }>('/api/v1/auth/otp/request', {
    method: 'POST',
    body: JSON.stringify({ phoneNumber: phone, purpose: 'login' }),
  });
  return data?.retryAfterSeconds ?? 45;
}

export async function verifyCode(phone: string, code: string, fullName: string): Promise<string> {
  const data = await api<{ accessToken: string }>('/api/v1/auth/otp/verify', {
    method: 'POST',
    body: JSON.stringify({
      phoneNumber: phone,
      code: code.trim(),
      fullName: fullName.trim(),
      language: 'en',
      deviceId: 'udrive-website',
      deviceName: 'UDrive website',
    }),
  });
  token = data.accessToken;
  tokenPhone = phone;
  return token;
}

export function signOut() {
  token = null;
  tokenPhone = null;
}
