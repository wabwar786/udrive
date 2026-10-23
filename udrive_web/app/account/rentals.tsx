'use client';

import { useEffect, useState } from 'react';

import { rs } from '@/lib/format';
import type { ListingHome, OwnerRental } from '@/lib/types';
import { call, dayLabel, json, Msg, useAction } from './ui';

const LABEL: Record<string, string> = {
  PendingOwner: 'Waiting for you', Confirmed: 'Confirmed', HandedOver: 'With customer', Returned: 'Returned',
  Completed: 'Completed', Cancelled: 'Cancelled', Rejected: 'Rejected', NoShow: 'No-show', Expired: 'Expired',
};

export function Rentals({ home }: { home: ListingHome | null }) {
  const [list, setList] = useState<OwnerRental[] | null>(null);
  const a = useAction();
  const load = () => a.run(async () => setList(await call<OwnerRental[]>('/api/v1/driver/rentals')));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { void load(); }, []);

  async function respond(r: OwnerRental, accept: boolean, driver?: string) {
    let reason: string | null = null;
    if (!accept) { reason = window.prompt('Reason (the customer sees this):', 'Not available on these days')?.replace(/[<>]/g, '').slice(0, 200) ?? null; if (reason === null) return; }
    await a.run(async () => { await call(`/api/v1/driver/rentals/${r.id}/respond`, json('POST', { accept, fleetDriverId: driver || null, reason })); await load(); }, accept ? 'Confirmed. The customer is told on WhatsApp.' : 'Rejected.');
  }

  const drivers = (home?.drivers ?? []).filter((d) => d.status === 'Approved' && d.licenceValid);
  const waiting = (list ?? []).filter((r) => r.status === 'PendingOwner');
  const rest = (list ?? []).filter((r) => r.status !== 'PendingOwner');

  return (
    <>
      <div className="acctHead"><div><h1>Rent bookings</h1><p className="muted">Requests for your cars. Answer quickly — requests expire if nobody replies.</p></div></div>
      <Msg error={a.error} ok={a.ok} />
      {list === null ? <div className="skel" style={{ minHeight: 200 }} /> : list.length === 0 ? <div className="empty">No rent bookings yet.</div> : (
        <>
          {waiting.map((r) => <Row key={r.id} r={r} drivers={drivers} onRespond={respond} busy={a.busy} />)}
          {rest.length > 0 && (
            <table className="tbl" style={{ marginTop: 18 }}>
              <thead><tr><th>Ref</th><th>Vehicle</th><th>Dates</th><th>Customer</th><th>Total</th><th>Status</th></tr></thead>
              <tbody>{rest.map((r) => (
                <tr key={r.id}><td>{r.bookingReference}</td><td>{r.vehicleName}</td><td>{dayLabel(r.startDate)} – {dayLabel(r.endDate)}</td><td>{r.counterpartName}{r.counterpartPhone ? <><br /><small>{r.counterpartPhone}</small></> : null}</td><td>{rs(r.subtotal)}</td><td>{LABEL[r.status] ?? r.status}</td></tr>
              ))}</tbody>
            </table>
          )}
        </>
      )}
    </>
  );
}

function Row({ r, drivers, onRespond, busy }: { r: OwnerRental; drivers: ListingHome['drivers']; onRespond: (r: OwnerRental, ok: boolean, d?: string) => void; busy: boolean }) {
  const [driver, setDriver] = useState('');
  return (
    <div className="sec2" style={{ borderColor: '#E9C46A' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}>
        <div>
          <span className="pill p-wait">Waiting for you</span>
          <h3 style={{ margin: '8px 0 4px' }}>{r.vehicleName} · {dayLabel(r.startDate)} – {dayLabel(r.endDate)} ({r.days} {r.days === 1 ? 'day' : 'days'})</h3>
          <div className="small muted">{r.rentalMode === 'SelfDrive' ? 'Self drive' : 'With driver'} · {r.counterpartName} · {rs(r.dailyRate)}/day · total {rs(r.subtotal)} · advance {rs(r.advanceAmount)}{r.securityDeposit ? ` · deposit ${rs(r.securityDeposit)}` : ''}</div>
        </div>
        <div className="acts" style={{ alignItems: 'center' }}>
          {r.rentalMode !== 'SelfDrive' && drivers.length > 0 && (
            <select className="selSm" value={driver} onChange={(e) => setDriver(e.target.value)} aria-label="Driver"><option value="">I will drive</option>{drivers.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select>
          )}
          <button className="btn dark" disabled={busy} onClick={() => onRespond(r, true, driver)}>Accept</button>
          <button className="btn ghost" disabled={busy} onClick={() => onRespond(r, false)}>Reject</button>
        </div>
      </div>
    </div>
  );
}
