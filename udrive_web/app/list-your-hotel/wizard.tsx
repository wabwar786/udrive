'use client';

import { useState } from 'react';

import { OtpForm } from '@/components/OtpForm';
import { PlayButton } from '@/components/PlayButton';
import { api, img } from '@/lib/api';
import { signedInPhone } from '@/lib/auth';
import { normalisePhone, rs } from '@/lib/format';

/*
 * Uses the app's own Hotel mode endpoints (/api/v1/hotels/owner/*) with the
 * owner's OTP sign-in, so the website can do nothing the app could not:
 * every rule (CNIC both sides, 3–9 photos, one room, owner-only access,
 * admin review before going live) is checked on the server.
 */

type Photo = { id: string; url: string; isMain: boolean };
type Room = { id: string; roomType: string; capacity: number; totalRooms: number; baseRate: number };
type Hotel = { id: string; photos: Photo[]; rooms: Room[]; missing: string[]; status: string };
type Profile = { cnicFront: boolean; cnicBack: boolean; complete: boolean };

const TYPES = ['Hotel', 'Guest house', 'Resort', 'Hut'];
const DISTRICTS = ['Muzaffarabad', 'Neelum', 'Hattian Bala', 'Bagh', 'Haveli', 'Poonch', 'Sudhnoti', 'Kotli', 'Mirpur', 'Bhimber'];
const AMENITIES = ['WiFi', 'Parking', 'Hot water', 'Heating', 'Restaurant', 'Family rooms', 'River view', 'Mountain view', 'Generator / backup power', 'Room service'];
const STEPS = ['Sign in', 'Owner', 'Hotel', 'Photos', 'Rooms', 'Send'];

/** Reads "@34.37,73.47" or "?q=34.37,73.47" or plain "34.37, 73.47". */
function parseLocation(text: string): [number, number] | null {
  const m = text.match(/(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})/);
  if (!m) return null;
  const lat = Number(m[1]);
  const lng = Number(m[2]);
  return lat > 23 && lat < 37.5 && lng > 60 && lng < 78 ? [lat, lng] : null;
}

export function HotelWizard() {
  const [step, setStep] = useState(0);
  const [token, setToken] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [profile, setProfile] = useState<Profile | null>(null);
  const [hotel, setHotel] = useState<Hotel | null>(null);
  const [owner, setOwner] = useState({ ownerName: '', businessName: '', email: '' });
  const [h, setH] = useState({
    name: '', propertyType: 'Hotel', district: 'Muzaffarabad', city: '', address: '', description: '',
    contactPhone: '', checkInTime: '14:00', checkOutTime: '12:00', amenities: [] as string[], transportAvailable: false,
    location: '', latitude: null as number | null, longitude: null as number | null,
  });
  const [room, setRoom] = useState({ roomType: 'Double room', capacity: 2, totalRooms: 1, baseRate: 5000, description: '' });

  const call = async <T,>(path: string, init: RequestInit = {}) => api<T>(path, { ...init, token });
  async function run(fn: () => Promise<void>) {
    setBusy(true);
    setError('');
    try { await fn(); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  // ── step 1: owner
  async function saveOwner() {
    await run(async () => {
      if (owner.ownerName.trim().length < 2) throw new Error('Write the owner name as on the CNIC.');
      if (owner.businessName.trim().length < 2) throw new Error('Write the business name.');
      const p = await call<Profile>('/api/v1/hotels/owner/profile', { method: 'PUT', body: JSON.stringify({ ...owner, phone: signedInPhone() }) });
      setProfile(p);
      if (!p.cnicFront || !p.cnicBack) throw new Error('Upload both sides of the CNIC.');
      setStep(2);
    });
  }
  async function uploadCnic(side: 'front' | 'back', file: File | undefined) {
    if (!file) return;
    await run(async () => {
      const form = new FormData();
      form.append('file', file);
      setProfile(await call<Profile>(`/api/v1/hotels/owner/profile/cnic/${side}`, { method: 'POST', body: form }));
    });
  }

  // ── step 2: hotel
  function useMyLocation() {
    if (!navigator.geolocation) return setError('This browser cannot share location. Paste a Google Maps link instead.');
    navigator.geolocation.getCurrentPosition(
      (p) => setH((x) => ({ ...x, latitude: +p.coords.latitude.toFixed(6), longitude: +p.coords.longitude.toFixed(6), location: `${p.coords.latitude.toFixed(5)}, ${p.coords.longitude.toFixed(5)}` })),
      () => setError('Location was not shared. Paste the hotel\'s Google Maps link instead.'),
      { enableHighAccuracy: true, timeout: 15000 },
    );
  }
  async function saveHotel() {
    await run(async () => {
      const loc = h.latitude != null ? [h.latitude, h.longitude] : parseLocation(h.location);
      if (h.name.trim().length < 2) throw new Error('Write the hotel name.');
      if (h.description.trim().length < 10) throw new Error('Write a few lines about the hotel.');
      if (!h.city.trim() || !h.address.trim()) throw new Error('Write the city and address.');
      if (!loc) throw new Error('Add the location: tap "Use my location" at the hotel, or paste its Google Maps link.');
      const phone = normalisePhone(h.contactPhone);
      if (!phone) throw new Error('Write the WhatsApp number where bookings should go.');
      const body = JSON.stringify({
        name: h.name, propertyType: h.propertyType, description: h.description, address: h.address, city: h.city,
        district: h.district, latitude: loc[0], longitude: loc[1], contactPhone: phone, amenities: h.amenities,
        transportAvailable: h.transportAvailable, checkInTime: h.checkInTime, checkOutTime: h.checkOutTime,
      });
      const saved = hotel
        ? await call<Hotel>(`/api/v1/hotels/owner/hotels/${hotel.id}`, { method: 'PUT', body })
        : await call<Hotel>('/api/v1/hotels/owner/hotels', { method: 'POST', body });
      if (!hotel) await call(`/api/v1/web/hotels/${saved.id}/from-web`, { method: 'POST' }).catch(() => undefined);
      setHotel(saved);
      setStep(3);
    });
  }

  // ── step 3: photos
  async function addPhotos(files: FileList | null) {
    if (!files || !hotel) return;
    await run(async () => {
      let current = hotel;
      for (const file of Array.from(files).slice(0, 9 - current.photos.length)) {
        const form = new FormData();
        form.append('file', file);
        current = await call<Hotel>(`/api/v1/hotels/owner/hotels/${hotel.id}/photos`, { method: 'POST', body: form });
        setHotel(current);
      }
    });
  }

  // ── step 4: rooms
  async function addRoom() {
    if (!hotel) return;
    await run(async () => {
      if (room.roomType.trim().length < 2) throw new Error('Write the room type, like "Double room".');
      if (room.baseRate < 500) throw new Error('Write the price per night.');
      setHotel(await call<Hotel>(`/api/v1/hotels/owner/hotels/${hotel.id}/rooms`, { method: 'POST', body: JSON.stringify(room) }));
    });
  }

  // ── step 5: submit
  async function submit() {
    if (!hotel) return;
    await run(async () => {
      setHotel(await call<Hotel>(`/api/v1/hotels/owner/hotels/${hotel.id}/submit`, { method: 'POST' }));
      setStep(6);
    });
  }

  const set = (k: string, v: unknown) => setH((x) => ({ ...x, [k]: v }));

  return (
    <div className="wiz">
      <div className="wsteps" aria-label="Steps">
        {STEPS.map((s, i) => <span key={s} className={i === step ? 'on' : i < step ? 'done' : ''}>{i + 1}. {s}</span>)}
      </div>
      {error && <div className="msg err" role="alert">{error}</div>}

      {step === 0 && (
        <div className="box">
          <h3 style={{ marginBottom: 6 }}>Sign in with WhatsApp</h3>
          <p className="muted" style={{ marginTop: 0 }}>Use the owner&apos;s own number. The same number opens Hotel mode in the UDrive app.</p>
          <OtpForm action="Continue" onVerified={(t, name) => { setToken(t); setOwner((o) => ({ ...o, ownerName: o.ownerName || name })); setStep(1); }} />
        </div>
      )}

      {step === 1 && (
        <div className="box">
          <h3 style={{ marginBottom: 14 }}>Owner details</h3>
          <div className="form2">
            <label className="fld"><span>Owner name (as on CNIC)</span><input value={owner.ownerName} onChange={(e) => setOwner({ ...owner, ownerName: e.target.value })} maxLength={120} /></label>
            <label className="fld"><span>Business name</span><input value={owner.businessName} onChange={(e) => setOwner({ ...owner, businessName: e.target.value })} maxLength={120} /></label>
          </div>
          <label className="fld"><span>Email (optional)</span><input type="email" value={owner.email} onChange={(e) => setOwner({ ...owner, email: e.target.value })} maxLength={160} /></label>
          <p className="small muted">CNIC photos are seen only by the UDrive team for verification. They are never shown on the website.</p>
          <div className="form2">
            <label className="fld"><span>CNIC front {profile?.cnicFront ? '✓ uploaded' : ''}</span><input type="file" accept="image/jpeg,image/png,image/webp" onChange={(e) => uploadCnic('front', e.target.files?.[0])} /></label>
            <label className="fld"><span>CNIC back {profile?.cnicBack ? '✓ uploaded' : ''}</span><input type="file" accept="image/jpeg,image/png,image/webp" onChange={(e) => uploadCnic('back', e.target.files?.[0])} /></label>
          </div>
          <button className="btn dark" onClick={saveOwner} disabled={busy}>{busy ? 'Saving…' : 'Next'}</button>
        </div>
      )}

      {step === 2 && (
        <div className="box">
          <h3 style={{ marginBottom: 14 }}>About the hotel</h3>
          <div className="form2">
            <label className="fld"><span>Hotel name</span><input value={h.name} onChange={(e) => set('name', e.target.value)} maxLength={120} /></label>
            <label className="fld"><span>Type</span><select value={h.propertyType} onChange={(e) => set('propertyType', e.target.value)}>{TYPES.map((t) => <option key={t}>{t}</option>)}</select></label>
            <label className="fld"><span>District</span><select value={h.district} onChange={(e) => set('district', e.target.value)}>{DISTRICTS.map((d) => <option key={d}>{d}</option>)}</select></label>
            <label className="fld"><span>City / town</span><input value={h.city} onChange={(e) => set('city', e.target.value)} maxLength={80} placeholder="Keran" /></label>
          </div>
          <label className="fld"><span>Address</span><input value={h.address} onChange={(e) => set('address', e.target.value)} maxLength={200} /></label>
          <label className="fld"><span>About the hotel</span><textarea value={h.description} onChange={(e) => set('description', e.target.value)} maxLength={2000} placeholder="Rooms, view, food, how far from the main road…" /></label>
          <div className="form2">
            <label className="fld"><span>WhatsApp for bookings</span><input value={h.contactPhone} onChange={(e) => set('contactPhone', e.target.value)} inputMode="tel" placeholder="0300 1234567" /></label>
            <div className="form2" style={{ gap: '0 10px' }}>
              <label className="fld"><span>Check-in</span><input type="time" value={h.checkInTime} onChange={(e) => set('checkInTime', e.target.value)} /></label>
              <label className="fld"><span>Check-out</span><input type="time" value={h.checkOutTime} onChange={(e) => set('checkOutTime', e.target.value)} /></label>
            </div>
          </div>
          <label className="fld"><span>Location — Google Maps link or coordinates</span><input value={h.location} onChange={(e) => setH((x) => ({ ...x, location: e.target.value, latitude: null, longitude: null }))} placeholder="https://maps.google.com/…@34.648,73.953…" /></label>
          <button className="btn ghost" type="button" onClick={useMyLocation} style={{ marginBottom: 14 }}>Use my location (stand at the hotel)</button>
          <div className="amen">
            {AMENITIES.map((a) => (
              <label key={a}><input type="checkbox" checked={h.amenities.includes(a)} onChange={(e) => set('amenities', e.target.checked ? [...h.amenities, a] : h.amenities.filter((x) => x !== a))} />{a}</label>
            ))}
            <label><input type="checkbox" checked={h.transportAvailable} onChange={(e) => set('transportAvailable', e.target.checked)} />Pickup / transport</label>
          </div>
          <button className="btn dark" onClick={saveHotel} disabled={busy}>{busy ? 'Saving…' : 'Next'}</button>
        </div>
      )}

      {step === 3 && hotel && (
        <div className="box">
          <h3 style={{ marginBottom: 6 }}>Photos (3 to 9)</h3>
          <p className="muted" style={{ marginTop: 0 }}>Outside, rooms, view and bathroom. Clear daylight photos get more bookings.</p>
          <div className="thumbs">{hotel.photos.map((p) => <div key={p.id}>{img(p.url) && <img src={img(p.url)!} alt="" />}</div>)}</div>
          {hotel.photos.length < 9 && <label className="fld"><span>Add photos</span><input type="file" multiple accept="image/jpeg,image/png,image/webp" onChange={(e) => addPhotos(e.target.files)} /></label>}
          <button className="btn dark" onClick={() => setStep(4)} disabled={busy || hotel.photos.length < 3}>{busy ? 'Uploading…' : hotel.photos.length < 3 ? `Add ${3 - hotel.photos.length} more` : 'Next'}</button>
        </div>
      )}

      {step === 4 && hotel && (
        <div className="box">
          <h3 style={{ marginBottom: 14 }}>Rooms</h3>
          {hotel.rooms.length > 0 && (
            <div className="rooms">{hotel.rooms.map((r) => <div key={r.id}><span>{r.roomType} · {r.capacity} guests · {r.totalRooms} rooms</span><b>{rs(r.baseRate)}</b></div>)}</div>
          )}
          <div className="form2">
            <label className="fld"><span>Room type</span><input value={room.roomType} onChange={(e) => setRoom({ ...room, roomType: e.target.value })} maxLength={60} /></label>
            <label className="fld"><span>Price per night (Rs)</span><input type="number" min={500} value={room.baseRate} onChange={(e) => setRoom({ ...room, baseRate: Number(e.target.value) })} /></label>
            <label className="fld"><span>Guests per room</span><input type="number" min={1} max={20} value={room.capacity} onChange={(e) => setRoom({ ...room, capacity: Number(e.target.value) })} /></label>
            <label className="fld"><span>How many rooms of this type</span><input type="number" min={1} max={500} value={room.totalRooms} onChange={(e) => setRoom({ ...room, totalRooms: Number(e.target.value) })} /></label>
          </div>
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
            <button className="btn ghost" onClick={addRoom} disabled={busy}>{hotel.rooms.length ? 'Add another room type' : 'Add room type'}</button>
            <button className="btn dark" onClick={() => setStep(5)} disabled={busy || hotel.rooms.length === 0}>Next</button>
          </div>
        </div>
      )}

      {step === 5 && hotel && (
        <div className="box">
          <h3 style={{ marginBottom: 6 }}>Send for review</h3>
          <p className="muted" style={{ marginTop: 0 }}>Our team checks the details and CNIC, then your hotel goes live on the app and website. You&apos;ll hear on WhatsApp.</p>
          {hotel.missing.length > 0 && <div className="msg info">Still needed: {hotel.missing.join(', ')}.</div>}
          <button className="btn dark" onClick={submit} disabled={busy}>{busy ? 'Sending…' : 'Send for review'}</button>
        </div>
      )}

      {step === 6 && (
        <div className="box done">
          <div className="big">✓</div>
          <h3>Sent for review</h3>
          <p className="muted">We&apos;ll check it soon. To edit photos, rooms or prices later, open the UDrive app with the same number and switch to Hotel mode. Keep your hotel wallet topped up to receive bookings.</p>
          <PlayButton />
        </div>
      )}
    </div>
  );
}
