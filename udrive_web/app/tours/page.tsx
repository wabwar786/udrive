import type { Metadata } from 'next';
import Link from 'next/link';
import { Suspense } from 'react';

import { JsonLd } from '@/components/JsonLd';
import { ToursList } from '@/components/ToursList';
import { atBuild } from '@/lib/api';
import { SITE_URL } from '@/lib/config';
import type { Destination, Page, TourCard } from '@/lib/types';

export const metadata: Metadata = {
  title: 'Tour packages in Azad Kashmir',
  description:
    'Upcoming tours from Muzaffarabad and across Azad Kashmir — Neelum, Leepa, Banjosa, Pir Chinasi and more. Book a seat or the whole vehicle with a verified local driver.',
  alternates: { canonical: '/tours/' },
};

export default async function Page() {
  const [first, destinations] = await Promise.all([
    atBuild<Page<TourCard>>('/api/v1/web/tours', { items: [], page: 1, hasMore: false }),
    atBuild<Destination[]>('/api/v1/web/destinations', []),
  ]);
  return (
    <div className="wrap">
      <JsonLd data={{
        '@context': 'https://schema.org', '@type': 'BreadcrumbList',
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE_URL}/` },
          { '@type': 'ListItem', position: 2, name: 'Tours', item: `${SITE_URL}/tours/` },
        ],
      }} />
      <div className="pagehead">
        <h1>Tour packages</h1>
        <p className="muted">Fixed dates, fixed prices, verified drivers. Per seat or the whole vehicle — you pay 20% when the driver confirms.</p>
      </div>
      {destinations.length > 0 && (
        <nav className="dest" aria-label="Destinations" style={{ marginBottom: 26 }}>
          {destinations.filter((d) => d.upcomingTours > 0).slice(0, 12).map((d) => (
            <Link key={d.slug} href={`/tours/${d.slug}/`}><b>{d.name}</b><span>{d.upcomingTours} upcoming</span></Link>
          ))}
        </nav>
      )}
      <section className="sec">
        <Suspense><ToursList initial={first} /></Suspense>
      </section>
    </div>
  );
}
