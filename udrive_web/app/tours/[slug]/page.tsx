import type { Metadata } from 'next';
import { Suspense } from 'react';

import { JsonLd } from '@/components/JsonLd';
import { atBuild, img } from '@/lib/api';
import { SITE_URL } from '@/lib/config';
import type { Destination, Page as P, TourCard } from '@/lib/types';
import { DestinationView } from './destination-view';

export const dynamicParams = false;

// One static page per destination (what search engines index). The list of
// tours on it is refreshed live in the browser. New destinations get a page
// on the next deploy; until then they are reachable from /tours/.
async function destinations() {
  return atBuild<Destination[]>('/api/v1/web/destinations', []);
}

export async function generateStaticParams() {
  const list = await destinations();
  // '_' is the shell Caddy serves for a destination added after this build:
  // it reads the real name from the address and loads it live.
  return [...list.map((d) => ({ slug: d.slug })), { slug: '_' }];
}

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const d = (await destinations()).find((x) => x.slug === slug);
  const name = d?.name ?? 'Azad Kashmir';
  const description = d
    ? `${name} tours with verified local drivers — dates, prices and seats left. ${d.summary}`.slice(0, 300)
    : 'Tours across Azad Kashmir with verified local drivers.';
  if (slug === '_') return { title: 'Tours', robots: { index: false, follow: true } };
  return {
    title: `${name} tours — dates, prices and seats`,
    description,
    alternates: { canonical: `/tours/${slug}/` },
    openGraph: { title: `${name} tours | UDrive`, description, url: `/tours/${slug}/`, ...(img(d?.imageUrl) ? { images: [img(d?.imageUrl)!] } : {}) },
  };
}

export default async function Page({ params }: Props) {
  const { slug } = await params;
  const d = (await destinations()).find((x) => x.slug === slug);
  const first = d
    ? await atBuild<P<TourCard>>(`/api/v1/web/tours?destination=${encodeURIComponent(slug)}`, { items: [], page: 1, hasMore: false })
    : { items: [], page: 1, hasMore: false };
  const name = d?.name ?? 'Azad Kashmir';

  return (
    <div className="wrap">
      {d && <JsonLd data={{
        '@context': 'https://schema.org',
        '@graph': [
          {
            '@type': 'TouristDestination',
            name,
            description: d?.summary,
            url: `${SITE_URL}/tours/${slug}/`,
            ...(img(d?.imageUrl) ? { image: img(d?.imageUrl) } : {}),
            containedInPlace: { '@type': 'AdministrativeArea', name: d?.district || 'Azad Jammu and Kashmir' },
          },
          {
            '@type': 'BreadcrumbList',
            itemListElement: [
              { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE_URL}/` },
              { '@type': 'ListItem', position: 2, name: 'Tours', item: `${SITE_URL}/tours/` },
              { '@type': 'ListItem', position: 3, name, item: `${SITE_URL}/tours/${slug}/` },
            ],
          },
          ...(first.items.length ? [{
            '@type': 'ItemList',
            itemListElement: first.items.slice(0, 10).map((t, i) => ({
              '@type': 'ListItem', position: i + 1,
              item: {
                '@type': 'TouristTrip', name: t.title, url: `${SITE_URL}/tour/?id=${t.id}`,
                itinerary: { '@type': 'Place', name: t.destination },
                offers: { '@type': 'Offer', priceCurrency: 'PKR', price: t.pricePerSeat > 0 ? t.pricePerSeat : t.wholeVehiclePrice, availability: 'https://schema.org/InStock', validFrom: new Date().toISOString() },
              },
            })),
          }] : []),
        ],
      }} />}
      <Suspense><DestinationView slug={slug} initialDestination={d ?? null} initialTours={first} /></Suspense>
    </div>
  );
}
