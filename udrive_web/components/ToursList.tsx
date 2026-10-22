'use client';

import { useSearchParams } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';

import { AdSlot } from './AdSlot';
import { SkeletonGrid, TourCard } from './Cards';
import { api } from '@/lib/api';
import { whatsappLink } from '@/lib/config';
import type { Page, TourCard as Tour } from '@/lib/types';

const DAYS = [['', 'Any length'], ['1', '1 day'], ['2-3', '2–3 days'], ['4+', '4+ days']] as const;
const MODES = [['', 'All'], ['seat', 'Per seat'], ['whole', 'Whole vehicle']] as const;

/** Live tour list with filters. `initial` is the build-time snapshot. */
export function ToursList({ destination, initial }: { destination?: string; initial: Page<Tour> }) {
  const params = useSearchParams();
  const [days, setDays] = useState('');
  const [mode, setMode] = useState('');
  const [date, setDate] = useState(params?.get('date') ?? '');
  const seats = Number(params?.get('seats') ?? 0) || 0;
  const [page, setPage] = useState(1);
  const [data, setData] = useState<Page<Tour> | null>(initial.items.length ? initial : null);
  const [error, setError] = useState('');

  useEffect(() => {
    const q = new URLSearchParams({ page: String(page) });
    if (destination) q.set('destination', destination);
    if (days) q.set('days', days);
    if (mode) q.set('mode', mode);
    if (date) q.set('date', date);
    let live = true;
    api<Page<Tour>>(`/api/v1/web/tours?${q}`)
      .then((d) => live && (setData((prev) => (page > 1 && prev ? { ...d, items: [...prev.items, ...d.items] } : d)), setError('')))
      .catch((e) => live && setError(e.message));
    return () => { live = false; };
  }, [destination, days, mode, date, page]);

  const items = useMemo(
    () => (data?.items ?? []).filter((t) => !seats || t.seatsLeft >= seats || t.wholeVehicleAvailable),
    [data, seats],
  );

  const reset = (fn: () => void) => { fn(); setPage(1); };

  return (
    <>
      <div className="filters" role="group" aria-label="Filter tours">
        {DAYS.map(([v, l]) => (
          <button key={v} className={`chip ${days === v ? 'on' : ''}`} onClick={() => reset(() => setDays(v))}>{l}</button>
        ))}
        {MODES.slice(1).map(([v, l]) => (
          <button key={v} className={`chip ${mode === v ? 'on' : ''}`} onClick={() => reset(() => setMode(mode === v ? '' : v))}>{l}</button>
        ))}
        <label className="chip">Date <input type="date" value={date} onChange={(e) => reset(() => setDate(e.target.value))} style={{ border: 'none', background: 'none', font: 'inherit' }} /></label>
        {date && <button className="chip" onClick={() => reset(() => setDate(''))}>Clear date</button>}
      </div>
      {error && <div className="msg err">{error}</div>}
      {!data && !error ? <SkeletonGrid n={8} /> : items.length === 0 ? (
        <div className="empty">
          No open tours match this right now. New departures are added daily —{' '}
          <a className="link" href={whatsappLink('Assalam o Alaikum, I am looking for a tour.')} target="_blank" rel="noopener noreferrer">ask us on WhatsApp</a>.
        </div>
      ) : (
        <div className="grid4">{items.map((t) => <TourCard key={t.id} t={t} />)}</div>
      )}
      {data?.hasMore && (
        <div style={{ textAlign: 'center', marginTop: 24 }}>
          <button className="btn ghost" onClick={() => setPage(page + 1)}>Show more tours</button>
        </div>
      )}
      <div style={{ marginTop: 48 }}><AdSlot slot="tours" /></div>
    </>
  );
}
