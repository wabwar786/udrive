'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { AdSlot } from '@/components/AdSlot';
import { PlayButton } from '@/components/PlayButton';
import { Picture } from '@/components/Scene';
import { api, img } from '@/lib/api';
import { rs } from '@/lib/format';
import type { HotelDetail } from '@/lib/types';

export function HotelView({ slug, initial }: { slug: string; initial: HotelDetail | null }) {
  const [d, setD] = useState<HotelDetail | null>(initial);
  const [gone, setGone] = useState(false);

  useEffect(() => {
    const s = slug === '_' ? decodeURIComponent(window.location.pathname.split('/').filter(Boolean)[1] ?? '') : slug;
    api<HotelDetail>(`/api/v1/web/hotels/by-slug/${encodeURIComponent(s)}`)
      .then((x) => { setD(x); document.title = `${x.hotel.name}, ${x.hotel.city} — rooms and rates | UDrive – Travel & Tour`; })
      .catch(() => setGone(true));
  }, [slug]);

  if (gone && !d) {
    return (
      <div style={{ padding: '60px 0' }}>
        <h1 style={{ fontSize: 32 }}>Hotel not listed right now</h1>
        <p className="muted">It may be full or taking a break from bookings.</p>
        <Link className="btn dark" href="/hotels/">See other hotels</Link>
      </div>
    );
  }
  if (!d) return <div style={{ padding: '40px 0' }}><div className="skel" style={{ height: 420 }} /></div>;

  const h = d.hotel;
  const photos = d.photos.map(img).filter(Boolean) as string[];
  return (
    <>
      <div className="crumb"><Link href="/">Home</Link> / <Link href="/hotels/">Hotels</Link> / {h.name}</div>
      <div className={`gal ${photos.length <= 1 ? 'one' : ''}`}>
        {photos.length <= 1 ? <Picture src={photos[0] ?? null} alt={h.name} seed={h.city + h.name} eager /> : photos.slice(0, 5).map((src, i) => (
          // eslint-disable-next-line @next/next/no-img-element
          <img key={src} src={src} alt={`${h.name} photo ${i + 1}`} loading={i === 0 ? 'eager' : 'lazy'} />
        ))}
      </div>
      <div className="det">
        <div>
          <h1>{h.name}</h1>
          <div className="muted" style={{ fontSize: 16 }}>{h.propertyType} · {[d.address, h.city, h.district].filter(Boolean).join(', ')}</div>
          <div className="facts">
            {h.startingRate > 0 && <div><b>from {rs(h.startingRate)}</b>per night</div>}
            {d.checkInTime && <div><b>{d.checkInTime}</b>check-in</div>}
            {d.checkOutTime && <div><b>{d.checkOutTime}</b>check-out</div>}
            {d.transportAvailable && <div><b>Pickup available</b>ask the hotel</div>}
          </div>
          {d.description && <p className="prose">{d.description}</p>}
          {d.rooms.length > 0 && (<>
            <h4>Rooms</h4>
            <div className="hotelRooms">
              {d.rooms.map((r) => (
                <div className="r" key={r.roomType + r.rate}>
                  <div><b>{r.roomType}</b><p>{r.description || `Up to ${r.capacity} guests`}</p></div>
                  <div style={{ textAlign: 'right' }}><b>{rs(r.rate)}</b><p>per night · {r.capacity} guests</p></div>
                </div>
              ))}
            </div>
          </>)}
          {d.amenities.length > 0 && (<><h4>Facilities</h4><ul className="ticks inc">{d.amenities.map((a) => <li key={a}>{a}</li>)}</ul></>)}
          {d.latitude && d.longitude && (
            <p style={{ marginTop: 24 }}>
              <a className="link" href={`https://www.google.com/maps/search/?api=1&query=${d.latitude},${d.longitude}`} target="_blank" rel="noopener noreferrer">Open in Google Maps</a>
            </p>
          )}
        </div>
        <div className="side">
          <div className="panel">
            <div className="pr">{h.startingRate > 0 ? <>{rs(h.startingRate)} <small>per night</small></> : 'Rooms and rates'}</div>
            <p className="muted" style={{ fontSize: 14.5, lineHeight: 1.55 }}>
              Book this hotel in the UDrive app — choose your dates and room, and the hotel confirms on WhatsApp. You can add a UDrive ride to get there.
            </p>
            <PlayButton />
          </div>
          <AdSlot slot="hotel" variant="side" />
        </div>
      </div>
    </>
  );
}
