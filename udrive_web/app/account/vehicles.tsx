'use client';

import { useEffect, useState } from 'react';

import { Scene } from '@/components/Scene';
import { api, img } from '@/lib/api';
import { rs } from '@/lib/format';
import type { Area, CalendarDay, Kit, ListingHome, OwnerVehicle } from '@/lib/types';
import { addDays, call, dayLabel, FilePick, json, Msg, Num, Pill, pkToday, Text, upload, useAction } from './ui';

const CATS = [['car', 'Car'], ['jeep', 'Jeep / 4×4'], ['hiace', 'Hiace'], ['coster', 'Coaster']] as const;
const KIT: [keyof Kit, string][] = [
  ['airConditioning', 'AC'], ['heating', 'Heater'], ['fourByFour', '4×4'], ['spareTyre', 'Spare tyre'],
  ['firstAidKit', 'First-aid kit'], ['fireExtinguisher', 'Fire extinguisher'], ['snowChains', 'Snow chains'],
];
const NO_KIT: Kit = { fourByFour: false, firstAidKit: false, spareTyre: false, fireExtinguisher: false, snowChains: false, heating: false, airConditioning: false };
const NEXT_YEAR = new Date().getFullYear() + 1;

type Go = (t: 'vehicles' | 'departures' | 'rentals' | 'drivers' | 'documents' | 'hotels' | 'partner') => void;

export function Vehicles({ home, reload, go }: { home: ListingHome | null; reload: () => Promise<void>; go: Go }) {
  const [edit, setEdit] = useState<OwnerVehicle | 'new' | null>(null);
  const [cal, setCal] = useState<OwnerVehicle | null>(null);

  if (!home) return <div className="skel" style={{ minHeight: 300 }} />;
  if (edit) return <VehicleEditor v={edit === 'new' ? null : edit} home={home} reload={reload} close={() => setEdit(null)} go={go} />;
  if (cal) return <RentCalendar v={cal} close={() => setCal(null)} />;

  const v = home.vehicles;
  const live = v.filter((x) => x.rentReview?.status === 'Approved' || x.tourReview?.status === 'Approved').length;
  const review = v.filter((x) => x.rentReview?.status === 'Pending' || x.tourReview?.status === 'Pending').length;

  return (
    <>
      <div className="acctHead">
        <div><h1>My vehicles</h1><p className="muted">Cars for rent and tour vehicles. Add as many as you own (up to 50).</p></div>
        <button className="btn dark" onClick={() => setEdit('new')} disabled={v.length >= 50}>+ Add vehicle</button>
      </div>
      <div className="kpi">
        <div><b>{v.length}</b><span>vehicles</span></div>
        <div><b>{live}</b><span>live</span></div>
        <div><b>{review}</b><span>in review</span></div>
        <div><b>{v.reduce((n, x) => n + x.pendingRentals, 0)}</b><span>rent requests waiting</span></div>
      </div>
      {v.length === 0 ? (
        <div className="empty">
          <b style={{ display: 'block', color: 'var(--ink)', fontSize: 17, marginBottom: 6 }}>No vehicles yet</b>
          Add your first car, jeep, Hiace or Coaster. You need its front photo, the registration book (both sides) and your CNIC.
          <div style={{ marginTop: 14 }}><button className="btn dark" onClick={() => setEdit('new')}>Add vehicle</button></div>
        </div>
      ) : v.map((x) => (
        <div className="vrow" key={x.id}>
          <div className="ph">{img(x.photoUrl) ? <img src={img(x.photoUrl)!} alt={x.name} /> : <Scene seed={x.name} label={x.name} />}</div>
          <div>
            <b>{x.name} {x.year}</b>
            <div className="s">{x.registrationNumber} · {x.seats} seats{x.tehsilName ? ` · ${x.tehsilName}` : ''}{x.withDriverDaily ? ` · ${rs(x.withDriverDaily)}/day with driver` : ''}{x.selfDriveDaily ? ` · ${rs(x.selfDriveDaily)} self drive` : ''}</div>
            {x.wantsRent && <Pill status={x.rentReview?.status ?? 'None'} label="Rent" />}
            {x.wantsTour && <Pill status={x.tourReview?.status ?? 'None'} label="Tours" />}
            {x.status === 'Draft' && <Pill status="Draft" />}
            {(x.rentReview?.note || x.tourReview?.note || x.reviewNote) && <div className="s" style={{ color: 'var(--warn)' }}>UDrive: {x.rentReview?.note || x.tourReview?.note || x.reviewNote}</div>}
          </div>
          <div className="acts">
            <button className="btn ghost" onClick={() => setEdit(x)}>Edit</button>
            {x.wantsRent && <button className="btn ghost" onClick={() => setCal(x)}>Rent days</button>}
            {x.wantsTour && <button className="btn ghost" onClick={() => go('departures')}>Departures</button>}
          </div>
        </div>
      ))}
    </>
  );
}

// ─────────────────────────────────────────────── add / edit

function VehicleEditor({ v, home, reload, close, go }: { v: OwnerVehicle | null; home: ListingHome; reload: () => Promise<void>; close: () => void; go: Go }) {
  const a = useAction();
  const [step, setStep] = useState(0);
  const [id, setId] = useState(v?.id ?? '');
  const [areas, setAreas] = useState<Area[]>([]);
  const [agreement, setAgreement] = useState('');
  const [accept, setAccept] = useState(false);
  const [lic, setLic] = useState({ number: home.owner.licenceNumber ?? '', expiry: home.owner.licenceExpiry ?? '' });
  const [f, setF] = useState({
    category: (v?.category ?? 'car').toLowerCase(), make: v?.make ?? '', model: v?.model ?? '', year: v?.year ?? 2018 as number | '',
    registrationNumber: v?.registrationNumber ?? '', seats: v?.seats ?? 4 as number | '', wantsRent: v?.wantsRent ?? true, wantsTour: v?.wantsTour ?? false,
    drivers: home.owner.drivesSelf ? 'Self' : 'Self', withDriverDaily: v?.withDriverDaily ?? '' as number | '', selfDriveDaily: v?.selfDriveDaily ?? '' as number | '',
    pickupPoint: v?.pickupPoint ?? '', kit: v?.kit ?? NO_KIT, districtId: '', tehsilId: v?.tehsilId ?? '',
  });
  const set = <K extends keyof typeof f>(k: K, val: (typeof f)[K]) => setF((x) => ({ ...x, [k]: val }));
  const current = home.vehicles.find((x) => x.id === id) ?? v;

  useEffect(() => {
    api<Area[]>('/api/v1/catalog/areas').then((list) => {
      setAreas(list);
      if (f.tehsilId) {
        const d = list.find((x) => x.tehsils.some((t) => t.id === f.tehsilId));
        if (d) setF((x) => ({ ...x, districtId: d.id }));
      }
    }).catch(() => undefined);
    api<Record<string, unknown>>('/api/v1/settings/public').then((s) => setAgreement(String(s['listing.owner_agreement_en'] ?? ''))).catch(() => undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function saveDetails() {
    const ok = await a.run(async () => {
      if (f.make.trim().length < 2 || f.model.trim().length < 1) throw new Error('Write the make and model, like Toyota Corolla.');
      if (!f.year || f.year < 1980 || f.year > NEXT_YEAR) throw new Error(`Year 1980 to ${NEXT_YEAR}.`);
      if (!/^[A-Za-z0-9 -]{3,20}$/.test(f.registrationNumber.trim())) throw new Error('Registration number: 3–20 letters and numbers, like LEA-1234.');
      if (!f.seats || f.seats < 1 || f.seats > 60) throw new Error('Seats 1 to 60.');
      if (!f.wantsRent && !f.wantsTour) throw new Error('Choose rent, tours, or both.');
      if (f.wantsRent && !f.withDriverDaily && !f.selfDriveDaily) throw new Error('Write at least one daily rent price.');
      if (!f.tehsilId) throw new Error('Choose where the vehicle is based.');
      const body = {
        category: f.category, make: f.make.trim(), model: f.model.trim(), year: f.year, registrationNumber: f.registrationNumber.trim().toUpperCase(),
        seats: f.seats, wantsRent: f.wantsRent, wantsTour: f.wantsTour, drivers: f.drivers,
        withDriverDaily: f.wantsRent && f.withDriverDaily ? f.withDriverDaily : null,
        selfDriveDaily: f.wantsRent && f.selfDriveDaily ? f.selfDriveDaily : null,
        pickupPoint: f.pickupPoint.trim() || null, kit: f.kit, tehsilId: f.tehsilId,
      };
      const saved = id
        ? await call<OwnerVehicle>(`/api/v1/listings/vehicles/${id}`, json('PUT', body))
        : await call<OwnerVehicle>('/api/v1/listings/vehicles', json('POST', body));
      setId(saved.id);
      await call(`/api/v1/listings/vehicles/${saved.id}/location`, json('PUT', { tehsilId: f.tehsilId })).catch(() => undefined);
      await reload();
    });
    if (ok) setStep(1);
  }

  async function photo(kind: 'front' | 'registration-front' | 'registration-back', file: File) {
    await a.run(async () => { await upload(`/api/v1/listings/vehicles/${id}/photos/${kind}`, file); await reload(); });
  }

  async function submit() {
    const ok = await a.run(async () => {
      if (!accept) throw new Error('Please read and accept the owner agreement.');
      await call(`/api/v1/listings/vehicles/${id}/submit`, json('POST', {
        licenceNumber: lic.number.trim() || null, licenceExpiry: lic.expiry || null,
        acceptAgreement: true, agreementVersion: home.owner.agreementVersion,
      }));
      await reload();
    });
    if (ok) setStep(3);
  }

  const district = areas.find((d) => d.id === f.districtId);
  const o = home.owner;
  const docsMissing = [!o.cnicFront && 'CNIC front', !o.cnicBack && 'CNIC back', !o.selfie && 'selfie',
    f.drivers !== 'Drivers' && !o.licenceFront && 'licence front', f.drivers !== 'Drivers' && !o.licenceBack && 'licence back'].filter(Boolean) as string[];

  return (
    <div className="wiz" style={{ maxWidth: 820 }}>
      <button className="link" style={{ background: 'none', border: 'none', cursor: 'pointer', marginBottom: 14 }} onClick={close}>← My vehicles</button>
      <h1 style={{ fontSize: 30 }}>{v ? `Edit ${v.name}` : 'Add a vehicle'}</h1>
      {v && (v.rentReview?.status === 'Approved' || v.tourReview?.status === 'Approved') && (
        <div className="msg info">Saving changed details sends the vehicle for a quick review again. Rent days and departures can be changed any time without review.</div>
      )}
      <div className="wsteps">{['Vehicle', 'Photos', 'Send', 'Done'].map((s, i) => <span key={s} className={i === step ? 'on' : i < step ? 'done' : ''}>{i + 1}. {s}</span>)}</div>
      <Msg error={a.error} ok={a.ok} />

      {step === 0 && (
        <div className="sec2">
          <div className="form2">
            <label className="fld"><span>Type</span><select value={f.category} onChange={(e) => set('category', e.target.value)}>{CATS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></label>
            <Text label="Registration number" value={f.registrationNumber} onChange={(x) => set('registrationNumber', x.replace(/[^A-Za-z0-9 -]/g, ''))} max={20} placeholder="LEA-1234" />
            <Text label="Make" value={f.make} onChange={(x) => set('make', x)} max={60} placeholder="Toyota" />
            <Text label="Model" value={f.model} onChange={(x) => set('model', x)} max={60} placeholder="Corolla" />
            <Num label="Year" value={f.year} onChange={(x) => set('year', x)} min={1980} max={NEXT_YEAR} />
            <Num label="Passenger seats" value={f.seats} onChange={(x) => set('seats', x)} min={1} max={60} />
            <label className="fld"><span>District</span><select value={f.districtId} onChange={(e) => setF((x) => ({ ...x, districtId: e.target.value, tehsilId: '' }))}><option value="">Choose…</option>{areas.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select></label>
            <label className="fld"><span>Tehsil / town</span><select value={f.tehsilId} onChange={(e) => set('tehsilId', e.target.value)} disabled={!district}><option value="">Choose…</option>{district?.tehsils.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}</select></label>
          </div>

          <div className="small muted" style={{ margin: '10px 0 6px' }}>Use it for</div>
          <div className="amen">
            <label><input type="checkbox" checked={f.wantsRent} onChange={(e) => set('wantsRent', e.target.checked)} />Rent by the day</label>
            <label><input type="checkbox" checked={f.wantsTour} onChange={(e) => set('wantsTour', e.target.checked)} />Tours (you post departures)</label>
          </div>
          <label className="fld"><span>Who drives</span>
            <select value={f.drivers} onChange={(e) => set('drivers', e.target.value)}>
              <option value="Self">I drive it myself</option><option value="Both">Me and my drivers</option><option value="Drivers">Only my drivers</option>
            </select>
          </label>
          {f.wantsRent && (
            <div className="form2">
              <Num label="Rent with driver (Rs / day)" value={f.withDriverDaily} onChange={(x) => set('withDriverDaily', x)} min={0} max={1_000_000} step={500} />
              <Num label="Self drive (Rs / day, optional)" value={f.selfDriveDaily} onChange={(x) => set('selfDriveDaily', x)} min={0} max={1_000_000} step={500} />
            </div>
          )}
          <Text label="Pickup point" value={f.pickupPoint} onChange={(x) => set('pickupPoint', x)} max={200} optional placeholder="Chattar Klas, near the bridge" />
          <div className="small muted" style={{ margin: '10px 0 6px' }}>In the vehicle</div>
          <div className="amen">
            {KIT.map(([k, l]) => <label key={k}><input type="checkbox" checked={f.kit[k]} onChange={(e) => set('kit', { ...f.kit, [k]: e.target.checked })} />{l}</label>)}
          </div>
          <button className="btn dark" onClick={saveDetails} disabled={a.busy}>{a.busy ? 'Saving…' : 'Save and next'}</button>
        </div>
      )}

      {step === 1 && current && (
        <div className="sec2">
          <h3 style={{ marginBottom: 4 }}>Photos</h3>
          <p className="muted small" style={{ marginTop: 0 }}>The front photo is what customers see. Registration book photos are seen only by the UDrive team.</p>
          <div className="fgrid">
            <FilePick label="Vehicle front" done={current.docs.front} onFile={(x) => photo('front', x)} disabled={a.busy} />
            <FilePick label="Registration book — front" done={current.docs.registrationFront} onFile={(x) => photo('registration-front', x)} disabled={a.busy} />
            <FilePick label="Registration book — back" done={current.docs.registrationBack} onFile={(x) => photo('registration-back', x)} disabled={a.busy} />
          </div>
          {img(current.photoUrl) && <div className="thumbs"><div><img src={img(current.photoUrl)!} alt={current.name} /></div></div>}
          <div style={{ display: 'flex', gap: 10 }}>
            <button className="btn ghost" onClick={() => setStep(0)}>Back</button>
            <button className="btn dark" onClick={() => setStep(2)} disabled={a.busy || !current.docs.front || !current.docs.registrationFront || !current.docs.registrationBack}>{a.busy ? 'Uploading…' : 'Next'}</button>
          </div>
        </div>
      )}

      {step === 2 && (
        <div className="sec2">
          <h3 style={{ marginBottom: 8 }}>Send for review</h3>
          {docsMissing.length > 0 ? (
            <div className="msg info">Your documents are still needed: {docsMissing.join(', ')}. <button className="link" style={{ background: 'none', border: 'none', cursor: 'pointer' }} onClick={() => go('documents')}>Upload in Documents</button> — they are used for all your vehicles.</div>
          ) : <div className="msg ok">Your CNIC, selfie{f.drivers !== 'Drivers' ? ' and licence' : ''} are on file.</div>}
          {f.drivers !== 'Drivers' && (
            <div className="form2">
              <Text label="Driving licence number" value={lic.number} onChange={(x) => setLic({ ...lic, number: x })} max={40} />
              <label className="fld"><span>Licence valid until</span><input type="date" value={lic.expiry} onChange={(e) => setLic({ ...lic, expiry: e.target.value })} /></label>
            </div>
          )}
          {agreement && <div className="agree">{agreement}</div>}
          <label style={{ display: 'block', margin: '10px 0 14px', fontSize: 14 }}><input type="checkbox" checked={accept} onChange={(e) => setAccept(e.target.checked)} /> I have read and accept the UDrive owner agreement (version {home.owner.agreementVersion}).</label>
          <div style={{ display: 'flex', gap: 10 }}>
            <button className="btn ghost" onClick={() => setStep(1)}>Back</button>
            <button className="btn dark" onClick={submit} disabled={a.busy || docsMissing.length > 0}>{a.busy ? 'Sending…' : 'Send for review'}</button>
          </div>
        </div>
      )}

      {step === 3 && (
        <div className="sec2 done">
          <div className="big">✓</div>
          <h3>Sent for review</h3>
          <p className="muted">UDrive checks the documents, usually within a day. You&apos;ll get a WhatsApp message when it is live.</p>
          <button className="btn dark" onClick={close}>Back to my vehicles</button>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────── rent calendar

function RentCalendar({ v, close }: { v: OwnerVehicle; close: () => void }) {
  const a = useAction();
  const [days, setDays] = useState<CalendarDay[]>([]);
  const [from, setFrom] = useState(pkToday());
  const [block, setBlock] = useState<Set<string>>(new Set());
  const [unblock, setUnblock] = useState<Set<string>>(new Set());

  useEffect(() => {
    void a.run(async () => setDays(await call<CalendarDay[]>(`/api/v1/listings/vehicles/${v.id}/calendar?from=${from}&days=42`)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [from, v.id]);

  function toggle(d: CalendarDay) {
    const b = new Set(block); const u = new Set(unblock);
    if (d.state === 'free') { if (b.has(d.date)) b.delete(d.date); else b.add(d.date); }
    else if (d.state === 'blocked') { if (u.has(d.date)) u.delete(d.date); else u.add(d.date); }
    setBlock(b); setUnblock(u);
  }

  async function save() {
    await a.run(async () => {
      setDays(await call<CalendarDay[]>(`/api/v1/listings/vehicles/${v.id}/blocked-days`, json('PUT', { block: [...block], unblock: [...unblock] }))
        .catch(async () => call<CalendarDay[]>(`/api/v1/listings/vehicles/${v.id}/calendar?from=${from}&days=42`)));
      setBlock(new Set()); setUnblock(new Set());
    }, 'Saved.');
  }

  const first = days[0] ? new Date(`${days[0].date}T00:00:00Z`).getUTCDay() : 0;
  const pad = (first + 6) % 7; // Monday first
  return (
    <>
      <button className="link" style={{ background: 'none', border: 'none', cursor: 'pointer', marginBottom: 14 }} onClick={close}>← My vehicles</button>
      <div className="acctHead"><div><h1>Rent days — {v.name}</h1><p className="muted">Tap a day to close it for rent (your own use, service). Tap again to open it.</p></div></div>
      <Msg error={a.error} ok={a.ok} />
      <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
        <button className="btn ghost" onClick={() => setFrom(addDays(from, -42))} disabled={from <= pkToday()}>← Earlier</button>
        <button className="btn ghost" onClick={() => setFrom(addDays(from, 42))}>Later →</button>
      </div>
      <div className="cal">
        {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => <div key={d} className="hd">{d}</div>)}
        {Array.from({ length: pad }, (_, i) => <div key={`p${i}`} className="hd" />)}
        {days.map((d) => {
          const closing = block.has(d.date); const opening = unblock.has(d.date);
          const state = closing ? 'blocked' : opening ? 'free' : d.state;
          const can = d.state === 'free' || d.state === 'blocked';
          return (
            <button key={d.date} className={`cd s-${state} ${closing || opening ? 'ch' : ''}`} disabled={!can} onClick={() => toggle(d)}>
              <b>{dayLabel(d.date)}</b>
              <span>{({ free: 'Open', blocked: 'Closed', booked: 'Booked', pending: 'Request', tour: 'Tour', past: '' } as Record<string, string>)[state] ?? state}</span>
            </button>
          );
        })}
      </div>
      <div style={{ marginTop: 14, display: 'flex', gap: 10, alignItems: 'center' }}>
        <button className="btn dark" onClick={save} disabled={a.busy || (block.size === 0 && unblock.size === 0)}>{a.busy ? 'Saving…' : `Save ${block.size + unblock.size || ''} change${block.size + unblock.size === 1 ? '' : 's'}`}</button>
        <span className="note2">Booked and tour days are set automatically.</span>
      </div>
    </>
  );
}
