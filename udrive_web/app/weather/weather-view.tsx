'use client';

import { useMemo, useState } from 'react';

import { Art } from '@/components/Art';
import { updatedAt, useWeather, WxIcon, WxRow } from '@/components/Weather';
import type { Weather } from '@/lib/types';

export function WeatherView({ initial }: { initial: Weather }) {
  const w = useWeather(initial);
  const [q, setQ] = useState('');
  const groups = useMemo(() => {
    const t = q.trim().toLowerCase();
    const list = w.places.filter((p) => !t || p.name.toLowerCase().includes(t) || p.district.toLowerCase().includes(t));
    const by = new Map<string, typeof list>();
    for (const p of list) { const k = p.district || 'Other'; by.set(k, [...(by.get(k) ?? []), p]); }
    // Spots first inside each district; districts with the most tourist spots first.
    return [...by.entries()].map(([d, ps]) => [d, [...ps].sort((a, b) => (a.kind === b.kind ? a.name.localeCompare(b.name) : a.kind === 'Spot' ? -1 : 1))] as const)
      .sort((a, b) => b[1].filter((p) => p.kind === 'Spot').length - a[1].filter((p) => p.kind === 'Spot').length || b[1].length - a[1].length || a[0].localeCompare(b[0]));
  }, [w.places, q]);

  return (
    <>
      <section className="wxhero">
        <Art seed="weather-page" w={1600} h={420} palette="alpine" lake />
        <div className="shade" />
        <div className="wrap in">
          <span className="kick">{w.updatedAt ? `Updated ${updatedAt(w.updatedAt)} · every hour` : 'Updated every hour'}</span>
          <h1>Azad Kashmir weather</h1>
          <p>Today and the next 3 days for every tehsil and tourist spot — snow, rain and wind before you set off.</p>
          <label className="srch"><span className="sr">Search a place</span>
            <input value={q} maxLength={40} onChange={(e) => setQ(e.target.value.replace(/[<>]/g, ''))} placeholder="Search a place — Keran, Leepa, Rawalakot…" />
          </label>
        </div>
      </section>
      <div className="wrap" style={{ paddingBottom: 70 }}>
        {w.roadUpdates.map((r, k) => (
          <div className="adv" key={k}>
            <WxIcon code={95} size={30} />
            <div><b>Road update{r.route ? ` · ${r.route}` : ''}</b> — {r.title}<br /><span>{r.details} ({r.source}, {updatedAt(r.startsAt)})</span></div>
          </div>
        ))}
        {w.places.length === 0 ? <div className="empty" style={{ marginTop: 30 }}>Weather is loading…</div> : groups.length === 0 ? <div className="empty" style={{ marginTop: 30 }}>No place matches “{q}”.</div> : groups.map(([d, ps]) => (
          <section key={d}>
            <div className="grpH"><h2>{d}</h2><span>{ps.length} {ps.length === 1 ? 'place' : 'places'}</span></div>
            <div className="wl">{ps.map((p) => <WxRow key={p.key} p={p} />)}</div>
          </section>
        ))}
        <p className="note2" style={{ marginTop: 24 }}>Forecast from Open-Meteo, refreshed every hour. Mountain weather changes fast — ask your driver on the day.</p>
      </div>
    </>
  );
}
