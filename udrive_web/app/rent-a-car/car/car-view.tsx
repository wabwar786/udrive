'use client';

import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';

import { addDays, pkToday } from '@/app/account/ui';
import { Art, Photo } from '@/components/Art';
import { RentStatus } from '@/components/RentStatus';
import { OtpForm } from '@/components/OtpForm';
import { api, ApiError, img } from '@/lib/api';
import { authApi } from '@/lib/auth';
import { rs } from '@/lib/format';
import type { CustomerDocs, MyRental, RentCar, RentQuote } from '@/lib/types';
import { useSession } from '@/lib/useSession';

type Terms = { version: number; text: string };
const DOCS: [keyof CustomerDocs, string, string][] = [
  ['cnicFront', 'CNIC front', 'cnic-front'], ['cnicBack', 'CNIC back', 'cnic-back'],
  ['drivingLicence', 'Driving licence', 'driving-licence'], ['selfie', 'Selfie', 'selfie'],
];
const monthStart = (iso: string) => `${iso.slice(0, 7)}-01`;
const shiftMonth = (ym1: string, n: number) => { const d = new Date(`${ym1}T00:00:00Z`); d.setUTCMonth(d.getUTCMonth() + n); return d.toISOString().slice(0, 10); };
const nice = (iso: string) => new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' });
const between = (a: string, b: string) => { const out: string[] = []; for (let d = a; d <= b; d = addDays(d, 1)) out.push(d); return out; };

export function CarView() {
  const { user } = useSession();
  const [id, setId] = useState('');
  const [car, setCar] = useState<RentCar | null>(null);
  const [missing, setMissing] = useState(false);
  const [taken, setTaken] = useState<Set<string>>(new Set());
  const [terms, setTerms] = useState<Terms>({ version: 1, text: '' });
  const [mode, setMode] = useState<'WithDriver' | 'SelfDrive'>('WithDriver');
  const [start, setStart] = useState<string | null>(null);
  const [end, setEnd] = useState<string | null>(null);
  const [wait, setWait] = useState(false); // waiting-list mode: taken days can be picked
  const [month, setMonth] = useState(monthStart(pkToday()));
  const [quote, setQuote] = useState<RentQuote | null>(null);
  const [docs, setDocs] = useState<CustomerDocs | null>(null);
  const [checks, setChecks] = useState([false, false, false]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [booked, setBooked] = useState<MyRental | null>(null);
  const [waited, setWaited] = useState(false);
  const today = pkToday();

  useEffect(() => {
    const v = new URLSearchParams(window.location.search).get('id') ?? '';
    if (!/^[0-9a-f-]{36}$/i.test(v)) { setMissing(true); return; }
    setId(v);
    api<RentCar>(`/api/v1/web/rent-cars/${v}`).then((c) => { setCar(c); if (!c.withDriverDaily && c.selfDriveDaily) setMode('SelfDrive'); }).catch(() => setMissing(true));
    api<{ date: string }[]>(`/api/v1/rentals/vehicles/${v}/blocked-days?from=${pkToday()}`).then((d) => setTaken(new Set(d.map((x) => x.date)))).catch(() => undefined);
    api<Record<string, unknown>>('/api/v1/settings/public').then((s) => setTerms({ version: Number(s['rental.disclaimer_version'] ?? 1) || 1, text: String(s['rental.disclaimer_text_en'] ?? '') })).catch(() => undefined);
  }, []);

  useEffect(() => {
    if (user) authApi<CustomerDocs>('/api/v1/customer/documents').then(setDocs).catch(() => undefined);
  }, [user]);

  // Price from the server for the chosen days and mode (signed-in callers also learn whether documents are on file).
  useEffect(() => {
    setQuote(null);
    if (!id || !start || wait) return;
    const body = JSON.stringify({ startDate: start, endDate: end ?? start, rentalMode: mode });
    const call = user ? authApi<RentQuote>(`/api/v1/rentals/vehicles/${id}/quote`, { method: 'POST', body }) : api<RentQuote>(`/api/v1/rentals/vehicles/${id}/quote`, { method: 'POST', body });
    setError('');
    call.then(setQuote).catch((e) => setError((e as Error).message));
  }, [id, start, end, mode, user, wait, docs]);

  function tap(d: string) {
    if (d < today) return;
    if (!wait && taken.has(d)) return;
    setError('');
    if (!start || end || d < start) { setStart(d); setEnd(null); return; }
    if (d === start) { setStart(null); return; }
    if (!wait && between(start, d).some((x) => taken.has(x))) { setStart(d); setEnd(null); return; }
    setEnd(d);
  }

  async function upload(kind: string, file: File | undefined) {
    if (!file) return;
    if (file.size > 10 * 1024 * 1024) return setError('Photo is too big. Max 10 MB.');
    const form = new FormData();
    form.append('file', file);
    setBusy(true);
    try { setDocs(await authApi<CustomerDocs>(`/api/v1/customer/documents/${kind}`, { method: 'POST', body: form })); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  async function book() {
    if (!quote || !start) return;
    setBusy(true); setError('');
    try {
      const r = await authApi<MyRental>('/api/v1/rentals/bookings', {
        method: 'POST',
        body: JSON.stringify({ vehicleId: id, startDate: start, endDate: end ?? start, rentalMode: mode, acceptedDisclaimerVersion: quote.disclaimerVersion || terms.version }),
      });
      setBooked(r);
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (e) {
      setError((e as Error).message);
      if (e instanceof ApiError && e.code === 'customer_documents_required') authApi<CustomerDocs>('/api/v1/customer/documents').then(setDocs).catch(() => undefined);
    } finally { setBusy(false); }
  }

  async function joinWaitlist() {
    if (!start) return;
    setBusy(true); setError('');
    try {
      await authApi('/api/v1/rentals/waitlist', { method: 'POST', body: JSON.stringify({ vehicleId: id, startDate: start, endDate: end ?? start, rentalMode: mode, notes: null }) });
      setWaited(true);
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  const rate = mode === 'SelfDrive' ? car?.selfDriveDaily : car?.withDriverDaily;
  const needDocs = quote?.requiresCustomerDocuments ?? mode === 'SelfDrive';
  const docsOk = !needDocs || (docs?.complete ?? quote?.customerDocumentsOnFile ?? false);
  const ready = !!quote && docsOk && checks.every(Boolean);
  const months = useMemo(() => [month, shiftMonth(month, 1)], [month]);

  if (missing) return <div className="wrap"><div className="empty" style={{ margin: '60px 0' }}>This car is not available for rent right now. <Link className="link" href="/rent-a-car/">See all cars</Link></div></div>;
  if (!car) return <div className="wrap"><div className="skel" style={{ margin: '30px 0', minHeight: 520 }} /></div>;

  if (booked) return <div className="wrap" style={{ maxWidth: 760, padding: '36px 0 70px' }}><RentStatus initial={booked} /></div>;

  return (
    <div className="wrap">
      <div className="crumb"><Link href="/">Home</Link> / <Link href="/rent-a-car/">Rent a car</Link> / {car.name} {car.year}</div>
      <div className="carHero">
        <div className="main"><span className="lbl">Owner&apos;s photo</span><Photo src={img(car.photoUrl)} alt={`${car.name} ${car.year}`} seed={car.name} eager /></div>
        <div className="side">
          <div><Art seed={`${car.pickupPoint ?? ''}pick`} w={560} h={210} palette="day" /><span className="lbl">Pickup · {car.pickupPoint || 'agreed with the owner'}</span></div>
          <div><Art seed={`${car.name}road`} w={560} h={210} palette="alpine" lake /><span className="lbl">{car.fourByFour ? '4×4 — good for high roads' : 'Good for the main roads'}</span></div>
        </div>
      </div>
      <div className="det3">
        <div>
          <h1>{car.name} {car.year}</h1>
          <div className="muted">{car.category}{car.pickupPoint ? ` · ${car.pickupPoint}` : ''} · {[car.withDriverDaily && 'with driver', car.selfDriveDaily && 'self drive'].filter(Boolean).join(' or ')}</div>
          <div className="specs">
            <span>{car.seats} seats</span>{car.airConditioning && <span>AC</span>}{car.fourByFour && <span>4×4</span>}
            {car.kmPerDay ? <span>{car.kmPerDay} km / day included</span> : null}
            <span>{car.fuelIncluded ? 'Fuel included' : 'Fuel not included'}</span><span>Min {car.minimumDays} {car.minimumDays === 1 ? 'day' : 'days'}</span>
            {car.securityDeposit > 0 && <span>Deposit {rs(car.securityDeposit)} (self drive)</span>}
          </div>
          <div className="ownerRow"><span className="av">{car.ownerName.slice(0, 1)}</span><div><b>{car.ownerName}</b>{car.ownerRating > 0 ? ` · ★ ${car.ownerRating.toFixed(1)}` : ' · new owner'}<div className="small muted">Owner checked by UDrive · CNIC, registration and photos</div></div></div>

          <h2 className="h4b">{wait ? 'Dates for the waiting list' : 'Pick your dates'}</h2>
          <div style={{ display: 'flex', gap: 8, marginBottom: 10 }}>
            <button className="btn ghost" onClick={() => setMonth(shiftMonth(month, -1))} disabled={month <= monthStart(today)}>←</button>
            <button className="btn ghost" onClick={() => setMonth(shiftMonth(month, 1))} disabled={month >= shiftMonth(monthStart(today), 4)}>→</button>
          </div>
          <div className="cal2">
            {months.map((m) => {
              const [y, mo] = m.split('-').map(Number);
              const days = new Date(Date.UTC(y, mo, 0)).getUTCDate();
              const pad = (new Date(Date.UTC(y, mo - 1, 1)).getUTCDay() + 6) % 7;
              return (
                <div className="mo" key={m}>
                  <b>{new Date(`${m}T00:00:00Z`).toLocaleDateString('en-GB', { month: 'long', year: 'numeric', timeZone: 'UTC' })}</b>
                  <div className="g">
                    {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d, k) => <span key={`h${k}`} className="h">{d}</span>)}
                    {Array.from({ length: pad }, (_, k) => <span key={`p${k}`} />)}
                    {Array.from({ length: days }, (_, k) => {
                      const d = `${m.slice(0, 8)}${String(k + 1).padStart(2, '0')}`;
                      const past = d < today; const x = taken.has(d);
                      const sel = d === start || d === end; const inR = !!(start && end && d > start && d < end);
                      const cls = past ? 'p' : sel ? `s ${d === start ? 'a' : ''} ${d === end || (!end && d === start) ? 'b' : ''}` : inR ? 'in' : x ? 'x' : '';
                      return <button key={d} className={cls} disabled={past || (!wait && x)} onClick={() => tap(d)} aria-label={`${nice(d)}${x ? ' — taken' : ''}`}>{k + 1}</button>;
                    })}
                  </div>
                </div>
              );
            })}
          </div>
          <div className="legend"><span><i style={{ background: 'var(--navy)' }} />Your dates</span><span><i style={{ background: '#F6F7F9', border: '1px solid #DCE1E7' }} />Taken — crossed out</span><span>Tap the first day, then the last day</span></div>
          <p className="small" style={{ marginTop: 10 }}>
            {wait
              ? <button className="link" style={{ background: 'none', border: 'none', cursor: 'pointer' }} onClick={() => { setWait(false); setStart(null); setEnd(null); }}>← Back to booking free days</button>
              : <>Need days that are taken? <button className="link" style={{ background: 'none', border: 'none', cursor: 'pointer' }} onClick={() => { setWait(true); setStart(null); setEnd(null); }}>Join the waiting list</button></>}
          </p>

          <h2 className="h4b">What you need</h2>
          <div className="need">
            <div><b>With driver</b><span>Nothing — the owner or their driver drives.</span></div>
            <div><b>Self drive</b><span>CNIC both sides, driving licence and a selfie — once. Only the owner of the car you book sees them.</span></div>
            <div><b>At pickup</b><span>Balance{car.securityDeposit > 0 ? ' and deposit' : ''} in cash to the owner. Take photos of the car&apos;s condition.</span></div>
            <div><b>If the owner says no</b><span>Or doesn&apos;t answer in time — your advance comes back in full.</span></div>
          </div>
        </div>

        <aside className="bookP" aria-label="Book this car">
          <div className="pr">{rate ? rs(rate) : '—'} <small>/ day · {mode === 'SelfDrive' ? 'self drive' : 'with driver'}</small></div>
          <div className="tabs" style={{ margin: '14px 0 4px' }}>
            <button className={mode === 'WithDriver' ? 'on' : ''} disabled={!car.withDriverDaily} onClick={() => setMode('WithDriver')}>With driver{car.withDriverDaily ? ` · ${rs(car.withDriverDaily)}` : ''}</button>
            <button className={mode === 'SelfDrive' ? 'on' : ''} disabled={!car.selfDriveDaily} onClick={() => setMode('SelfDrive')}>Self drive{car.selfDriveDaily ? ` · ${rs(car.selfDriveDaily)}` : ''}</button>
          </div>
          <div className="dates"><div><small>Pick up</small><b>{start ? nice(start) : 'Choose'}</b></div><div><small>Return</small><b>{start ? nice(end ?? start) : '—'}</b></div></div>
          {error && <div className="msg err" role="alert">{error}</div>}

          {wait ? (
            waited ? <div className="msg ok">You are on the waiting list. If these days free up, the owner can offer the car to you first — you&apos;ll hear on WhatsApp.</div> : (
              <>
                <p className="small muted">If someone cancels, the owner can offer these days to you first.</p>
                {user ? <button className="btn dark block" disabled={busy || !start} onClick={joinWaitlist}>{busy ? 'Please wait…' : 'Join waiting list'}</button>
                  : start ? <OtpForm action="Join waiting list" busy={busy} onVerified={() => void joinWaitlist()} /> : null}
              </>
            )
          ) : (
            <>
              {quote ? (
                <div className="money">
                  <div><span>{rs(quote.dailyRate)} × {quote.days} {quote.days === 1 ? 'day' : 'days'}</span><span>{rs(quote.subtotal)}</span></div>
                  {quote.securityDeposit > 0 && <div><span>Security deposit (refundable)</span><span>{rs(quote.securityDeposit)}</span></div>}
                  {quote.kmIncluded ? <div><span>Kilometres included</span><span>{quote.kmIncluded} km</span></div> : null}
                  <div className="now"><span>Advance (pay to book)</span><span>{rs(quote.advanceAmount)}</span></div>
                  <div><span>Balance at pickup, cash to owner</span><span>{rs(quote.balanceDue)}</span></div>
                </div>
              ) : <p className="small muted">{start ? 'Working out the price…' : `Choose your dates. Minimum ${car.minimumDays} ${car.minimumDays === 1 ? 'day' : 'days'}.`}</p>}

              {needDocs && (
                <>
                  <div className="ov3">YOUR DOCUMENTS · SELF DRIVE</div>
                  {user ? (
                    <div className="docs">
                      {DOCS.map(([k, label, kind]) => (
                        <label key={kind} className={docs?.[k] ? 'ok' : ''}>
                          {docs?.[k] ? '✓ ' : '+ '}{label}
                          <input type="file" accept="image/jpeg,image/png,image/webp" disabled={busy} onChange={(e) => { void upload(kind, e.target.files?.[0]); e.target.value = ''; }} />
                        </label>
                      ))}
                    </div>
                  ) : <p className="small muted">Log in below, then add your CNIC, licence and a selfie — asked once.</p>}
                  <p className="note2" style={{ marginTop: 0 }}>Only the owner of the car you book sees them.</p>
                </>
              )}

              <div className="ov3">TERMS</div>
              {terms.text && <div className="terms">{terms.text}</div>}
              {[
                "I will check the vehicle's papers — registration, insurance, fitness — myself. UDrive has not checked them.",
                'A fine, a crash or damage during the rental is my responsibility.',
                "I will photograph the car's condition at collection — for both sides' protection.",
              ].map((t, k) => (
                <label key={k} className="chk2"><input type="checkbox" checked={checks[k]} onChange={(e) => setChecks(checks.map((c, j) => (j === k ? e.target.checked : c)))} />{t}</label>
              ))}

              {user ? (
                <button className="btn dark block" style={{ padding: 15, marginTop: 10 }} disabled={busy || !ready} onClick={book}>
                  {busy ? 'Sending…' : !quote ? 'Choose your dates first' : !docsOk ? 'Add your documents first' : `Book · advance ${rs(quote.advanceAmount)}`}
                </button>
              ) : quote && checks.every(Boolean) ? (
                <div style={{ marginTop: 10 }}><OtpForm action={needDocs ? 'Log in to add documents' : `Book · advance ${rs(quote.advanceAmount)}`} busy={busy} onVerified={() => { if (!needDocs) void book(); }} /></div>
              ) : (
                <button className="btn dark block" style={{ padding: 15, marginTop: 10 }} disabled>{!quote ? 'Choose your dates first' : 'Tick the three lines above'}</button>
              )}
              <div className="note">The owner confirms on WhatsApp. If they say no or don&apos;t answer in time, your advance comes back.</div>
            </>
          )}
        </aside>
      </div>
    </div>
  );
}
