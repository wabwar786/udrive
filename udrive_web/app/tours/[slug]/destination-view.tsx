'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { Picture } from '@/components/Scene';
import { ToursList } from '@/components/ToursList';
import { WxDestination } from '@/components/Weather';
import { api, img } from '@/lib/api';
import type { Destination, Page, TourCard } from '@/lib/types';

/** A destination page. For '_' (added after the last build) the slug comes from the address. */
export function DestinationView({ slug, initialDestination, initialTours }: {
  slug: string;
  initialDestination: Destination | null;
  initialTours: Page<TourCard>;
}) {
  const [realSlug, setRealSlug] = useState(slug === '_' ? '' : slug);
  const [d, setD] = useState<Destination | null>(initialDestination);
  const [missing, setMissing] = useState(false);

  useEffect(() => {
    const s = slug === '_' ? decodeURIComponent(window.location.pathname.split('/').filter(Boolean)[1] ?? '') : slug;
    setRealSlug(s);
    api<Destination[]>('/api/v1/web/destinations')
      .then((list) => {
        const found = list.find((x) => x.slug === s) ?? null;
        setD(found);
        setMissing(!found);
        if (found) document.title = `${found.name} tours — dates, prices and seats | UDrive – Travel & Tour`;
      })
      .catch(() => undefined);
  }, [slug]);

  if (missing && !d) {
    return (
      <div style={{ padding: '60px 0' }}>
        <h1 style={{ fontSize: 32 }}>Place not found</h1>
        <p className="muted">We don&apos;t have tours listed for this place.</p>
        <Link className="btn dark" href="/tours/">See all tours</Link>
      </div>
    );
  }

  const name = d?.name ?? '';
  return (
    <>
      <div className="crumb"><Link href="/">Home</Link> / <Link href="/tours/">Tours</Link> / {name}</div>
      <div className="det" style={{ marginBottom: 36 }}>
        <div>
          <h1>{name ? `${name} tours` : 'Tours'}</h1>
          <p className="lead" style={{ marginBottom: 12 }}>{d?.summary || 'Tours with verified local drivers, per seat or the whole vehicle.'}</p>
          {d && (
            <div className="facts">
              <div><b>{d.district || 'Azad Kashmir'}</b>district</div>
              {d.bestSeason && <div><b>{d.bestSeason}</b>best season</div>}
              <div><b>{d.upcomingTours}</b>upcoming tours</div>
            </div>
          )}
          {d && <WxDestination name={d.name} district={d.district} lat={d.latitude} lng={d.longitude} />}
        </div>
        <div className="heroimg" style={{ height: 240 }}>
          <Picture src={img(d?.imageUrl)} alt={`${name || 'Mountains'}, Azad Kashmir`} seed={realSlug || 'x'} eager />
        </div>
      </div>
      <section className="sec">
        <div className="head"><h2>Upcoming departures</h2></div>
        {realSlug && <ToursList destination={realSlug} initial={initialTours} />}
      </section>
    </>
  );
}
