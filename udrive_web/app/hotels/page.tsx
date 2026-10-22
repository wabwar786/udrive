import type { Metadata } from 'next';

import { atBuild } from '@/lib/api';
import type { HotelCard, Page as P } from '@/lib/types';
import { HotelsView } from './hotels-view';

export const metadata: Metadata = {
  title: 'Hotels and guest houses in Azad Kashmir',
  description: 'Hotels, guest houses and huts in Muzaffarabad, Neelum, Rawalakot and across Azad Kashmir — listed by their owners on UDrive.',
  alternates: { canonical: '/hotels/' },
};

export default async function Page() {
  const first = await atBuild<P<HotelCard>>('/api/v1/web/hotels', { items: [], page: 1, hasMore: false });
  return (
    <div className="wrap">
      <div className="pagehead">
        <h1>Places to stay</h1>
        <p className="muted">Hotels and guest houses listed by their owners. See rooms and rates, then book in the UDrive app.</p>
      </div>
      <HotelsView initial={first} />
    </div>
  );
}
