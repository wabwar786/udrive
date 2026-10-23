'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';

import { AdSlot } from '@/components/AdSlot';
import { HotelCard, RentCard, SkeletonGrid, TourCard } from '@/components/Cards';
import { HeroSlides, type Slide } from '@/components/HeroSlides';
import { PlayButton } from '@/components/PlayButton';
import { api, img } from '@/lib/api';
import { whatsappLink } from '@/lib/config';
import type { Home, RentCar } from '@/lib/types';
import { DestinationsGrid } from './destinations/grid';

const POPULAR = ['Keran · 2 days', 'Sharda & Kel · 3 days', 'Arang Kel · 4 days', 'Ratti Gali · 4 days', 'Leepa · 2 days', 'Pir Chinasi · half day', 'Banjosa & Toli Pir · 1 day'];
const HOTEL_CITIES = ['Muzaffarabad', 'Neelum', 'Rawalakot', 'Bagh', 'Kotli', 'Mirpur', 'Leepa'];
type Tab = 'tours' | 'rent' | 'hotels';

export function HomeView({ initial, initialCars }: { initial: Home; initialCars: RentCar[] }) {
  const [home, setHome] = useState(initial);
  const [cars, setCars] = useState(initialCars);
  const [loaded, setLoaded] = useState(initial.destinations.length > 0);
  const router = useRouter();
  const [tab, setTab] = useState<Tab>('tours');
  const [q, setQ] = useState({ dest: '', date: '', people: '2', mode: '', category: '', city: '' });
  const [plan, setPlan] = useState({ to: '', date: '', people: '4', days: '2' });

  useEffect(() => {
    api<Home>('/api/v1/web/home').then(setHome).catch(() => undefined).finally(() => setLoaded(true));
    api<RentCar[]>('/api/v1/web/rent-cars').then(setCars).catch(() => undefined);
  }, []);

  const s = home.stats;
  const districts = new Set(home.destinations.map((d) => d.district).filter(Boolean)).size;
  // Hero: one photo per place, real photos first.
  const slides: Slide[] = useMemo(() => {
    const seen = new Set<string>();
    const out: Slide[] = [];
    for (const d of home.destinations) {
      const src = img(d.imageUrl);
      if (!src || seen.has(src)) continue;
      seen.add(src);
      out.push({ src, name: d.name, district: d.district });
      if (out.length === 6) break;
    }
    return out.length ? out : [{ src: null, name: 'Arang Kel', district: 'Neelum' }, { src: null, name: 'Banjosa Lake', district: 'Poonch' }, { src: null, name: 'Ratti Gali Lake', district: 'Neelum' }];
  }, [home.destinations]);

  function search(e: React.FormEvent) {
    e.preventDefault();
    if (tab === 'rent') {
      const p = new URLSearchParams();
      if (q.mode) p.set('mode', q.mode);
      if (q.category) p.set('category', q.category);
      return router.push(`/rent-a-car/?${p}`);
    }
    if (tab === 'hotels') return router.push(q.city ? `/hotels/?city=${encodeURIComponent(q.city)}` : '/hotels/');
    const p = new URLSearchParams();
    if (q.date) p.set('date', q.date);
    if (q.people) p.set('seats', q.people);
    router.push(q.dest ? `/tours/${q.dest}/?${p}` : `/tours/?${p}`);
  }

  const planText = `Assalam o Alaikum UDrive, I want a trip.\nTo: ${plan.to || 'not sure yet'}\nDate: ${plan.date || 'flexible'}\nPeople: ${plan.people}\nDays: ${plan.days}`;

  return (
    <>
      <div className="wrap">
        <section className="h2">
          <div>
            <span className="eyebrow">Azad Kashmir · Muzaffarabad first</span>
            <h1>Tours, cars and stays across Azad Kashmir.</h1>
            <p className="lead">Local drivers and owners, checked by UDrive. Book a tour seat, rent a car by the day, or find a room on the way.</p>
            <div className="stabs" role="tablist" aria-label="Search">
              {([['tours', 'Tours'], ['rent', 'Rent a car'], ['hotels', 'Hotels']] as const).map(([k, l]) => (
                <button key={k} role="tab" aria-selected={tab === k} className={tab === k ? 'on' : ''} onClick={() => setTab(k)}>{l}</button>
              ))}
            </div>
            <form className="search tabbed" onSubmit={search} role="search">
              {tab === 'tours' && (
                <>
                  <label>Where to
                    <select value={q.dest} onChange={(e) => setQ({ ...q, dest: e.target.value })}>
                      <option value="">Anywhere</option>
                      {home.destinations.map((d) => <option key={d.slug} value={d.slug}>{d.name}</option>)}
                    </select>
                  </label>
                  <label>When<input type="date" value={q.date} onChange={(e) => setQ({ ...q, date: e.target.value })} /></label>
                  <label>People
                    <select value={q.people} onChange={(e) => setQ({ ...q, people: e.target.value })}>
                      {[1, 2, 3, 4, 5, 6, 8, 10, 12].map((n) => <option key={n} value={n}>{n} {n === 1 ? 'person' : 'people'}</option>)}
                    </select>
                  </label>
                </>
              )}
              {tab === 'rent' && (
                <>
                  <label>Vehicle
                    <select value={q.category} onChange={(e) => setQ({ ...q, category: e.target.value })}>
                      <option value="">Any</option><option value="car">Car</option><option value="jeep">Jeep / 4×4</option><option value="hiace">Hiace</option><option value="coster">Coaster</option>
                    </select>
                  </label>
                  <label>Driver
                    <select value={q.mode} onChange={(e) => setQ({ ...q, mode: e.target.value })}>
                      <option value="">With or without</option><option value="WithDriver">With driver</option><option value="SelfDrive">Self drive</option>
                    </select>
                  </label>
                  <label>From<input type="date" value={q.date} onChange={(e) => setQ({ ...q, date: e.target.value })} /></label>
                </>
              )}
              {tab === 'hotels' && (
                <>
                  <label style={{ gridColumn: 'span 2' }}>City / area
                    <select value={q.city} onChange={(e) => setQ({ ...q, city: e.target.value })}>
                      <option value="">Anywhere</option>{HOTEL_CITIES.map((c) => <option key={c}>{c}</option>)}
                    </select>
                  </label>
                  <label>Check-in<input type="date" value={q.date} onChange={(e) => setQ({ ...q, date: e.target.value })} /></label>
                </>
              )}
              <div className="go"><button className="btn dark" type="submit">Search</button></div>
            </form>
          </div>
          <HeroSlides slides={slides} />
        </section>

        <div className="strip">
          {home.destinations.length > 0 && <span><b>{home.destinations.length}</b>destinations</span>}
          {districts > 0 && <span><b>{districts}</b>districts</span>}
          {s.verifiedDrivers > 0 && <span><b>{s.verifiedDrivers}</b>verified drivers</span>}
          {s.hotels > 0 && <span><b>{s.hotels}</b>{s.hotels === 1 ? 'hotel' : 'hotels'}</span>}
          <span><b>✓</b>WhatsApp confirmation</span>
          <span><b>20%</b>advance only</span>
        </div>

        <section className="sec" aria-labelledby="dest-h">
          <div className="head">
            <div><h2 id="dest-h">Explore Azad Kashmir</h2><p className="muted">Lakes, meadows and river towns — pick a place and we&apos;ll find you a driver.</p></div>
            <Link className="link" href="/destinations/">All {home.destinations.length || ''} places</Link>
          </div>
          {!loaded ? <SkeletonGrid /> : <DestinationsGrid initial={home.destinations} limit={8} />}
        </section>

        <section className="sec" aria-labelledby="rent-h">
          <div className="head">
            <div><h2 id="rent-h">Rent a car</h2><p className="muted">By the day, with or without driver — from owners on UDrive.</p></div>
            <Link className="link" href="/rent-a-car/">All cars</Link>
          </div>
          <div className="rent">
            {cars.slice(0, 3).map((c) => <RentCard key={c.id} c={c} />)}
            <div className="addc"><b>Have a car?</b><p>Rent it out by the day. Add as many vehicles as you own from your UDrive account.</p><Link className="btn dark" href="/account/">List your car</Link></div>
          </div>
        </section>

        <section className="sec" aria-labelledby="tours-h">
          <div className="head">
            <div><h2 id="tours-h">Tours</h2><p className="muted">{home.tours.length ? 'Live from the UDrive app — seats update as people book.' : 'Fixed-date tours appear here as drivers post them.'}</p></div>
            <Link className="link" href="/tours/">All tours</Link>
          </div>
          {home.tours.length > 0 ? (
            <div className="grid4">{home.tours.slice(0, 8).map((t) => <TourCard key={t.id} t={t} />)}</div>
          ) : (
            <div className="plan">
              <div className="l">
                <h3 style={{ fontSize: 21, marginBottom: 6 }}>No fixed tour on your date? Tell us your plan.</h3>
                <p className="muted" style={{ margin: '0 0 16px' }}>We&apos;ll match you with a checked local driver on WhatsApp.</p>
                <div className="form2">
                  <label className="fld"><span>Where to</span><select value={plan.to} onChange={(e) => setPlan({ ...plan, to: e.target.value })}><option value="">Not sure yet</option>{home.destinations.map((d) => <option key={d.slug}>{d.name}</option>)}</select></label>
                  <label className="fld"><span>When</span><input type="date" value={plan.date} onChange={(e) => setPlan({ ...plan, date: e.target.value })} /></label>
                  <label className="fld"><span>People</span><select value={plan.people} onChange={(e) => setPlan({ ...plan, people: e.target.value })}>{[1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20].map((n) => <option key={n}>{n}</option>)}</select></label>
                  <label className="fld"><span>Days</span><select value={plan.days} onChange={(e) => setPlan({ ...plan, days: e.target.value })}>{['Half day', '1', '2', '3', '4', '5', '6', '7'].map((n) => <option key={n}>{n}</option>)}</select></label>
                </div>
                <a className="btn dark" href={whatsappLink(planText)} target="_blank" rel="noopener noreferrer">Send on WhatsApp</a>
              </div>
              <div className="r">
                <b>Popular trips from Muzaffarabad</b>
                <div className="routes">{POPULAR.map((p) => <button key={p} type="button" onClick={() => setPlan({ ...plan, to: home.destinations.find((d) => p.startsWith(d.name.split(' ')[0]))?.name ?? plan.to, days: p.includes('half') ? 'Half day' : p.match(/(\d) day/)?.[1] ?? plan.days })}>{p}</button>)}</div>
                <p className="small muted" style={{ marginTop: 16 }}>When drivers post fixed departures, they show here with dates, seats left and price per seat.</p>
              </div>
            </div>
          )}
        </section>

        <AdSlot slot="home" initial={home.ads} />

        <section className="sec" aria-labelledby="hotels-h">
          <div className="head">
            <div><h2 id="hotels-h">Places to stay</h2><p className="muted">Hotels listed by their owners on UDrive.</p></div>
            <Link className="link" href="/hotels/">All hotels</Link>
          </div>
          <div className="grid4">
            {home.hotels.slice(0, 3).map((h) => <HotelCard key={h.id} h={h} />)}
            <div className="addc"><b>Own a hotel?</b><p>List it free, set your own rates any time, bookings on WhatsApp.</p><Link className="btn dark" href="/list-your-hotel/">List your hotel</Link></div>
          </div>
        </section>

        <section className="sec owner">
          <div className="ob">
            <h3>List your vehicle or hotel</h3>
            <p>One UDrive account for everything — cars for rent, tour vehicles and hotels. Log in with your WhatsApp number.</p>
            <ul className="ticks"><li>Add many vehicles from your computer</li><li>Change rent, tour and room rates any time</li><li>Checked by UDrive before going live</li></ul>
            <Link className="btn dark" href="/account/">Log in to start</Link>
          </div>
          <div className="ob navy">
            <h3>Bring UDrive to your city</h3>
            <p>We are looking for partners across Azad Kashmir — Bagh, Rawalakot, Kotli, Mirpur and more.</p>
            <ul className="ticks"><li>Run UDrive&apos;s network in your area</li><li>Budgets from Rs 1M</li><li>Written agreement before any payment</li></ul>
            <Link className="btn lime" href="/partner/">Become a partner</Link>
          </div>
        </section>

        <section className="appband">
          <div className="t">
            <h2>Everything else is in the app.</h2>
            <p>City rides where you name the fare, live tracking, SOS, city-to-city trips and custom tours with driver offers.</p>
            <PlayButton />
          </div>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <div className="ph"><img src="/app-screen.webp" alt="The UDrive app home screen" width={290} height={479} loading="lazy" /></div>
        </section>
      </div>
    </>
  );
}
