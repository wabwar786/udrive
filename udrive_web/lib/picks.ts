import { placeFor } from '@/components/Weather';
import type { Destination, TourCard, Weather, WxPlace } from './types';

/**
 * "Where to go this week" — ranks UDrive's own destinations (Azad Kashmir
 * only; the API never sends anything else) from this week's weather, the
 * season, road updates and the tours already going.
 */
export type Trip = 'day' | 'short' | 'long';
export type Love = 'any' | 'lake' | 'meadow' | 'river' | 'snow';
export const ORIGINS = {
  Muzaffarabad: [34.37, 73.4711],
  Rawalakot: [33.8578, 73.7604],
  Mirpur: [33.1484, 73.7516],
} as const;
export type Origin = keyof typeof ORIGINS;

export type Pick = { d: Destination; score: number; hours: number | null; wx: WxPlace | null; reasons: string[]; tours: number };
export type Picks = { top: Pick[]; ranked: Pick[]; avoid: string[]; note: string };

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/** "May to September", "April – October", "All year" → months (1–12), or null when unknown. */
export function seasonMonths(text: string): Set<number> | null {
  const t = (text || '').toLowerCase();
  if (!t.trim()) return null;
  if (t.includes('all year') || t.includes('year round') || t.includes('round the year')) return new Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  const found = MONTHS.map((m, i) => ({ i, at: t.indexOf(m) })).filter((x) => x.at >= 0).sort((a, b) => a.at - b.at);
  if (found.length < 2) return found.length === 1 ? new Set([found[0].i + 1]) : null;
  const a = found[0].i, b = found[found.length - 1].i;
  const out = new Set<number>();
  for (let k = a; ; k = (k + 1) % 12) { out.add(k + 1); if (k === b) break; }
  return out;
}

function km(a: readonly [number, number], b: readonly [number, number]) {
  const r = Math.PI / 180, dLat = (b[0] - a[0]) * r, dLng = (b[1] - a[1]) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a[0] * r) * Math.cos(b[0] * r) * Math.sin(dLng / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
}

/** Mountain roads: about 1.8× the straight line at about 32 km/h, never under an hour. */
export function driveHours(d: Destination, from: Origin): number | null {
  if (from === 'Muzaffarabad' && d.driveHours) return Number(d.driveHours);
  if (d.latitude == null || d.longitude == null) return null;
  const h = (km(ORIGINS[from], [d.latitude, d.longitude]) * 1.8) / 32;
  return Math.max(1, Math.round(h * 2) / 2);
}

const fits = (trip: Trip, h: number | null) => h == null || (trip === 'day' ? h <= 3 : trip === 'short' ? h <= 7 : true);
const snowy = (p: WxPlace | null) => !!p && (p.advice.level === 'bad' || p.days.slice(0, 3).some((x) => x.snow >= 1));

export function rankPicks(destinations: Destination[], weather: Weather, tours: TourCard[], o: { trip: Trip; love: Love; from: Origin; month: number }): Picks {
  const roads = weather.roadUpdates.map((r) => `${r.title} ${r.route ?? ''} ${r.details}`.toLowerCase());
  const all: Pick[] = [];
  for (const d of destinations) {
    const wx = placeFor(weather, d.name, d.district, d.latitude, d.longitude);
    const hours = driveHours(d, o.from);
    const months = seasonMonths(d.bestSeason);
    const going = Math.max(d.upcomingTours, tours.filter((t) => t.destinationSlug === d.slug).length);
    const blocked = roads.some((r) => r.includes(d.name.toLowerCase()) || (d.district && r.includes(d.district.toLowerCase()) && r.includes('road')));
    const reasons: string[] = [];
    let score = 0;
    if (wx) {
      const day = wx.days[0];
      if (o.love === 'snow') { if (snowy(wx)) { score += 6; reasons.push(`Snow now — ${Math.round(wx.now.temperature)}°, 4×4 jeep only`); } }
      else if (wx.advice.level === 'ok') { score += 3; reasons.push(day ? `Good weather — ${Math.round(day.max)}° by day, ${Math.round(day.min)}° at night` : 'Good weather this week'); }
      else if (wx.advice.level === 'warn') reasons.push(wx.advice.text);
      else score -= 6;
    }
    if (months && o.month > 0) {
      if (months.has(o.month)) { score += 3; reasons.push(`Best season now (${d.bestSeason})`); }
      else score -= 3;
    }
    if (going > 0) { score += 2 + Math.min(going, 3); reasons.push(`${going} ${going === 1 ? 'tour' : 'tours'} going`); }
    if (d.imageUrl) score += 1;
    if (blocked) { score -= 3; reasons.push('Road update on the way — check before leaving'); }
    if (hours != null) reasons.push(`About ${hours} h from ${o.from}`);
    if (o.trip === 'long' && hours != null && hours >= 4) score += 1;
    all.push({ d, score, hours, wx, reasons, tours: going });
  }

  let pool = all.filter((p) => fits(o.trip, p.hours));
  if (o.love === 'snow') pool = pool.filter((p) => snowy(p.wx));
  else if (o.love !== 'any') {
    const kind = pool.filter((p) => p.d.kind === o.love);
    if (kind.length) pool = kind;
  }
  const good = pool.filter((p) => o.love === 'snow' || !(p.wx?.advice.level === 'bad')).sort((a, b) => b.score - a.score || (a.hours ?? 99) - (b.hours ?? 99));
  const top = good.slice(0, 3);

  const avoid: string[] = [];
  if (o.love !== 'snow') for (const p of all.filter((x) => x.wx?.advice.level === 'bad').sort((a, b) => b.tours - a.tours).slice(0, 3)) avoid.push(`❄ ${p.d.name} — ${p.wx!.advice.text.toLowerCase()}`);
  for (const r of weather.roadUpdates.slice(0, 2)) avoid.push(`⚠ ${r.route ? `${r.route} — ` : ''}${r.title}`);

  const note = top.length === 0
    ? o.love === 'snow' ? 'No snow in Azad Kashmir this week — try Meadows or Lakes.' : 'Nothing fits these choices this week — try a longer trip.'
    : '';
  return { top, ranked: good, avoid, note };
}
