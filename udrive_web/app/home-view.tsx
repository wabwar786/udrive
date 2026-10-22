'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { AdSlot } from '@/components/AdSlot';
import { HotelCard, SkeletonGrid, TourCard } from '@/components/Cards';
import { CarIcon, HotelIcon, KeyIcon, TourIcon } from '@/components/Icons';
import { PlayButton } from '@/components/PlayButton';
import { Picture } from '@/components/Scene';
import { api, img } from '@/lib/api';
import { daysLabel, rs } from '@/lib/format';
import type { Home } from '@/lib/types';

export function HomeView({ initial }: { initial: Home }) {
  const [home, setHome] = useState(initial);
  const [loaded, setLoaded] = useState(initial.tours.length > 0);
  const router = useRouter();
  const [dest, setDest] = useState('');
  const [date, setDate] = useState('');
  const [people, setPeople] = useState('2');

  useEffect(() => {
    api<Home>('/api/v1/web/home').then(setHome).catch(() => undefined).finally(() => setLoaded(true));
  }, []);

  const s = home.stats;
  const lead = home.tours[0];

  function search(e: React.FormEvent) {
    e.preventDefault();
    const q = new URLSearchParams();
    if (date) q.set('date', date);
    if (people) q.set('seats', people);
    router.push(dest ? `/tours/${dest}/?${q}` : `/tours/?${q}`);
  }

  return (
    <>
      <section className="hero">
        <div className="wrap">
          <div>
            <span className="eyebrow">Now live in Muzaffarabad</span>
            <h1>Kashmir trips with local drivers, at a price you can see.</h1>
            <p className="lead">
              Book a seat or the whole vehicle on tours leaving this week. Every driver is licence-checked, and you pay
              only 20% when the driver confirms — the rest to the driver on the day.
            </p>
            <form className="search" onSubmit={search} role="search">
              <label>Where to
                <select value={dest} onChange={(e) => setDest(e.target.value)}>
                  <option value="">Anywhere</option>
                  {home.destinations.filter((d) => d.upcomingTours > 0).map((d) => (
                    <option key={d.slug} value={d.slug}>{d.name}</option>
                  ))}
                </select>
              </label>
              <label>When<input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></label>
              <label>People
                <select value={people} onChange={(e) => setPeople(e.target.value)}>
                  {[1, 2, 3, 4, 5, 6, 8, 10, 12].map((n) => <option key={n} value={n}>{n} {n === 1 ? 'person' : 'people'}</option>)}
                </select>
              </label>
              <div className="go"><button className="btn dark" type="submit">Find tours</button></div>
            </form>
            <div className="trust">
              {s.verifiedDrivers >= 20 && <span><b>{s.verifiedDrivers}</b> verified drivers</span>}
              {s.toursThisWeek > 0 && <span><b>{s.toursThisWeek}</b> tours this week</span>}
              <span>WhatsApp confirmation</span>
              <span>20% advance only</span>
            </div>
          </div>
          <div className="heroimg">
            <Picture src={img(lead?.imageUrl)} alt="Mountains of Azad Kashmir" seed="hero-neelum" eager />
            {s.toursToday > 0 && (
              <div className="tag" style={{ left: 20, top: 20 }}>
                <b><span className="dot" />{s.toursToday} {s.toursToday === 1 ? 'tour' : 'tours'} leaving today</b>
                <span className="muted">{[...new Set(home.tours.slice(0, 4).map((t) => t.destination))].join(' · ')}</span>
              </div>
            )}
            {lead && (
              <Link className="tag" style={{ right: 20, bottom: 20 }} href={`/tour/?id=${lead.id}`}>
                <b>{lead.title}</b>
                <span className="muted">
                  {daysLabel(lead.days)} · {lead.seatsLeft} seats left · {lead.pricePerSeat > 0 ? `${rs(lead.pricePerSeat)}/seat` : rs(lead.wholeVehiclePrice)}
                </span>
              </Link>
            )}
          </div>
        </div>
      </section>

      <div className="wrap">
        <nav className="svc" aria-label="Services">
          <Link href="/tours/"><TourIcon /><div><b>Tours</b><span>Fixed packages with set dates and seats</span></div></Link>
          <Link href="/hotels/"><HotelIcon /><div><b>Hotels</b><span>Guest houses and hotels on the route</span></div></Link>
          <Link href="/rides/"><CarIcon /><div><b>City rides</b><span>Name your fare in the app, drivers answer</span></div></Link>
          <Link href="/rides/#rent"><KeyIcon /><div><b>Rent a car</b><span>With or without driver, by the day</span></div></Link>
        </nav>

        <section className="sec" aria-labelledby="tours-h">
          <div className="head">
            <div><h2 id="tours-h">Tours leaving this week</h2><p className="muted">Live from the UDrive app — seats update as people book.</p></div>
            <Link className="link" href="/tours/">All tours</Link>
          </div>
          {!loaded ? <SkeletonGrid /> : home.tours.length === 0 ? (
            <div className="empty">No tours are open right now. New departures are added every day — check again soon or ask us on WhatsApp.</div>
          ) : (
            <div className="grid4">{home.tours.map((t) => <TourCard key={t.id} t={t} />)}</div>
          )}
        </section>

        <AdSlot slot="home" initial={home.ads} />

        <section className="sec" aria-labelledby="how-h">
          <div className="head"><h2 id="how-h">How booking works</h2></div>
          <div className="steps">
            <div className="step"><em>01</em><b>Pick a tour and seats</b><p>See the date, route, vehicle and driver before you book. Per seat or the whole vehicle.</p></div>
            <div className="step"><em>02</em><b>Confirm with your WhatsApp</b><p>We send a code to your WhatsApp. Your seats are held as soon as you confirm.</p></div>
            <div className="step"><em>03</em><b>Driver confirms on WhatsApp</b><p>The driver sees your booking in his app and messages you the pickup point, time and how to send the 20% advance.</p></div>
          </div>
        </section>

        {home.destinations.length > 0 && (
          <section className="sec" aria-labelledby="dest-h">
            <div className="head"><div><h2 id="dest-h">Where people are going</h2><p className="muted">Tours by destination.</p></div></div>
            <div className="dest">
              {home.destinations.slice(0, 12).map((d) => (
                <Link key={d.slug} href={`/tours/${d.slug}/`}><b>{d.name}</b><span>{d.upcomingTours > 0 ? `${d.upcomingTours} upcoming ${d.upcomingTours === 1 ? 'tour' : 'tours'}` : d.district}</span></Link>
              ))}
            </div>
          </section>
        )}

        {home.hotels.length > 0 && (
          <section className="sec" aria-labelledby="hotels-h">
            <div className="head">
              <div><h2 id="hotels-h">Places to stay</h2><p className="muted">Hotels listed by their owners on UDrive.</p></div>
              <Link className="link" href="/hotels/">All hotels</Link>
            </div>
            <div className="grid3">{home.hotels.slice(0, 3).map((h) => <HotelCard key={h.id} h={h} />)}</div>
          </section>
        )}

        <section className="sec owner">
          <div className="ob">
            <h3>Own a hotel or guest house?</h3>
            <p>List it on UDrive and get bookings from tour travellers on WhatsApp.</p>
            <ul className="ticks"><li>Register here on the website — takes 5 minutes</li><li>Add 3–9 photos, rooms and prices</li><li>Live after a quick check by our team</li></ul>
            <Link className="btn dark" href="/list-your-hotel/">List your hotel</Link>
          </div>
          <div className="ob">
            <h3>Drive with UDrive</h3>
            <p>Rides, tours and rentals — drivers register in the UDrive app, not on the website.</p>
            <ul className="ticks"><li>Rs 1,000 welcome bonus in your wallet</li><li>You set your own tour packages and dates</li><li>Bookings straight to your phone</li></ul>
            <Link className="btn ghost" href="/drive/">How to join</Link>
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
