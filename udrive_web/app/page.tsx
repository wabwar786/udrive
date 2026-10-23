import { atBuild } from '@/lib/api';
import { EMPTY_HOME, type Home, type RentCar } from '@/lib/types';
import { HomeView } from './home-view';

export const metadata = { alternates: { canonical: '/' } };

/** Built with a snapshot (what search engines read), then refreshed live in the browser. */
export default async function Page() {
  const [home, cars] = await Promise.all([
    atBuild<Home>('/api/v1/web/home', EMPTY_HOME),
    atBuild<RentCar[]>('/api/v1/web/rent-cars', []),
  ]);
  return <HomeView initial={home} initialCars={cars} />;
}
