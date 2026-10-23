'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';

import { AdSlot } from '@/components/AdSlot';
import { PALETTES, Photo } from '@/components/Art';
import { TourCard } from '@/components/Cards';
import { HeroBackground, HeroCaption, type Slide, useSlides } from '@/components/HeroSlides';
import { PlayButton } from '@/components/PlayButton';
import { api, img } from '@/lib/api';
import { whatsappLink } from '@/lib/config';
import { rs } from '@/lib/format';
import type { Destination, Home, RentCar } from '@/lib/types';

const POPULAR = ['Keran · 2 days', 'Sharda & Kel · 3 days', 'Arang Kel · 4 days', 'Ratti Gali · 4 days', 'Leepa · 2 days', 'Banjosa & Toli Pir · 1 day'];
const HOTEL_CITIES = ['Muzaffarabad', 'Neelum', 'Rawalakot', 'Bagh', 'Kotli', 'Mirpur', 'Leepa'];
const FALLBACK: Slide[] = [
  { src: null, name: 'Arang Kel', district: 'Neelum', season: 'May to September' },
  { src: null, name: 'Ratti Gali Lake', district: 'Neelum', season: 'July to September' },
  { src: null, name: 'Banjosa Lake', district: 'Poonch', season: 'March to November' },
];
type Tab = 'tours' | 'rent' | 'hotels';

export function HomeView({ initial, initialCars }: { initial: Home; initialCars: RentCar[] }) {
  const [home, setHome] = useState(initial);
  const [cars, setCars] = useState(initialCars);
  const router = useRouter();
  const [tab, setTab] = useState<Tab>('tours');
  const [q, setQ] = useState({ dest: '', date: '', people: '2', mode: '', category: '', city: '' });
  const [plan, setPlan] = useState({ to: '', date: '', people: '4', days: '2' });
  const [district, setDistrict] = useState('');

  useEffect(() => {
    api<Home>('/api/v1/web/home').then(setHome).catch(() => undefined);
    api<RentCar[]>('/api/v1/web/rent-cars').then(setCars).catch(() => undefined);
  }, []);

  const slides: Slide[] = useMemo(() => {
    const seen = new Set<string>();
    const out: Slide[] = [];
    for (const d of home.destinations) {
      const src = img(d.imageUrl);
      if (!src || seen.has(src)) continue;
      seen.add(src);
      out.push({ src, name: d.name, district: d.district, season: d.bestSeason });
      if (out.length === 6) break;
    }
    return out.length ? out : FALLBACK;
  }, [home.destinations]);
  const { i, seen, go, paused } = useSlides(slides.length);

  const s = home.stats;
  const districts = [...new Set(home.destinations.map((d) => d.district).filter(Boolean))].sort();
  const tiles = home.destinations.filter((d) => !district || d.district === district).slice(0, 5);

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
  const names = home.destinations.length ? home.destinations.map((d) => d.name) : FALLBACK.map((x) => x.name);

  return (
    <>
      <section className="hero3" onMouseEnter={() => (paused.current = true)} onMouseLeave={() => (paused.current = false)}>
        <HeroBackground slides={slides} i={i} seen={seen} />
        <div className="shade" />
        <div className="wrap in">
          <div className="heroText">
            <span className="kick">Azad Jammu &amp; Kashmir</span>
            <h1>Kashmir, the way <em>locals</em> know it.</h1>
            <p className="l">Book a tour seat, rent a car by the day or find a room on the way — with drivers and owners checked by UDrive.</p>
            <form className="find" onSubmit={search} role="search">
              <div className="tb" role="tablist" aria-label="Search">
                {([['tours', 'Tours'], ['rent', 'Rent a car'], ['hotels', 'Hotels']] as const).map(([k, l]) => (
                  <button type="button" key={k} role="tab" aria-selected={tab === k} className={tab === k ? 'on' : ''} onClick={() => setTab(k)}>{l}</button>
                ))}
              </div>
              <div className="row">
                {tab === 'tours' && (
                  <>
                    <label><small>Where to</small><select value={q.dest} onChange={(e) => setQ({ ...q, dest: e.target.value })}><option value="">Anywhere</option>{home.destinations.map((d) => <option key={d.slug} value={d.slug}>{d.name}</option>)}</select></label>
                    <label><small>When</small><input type="date" value={q.date} onChange={(e) => setQ({ ...q, date: e.target.value })} /></label>
                    <label><small>People</small><select value={q.people} onChange={(e) => setQ({ ...q, people: e.target.value })}>{[1, 2, 3, 4, 5, 6, 8, 10, 12].map((n) => <option key={n} value={n}>{n} {n === 1 ? 'person' : 'people'}</option>)}</select></label>
                  </>
                )}
                {tab === 'rent' && (
                  <>
                    <label><small>Vehicle</small><select value={q.category} onChange={(e) => setQ({ ...q, category: e.target.value })}><option value="">Any</option><option value="car">Car</option><option value="jeep">Jeep / 4×4</option><option value="hiace">Hiace</option><option value="coster">Coaster</option></select></label>
                    <label><small>Driver</small><select value={q.mode} onChange={(e) => setQ({ ...q, mode: e.target.value })}><option value="">With or without</option><option value="WithDriver">With driver</option><option value="SelfDrive">Self drive</option></select></label>
                    <label><small>From</small><input type="date" value={q.date} onChange={(e) => setQ({ ...q, date: e.target.value })} /></label>
                  </>
                )}
                {tab === 'hotels' && (
                  <>
                    <label className="wide"><small>City / area</small><select value={q.city} onChange={(e) => setQ({ ...q, city: e.target.value })}><option value="">Anywhere</option>{HOTEL_CITIES.map((c) => <option key={c}>{c}</option>)}</select></label>
                    <label><small>Check-in</small><input type="date" value={q.date} onChange={(e) => setQ({ ...q, date: e.target.value })} /></label>
                  </>
                )}
                <button className="go" type="submit">Search →</button>
              </div>
            </form>
          </div>
          <HeroCaption slides={slides} i={i} go={go} />
        </div>
      </section>

      <div className="marq" aria-hidden="true"><div className="track">{[...names, ...names].map((n, k) => <span key={k}>{n}<i>✦</i></span>)}</div></div>

      <div className="wrap">
        <div className="nums">
          <div><b>{home.destinations.length || 35}</b><span>places to visit</span></div>
          <div><b>{districts.length || 8}</b><span>districts covered</span></div>
          <div><b>20<sup>%</sup></b><span>advance only — rest on the day</span></div>
          <div><b>{s.verifiedDrivers > 0 ? s.verifiedDrivers : '✓'}</b><span>{s.verifiedDrivers > 0 ? 'verified drivers' : 'every driver and owner checked'}</span></div>
        </div>

        <section className="s3" aria-labelledby="dest-h">
          <div className="h3row">
            <div><h2 id="dest-h">Explore Azad Kashmir</h2><p>Lakes, meadows and river towns. Pick a place — we&apos;ll find you a checked local driver.</p></div>
            <Link className="arrowLink" href="/destinations/">All {home.destinations.length || ''} places →</Link>
          </div>
          {districts.length > 1 && (
            <div className="chips3" role="tablist" aria-label="Districts">
              <button className={district === '' ? 'on' : ''} onClick={() => setDistrict('')}>All</button>
              {districts.map((d) => <button key={d} className={district === d ? 'on' : ''} onClick={() => setDistrict(d)}>{d}</button>)}
            </div>
          )}
          <div className="bento">
            {(tiles.length ? tiles : ([] as Destination[])).map((d, k) => (
              <Link key={d.slug} href={`/tours/${d.slug}/`} className={`tile ${k === 0 ? 'big' : ''}`}>
                <Photo src={img(d.imageUrl)} alt={`${d.name}, ${d.district} — Azad Kashmir`} seed={d.name} w={k === 0 ? 900 : 460} h={k === 0 ? 580 : 280} palette={PALETTES[k % 6]} lake={k % 2 === 0} />
                <div className="ov" />
                <span className="goC" aria-hidden="true">↗</span>
                <div className="tx">
                  <em>{d.district}</em>
                  <b>{d.name}</b>
                  <span>{d.upcomingTours > 0 ? `${d.upcomingTours} upcoming ${d.upcomingTours === 1 ? 'tour' : 'tours'}` : d.bestSeason ? `Best ${d.bestSeason}` : 'Plan a trip'}</span>
                </div>
              </Link>
            ))}
          </div>
        </section>
      </div>

      <section className="dark3" aria-labelledby="rent-h">
        <div className="wrap">
          <div className="h3row">
            <div><h2 id="rent-h">Rent a car.<br />Book it right here.</h2><p>By the day, with a driver or self drive — from owners on UDrive. Pick your dates, see the full price, send the request.</p></div>
            <Link className="arrowLink" href="/rent-a-car/">All cars →</Link>
          </div>
          <div className="feat"><span>Taken days shown before you pick</span><span>Full price before you book</span><span>Owner confirms on WhatsApp</span><span>Advance back if they don&apos;t</span></div>
          <div className="cars">
            {cars.slice(0, 3).map((c, k) => (
              <div className="car3" key={c.id}>
                <div className="ph"><Photo src={img(c.photoUrl)} alt={`${c.name} ${c.year} for rent`} seed={c.name} w={480} h={260} palette={PALETTES[(k + 1) % 6]} /></div>
                <div className="bd">
                  <span className="ctag">{[c.fourByFour && '4×4', c.withDriverDaily && 'With driver', c.selfDriveDaily && 'Self drive'].filter(Boolean).join(' · ')}</span>
                  <b>{c.name} {c.year}</b>
                  <div className="m">{[`${c.seats} seats`, c.airConditioning && 'AC', c.pickupPoint, c.ownerRating > 0 ? `★ ${c.ownerRating.toFixed(1)} ${c.ownerName}` : c.ownerName].filter(Boolean).join(' · ')}</div>
                  <div className="pr">
                    <span>with driver<strong>{c.withDriverDaily ? rs(c.withDriverDaily) : '—'}</strong></span>
                    <span style={{ textAlign: 'right' }}>{c.selfDriveDaily ? <>self drive<strong>{rs(c.selfDriveDaily)}</strong></> : <>min<strong>{c.minimumDays} {c.minimumDays === 1 ? 'day' : 'days'}</strong></>}</span>
                  </div>
                  <Link className="bk" href={`/rent-a-car/car/?id=${c.id}`}>Book this car</Link>
                </div>
              </div>
            ))}
            <div className="own"><b>Own a car?<br />Earn with it.</b><p>List as many vehicles as you have. You set the price and the days.</p><Link className="limeBtn" href="/account/">List your car</Link></div>
          </div>
        </div>
      </section>

      <div className="wrap">
        <section className="s3" aria-labelledby="tours-h">
          <div className="h3row">
            <div><h2 id="tours-h">Tours</h2><p>{home.tours.length ? 'Live from the UDrive app — seats update as people book.' : 'Fixed-date tours show here as drivers post them — with seats left and price per seat.'}</p></div>
            <Link className="arrowLink" href="/tours/">All tours →</Link>
          </div>
          {home.tours.length > 0 && <div className="grid4" style={{ marginBottom: 24 }}>{home.tours.slice(0, 4).map((t) => <TourCard key={t.id} t={t} />)}</div>}
          <div className="plan3">
            <div className="pic">
              <Photo src={img(home.destinations[1]?.imageUrl)} alt="Plan your trip in Azad Kashmir" seed="plan-your-trip" w={800} h={470} palette="day" />
              <div className="ov" />
              <div className="tx"><h3>{home.tours.length ? 'Want something else?' : 'No tour on your date?'}<br />Tell us your plan.</h3><p>A checked local driver answers on WhatsApp.</p></div>
            </div>
            <div className="fm">
              <h4>Plan your trip</h4>
              <p className="muted" style={{ margin: '0 0 6px' }}>Popular from Muzaffarabad</p>
              <div className="routes3">{POPULAR.map((p) => <button key={p} type="button" onClick={() => setPlan({ ...plan, to: home.destinations.find((d) => p.startsWith(d.name.split(' ')[0]))?.name ?? plan.to, days: p.match(/(\d) day/)?.[1] ?? plan.days })}>{p}</button>)}</div>
              <div className="form2">
                <label className="fld"><span>Where to</span><select value={plan.to} onChange={(e) => setPlan({ ...plan, to: e.target.value })}><option value="">Not sure yet</option>{home.destinations.map((d) => <option key={d.slug}>{d.name}</option>)}</select></label>
                <label className="fld"><span>When</span><input type="date" value={plan.date} onChange={(e) => setPlan({ ...plan, date: e.target.value })} /></label>
                <label className="fld"><span>People</span><select value={plan.people} onChange={(e) => setPlan({ ...plan, people: e.target.value })}>{[1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20].map((n) => <option key={n}>{n}</option>)}</select></label>
                <label className="fld"><span>Days</span><select value={plan.days} onChange={(e) => setPlan({ ...plan, days: e.target.value })}>{['Half day', '1', '2', '3', '4', '5', '6', '7'].map((n) => <option key={n}>{n}</option>)}</select></label>
              </div>
              <a className="waBtn" href={whatsappLink(planText)} target="_blank" rel="noopener noreferrer">Send on WhatsApp</a>
            </div>
          </div>
        </section>

        <AdSlot slot="home" initial={home.ads} />

        <section className="s3" aria-labelledby="hotels-h">
          <div className="h3row">
            <div><h2 id="hotels-h">Places to stay</h2><p>Hotels and guest houses listed by their owners — rates set by them, bookings on WhatsApp.</p></div>
            <Link className="arrowLink" href="/hotels/">All hotels →</Link>
          </div>
          <div className="hot">
            {home.hotels.slice(0, 2).map((h, k) => (
              <Link key={h.id} className="hc" href={`/hotels/${h.slug}/`}>
                <div className="ph"><Photo src={img(h.imageUrl)} alt={`${h.name}, ${h.city}`} seed={h.city + h.name} w={480} h={240} palette={PALETTES[(k + 2) % 6]} lake /><em>{[h.city, h.district].filter(Boolean).join(' · ')}</em></div>
                <div className="bd"><div><b>{h.name}</b><div className="m">{h.propertyType}</div></div><div style={{ textAlign: 'right' }}>{h.startingRate > 0 && <><div className="m">from</div><strong>{rs(h.startingRate)}</strong></>}</div></div>
              </Link>
            ))}
            <div className="listH"><div><b>Own a hotel or guest house?</b><p>List it free. Change rates any time, add special dates for Eid and holidays.</p></div><Link className="btn dark" href="/list-your-hotel/" style={{ alignSelf: 'flex-start' }}>List your hotel</Link></div>
          </div>
        </section>

        <section className="s3" aria-labelledby="how-h">
          <div className="h3row"><div><h2 id="how-h">How it works</h2></div></div>
          <div className="how3">
            <div><em>01</em><b>Pick and see the price</b><p>Tour seat, car or room — dates, route, vehicle and the full price before you book.</p></div>
            <div><em>02</em><b>Confirm with WhatsApp</b><p>A code on WhatsApp is your login. No password needed.</p></div>
            <div><em>03</em><b>Owner confirms</b><p>The driver or owner confirms on WhatsApp. You pay a 20% advance, the rest on the day.</p></div>
          </div>
        </section>

        <div className="bands">
          <div className="band a">
            <div><h3>List your vehicle or hotel</h3><p>One UDrive account for cars, tour vehicles and hotels. Add many vehicles from your computer.</p>
              <div className="pillsRow"><span>Many vehicles</span><span>Rates any time</span><span>Rent calendar</span><span>Tour departures</span></div></div>
            <Link className="btn dark" href="/account/" style={{ alignSelf: 'flex-start' }}>Log in to start</Link>
          </div>
          <div className="band b">
            <div><h3>Bring UDrive to your city</h3><p>Partners across Azad Kashmir — Bagh, Rawalakot, Kotli, Mirpur and more. Written agreement before any payment.</p>
              <div className="pillsRow"><span>Rs 1M</span><span>Rs 2M</span><span>Rs 3M</span><span>Rs 4M+</span></div></div>
            <Link className="limeBtn" href="/partner/" style={{ alignSelf: 'flex-start', position: 'relative', zIndex: 1 }}>Become a partner</Link>
          </div>
        </div>

        <section className="app3">
          <Photo src={img(home.destinations[2]?.imageUrl)} alt="" seed="udrive-app-night" w={1240} h={420} palette="night" lake />
          <div className="shade" />
          <div className="t"><h2>Everything else is in the app.</h2><p>City rides where you name the fare, live tracking, SOS and city-to-city trips.</p><PlayButton /></div>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="phone" src="/app-screen.webp" alt="The UDrive app home screen" width={240} height={396} />
        </section>
      </div>
    </>
  );
}
