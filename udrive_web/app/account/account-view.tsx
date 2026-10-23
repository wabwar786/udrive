'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';

import { signOut } from '@/lib/auth';
import type { ListingHome } from '@/lib/types';
import { useSession } from '@/lib/useSession';
import { Departures } from './departures';
import { Documents } from './documents';
import { Drivers } from './drivers';
import { Hotels } from './hotels';
import { MyRentals } from './my-rentals';
import { PartnerTrack } from './partner-track';
import { Rentals } from './rentals';
import { call, Msg } from './ui';
import { Vehicles } from './vehicles';

const TABS = [
  ['myrentals', 'My rentals'],
  ['vehicles', 'Vehicles'],
  ['departures', 'Tour departures'],
  ['rentals', 'Rent bookings'],
  ['drivers', 'Drivers'],
  ['documents', 'Documents'],
  ['hotels', 'Hotels'],
  ['partner', 'Partnership'],
] as const;
// Owner tabs below a thin line in the sidebar.
const OWNER_FROM = 'vehicles';
type Tab = (typeof TABS)[number][0];

export function AccountView() {
  const router = useRouter();
  const { ready, user } = useSession();
  const [tab, setTab] = useState<Tab>('vehicles');
  const [home, setHome] = useState<ListingHome | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    const t = new URLSearchParams(window.location.search).get('tab');
    if (t && TABS.some(([k]) => k === t)) setTab(t as Tab);
  }, []);

  useEffect(() => {
    if (ready && !user) router.replace('/login/?next=/account/');
  }, [ready, user, router]);

  const reload = useCallback(async () => {
    try {
      setHome(await call<ListingHome>('/api/v1/listings/me'));
      setError('');
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);

  useEffect(() => {
    if (ready && user) void reload();
  }, [ready, user, reload]);

  function go(t: Tab) {
    setTab(t);
    window.history.replaceState(null, '', `/account/?tab=${t}`);
    window.scrollTo({ top: 0 });
  }

  if (!ready || !user) return <div className="wrap"><div className="skel" style={{ margin: '40px 0', minHeight: 420 }} /></div>;

  const v = home?.vehicles ?? [];
  const count: Partial<Record<Tab, number>> = {
    vehicles: v.length,
    rentals: v.reduce((n, x) => n + x.pendingRentals, 0),
    drivers: home?.drivers.length,
  };

  return (
    <div className="wrap">
      <div className="acct">
        <aside className="side2" aria-label="Account">
          <div className="whoBox"><b>{user.name || 'UDrive owner'}</b>{user.phone}</div>
          {TABS.map(([k, label]) => (
            <a key={k} data-split={k === OWNER_FROM ? '' : undefined} href={`/account/?tab=${k}`} className={tab === k ? 'on' : ''} onClick={(e) => { e.preventDefault(); go(k); }}>
              {label}{count[k] ? <span>{count[k]}</span> : null}
            </a>
          ))}
          <button className="out" onClick={async () => { await signOut(); router.push('/'); }}>Log out</button>
        </aside>
        <section className="acctMain">
          <Msg error={error} />
          {tab === 'myrentals' && <MyRentals />}
          {tab === 'vehicles' && <Vehicles home={home} reload={reload} go={go} />}
          {tab === 'departures' && <Departures home={home} />}
          {tab === 'rentals' && <Rentals home={home} />}
          {tab === 'drivers' && <Drivers home={home} reload={reload} />}
          {tab === 'documents' && <Documents home={home} reload={reload} />}
          {tab === 'hotels' && <Hotels />}
          {tab === 'partner' && <PartnerTrack />}
          <p className="note2" style={{ marginTop: 28 }}>
            Same account as the UDrive app. Everything you change here shows in the app too. Need help?{' '}
            <Link className="link" href="/about/">Contact UDrive</Link>
          </p>
        </section>
      </div>
    </div>
  );
}
