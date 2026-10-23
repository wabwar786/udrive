'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { authApi } from '@/lib/auth';
import { rs } from '@/lib/format';
import type { MyRental } from '@/lib/types';

const nice = (iso: string) => new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' });
const clock = (iso: string) => new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Karachi', hour: 'numeric', minute: '2-digit', hour12: true }).format(new Date(iso));
const local = (p: string | null | undefined) => (p && p.startsWith('+92') ? `0${p.slice(3, 6)} ${p.slice(6)}` : p ?? '');
const wa = (p: string) => `https://wa.me/${p.replace(/\D/g, '')}`;

export const RENT_LABEL: Record<string, [string, string]> = {
  PendingOwner: ['p-wait', 'Waiting for the owner'], Confirmed: ['p-ok', 'Confirmed'], HandedOver: ['p-ok', 'With you'],
  Returned: ['p-no', 'Returned'], Completed: ['p-no', 'Completed'], Rejected: ['p-bad', 'Owner said no'],
  Expired: ['p-bad', 'No answer in time'], Cancelled: ['p-no', 'Cancelled'], NoShow: ['p-bad', 'No-show'],
};

/** One rental after booking — same states as the app's waiting screen. Refreshes itself while waiting. */
export function RentStatus({ initial, compact }: { initial: MyRental; compact?: boolean }) {
  const [b, setB] = useState(initial);
  const [now, setNow] = useState(() => Date.now());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const pending = b.status === 'PendingOwner';
  const confirmed = b.status === 'Confirmed' || b.status === 'HandedOver';
  const refunded = ['Rejected', 'Expired'].includes(b.status) || (b.status === 'Cancelled' && b.advanceRefundableNow);

  useEffect(() => {
    if (!pending) return;
    const tick = window.setInterval(() => setNow(Date.now()), 1000);
    const poll = window.setInterval(() => {
      authApi<MyRental[]>('/api/v1/rentals/bookings').then((list) => { const x = list.find((y) => y.id === b.id); if (x) setB(x); }).catch(() => undefined);
    }, 30_000);
    return () => { window.clearInterval(tick); window.clearInterval(poll); };
  }, [pending, b.id]);

  async function cancel() {
    if (!window.confirm(b.advanceRefundableNow ? 'Cancel this booking? Your advance comes back.' : 'Cancel this booking? The advance may not come back now.')) return;
    setBusy(true); setError('');
    try { setB(await authApi<MyRental>(`/api/v1/rentals/bookings/${b.id}/cancel`, { method: 'POST', body: JSON.stringify({ reason: null }) })); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  const left = b.ownerRespondBy ? Math.max(0, Date.parse(b.ownerRespondBy) - now) : 0;
  const hh = Math.floor(left / 3_600_000), mm = Math.floor((left % 3_600_000) / 60_000), ss = Math.floor((left % 60_000) / 1000);
  const [cls, label] = RENT_LABEL[b.status] ?? ['p-no', b.status];
  const phone = b.driverPhone || b.counterpartPhone;

  return (
    <div className="st">
      <span className={`pill ${cls}`}>{label}</span>
      <h3 style={{ fontSize: compact ? 19 : 26, margin: '10px 0 4px', letterSpacing: '-.02em' }}>
        {pending ? 'Booking sent' : confirmed ? `${b.counterpartName.split(' ')[0]} confirmed` : b.vehicleName}
      </h3>
      <p className="muted small" style={{ margin: 0 }}>{b.vehicleName} · {nice(b.startDate)} – {nice(b.endDate)} · {b.rentalMode === 'SelfDrive' ? 'self drive' : 'with driver'} · Ref {b.bookingReference}</p>
      {error && <div className="msg err">{error}</div>}
      {pending && b.ownerRespondBy && (
        <div className="clock"><b>{left > 0 ? `${hh}:${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}` : '0:00:00'}</b><span className="small">left for the owner to confirm — by {clock(b.ownerRespondBy)}. If they don&apos;t, your advance comes back.</span></div>
      )}
      {pending && (
        <ul className="steps3"><li className="d"><i>✓</i>Booking sent · advance {rs(b.advanceAmount)}</li><li><i>2</i>Owner confirms on WhatsApp</li><li><i>3</i>Pick up the car · owner&apos;s number shown here</li></ul>
      )}
      {confirmed && phone && (
        <div className="phoneBox"><div><div className="small muted">{b.driverPhone ? `Driver ${b.driverName ?? ''}` : "Owner's number"}</div><b>{local(phone)}</b></div><a className="btn dark" href={wa(phone)} target="_blank" rel="noopener noreferrer">WhatsApp</a></div>
      )}
      {refunded && <div className="msg ok">Advance refunded — {rs(b.advanceAmount)} comes back to you in full.</div>}
      <div className="money" style={{ marginTop: 10 }}>
        <div><span>Advance</span><span>{rs(b.advanceAmount)}</span></div>
        <div><span>Balance at pickup (cash to owner)</span><span>{rs(b.balanceDue)}</span></div>
        {b.securityDeposit > 0 && <div><span>Deposit (refundable)</span><span>{rs(b.securityDeposit)}</span></div>}
        {b.pickupPoint && <div><span>Pickup</span><span>{b.pickupPoint}</span></div>}
      </div>
      <div style={{ display: 'flex', gap: 10, marginTop: 14, flexWrap: 'wrap' }}>
        {(pending || b.status === 'Confirmed') && <button className="btn ghost" disabled={busy} onClick={cancel}>{busy ? 'Please wait…' : 'Cancel booking'}</button>}
        {!compact && <Link className="btn ghost" href="/account/?tab=myrentals">My rentals</Link>}
      </div>
    </div>
  );
}
