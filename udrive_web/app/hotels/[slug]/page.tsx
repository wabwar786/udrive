import type { Metadata } from 'next';

import { JsonLd } from '@/components/JsonLd';
import { atBuild, img } from '@/lib/api';
import { SITE_URL } from '@/lib/config';
import type { HotelDetail, Sitemap } from '@/lib/types';
import { HotelView } from './hotel-view';

export const dynamicParams = false;

const sitemap = () => atBuild<Sitemap>('/api/v1/web/sitemap', { destinations: [], hotels: [], generatedAt: '' });

// One static page per listed hotel, plus '_' — the shell Caddy serves for a
// hotel listed after this build, which loads it live from the address.
export async function generateStaticParams() {
  const s = await sitemap();
  return [...s.hotels.map((h) => ({ slug: h.slug })), { slug: '_' }];
}

type Props = { params: Promise<{ slug: string }> };

async function detail(slug: string) {
  if (slug === '_') return null;
  return atBuild<HotelDetail | null>(`/api/v1/web/hotels/by-slug/${encodeURIComponent(slug)}`, null);
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const d = await detail(slug);
  if (!d) return { title: 'Hotel', robots: { index: false, follow: true } };
  const h = d.hotel;
  const description = `${h.name} — ${h.propertyType.toLowerCase()} in ${[h.city, h.district].filter(Boolean).join(', ')}. ${d.description}`.slice(0, 300);
  const photo = img(d.photos[0]);
  return {
    title: `${h.name}, ${h.city} — rooms and rates`,
    description,
    alternates: { canonical: `/hotels/${slug}/` },
    openGraph: { title: `${h.name}, ${h.city}`, description, url: `/hotels/${slug}/`, ...(photo ? { images: [photo] } : {}) },
  };
}

export default async function Page({ params }: Props) {
  const { slug } = await params;
  const d = await detail(slug);
  return (
    <div className="wrap">
      {d && (
        <JsonLd data={{
          '@context': 'https://schema.org',
          '@graph': [
            {
              '@type': d.hotel.propertyType === 'Guest house' ? 'BedAndBreakfast' : 'Hotel',
              name: d.hotel.name,
              description: d.description || undefined,
              url: `${SITE_URL}/hotels/${slug}/`,
              image: d.photos.map(img).filter(Boolean),
              address: { '@type': 'PostalAddress', streetAddress: d.address || undefined, addressLocality: d.hotel.city, addressRegion: d.hotel.district, addressCountry: 'PK' },
              ...(d.latitude && d.longitude ? { geo: { '@type': 'GeoCoordinates', latitude: d.latitude, longitude: d.longitude } } : {}),
              ...(d.hotel.startingRate > 0 ? { priceRange: `From PKR ${Math.round(d.hotel.startingRate)} per night` } : {}),
              amenityFeature: d.amenities.map((a) => ({ '@type': 'LocationFeatureSpecification', name: a, value: true })),
              ...(d.checkInTime ? { checkinTime: d.checkInTime } : {}),
              ...(d.checkOutTime ? { checkoutTime: d.checkOutTime } : {}),
            },
            {
              '@type': 'BreadcrumbList',
              itemListElement: [
                { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE_URL}/` },
                { '@type': 'ListItem', position: 2, name: 'Hotels', item: `${SITE_URL}/hotels/` },
                { '@type': 'ListItem', position: 3, name: d.hotel.name, item: `${SITE_URL}/hotels/${slug}/` },
              ],
            },
          ],
        }} />
      )}
      <HotelView slug={slug} initial={d} />
    </div>
  );
}
