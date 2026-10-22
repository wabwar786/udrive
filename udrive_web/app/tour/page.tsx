import type { Metadata } from 'next';
import { Suspense } from 'react';

import { TourView } from './tour-view';

// One page for every departure, filled in the browser. Departures expire
// within days, so these are kept out of search results; the destination pages
// (/tours/<place>/) are the ones that rank.
export const metadata: Metadata = {
  title: 'Tour details and booking',
  robots: { index: false, follow: true },
  alternates: { canonical: '/tours/' },
};

export default function Page() {
  return <Suspense><TourView /></Suspense>;
}
