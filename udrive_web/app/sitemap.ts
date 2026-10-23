import type { MetadataRoute } from 'next';

import { atBuild } from '@/lib/api';
import { SITE_URL } from '@/lib/config';
import type { Sitemap } from '@/lib/types';

export const dynamic = 'force-static';

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const now = new Date();
  const s = await atBuild<Sitemap>('/api/v1/web/sitemap', { destinations: [], hotels: [], generatedAt: '' });
  const page = (path: string, priority: number, changeFrequency: 'hourly' | 'daily' | 'weekly' | 'monthly') =>
    ({ url: `${SITE_URL}${path}`, lastModified: now, changeFrequency, priority });
  return [
    page('/', 1, 'daily'),
    page('/tours/', 0.9, 'daily'),
    page('/rent-a-car/', 0.9, 'daily'),
    page('/destinations/', 0.9, 'weekly'),
    page('/weather/', 0.9, 'hourly'),
    page('/hotels/', 0.8, 'daily'),
    page('/partner/', 0.7, 'monthly'),
    ...s.destinations.map((d) => page(`/tours/${d.slug}/`, d.upcomingTours > 0 ? 0.8 : 0.5, 'daily')),
    ...s.hotels.map((h) => page(`/hotels/${h.slug}/`, 0.7, 'weekly')),
    page('/list-your-hotel/', 0.6, 'monthly'),
    page('/rides/', 0.5, 'monthly'),
    page('/drive/', 0.5, 'monthly'),
    page('/about/', 0.3, 'monthly'),
  ];
}
