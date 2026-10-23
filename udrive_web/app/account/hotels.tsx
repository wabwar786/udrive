'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { Scene } from '@/components/Scene';
import { img } from '@/lib/api';
import { rs } from '@/lib/format';
import type { HotelOwnerHome, OwnerHotel, OwnerRoom, SpecialRate } from '@/lib/types';
import { call, dayLabel, json, Msg, Num, Pill, pkToday, Text, upload, useAction } from './ui';

export function Hotels() {
  const [home, setHome] = useState<HotelOwnerHome | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const a = useAction();
  const load = () => a.run(async () => setHome(await call<HotelOwnerHome>('/api/v1/hotels/owner/home')));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { void load(); }, []);

  if (open) return <HotelManager id={open} close={() => { setOpen(null); void load(); }} />;
  const hotels = home?.hotels ?? [];
  return (
    <>
      <div className="acctHead">
        <div><h1>My hotels</h1><p className="muted">Change room rates any time — the new rate shows straight away. Add special dates for Eid, holidays or the off-season.</p></div>
        <Link className="btn dark" href="/list-your-hotel/">+ Add hotel</Link>
      </div>
      <Msg error={a.error} />
      {home === null && !a.error ? <div className="skel" style={{ minHeight: 200 }} /> : hotels.length === 0 ? (
        <div className="empty">No hotel yet. <Link className="link" href="/list-your-hotel/">List your hotel</Link> — about 5 minutes.</div>
      ) : hotels.map((h) => (
        <div className="vrow" key={h.id}>
          <div className="ph">{img(h.photoUrl) ? <img src={img(h.photoUrl)!} alt={h.name} /> : <Scene seed={h.name} label={h.name} />}</div>
          <div>
            <b>{h.name}</b>
            <div className="s">{h.propertyType} · {[h.city, h.district].filter(Boolean).join(', ')} · {h.roomTypes} room types · {h.photoCount} photos</div>
            <Pill status={h.status} />{!h.isActive && h.status === 'Approved' && <span className="pill p-no">Paused</span>}
            {h.rejectionReason && <div className="s" style={{ color: 'var(--warn)' }}>UDrive: {h.rejectionReason}</div>}
          </div>
          <div className="acts"><button className="btn dark" onClick={() => setOpen(h.id)}>Rooms & rates</button></div>
        </div>
      ))}
    </>
  );
}

function HotelManager({ id, close }: { id: string; close: () => void }) {
  const [h, setH] = useState<OwnerHotel | null>(null);
  const [rates, setRates] = useState<SpecialRate[]>([]);
  const a = useAction();
  useEffect(() => {
    void a.run(async () => {
      const [hotel, special] = await Promise.all([
        call<OwnerHotel>(`/api/v1/hotels/owner/hotels/${id}`),
        call<SpecialRate[]>(`/api/v1/hotels/owner/hotels/${id}/special-rates`).catch(() => []),
      ]);
      setH(hotel); setRates(special);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  if (!h) return <><Msg error={a.error} /><div className="skel" style={{ minHeight: 300 }} /></>;
  const base = `/api/v1/hotels/owner/hotels/${id}`;

  return (
    <>
      <button className="link" style={{ background: 'none', border: 'none', cursor: 'pointer', marginBottom: 14 }} onClick={close}>← My hotels</button>
      <div className="acctHead"><div><h1>{h.name}</h1><p className="muted">{h.propertyType} · {h.city}, {h.district} · <Pill status={h.status} /></p></div></div>
      <Msg error={a.error} ok={a.ok} />
      <RoomsTable h={h} base={base} onSaved={setH} onRates={setRates} />
      <SpecialDates h={h} base={base} rates={rates} setRates={setRates} />
      <Photos h={h} base={base} onSaved={setH} />
      {h.missing.length > 0 && <div className="msg info">Still needed before review: {h.missing.join(', ')}.</div>}
      {h.status === 'Draft' && h.missing.length === 0 && (
        <button className="btn dark" disabled={a.busy} onClick={() => a.run(async () => setH(await call<OwnerHotel>(`${base}/submit`, { method: 'POST' })), 'Sent for review.')}>Send for review</button>
      )}
    </>
  );
}

function RoomsTable({ h, base, onSaved, onRates }: { h: OwnerHotel; base: string; onSaved: (x: OwnerHotel) => void; onRates: (r: SpecialRate[]) => void }) {
  const a = useAction();
  const [edit, setEdit] = useState<Record<string, { rate: number | ''; total: number | '' }>>({});
  const [add, setAdd] = useState({ roomType: '', capacity: 2 as number | '', totalRooms: 1 as number | '', baseRate: '' as number | '', description: '' });
  const changed = Object.keys(edit).filter((k) => {
    const r = h.rooms.find((x) => x.id === k);
    return r && (edit[k].rate !== r.baseRate || edit[k].total !== r.totalRooms);
  });
  const val = (r: OwnerRoom) => edit[r.id] ?? { rate: r.baseRate, total: r.totalRooms };

  async function saveAll() {
    await a.run(async () => {
      let last = h;
      for (const k of changed) {
        const r = h.rooms.find((x) => x.id === k)!;
        const e = edit[k];
        if (!e.rate || e.rate < 1) throw new Error(`Write a rate for ${r.roomType}.`);
        if (!e.total || e.total < 1) throw new Error(`Write how many ${r.roomType} rooms.`);
        last = await call<OwnerHotel>(`${base}/rooms/${k}`, json('PUT', { roomType: r.roomType, capacity: r.capacity, totalRooms: e.total, baseRate: e.rate, description: r.description }));
      }
      onSaved(last); setEdit({});
      onRates(await call<SpecialRate[]>(`${base}/special-rates`).catch(() => []));
    }, 'Rates saved — live now.');
  }
  async function addRoom() {
    await a.run(async () => {
      if (add.roomType.trim().length < 2) throw new Error('Write the room type, like "Double room".');
      if (!add.baseRate) throw new Error('Write the rate per night.');
      onSaved(await call<OwnerHotel>(`${base}/rooms`, json('POST', { ...add, roomType: add.roomType.trim() })));
      setAdd({ roomType: '', capacity: 2, totalRooms: 1, baseRate: '', description: '' });
    }, 'Room type added.');
  }
  async function remove(r: OwnerRoom) {
    if (!window.confirm(`Remove "${r.roomType}"? This can't be undone; past bookings stay.`)) return;
    await a.run(async () => onSaved(await call<OwnerHotel>(`${base}/rooms/${r.id}/remove`, { method: 'POST' })), 'Removed.');
  }

  return (
    <div className="sec2">
      <h3 style={{ marginBottom: 10 }}>Rooms and rates</h3>
      <Msg error={a.error} ok={a.ok} />
      <table className="tbl">
        <thead><tr><th>Room type</th><th>Guests</th><th>Rooms</th><th>Rate per night (Rs)</th><th /></tr></thead>
        <tbody>{h.rooms.map((r) => {
          const v = val(r);
          return (
            <tr key={r.id}>
              <td><b>{r.roomType}</b></td><td>{r.capacity}</td>
              <td><input className={v.total !== r.totalRooms ? 'ch' : ''} type="number" min={1} max={500} value={v.total} onChange={(e) => setEdit({ ...edit, [r.id]: { ...v, total: e.target.value === '' ? '' : Math.min(500, Number(e.target.value)) } })} style={{ width: 80 }} /></td>
              <td><input className={v.rate !== r.baseRate ? 'ch' : ''} type="number" min={1} max={1000000} step={100} value={v.rate} onChange={(e) => setEdit({ ...edit, [r.id]: { ...v, rate: e.target.value === '' ? '' : Math.min(1_000_000, Number(e.target.value)) } })} /></td>
              <td><button className="btn ghost" onClick={() => remove(r)} disabled={a.busy}>Remove</button></td>
            </tr>
          );
        })}</tbody>
      </table>
      <div style={{ margin: '12px 0 18px', display: 'flex', gap: 10, alignItems: 'center' }}>
        <button className="btn dark" onClick={saveAll} disabled={a.busy || changed.length === 0}>{a.busy ? 'Saving…' : `Save ${changed.length || ''} change${changed.length === 1 ? '' : 's'}`}</button>
        <span className="note2">Bookings already made keep their price.</span>
      </div>
      <details>
        <summary className="link" style={{ cursor: 'pointer', display: 'inline-block' }}>+ Add a room type</summary>
        <div className="form2" style={{ marginTop: 12 }}>
          <Text label="Room type" value={add.roomType} onChange={(x) => setAdd({ ...add, roomType: x })} max={60} placeholder="Family suite" />
          <Num label="Rate per night (Rs)" value={add.baseRate} onChange={(x) => setAdd({ ...add, baseRate: x })} min={1} max={1_000_000} step={100} />
          <Num label="Guests per room" value={add.capacity} onChange={(x) => setAdd({ ...add, capacity: x })} min={1} max={20} />
          <Num label="How many rooms" value={add.totalRooms} onChange={(x) => setAdd({ ...add, totalRooms: x })} min={1} max={500} />
        </div>
        <Text label="About the room" value={add.description} onChange={(x) => setAdd({ ...add, description: x })} max={500} area optional />
        <button className="btn ghost" onClick={addRoom} disabled={a.busy}>Add room type</button>
      </details>
    </div>
  );
}

function SpecialDates({ h, base, rates, setRates }: { h: OwnerHotel; base: string; rates: SpecialRate[]; setRates: (r: SpecialRate[]) => void }) {
  const a = useAction();
  const today = pkToday();
  const [f, setF] = useState({ roomId: '', startsOn: today, endsOn: today, kind: 'percent' as 'percent' | 'rate', percent: 20 as number | '', rate: '' as number | '', roomsOpen: '' as number | '' });

  async function add() {
    await a.run(async () => {
      if (f.endsOn < f.startsOn) throw new Error('End date is before the start date.');
      const body = {
        roomId: f.roomId || null, startsOn: f.startsOn, endsOn: f.endsOn,
        rate: f.kind === 'rate' ? f.rate || null : null, percent: f.kind === 'percent' ? f.percent || null : null,
        roomsOpen: f.roomsOpen === '' ? null : f.roomsOpen,
      };
      setRates(await call<SpecialRate[]>(`${base}/special-rates`, json('POST', body)));
    }, 'Special dates saved — live now.');
  }
  async function remove(r: SpecialRate) {
    await a.run(async () => setRates(await call<SpecialRate[]>(`${base}/special-rates/${r.id}/remove`, { method: 'POST' })), 'Removed.');
  }
  const preview = (() => {
    const room = h.rooms.find((r) => r.id === f.roomId) ?? h.rooms[0];
    if (!room) return '';
    const v = f.kind === 'rate' ? (f.rate || 0) : Math.round(room.baseRate * (100 + Number(f.percent || 0)) / 100);
    return `${room.roomType}: ${rs(room.baseRate)} → ${rs(v)} per night`;
  })();

  return (
    <div className="sec2">
      <h3 style={{ marginBottom: 4 }}>Special dates</h3>
      <p className="muted small" style={{ marginTop: 0 }}>A different price — or fewer rooms open — for some days. Up to 120 days at a time. Where two overlap, the newer one wins.</p>
      <Msg error={a.error} ok={a.ok} />
      {rates.length > 0 && (
        <table className="tbl" style={{ marginBottom: 14 }}>
          <thead><tr><th>Dates</th><th>Rooms</th><th>Price</th><th>Rooms open</th><th /></tr></thead>
          <tbody>{rates.map((r) => (
            <tr key={r.id}>
              <td>{dayLabel(r.startsOn)}{r.endsOn !== r.startsOn ? ` – ${dayLabel(r.endsOn)}` : ''}</td><td>{r.roomType}</td>
              <td>{r.rate != null ? rs(r.rate) : `${r.percent! > 0 ? '+' : ''}${r.percent}%`}</td><td>{r.roomsOpen ?? 'all'}</td>
              <td><button className="btn ghost" onClick={() => remove(r)} disabled={a.busy}>Remove</button></td>
            </tr>
          ))}</tbody>
        </table>
      )}
      <div className="form2">
        <label className="fld"><span>From</span><input type="date" min={today} value={f.startsOn} onChange={(e) => setF({ ...f, startsOn: e.target.value, endsOn: e.target.value > f.endsOn ? e.target.value : f.endsOn })} /></label>
        <label className="fld"><span>To (including)</span><input type="date" min={f.startsOn} value={f.endsOn} onChange={(e) => setF({ ...f, endsOn: e.target.value })} /></label>
        <label className="fld"><span>Rooms</span><select value={f.roomId} onChange={(e) => setF({ ...f, roomId: e.target.value })}><option value="">All room types</option>{h.rooms.map((r) => <option key={r.id} value={r.id}>{r.roomType}</option>)}</select></label>
        <label className="fld"><span>Change price by</span><select value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value as 'percent' | 'rate' })}><option value="percent">Percent (+ or −)</option><option value="rate">New fixed rate</option></select></label>
        {f.kind === 'percent'
          ? <label className="fld"><span>Percent (−50 to +200)</span><input type="number" min={-50} max={200} value={f.percent} onChange={(e) => setF({ ...f, percent: e.target.value === '' ? '' : Math.max(-50, Math.min(200, Number(e.target.value))) })} /></label>
          : <Num label="Rate per night (Rs)" value={f.rate} onChange={(x) => setF({ ...f, rate: x })} min={1} max={1_000_000} step={100} />}
        <label className="fld"><span>Rooms open (optional)</span><input type="number" min={0} max={500} placeholder="all" value={f.roomsOpen} onChange={(e) => setF({ ...f, roomsOpen: e.target.value === '' ? '' : Math.max(0, Math.min(500, Number(e.target.value))) })} /></label>
      </div>
      {preview && <p className="note2" style={{ marginTop: 0 }}>{preview}</p>}
      <button className="btn dark" onClick={add} disabled={a.busy}>{a.busy ? 'Saving…' : 'Save special dates'}</button>
    </div>
  );
}

function Photos({ h, base, onSaved }: { h: OwnerHotel; base: string; onSaved: (x: OwnerHotel) => void }) {
  const a = useAction();
  async function addFiles(files: FileList | null) {
    if (!files) return;
    await a.run(async () => {
      let cur = h;
      for (const file of Array.from(files).slice(0, 9 - cur.photos.length)) { cur = await upload<OwnerHotel>(`${base}/photos`, file); onSaved(cur); }
    }, 'Photos added.');
  }
  return (
    <div className="sec2">
      <h3 style={{ marginBottom: 4 }}>Photos ({h.photos.length}/9)</h3>
      <Msg error={a.error} ok={a.ok} />
      <div className="thumbs big">
        {h.photos.map((p) => (
          <div key={p.id} className={p.isMain ? 'main' : ''}>
            {img(p.url) && <img src={img(p.url)!} alt="" />}
            <span className="tb">
              {p.isMain ? <em>Main</em> : <button onClick={() => a.run(async () => onSaved(await call<OwnerHotel>(`${base}/photos/${p.id}/main`, { method: 'POST' })))}>Make main</button>}
              {h.photos.length > 3 && <button onClick={() => a.run(async () => onSaved(await call<OwnerHotel>(`${base}/photos/${p.id}/remove`, { method: 'POST' })))}>Remove</button>}
            </span>
          </div>
        ))}
      </div>
      {h.photos.length < 9 && <label className="fld"><span>Add photos</span><input type="file" multiple accept="image/jpeg,image/png,image/webp" onChange={(e) => { void addFiles(e.target.files); e.target.value = ''; }} /></label>}
    </div>
  );
}
