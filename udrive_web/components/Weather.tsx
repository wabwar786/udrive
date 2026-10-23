'use client';

import { useEffect, useState } from 'react';

import { api } from '@/lib/api';
import { EMPTY_WEATHER, type Weather, type WxDay, type WxPlace } from '@/lib/types';

// WMO weather codes (Open-Meteo) → icon and words.
type Kind = 'sun' | 'cloud' | 'fog' | 'rain' | 'snow' | 'storm';
export function kindOf(code: number): Kind {
  if (code >= 95) return 'storm';
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return 'snow';
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return 'rain';
  if (code === 45 || code === 48) return 'fog';
  if (code >= 2) return 'cloud';
  return 'sun';
}
export function words(code: number) {
  if (code === 0) return 'Clear';
  if (code === 1) return 'Mostly sunny';
  if (code === 2) return 'Partly cloudy';
  if (code === 3) return 'Cloudy';
  if (code === 45 || code === 48) return 'Fog';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return code >= 65 ? 'Heavy rain' : 'Rain';
  if (code >= 71 && code <= 77) return code >= 75 ? 'Heavy snow' : 'Light snow';
  if (code >= 80 && code <= 82) return 'Showers';
  if (code === 85 || code === 86) return 'Snow showers';
  if (code >= 95) return 'Thunderstorm';
  return 'Mixed';
}

const RAYS = [0, 45, 90, 135, 180, 225, 270, 315].map((a) => { const r = (a * Math.PI) / 180; return [24 + 15 * Math.cos(r), 24 + 15 * Math.sin(r), 24 + 20 * Math.cos(r), 24 + 20 * Math.sin(r)]; });
export function WxIcon({ code, size = 40 }: { code: number; size?: number }) {
  const k = kindOf(code);
  const cloud = (fill: string) => <path d="M12 28h24a8 8 0 0 0 0-16 10 10 0 0 0-19 3 7 7 0 0 0-5 13z" fill={fill} />;
  return (
    <svg viewBox="0 0 48 48" width={size} height={size} role="img" aria-label={words(code)} className="wxi">
      {k === 'sun' && <><circle cx="24" cy="24" r="9" fill="#FFC93C" /><g stroke="#FFC93C" strokeWidth="3" strokeLinecap="round">{RAYS.map(([a, b, c, d], i) => <line key={i} x1={a} y1={b} x2={c} y2={d} />)}</g></>}
      {k === 'cloud' && <><circle cx="18" cy="18" r="7" fill="#FFC93C" /><path d="M14 36h22a8 8 0 0 0 0-16 10 10 0 0 0-19 3 7 7 0 0 0-3 13z" fill="#E6ECF3" /></>}
      {k === 'fog' && <><path d="M14 30h22a8 8 0 0 0 0-16 10 10 0 0 0-19 3 7 7 0 0 0-3 13z" fill="#E6ECF3" /><g stroke="#B8C4D2" strokeWidth="3" strokeLinecap="round"><line x1="10" y1="36" x2="38" y2="36" /><line x1="14" y1="42" x2="34" y2="42" /></g></>}
      {k === 'rain' && <>{cloud('#C9D4E0')}<g stroke="#4DA3FF" strokeWidth="3" strokeLinecap="round"><line x1="16" y1="33" x2="14" y2="40" /><line x1="24" y1="33" x2="22" y2="40" /><line x1="32" y1="33" x2="30" y2="40" /></g></>}
      {k === 'snow' && <>{cloud('#DDE6F0')}<g fill="#9FD3FF"><circle cx="16" cy="34" r="2.5" /><circle cx="24" cy="38" r="2.5" /><circle cx="32" cy="34" r="2.5" /><circle cx="20" cy="43" r="2" /><circle cx="28" cy="43" r="2" /></g></>}
      {k === 'storm' && <>{cloud('#9AA8B8')}<path d="M24 28l-5 9h5l-3 8 9-11h-5l3-6z" fill="#FFC93C" /></>}
    </svg>
  );
}

const deg = (n: number) => `${Math.round(n)}°`;
export function dayName(iso: string, k: number) {
  if (k === 0) return 'Today';
  return new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-GB', { weekday: 'short', timeZone: 'UTC' });
}
export const updatedAt = (iso: string | null) => (iso ? new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Karachi', hour: 'numeric', minute: '2-digit', hour12: true }).format(new Date(iso)) : '');

/** Live weather: build-time snapshot first, then fresh from the API. */
export function useWeather(initial: Weather = EMPTY_WEATHER) {
  const [w, setW] = useState(initial);
  useEffect(() => { api<Weather>('/api/v1/web/weather').then(setW).catch(() => undefined); }, []);
  return w;
}

function Days({ days, size = 26 }: { days: WxDay[]; size?: number }) {
  return (
    <div className="wxd">
      {days.slice(0, 4).map((d, k) => <div key={d.date}>{dayName(d.date, k)}<WxIcon code={d.code} size={size} /><b>{deg(d.max)}</b>{deg(d.min)}</div>)}
    </div>
  );
}

/** Dark card for the home page. */
export function WxCard({ p }: { p: WxPlace }) {
  return (
    <div className="wc">
      <div className="t"><div><b>{p.name}</b><small>{p.district}{p.kind === 'Spot' ? ' · spot' : ''}</small></div><WxIcon code={p.now.code} size={46} /></div>
      <div className="deg">{deg(p.now.temperature)}</div>
      <div className="cond">{words(p.now.code)} · wind {Math.round(p.now.wind)} km/h</div>
      <span className={`go g-${p.advice.level}`}>{p.advice.text}</span>
      <Days days={p.days} />
    </div>
  );
}

/** Light row for the weather page. */
export function WxRow({ p }: { p: WxPlace }) {
  return (
    <div className="wr" id={p.key}>
      <div><b>{p.name}</b><small>{p.kind === 'Spot' ? 'Tourist spot' : 'Tehsil'} · {words(p.now.code)}</small></div>
      <div className="now"><WxIcon code={p.now.code} size={36} />{deg(p.now.temperature)}</div>
      <Days days={p.days} size={24} />
      <div className={`tagx t-${p.advice.level}`}>{p.advice.text}</div>
    </div>
  );
}

/**
 * The reading for a destination: the nearest place within 25 km when the
 * destination has a map location (so a lake is never given a far-away town's
 * snow), otherwise a place with the same name.
 */
export function placeFor(w: Weather, name: string, district: string, lat?: number | null, lng?: number | null): WxPlace | null {
  const n = name.toLowerCase();
  const same = w.places.find((p) => p.name.toLowerCase() === n);
  if (same) return same;
  if (lat != null && lng != null) {
    let best: WxPlace | null = null, bestKm = 25;
    for (const p of w.places) {
      if (p.latitude == null || p.longitude == null) continue;
      const k = Math.hypot((p.latitude - lat) * 111, (p.longitude - lng) * 111 * Math.cos((lat * Math.PI) / 180));
      if (k < bestKm) { bestKm = k; best = p; }
    }
    return best;
  }
  const first = n.split(/[\s-]+/)[0];
  return w.places.find((p) => first.length > 3 && p.name.toLowerCase().startsWith(first))
    ?? w.places.find((p) => p.kind === 'Tehsil' && p.name.toLowerCase() === district.toLowerCase())
    ?? null;
}

/** Card on a destination page. */
export function WxDestination({ name, district, lat, lng }: { name: string; district: string; lat?: number | null; lng?: number | null }) {
  const w = useWeather();
  const p = name ? placeFor(w, name, district, lat, lng) : null;
  if (!p) return null;
  const lo = Math.min(...p.days.map((d) => d.min)), hi = Math.max(...p.days.map((d) => d.max)), span = Math.max(1, hi - lo);
  return (
    <div className="dw">
      <div className="top">
        <div>
          <small>WEATHER {p.name.toLowerCase() === name.toLowerCase() ? `AT ${p.name.toUpperCase()}` : `NEAR ${name.toUpperCase()} (${p.name.toUpperCase()})`} · NOW</small>
          <div className="deg">{deg(p.now.temperature)}</div>
          <div>{words(p.now.code)} · wind {Math.round(p.now.wind)} km/h</div>
        </div>
        <WxIcon code={p.now.code} size={72} />
      </div>
      <div className="rows">
        {p.days.slice(0, 4).map((d, k) => (
          <div key={d.date}>
            <b>{dayName(d.date, k)}</b><WxIcon code={d.code} size={30} />
            <span className="bar"><i style={{ left: `${((d.min - lo) / span) * 100}%`, right: `${100 - ((d.max - lo) / span) * 100}%` }} /></span>
            <span>{deg(d.min)} / <b>{deg(d.max)}</b>{d.snow >= 1 ? ` · snow ${Math.round(d.snow)} cm` : d.rain >= 2 ? ` · rain ${Math.round(d.rain)} mm` : ''}</span>
          </div>
        ))}
      </div>
      <div className="foot"><span className={`pill t-${p.advice.level}`} style={{ margin: '0 8px 0 0' }}>{p.advice.text}</span>Updated {updatedAt(w.updatedAt)} · Open-Meteo</div>
    </div>
  );
}
