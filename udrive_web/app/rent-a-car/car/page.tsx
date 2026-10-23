import type { Metadata } from 'next';
import { Suspense } from 'react';

import { CarView } from './car-view';

// One shell page for every car (/rent-a-car/car/?id=…). The cars themselves are
// listed on /rent-a-car/, which is what search engines index.
export const metadata: Metadata = {
  title: 'Book a car',
  alternates: { canonical: '/rent-a-car/' },
  robots: { index: false, follow: true },
};

export default function Page() {
  return <Suspense><CarView /></Suspense>;
}
