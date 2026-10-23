'use client';

import { useEffect, useMemo, useState } from 'react';

import { rs } from '@/lib/format';
import type { Departure, DepartureMonth, ListingHome } from '@/lib/types';
import { call, json, Msg, Num, pkToday, Text, useAction } from './ui';

const monthOf = (iso: string) => iso.slice(0, 7);
const shift = (ym: string, n: number) => { const [y, m] = ym.split('-').map(Number); const d = new Date(Date.UTC(y, m - 1 + n, 1)); return d.toISOString().slice(0, 7); };
const monthName = (ym: string) => new Date(`${ym}-01T00:00:00Z`).toLocaleDateString('en-GB', { month: 'long', year: 'numeric', timeZone: 'UTC' });

export function Departures({ home }: { home: ListingHome | null }) {
  const tourVehicles = useMemo(() => (home?.vehicles ?? []).filter((v) => v.wantsTour), [home]);
  const [vid, setVid] = useState('');
  const [month, setMonth] = useState(monthOf(pkToday()));
  const [data, setData] = useState<DepartureMonth | null>(null);
  const [day, setDay] = useState<string | null>(null);
  const a = useAction();

  useEffect(() => { if (!vid && tourVehicles[0]) setVid(tourVehicles[0].id); }, [tourVehicles, vid]);

  async function load() {
    if (!vid) return;
    await a.run(async () => setData(await call<DepartureMonth>(`/api/v1/listings/vehicles/${vid}/departures?month=${month}`)));
  }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { void load(); }, [vid, month]);

  if (!home) return <div className="skel" style={{ minHeight: 300 }} />;
  if (tourVehicles.length === 0) {
    return (
      <>
        <div className="acctHead"><div><h1>Tour departures</h1></div></div>
        <div className="empty">No vehicle is set for tours yet. Edit a vehicle in <b>Vehicles</b> and tick “Tours”.</div>
      </>
    );
  }

  const v = tourVehicles.find((x) => x.id === vid);
  const live = v?.tourReview?.status === 'Approved';
  const byDate = new Map((data?.days ?? []).filter((d) => d.date).map((d) => [d.date!, d]));
  const [y, m] = month.split('-').map(Number);
  const daysIn = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const pad = (new Date(Date.UTC(y, m - 1, 1)).getUTCDay() + 6) % 7;
  const today = pkToday();

  return (
    <>
      <div className="acctHead">
        <div><h1>Tour departures</h1><p className="muted">Pick a day and post a departure. It shows on the website and app with seats left.</p></div>
        <label className="fld" style={{ minWidth: 240, marginBottom: 0 }}><span>Vehicle</span>
          <select value={vid} onChange={(e) => { setVid(e.target.value); setDay(null); }}>{tourVehicles.map((x) => <option key={x.id} value={x.id}>{x.name} · {x.registrationNumber}</option>)}</select>
        </label>
      </div>
      {!live && <div className="msg info">This vehicle is not live for tours yet ({v?.tourReview?.status ?? 'not sent'}). You can post departures once UDrive approves it.</div>}
      <Msg error={a.error} ok={a.ok} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
        <button className="btn ghost" onClick={() => setMonth(shift(month, -1))} disabled={month <= monthOf(today)}>←</button>
        <b style={{ minWidth: 150, textAlign: 'center' }}>{monthName(month)}</b>
        <button className="btn ghost" onClick={() => setMonth(shift(month, 1))} disabled={month >= shift(monthOf(today), 3)}>→</button>
      </div>
      <div className="cal">
        {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => <div key={d} className="hd">{d}</div>)}
        {Array.from({ length: pad }, (_, i) => <div key={`p${i}`} className="hd" />)}
        {Array.from({ length: daysIn }, (_, i) => {
          const iso = `${month}-${String(i + 1).padStart(2, '0')}`;
          const d = byDate.get(iso);
          const past = iso < today;
          return (
            <button key={iso} className={`cd ${d ? 's-dep' : past ? 's-past' : 's-free'} ${day === iso ? 'ch' : ''}`} disabled={past || !live} onClick={() => setDay(iso)}>
              <b>{i + 1}</b>
              {d ? <span>{d.time} → {d.destination}<br />{d.seatsSold}/{d.totalSeats} sold</span> : <span>{past ? '' : '+ add'}</span>}
            </button>
          );
        })}
      </div>
      {day && data && v && <DayForm key={`${vid}${day}`} vid={vid} date={day} existing={byDate.get(day) ?? null} month={data} home={home} onDone={async () => { setDay(null); await load(); }} />}
    </>
  );
}

function DayForm({ vid, date, existing, month, home, onDone }: { vid: string; date: string; existing: Departure | null; month: DepartureMonth; home: ListingHome; onDone: () => Promise<void> }) {
  const t = existing ?? month.template;
  const a = useAction();
  const [f, setF] = useState({
    from: t?.from ?? 'Muzaffarabad', to: t?.destination ?? '', time: t?.time ?? '07:00', durationDays: t?.durationDays ?? 1,
    pricePerSeat: (t?.pricePerSeat ?? '') as number | '', wholeVehiclePrice: (t?.wholeVehiclePrice ?? '') as number | '',
    pickupPoint: t?.pickupPoint ?? '', fleetDriverId: t?.fleetDriverId ?? '',
  });
  const drivers = home.drivers.filter((d) => d.status === 'Approved' && d.licenceValid);

  async function save() {
    await a.run(async () => {
      if (f.to.trim().length < 2) throw new Error('Where does the trip go?');
      if (!f.wholeVehiclePrice) throw new Error('Write the price for the whole vehicle.');
      await call(`/api/v1/listings/vehicles/${vid}/departures/${date}`, json('PUT', {
        from: f.from.trim(), to: f.to.trim(), destinationId: '00000000-0000-0000-0000-000000000000', time: f.time,
        durationDays: f.durationDays, pricePerSeat: month.perSeatAllowed ? f.pricePerSeat || 0 : 0, wholeVehiclePrice: f.wholeVehiclePrice,
        pickupPoint: f.pickupPoint.trim() || null, fleetDriverId: f.fleetDriverId || null,
      }));
      await onDone();
    });
  }
  async function cancel() {
    if (!window.confirm('Cancel this departure? People who booked are told on WhatsApp.')) return;
    await a.run(async () => { await call(`/api/v1/listings/vehicles/${vid}/departures/${date}/cancel`, { method: 'POST' }); await onDone(); });
  }

  return (
    <div className="sec2" style={{ marginTop: 16 }}>
      <h3 style={{ marginBottom: 10 }}>{existing ? 'Change' : 'New'} departure · {new Date(`${date}T00:00:00Z`).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' })}</h3>
      <Msg error={a.error} />
      <div className="form2">
        <Text label="From" value={f.from} onChange={(x) => setF({ ...f, from: x })} max={120} />
        <Text label="To" value={f.to} onChange={(x) => setF({ ...f, to: x })} max={120} placeholder="Arang Kel" />
        <label className="fld"><span>Leaves at</span><input type="time" value={f.time} onChange={(e) => setF({ ...f, time: e.target.value })} /></label>
        <label className="fld"><span>Days</span><select value={f.durationDays} onChange={(e) => setF({ ...f, durationDays: Number(e.target.value) })}>{[1, 2, 3, 4, 5, 6, 7].map((n) => <option key={n} value={n}>{n} {n === 1 ? 'day' : 'days'}</option>)}</select></label>
        {month.perSeatAllowed && <Num label={`Price per seat (Rs) · ${month.totalSeats} seats`} value={f.pricePerSeat} onChange={(x) => setF({ ...f, pricePerSeat: x })} min={0} max={2_000_000} step={100} />}
        <Num label="Whole vehicle (Rs)" value={f.wholeVehiclePrice} onChange={(x) => setF({ ...f, wholeVehiclePrice: x })} min={0} max={2_000_000} step={500} />
      </div>
      <Text label="Pickup point" value={f.pickupPoint} onChange={(x) => setF({ ...f, pickupPoint: x })} max={200} optional />
      <label className="fld"><span>Driver</span>
        <select value={f.fleetDriverId} onChange={(e) => setF({ ...f, fleetDriverId: e.target.value })}>
          <option value="">Me</option>{drivers.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
      </label>
      {existing && existing.seatsSold > 0 && <div className="msg info">{existing.seatsSold} seats already sold ({rs(existing.pricePerSeat * existing.seatsSold)}).</div>}
      <div style={{ display: 'flex', gap: 10 }}>
        <button className="btn dark" onClick={save} disabled={a.busy}>{a.busy ? 'Saving…' : existing ? 'Save changes' : 'Post departure'}</button>
        {existing && <button className="btn ghost" onClick={cancel} disabled={a.busy}>Cancel departure</button>}
      </div>
    </div>
  );
}
