'use client';

import { useState } from 'react';

import { api } from '@/lib/api';
import { whatsappLink } from '@/lib/config';
import { rs, when } from '@/lib/format';
import type { BookingResult, TourDetail } from '@/lib/types';
import { OtpForm } from './OtpForm';

export function BookingPanel({ detail }: { detail: TourDetail }) {
  const t = detail.tour;
  const seatSale = t.pricePerSeat > 0 && t.seatsLeft > 0;
  const [mode, setMode] = useState<'seat' | 'whole'>(seatSale ? 'seat' : 'whole');
  const [seats, setSeats] = useState(Math.min(2, Math.max(1, t.seatsLeft)));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState<BookingResult | null>(null);

  const total = mode === 'whole' ? t.wholeVehiclePrice : t.pricePerSeat * seats;
  const advance = Math.ceil((total * detail.advancePercent) / 100);
  const canBook = mode === 'whole' ? t.wholeVehicleAvailable : seatSale;

  async function book(token: string, name: string) {
    setBusy(true);
    setError('');
    try {
      const r = await api<BookingResult>(`/api/v1/web/tours/${t.id}/book`, {
        method: 'POST',
        token,
        body: JSON.stringify({ mode, seats: mode === 'whole' ? t.totalSeats : seats, fullName: name }),
      });
      setDone(r);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  if (done) {
    return (
      <div className="panel done" role="status">
        <div className="big">✓</div>
        <h3>Booking received</h3>
        <p className="muted" style={{ margin: '0 0 14px' }}>Reference <b style={{ color: 'var(--ink)' }}>{done.reference}</b></p>
        <div className="sum" style={{ textAlign: 'left' }}>
          <div><span>{done.tour}</span><span>{done.mode === 'Whole vehicle' ? 'Whole vehicle' : `${done.seats} seats`}</span></div>
          <div><span>Departs</span><span>{when(done.departureAt)}</span></div>
          {done.pickupPoint && <div><span>Pickup</span><span>{done.pickupPoint}</span></div>}
          <div><span>Total</span><span>{rs(done.total)}</span></div>
          <div><span>Advance (20%)</span><span>{rs(done.advance)}</span></div>
          <div className="t"><span>Pay driver on the day</span><span>{rs(done.payDriverOnTheDay)}</span></div>
        </div>
        <p className="note">{done.driverName} will message you on WhatsApp to confirm, with the pickup point and how to send the advance. You also got the booking details on WhatsApp.</p>
        <a className="btn ghost block" href={whatsappLink(`Booking ${done.reference}`)} target="_blank" rel="noopener noreferrer" style={{ marginTop: 10 }}>Questions? WhatsApp UDrive</a>
      </div>
    );
  }

  return (
    <div className="panel">
      <div className="pr">
        {mode === 'whole' ? rs(t.wholeVehiclePrice) : rs(t.pricePerSeat)} <small>{mode === 'whole' ? `whole ${t.vehicle || 'vehicle'}` : 'per seat'}</small>
      </div>
      <div className="tabs" role="tablist">
        <button role="tab" aria-selected={mode === 'seat'} className={mode === 'seat' ? 'on' : ''} disabled={!seatSale} onClick={() => setMode('seat')}>Per seat</button>
        <button role="tab" aria-selected={mode === 'whole'} className={mode === 'whole' ? 'on' : ''} disabled={!t.wholeVehicleAvailable} onClick={() => setMode('whole')}>Whole vehicle</button>
      </div>
      {mode === 'seat' && (
        <div className="fld cnt">
          <div><span style={{ display: 'block', fontSize: 12, color: 'var(--soft)' }}>Seats</span><b>{seats}</b></div>
          <div>
            <button aria-label="One seat less" onClick={() => setSeats(Math.max(1, seats - 1))}>−</button>
            <button aria-label="One seat more" onClick={() => setSeats(Math.min(t.seatsLeft, seats + 1))}>+</button>
          </div>
        </div>
      )}
      <div className="sum">
        <div><span>{mode === 'whole' ? `Whole ${t.vehicle || 'vehicle'} · ${t.totalSeats} seats` : `${seats} × ${rs(t.pricePerSeat)}`}</span><span>{rs(total)}</span></div>
        <div><span>Advance ({detail.advancePercent}%) when the driver confirms</span><span>{rs(advance)}</span></div>
        <div className="t"><span>Pay driver on the day</span><span>{rs(total - advance)}</span></div>
      </div>
      {!canBook ? (
        <div className="msg info">This option is not available on this tour any more.</div>
      ) : (
        <OtpForm action={mode === 'whole' ? 'Book whole vehicle' : `Book ${seats} ${seats === 1 ? 'seat' : 'seats'}`} onVerified={book} busy={busy} />
      )}
      {error && <div className="msg err" role="alert">{error}</div>}
      <div className="note">We send a code to your WhatsApp to confirm it is you. The driver gets your booking in the UDrive app and confirms on WhatsApp. The final price is checked by UDrive when you book.</div>
    </div>
  );
}
