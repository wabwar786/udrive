'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { Picture } from '@/components/Scene';
import { api, img } from '@/lib/api';
import type { Destination } from '@/lib/types';

/** Destinations with district chips. Used on the home page (limit) and /destinations/. */
export function DestinationsGrid({ initial, limit }: { initial: Destination[]; limit?: number }) {
  const [list, setList] = useState(initial);
  const [district, setDistrict] = useState('');
  useEffect(() => {
    if (initial.length === 0) api<Destination[]>('/api/v1/web/destinations').then(setList).catch(() => undefined);
  }, [initial.length]);
  useEffect(() => { if (initial.length) setList(initial); }, [initial]);

  const districts = [...new Set(list.map((d) => d.district).filter(Boolean))].sort();
  const shown = list.filter((d) => !district || d.district === district);
  const items = limit ? shown.slice(0, limit) : shown;

  if (list.length === 0) return <div className="empty">Destinations are loading…</div>;
  return (
    <>
      <div className="filters" role="tablist" aria-label="Districts">
        <button className={`chip ${district === '' ? 'on' : ''}`} onClick={() => setDistrict('')}>All</button>
        {districts.map((d) => <button key={d} className={`chip ${district === d ? 'on' : ''}`} onClick={() => setDistrict(d)}>{d}</button>)}
      </div>
      <div className="dg">
        {items.map((d) => (
          <Link key={d.slug} className="dc" href={`/tours/${d.slug}/`}>
            <div className="im"><Picture src={img(d.imageUrl)} alt={`${d.name}, ${d.district} — Azad Kashmir`} seed={d.name} /><em>{d.district}</em></div>
            <div className="bd">
              <b>{d.name}</b>
              <div className="m">{d.bestSeason ? `Best: ${d.bestSeason}` : d.summary.slice(0, 60)}</div>
              <div className="l">{d.upcomingTours > 0 ? `${d.upcomingTours} upcoming ${d.upcomingTours === 1 ? 'tour' : 'tours'} →` : 'Plan a trip →'}</div>
            </div>
          </Link>
        ))}
      </div>
    </>
  );
}
