import Link from 'next/link';

import { img } from '@/lib/api';
import { daysLabel, rs, when } from '@/lib/format';
import type { HotelCard as Hotel, RentCar, TourCard as Tour } from '@/lib/types';
import { Picture } from './Scene';

export function TourCard({ t }: { t: Tour }) {
  const booked = Math.max(0, t.totalSeats - t.seatsLeft);
  const seatSale = t.pricePerSeat > 0;
  return (
    <Link href={`/tour/?id=${t.id}`} className="card">
      <div className="img">
        <Picture src={img(t.imageUrl)} alt={`${t.title} — ${t.destination}`} seed={t.destination} />
        <span className="when">{when(t.departureAt)}</span>
      </div>
      <div className="body">
        <h3>{t.title}</h3>
        <div className="meta">{t.from} → {t.destination} · {daysLabel(t.days)}</div>
        {seatSale && (
          <>
            <div className="seats"><i style={{ width: `${(booked / Math.max(1, t.totalSeats)) * 100}%` }} /></div>
            <div className="small muted">{t.seatsLeft} of {t.totalSeats} seats left</div>
          </>
        )}
        <div className="price">
          {seatSale ? (
            <>
              <small>from</small>
              <b>{rs(t.pricePerSeat)}</b>
              <small>per seat{t.wholeVehicleAvailable ? ` · or ${rs(t.wholeVehiclePrice)} whole ${t.vehicle || 'vehicle'}` : ''}</small>
            </>
          ) : (
            <>
              <small>whole {t.vehicle || 'vehicle'}</small>
              <b>{rs(t.wholeVehiclePrice)}</b>
              <small>{t.totalSeats} seats</small>
            </>
          )}
          <div className="driver">
            <span className="av">{t.driver.initials}</span>
            {t.driver.name}
            {t.driver.rating > 0 ? ` · ★ ${t.driver.rating.toFixed(1)}` : ' · new driver'}
          </div>
        </div>
      </div>
    </Link>
  );
}

export function HotelCard({ h, href }: { h: Hotel; href?: string }) {
  return (
    <Link href={href ?? `/hotels/${h.slug}/`} className="card">
      <div className="img" style={{ height: 190 }}>
        <Picture src={img(h.imageUrl)} alt={`${h.name}, ${h.city}`} seed={h.city + h.name} />
      </div>
      <div className="body">
        <h3>{h.name}</h3>
        <div className="meta">{h.propertyType} · {[h.city, h.district].filter(Boolean).join(', ')}</div>
        <div className="price row">
          <div>
            {h.startingRate > 0 ? (<><b style={{ fontSize: 16 }}>from {rs(h.startingRate)}</b><small>per night</small></>) : <small>Rates in the app</small>}
          </div>
          <span className="btn ghost" style={{ padding: '8px 14px' }}>See rooms</span>
        </div>
      </div>
    </Link>
  );
}

export function SkeletonGrid({ n = 4, cls = 'grid4' }: { n?: number; cls?: string }) {
  return <div className={cls}>{Array.from({ length: n }, (_, i) => <div key={i} className="skel" />)}</div>;
}

/** A car for rent. Booking happens in the UDrive app (deposit, handover photos). */
export function RentCard({ c }: { c: RentCar }) {
  const extras = [`${c.seats} seats`, c.airConditioning && 'AC', c.fourByFour && '4×4', c.pickupPoint].filter(Boolean).join(' · ');
  return (
    <div className="rc">
      <div className="im"><Picture src={img(c.photoUrl)} alt={`${c.name} ${c.year} for rent`} seed={c.name} /></div>
      <div className="bd">
        <b>{c.name} {c.year}</b>
        <div className="m">{extras}</div>
        <div className="p">
          <span>with driver<br /><strong>{c.withDriverDaily ? rs(c.withDriverDaily) : '—'}</strong>{c.withDriverDaily ? '/day' : ''}</span>
          <span style={{ textAlign: 'right' }}>self drive<br /><strong>{c.selfDriveDaily ? rs(c.selfDriveDaily) : '—'}</strong>{c.selfDriveDaily ? '/day' : ''}</span>
        </div>
        <div className="driver" style={{ marginTop: 8 }}>
          <span className="av">{c.ownerName.slice(0, 1)}</span>{c.ownerName}{c.ownerRating > 0 ? ` · ★ ${c.ownerRating.toFixed(1)}` : ' · new owner'}
          {c.minimumDays > 1 ? ` · min ${c.minimumDays} days` : ''}
        </div>
      </div>
    </div>
  );
}
