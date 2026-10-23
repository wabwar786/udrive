'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { RentCard, SkeletonGrid } from '@/components/Cards';
import { PlayButton } from '@/components/PlayButton';
import { api } from '@/lib/api';
import { whatsappLink } from '@/lib/config';
import type { RentCar } from '@/lib/types';

const MODES = [['', 'Any'], ['WithDriver', 'With driver'], ['SelfDrive', 'Self drive']] as const;
const CATS = [['', 'All'], ['car', 'Car'], ['jeep', 'Jeep / 4×4'], ['hiace', 'Hiace'], ['coster', 'Coaster']] as const;

export function RentView({ initial }: { initial: RentCar[] }) {
  const [mode, setMode] = useState('');
  const [cat, setCat] = useState('');
  const [cars, setCars] = useState<RentCar[] | null>(initial.length ? initial : null);
  const [error, setError] = useState('');

  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const m = q.get('mode') ?? ''; const c = q.get('category') ?? '';
    if (MODES.some(([k]) => k === m)) setMode(m);
    if (CATS.some(([k]) => k === c)) setCat(c);
  }, []);

  useEffect(() => {
    const q = new URLSearchParams();
    if (mode) q.set('mode', mode);
    if (cat) q.set('category', cat);
    api<RentCar[]>(`/api/v1/web/rent-cars?${q}`).then((x) => { setCars(x); setError(''); }).catch((e) => setError(e.message));
  }, [mode, cat]);

  return (
    <section className="sec">
      <div className="filters">
        {MODES.map(([k, l]) => <button key={k} className={`chip ${mode === k ? 'on' : ''}`} onClick={() => setMode(k)}>{l}</button>)}
        <span style={{ width: 12 }} />
        {CATS.map(([k, l]) => <button key={k} className={`chip ${cat === k ? 'on' : ''}`} onClick={() => setCat(k)}>{l}</button>)}
      </div>
      {error && <div className="msg err">{error}</div>}
      {cars === null ? <SkeletonGrid /> : (
        <div className="rent">
          {cars.map((c) => <RentCard key={c.id} c={c} />)}
          <div className="addc">
            <b>{cars.length ? 'Book in the UDrive app' : 'No car matches yet'}</b>
            <p>{cars.length ? 'Pick dates, pay the advance, and the owner confirms on WhatsApp.' : 'Tell us your dates on WhatsApp — we will find an owner.'}</p>
            {cars.length ? <PlayButton /> : <a className="btn dark" href={whatsappLink('Assalam o Alaikum, I need a car on rent.')} target="_blank" rel="noopener noreferrer">Ask on WhatsApp</a>}
          </div>
          <div className="addc">
            <b>Have a car?</b>
            <p>Rent it out by the day. Add as many vehicles as you own from your UDrive account.</p>
            <Link className="btn dark" href="/account/">List your car</Link>
          </div>
        </div>
      )}
    </section>
  );
}
