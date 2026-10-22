'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';

import { AdSlot } from '@/components/AdSlot';
import { BookingPanel } from '@/components/BookingPanel';
import { JsonLd } from '@/components/JsonLd';
import { Picture } from '@/components/Scene';
import { api, img } from '@/lib/api';
import { SITE_URL } from '@/lib/config';
import { daysLabel, longDate, time } from '@/lib/format';
import type { TourDetail } from '@/lib/types';

export function TourView() {
  const id = useSearchParams()?.get('id') ?? '';
  const [d, setD] = useState<TourDetail | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!/^[0-9a-f-]{36}$/i.test(id)) {
      setError('This tour link is not complete.');
      return;
    }
    api<TourDetail>(`/api/v1/web/tours/${id}`)
      .then((x) => { setD(x); document.title = `${x.tour.title} — ${x.tour.destination} | UDrive`; })
      .catch((e) => setError(e.message));
  }, [id]);

  if (error) {
    return (
      <div className="wrap" style={{ padding: '60px 0' }}>
        <h1 style={{ fontSize: 32 }}>Tour not available</h1>
        <p className="muted">{error}</p>
        <Link className="btn dark" href="/tours/">See open tours</Link>
      </div>
    );
  }
  if (!d) return <div className="wrap" style={{ padding: '40px 0' }}><div className="skel" style={{ height: 420 }} /></div>;

  const t = d.tour;
  const photos = d.images.map(img).filter(Boolean) as string[];
  const gal = photos.length ? photos.slice(0, 5) : [];

  return (
    <div className="wrap">
      <JsonLd data={{
        '@context': 'https://schema.org', '@type': 'TouristTrip', name: t.title, description: d.description ?? undefined,
        url: `${SITE_URL}/tour/?id=${t.id}`, ...(gal[0] ? { image: gal } : {}),
        itinerary: { '@type': 'ItemList', itemListElement: d.plan.map((p, i) => ({ '@type': 'ListItem', position: i + 1, name: p.title })) },
        offers: { '@type': 'Offer', priceCurrency: 'PKR', price: t.pricePerSeat > 0 ? t.pricePerSeat : t.wholeVehiclePrice, availability: 'https://schema.org/InStock' },
        provider: { '@id': `${SITE_URL}/#org` },
      }} />
      <div className="crumb">
        <Link href="/tours/">Tours</Link>
        {t.destinationSlug && <> / <Link href={`/tours/${t.destinationSlug}/`}>{t.destination}</Link></>} / {t.title}
      </div>
      <div className={`gal ${gal.length <= 1 ? 'one' : ''}`}>
        {gal.length <= 1 ? <Picture src={gal[0] ?? null} alt={t.title} seed={t.destination} eager /> : gal.map((src, i) => (
          // eslint-disable-next-line @next/next/no-img-element
          <img key={src} src={src} alt={`${t.title} photo ${i + 1}`} loading={i === 0 ? 'eager' : 'lazy'} />
        ))}
      </div>
      <div className="det">
        <div>
          <h1>{t.title}</h1>
          <div className="muted" style={{ fontSize: 16 }}>{[t.from, ...d.routeStops, t.destination].filter(Boolean).join(' → ')}</div>
          <div className="facts">
            <div><b>{longDate(t.departureAt)}</b>departs {time(t.departureAt)}</div>
            <div><b>{t.vehicle || 'Vehicle'}</b>{t.totalSeats} seats</div>
            <div><b>{daysLabel(t.days)}</b>trip</div>
            {t.pricePerSeat > 0 && <div><b>{t.seatsLeft} seats left</b>of {t.totalSeats}</div>}
            {t.pickupPoint && <div><b>Pickup</b>{t.pickupPoint}</div>}
          </div>
          {d.description && <p className="prose">{d.description}</p>}
          {d.plan.length > 0 && (<>
            <h4>Plan</h4>
            {d.plan.map((p) => (
              <div className="day" key={p.day}><em>Day {p.day}</em><div><b>{p.title}</b>{p.text && <p>{p.text}</p>}</div></div>
            ))}
          </>)}
          {(d.included.length > 0 || d.notIncluded.length > 0) && (<>
            <h4>Included</h4>
            <ul className="ticks inc">
              {d.included.map((x) => <li key={x}>{x}</li>)}
              {d.notIncluded.map((x) => <li key={x} className="no">{x} — not included</li>)}
            </ul>
          </>)}
          {(d.familyOnly || d.womenOnly || d.luggage || d.cancellationPolicy) && (<>
            <h4>Good to know</h4>
            <ul className="ticks">
              {d.familyOnly && <li>Families only</li>}
              {d.womenOnly && <li>Women only</li>}
              {d.luggage && <li>Luggage: {d.luggage}</li>}
              {d.cancellationPolicy && <li>Cancellation: {d.cancellationPolicy}</li>}
              <li>{d.passengerPolicy}</li>
            </ul>
          </>)}
          <h4>Your driver</h4>
          <div className="drv">
            <span className="av">{t.driver.initials}</span>
            <div>
              <b>{t.driver.name}</b>
              <div className="small muted">
                {t.driver.rating > 0 ? `★ ${t.driver.rating.toFixed(1)} · ` : ''}{t.driver.toursDone > 0 ? `${t.driver.toursDone} tours on UDrive · ` : ''}licence verified by UDrive
              </div>
            </div>
          </div>
        </div>
        <div className="side">
          <BookingPanel detail={d} />
          <AdSlot slot="tour" variant="side" />
        </div>
      </div>
    </div>
  );
}
