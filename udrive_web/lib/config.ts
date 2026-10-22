/** Public settings, read at build time from Railway Variables (see .env.example). */
const trim = (v: string | undefined) => (v ?? '').trim().replace(/\/+$/, '');

export const API_URL = trim(process.env.NEXT_PUBLIC_API_URL);
export const SITE_URL = trim(process.env.NEXT_PUBLIC_SITE_URL) || 'https://udrive.pk';
export const WHATSAPP = (process.env.NEXT_PUBLIC_WHATSAPP ?? '').replace(/\D/g, '');
export const PLAY_URL =
  (process.env.NEXT_PUBLIC_PLAY_URL ?? '').trim() ||
  'https://play.google.com/store/apps/details?id=com.wabwar.udrive';

export const SITE_NAME = 'UDrive – Travel & Tour';
export const SITE_DESCRIPTION =
  'Book tours across Azad Kashmir with verified local drivers — Neelum, Leepa, Banjosa and more. Per seat or the whole vehicle, 20% advance, hotels on the route.';

export const whatsappLink = (text?: string) =>
  WHATSAPP ? `https://wa.me/${WHATSAPP}${text ? `?text=${encodeURIComponent(text)}` : ''}` : PLAY_URL;

export const whatsappLabel = () =>
  WHATSAPP.startsWith('92') && WHATSAPP.length === 12
    ? `0${WHATSAPP.slice(2, 5)} ${WHATSAPP.slice(5)}`
    : WHATSAPP;
