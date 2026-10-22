const PK = 'Asia/Karachi';

export const rs = (n: number) => `Rs ${Math.round(n).toLocaleString('en-US')}`;

// Built from parts rather than toLocaleString: Node (at build) and browsers
// punctuate locale strings differently, which breaks React hydration.
const parts = (iso: string) => {
  const p: Record<string, string> = {};
  for (const x of new Intl.DateTimeFormat('en-US', {
    timeZone: PK, weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', hour12: true,
  }).formatToParts(new Date(iso))) p[x.type] = x.value;
  return p;
};
const LONG_DAY: Record<string, string> = { Mon: 'Monday', Tue: 'Tuesday', Wed: 'Wednesday', Thu: 'Thursday', Fri: 'Friday', Sat: 'Saturday', Sun: 'Sunday' };
const LONG_MONTH: Record<string, string> = { Jan: 'January', Feb: 'February', Mar: 'March', Apr: 'April', May: 'May', Jun: 'June', Jul: 'July', Aug: 'August', Sep: 'September', Oct: 'October', Nov: 'November', Dec: 'December' };

export const shortDate = (iso: string) => { const p = parts(iso); return `${p.weekday} ${p.day} ${p.month}`; };

export const time = (iso: string) => { const p = parts(iso); return `${p.hour}:${p.minute} ${(p.dayPeriod ?? '').toLowerCase()}`.trim(); };

export const when = (iso: string) => `${shortDate(iso)} · ${time(iso)}`;

export const longDate = (iso: string) => { const p = parts(iso); return `${LONG_DAY[p.weekday] ?? p.weekday} ${p.day} ${LONG_MONTH[p.month] ?? p.month}`; };

export const daysLabel = (d: number) => (d <= 1 ? '1 day' : `${d} days`);

/** Pakistani mobile in any common shape → 03XXXXXXXXX, or null. */
export function normalisePhone(raw: string): string | null {
  const d = raw.replace(/\D/g, '');
  const local = d.startsWith('0092') ? d.slice(4) : d.startsWith('92') ? d.slice(2) : d.startsWith('0') ? d.slice(1) : d;
  return /^3\d{9}$/.test(local) ? `0${local}` : null;
}
