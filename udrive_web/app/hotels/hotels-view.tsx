'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { AdSlot } from '@/components/AdSlot';
import { HotelCard, SkeletonGrid } from '@/components/Cards';
import { api } from '@/lib/api';
import type { HotelCard as Hotel, Page } from '@/lib/types';

const CITIES = ['', 'Muzaffarabad', 'Neelum', 'Rawalakot', 'Bagh', 'Kotli', 'Mirpur', 'Leepa'];

export function HotelsView({ initial }: { initial: Page<Hotel> }) {
  const [city, setCity] = useState('');
  const [page, setPage] = useState(1);
  const [data, setData] = useState<Page<Hotel> | null>(initial.items.length ? initial : null);
  const [error, setError] = useState('');

  // /hotels/?city=Neelum from the home page search.
  useEffect(() => {
    const c = new URLSearchParams(window.location.search).get('city');
    if (c && CITIES.includes(c)) setCity(c);
  }, []);

  useEffect(() => {
    const q = new URLSearchParams({ page: String(page) });
    if (city) q.set('city', city);
    api<Page<Hotel>>(`/api/v1/web/hotels?${q}`)
      .then((d) => setData((prev) => (page > 1 && prev ? { ...d, items: [...prev.items, ...d.items] } : d)))
      .catch((e) => setError(e.message));
  }, [city, page]);

  return (
    <section className="sec">
      <div className="filters">
        {CITIES.map((c) => (
          <button key={c} className={`chip ${city === c ? 'on' : ''}`} onClick={() => { setCity(c); setPage(1); }}>{c || 'All'}</button>
        ))}
      </div>
      {error && <div className="msg err">{error}</div>}
      {!data && !error ? <SkeletonGrid n={6} cls="grid3" /> : (data?.items.length ?? 0) === 0 ? (
        <div className="empty">No hotels listed here yet. <Link className="link" href="/list-your-hotel/">Own one? List it</Link></div>
      ) : (
        <div className="grid3">{data!.items.map((h) => <HotelCard key={h.id} h={h} />)}</div>
      )}
      {data?.hasMore && <div style={{ textAlign: 'center', marginTop: 24 }}><button className="btn ghost" onClick={() => setPage(page + 1)}>Show more</button></div>}
      <div style={{ marginTop: 48 }}><AdSlot slot="hotels" /></div>
    </section>
  );
}
