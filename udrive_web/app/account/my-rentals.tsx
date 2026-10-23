'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { RENT_LABEL, RentStatus } from '@/components/RentStatus';
import type { MyRental, Waitlist } from '@/lib/types';
import { call, dayLabel, Msg, useAction } from './ui';

/** Cars this person rented as a customer, and their waiting-list requests. */
export function MyRentals() {
  const [list, setList] = useState<MyRental[] | null>(null);
  const [waits, setWaits] = useState<Waitlist[]>([]);
  const a = useAction();
  useEffect(() => {
    void a.run(async () => {
      const [b, w] = await Promise.all([call<MyRental[]>('/api/v1/rentals/bookings'), call<Waitlist[]>('/api/v1/rentals/waitlist/my').catch(() => [])]);
      setList(b); setWaits(w);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const live = (list ?? []).filter((r) => ['PendingOwner', 'Confirmed', 'HandedOver'].includes(r.status));
  const past = (list ?? []).filter((r) => !live.includes(r));
  return (
    <>
      <div className="acctHead"><div><h1>My rentals</h1><p className="muted">Cars you booked. The owner&apos;s number shows once they confirm.</p></div><Link className="btn dark" href="/rent-a-car/">Rent a car</Link></div>
      <Msg error={a.error} />
      {list === null ? <div className="skel" style={{ minHeight: 200 }} /> : list.length === 0 && waits.length === 0 ? (
        <div className="empty">No rentals yet. <Link className="link" href="/rent-a-car/">Find a car</Link></div>
      ) : (
        <>
          <div className="liveGrid">{live.map((r) => <RentStatus key={r.id} initial={r} compact />)}</div>
          {waits.length > 0 && (
            <div className="sec2"><h3 style={{ marginBottom: 8 }}>Waiting list</h3>
              <table className="tbl"><tbody>{waits.map((w) => <tr key={w.id}><td><b>{w.vehicleName}</b></td><td>{dayLabel(w.startDate)} – {dayLabel(w.endDate)}</td><td>{w.rentalMode === 'SelfDrive' ? 'Self drive' : 'With driver'}</td><td>{w.status}</td></tr>)}</tbody></table>
            </div>
          )}
          {past.length > 0 && (
            <table className="tbl" style={{ marginTop: 16 }}>
              <thead><tr><th>Ref</th><th>Car</th><th>Dates</th><th>Advance</th><th>Status</th></tr></thead>
              <tbody>{past.map((r) => { const [cls, label] = RENT_LABEL[r.status] ?? ['p-no', r.status]; return (
                <tr key={r.id}><td>{r.bookingReference}</td><td>{r.vehicleName}</td><td>{dayLabel(r.startDate)} – {dayLabel(r.endDate)}</td><td>Rs {Math.round(r.advanceAmount).toLocaleString('en-US')}</td><td><span className={`pill ${cls}`} style={{ margin: 0 }}>{label}</span></td></tr>
              ); })}</tbody>
            </table>
          )}
        </>
      )}
    </>
  );
}
