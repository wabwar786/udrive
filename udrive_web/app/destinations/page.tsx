import type { Metadata } from 'next';

import { JsonLd } from '@/components/JsonLd';
import { atBuild, img } from '@/lib/api';
import { SITE_URL } from '@/lib/config';
import type { Destination } from '@/lib/types';
import { DestinationsGrid } from './grid';

export const metadata: Metadata = {
  title: 'Places to visit in Azad Kashmir',
  description:
    'Lakes, meadows and river towns of Azad Kashmir — Neelum, Arang Kel, Ratti Gali, Leepa, Banjosa, Toli Pir and more, with the best season to go and tours with local drivers.',
  alternates: { canonical: '/destinations/' },
};

export default async function Page() {
  const list = await atBuild<Destination[]>('/api/v1/web/destinations', []);
  return (
    <div className="wrap">
      <JsonLd data={{
        '@context': 'https://schema.org',
        '@graph': [
          { '@type': 'BreadcrumbList', itemListElement: [
            { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE_URL}/` },
            { '@type': 'ListItem', position: 2, name: 'Destinations', item: `${SITE_URL}/destinations/` },
          ] },
          { '@type': 'ItemList', itemListElement: list.map((d, i) => ({
            '@type': 'ListItem', position: i + 1, url: `${SITE_URL}/tours/${d.slug}/`, name: d.name,
            ...(img(d.imageUrl) ? { image: img(d.imageUrl) } : {}),
          })) },
        ],
      }} />
      <div className="pagehead">
        <h1>Places to visit in Azad Kashmir</h1>
        <p className="muted" style={{ maxWidth: 680 }}>{list.length ? `${list.length} places` : 'Lakes, meadows and river towns'} — the best time to go, and tours with checked local drivers.</p>
      </div>
      <section className="sec"><DestinationsGrid initial={list} /></section>
    </div>
  );
}
