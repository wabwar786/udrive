import type { Metadata } from 'next';

import { JsonLd } from '@/components/JsonLd';
import { atBuild } from '@/lib/api';
import { SITE_URL } from '@/lib/config';
import { EMPTY_WEATHER, type Weather } from '@/lib/types';
import { WeatherView } from './weather-view';

export const metadata: Metadata = {
  title: 'Azad Kashmir weather today — Neelum, Leepa, Banjosa, Rawalakot',
  description:
    'Weather now and for the next 3 days in every tehsil and tourist spot of Azad Kashmir — Arang Kel, Keran, Sharda, Leepa, Banjosa, Toli Pir — with snow, rain, wind and road updates before you travel.',
  alternates: { canonical: '/weather/' },
  openGraph: { title: 'Azad Kashmir weather today | UDrive', url: '/weather/' },
};

export default async function Page() {
  const w = await atBuild<Weather>('/api/v1/web/weather', EMPTY_WEATHER);
  return (
    <>
      <JsonLd data={{
        '@context': 'https://schema.org',
        '@type': 'BreadcrumbList',
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE_URL}/` },
          { '@type': 'ListItem', position: 2, name: 'Weather', item: `${SITE_URL}/weather/` },
        ],
      }} />
      <WeatherView initial={w} />
    </>
  );
}
