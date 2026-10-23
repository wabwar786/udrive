'use client';

import { useCallback, useEffect, useState } from 'react';
import { Plus, RefreshCw, Trash2, Upload } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { API_BASE, apiAction, apiFetch, apiUpload } from '../lib/admin-api';
import { PhotosTab } from './photos-tab';

/**
 * Website ("UDrive – Travel & Tour"): what came in from the website, and the
 * ad places on it. The website itself reads only /api/v1/web/*.
 */

const SLOTS: [string, string][] = [
  ['home', 'Home page — wide banner'],
  ['tours', 'Tours list — wide banner'],
  ['tour', 'Tour page — beside booking'],
  ['hotels', 'Hotels list — wide banner'],
  ['hotel', 'Hotel page — beside rooms'],
];

type Ad = {
  id?: string;
  slot: string;
  title: string;
  body: string;
  imageUrl: string | null;
  linkUrl: string | null;
  ctaLabel: string;
  startsOn: string | null;
  endsOn: string | null;
  isActive: boolean;
  sortOrder: number;
  clicks?: number;
  liveNow?: boolean;
};

type Booking = {
  id: string; reference: string; tour: string; departureAt: string; customer: string; customerPhone: string;
  mode: string; seats: number; total: number; advance: number; status: string; driver: string; createdAt: string;
};
type Hotel = { id: string; name: string; city: string; owner: string; ownerPhone: string; status: string; createdAt: string };
type Activity = { bookingsToday: number; bookingsThisMonth: number; valueThisMonth: number; hotelsThisMonth: number; bookings: Booking[]; hotels: Hotel[] };

const BLANK: Ad = { slot: 'home', title: '', body: '', imageUrl: null, linkUrl: null, ctaLabel: 'View', startsOn: null, endsOn: null, isActive: true, sortOrder: 0 };
const rs = (n: number) => `Rs ${Math.round(n).toLocaleString('en-US')}`;
const dt = (s: string) => new Date(s).toLocaleString('en-GB', { timeZone: 'Asia/Karachi', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
const apiBase = API_BASE.replace(/\/$/, '');
const preview = (u: string | null) => (!u ? null : u.startsWith('/') ? `${apiBase}${u}` : u);

export default function Page() {
  const [tab, setTab] = useState<'activity' | 'ads' | 'photos'>('activity');
  const [activity, setActivity] = useState<Activity | null>(null);
  const [ads, setAds] = useState<Ad[] | null>(null);
  const [form, setForm] = useState<Ad | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError('');
    try {
      const [a, list] = await Promise.all([apiFetch<Activity>('/api/v1/admin/web/activity'), apiFetch<Ad[]>('/api/v1/admin/web/ads')]);
      setActivity(a);
      setAds(list);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load the website data.');
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function save() {
    if (!form) return;
    setBusy(true);
    setError('');
    try {
      const { id, clicks: _c, liveNow: _l, ...body } = form;
      const { message } = await apiAction(`/api/v1/admin/web/ads${id ? `/${id}` : ''}`, {
        method: id ? 'PUT' : 'POST',
        body: JSON.stringify({ ...body, linkUrl: body.linkUrl || null, imageUrl: body.imageUrl || null, startsOn: body.startsOn || null, endsOn: body.endsOn || null }),
      });
      setForm(null);
      setNotice(message || 'Saved.');
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save the ad.');
    } finally {
      setBusy(false);
    }
  }

  async function remove(ad: Ad) {
    if (!ad.id || !window.confirm(`Remove the ad "${ad.title}" from the website?`)) return;
    try {
      await apiAction(`/api/v1/admin/web/ads/${ad.id}/remove`, { method: 'POST' });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not remove the ad.');
    }
  }

  async function upload(file: File | undefined) {
    if (!file || !form) return;
    setBusy(true);
    try {
      const { url } = await apiUpload<{ url: string }>('/api/v1/admin/web/ads/image', file);
      setForm({ ...form, imageUrl: url });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Upload failed.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <AdminFrame
      title="Website"
      subtitle="Bookings and hotel registrations from the website, and the ad places on it."
      actions={
        <div className="tableTools">
          <button className={tab === 'activity' ? 'primaryButton' : 'secondaryButton'} onClick={() => setTab('activity')}>From the website</button>
          <button className={tab === 'ads' ? 'primaryButton' : 'secondaryButton'} onClick={() => setTab('ads')}>Ads</button>
          <button className={tab === 'photos' ? 'primaryButton' : 'secondaryButton'} onClick={() => setTab('photos')}>Photos</button>
          <button className="secondaryButton" onClick={() => void load()}><RefreshCw /> Refresh</button>
        </div>
      }
    >
      {error && <ErrorBox message={error} />}
      {notice && <div className="successBox">{notice}</div>}

      {tab === 'activity' && (!activity ? <Loading /> : (
        <>
          <section className="statGrid">
            <Stat label="Bookings today" value={activity.bookingsToday} />
            <Stat label="Bookings this month" value={activity.bookingsThisMonth} />
            <Stat label="Booked value this month" value={rs(activity.valueThisMonth)} />
            <Stat label="Hotels registered this month" value={activity.hotelsThisMonth} />
          </section>
          <section className="panel">
            <header className="panelHeader"><div><h2>Tour bookings from the website</h2><p>Same bookings the driver sees in his app. Customer and driver both get WhatsApp.</p></div></header>
            {activity.bookings.length === 0 ? <Empty title="No website bookings yet" copy="They appear here as soon as someone books a tour on the website." /> : (
              <div className="tableWrap"><table>
                <thead><tr><th>Booked</th><th>Reference</th><th>Tour</th><th>Departs</th><th>Customer</th><th>Seats</th><th>Total</th><th>Advance</th><th>Driver</th><th>Status</th></tr></thead>
                <tbody>{activity.bookings.map((b) => (
                  <tr key={b.id}>
                    <td>{dt(b.createdAt)}</td><td><strong>{b.reference}</strong></td><td>{b.tour}</td><td>{dt(b.departureAt)}</td>
                    <td>{b.customer}<br /><small>{b.customerPhone}</small></td><td>{b.mode === 'Whole vehicle' ? 'Whole' : b.seats}</td>
                    <td>{rs(b.total)}</td><td>{rs(b.advance)}</td><td>{b.driver}</td><td><Badge value={b.status} /></td>
                  </tr>
                ))}</tbody>
              </table></div>
            )}
          </section>
          <section className="panel">
            <header className="panelHeader"><div><h2>Hotels registered on the website</h2><p>Approve them under Tourism → Hotels &amp; approvals, like any other hotel.</p></div></header>
            {activity.hotels.length === 0 ? <Empty title="No hotels from the website yet" /> : (
              <div className="tableWrap"><table>
                <thead><tr><th>Registered</th><th>Hotel</th><th>City</th><th>Owner</th><th>Status</th></tr></thead>
                <tbody>{activity.hotels.map((h) => (
                  <tr key={h.id}><td>{dt(h.createdAt)}</td><td><strong>{h.name}</strong></td><td>{h.city}</td><td>{h.owner}<br /><small>{h.ownerPhone}</small></td><td><Badge value={h.status} /></td></tr>
                ))}</tbody>
              </table></div>
            )}
          </section>
        </>
      ))}

      {tab === 'ads' && (
        <section className="panel">
          <header className="panelHeader">
            <div><h2>Ad places</h2><p>Your own ads on the website — no Google AdSense. Only live ads (active and inside their dates) are shown; the first by order wins each place.</p></div>
            <div className="tableTools"><button className="primaryButton" onClick={() => setForm({ ...BLANK })}><Plus /> New ad</button></div>
          </header>
          {!ads ? <Loading /> : ads.length === 0 ? <Empty title="No ads yet" copy="Add one to fill a place on the website." /> : (
            <div className="tableWrap"><table>
              <thead><tr><th>Picture</th><th>Title</th><th>Place</th><th>Dates</th><th>Order</th><th>Clicks</th><th>Status</th><th /></tr></thead>
              <tbody>{ads.map((a) => (
                <tr key={a.id} className="clickable" onClick={() => setForm({ ...a })}>
                  <td>{preview(a.imageUrl) ? <img src={preview(a.imageUrl)!} alt="" style={{ width: 72, height: 44, objectFit: 'cover', borderRadius: 6 }} /> : '—'}</td>
                  <td><strong>{a.title}</strong><br /><small>{a.body}</small></td>
                  <td>{SLOTS.find(([k]) => k === a.slot)?.[1] ?? a.slot}</td>
                  <td>{a.startsOn ?? 'now'} → {a.endsOn ?? 'no end'}</td>
                  <td>{a.sortOrder}</td><td>{a.clicks ?? 0}</td>
                  <td><Badge value={a.liveNow ? 'Live' : a.isActive ? 'Scheduled' : 'Off'} /></td>
                  <td><button className="iconButton" title="Remove" onClick={(e) => { e.stopPropagation(); void remove(a); }}><Trash2 /></button></td>
                </tr>
              ))}</tbody>
            </table></div>
          )}
        </section>
      )}

      {tab === 'photos' && <PhotosTab />}

      {form && (
        <Modal title={form.id ? 'Edit ad' : 'New ad'} onClose={() => setForm(null)}>
          <div className="formGrid">
            <Field label="Place on the website">
              <select value={form.slot} onChange={(e) => setForm({ ...form, slot: e.target.value })}>
                {SLOTS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
            </Field>
            <Field label="Title"><input value={form.title} maxLength={120} onChange={(e) => setForm({ ...form, title: e.target.value })} /></Field>
            <Field label="Text (one or two lines)"><input value={form.body} maxLength={300} onChange={(e) => setForm({ ...form, body: e.target.value })} /></Field>
            <Field label="Button text"><input value={form.ctaLabel} maxLength={40} onChange={(e) => setForm({ ...form, ctaLabel: e.target.value })} /></Field>
            <Field label="Link (https://…, optional)"><input value={form.linkUrl ?? ''} placeholder="https://" onChange={(e) => setForm({ ...form, linkUrl: e.target.value })} /></Field>
            <Field label="Picture (JPG, PNG or WebP)">
              <label className="secondaryButton" style={{ cursor: 'pointer' }}>
                <Upload /> {busy ? 'Uploading…' : form.imageUrl ? 'Change picture' : 'Upload picture'}
                <input type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => void upload(e.target.files?.[0])} />
              </label>
            </Field>
            <Field label="Show from (optional)"><input type="date" value={form.startsOn ?? ''} onChange={(e) => setForm({ ...form, startsOn: e.target.value || null })} /></Field>
            <Field label="Show until (optional)"><input type="date" value={form.endsOn ?? ''} onChange={(e) => setForm({ ...form, endsOn: e.target.value || null })} /></Field>
            <Field label="Order (lower shows first)"><input type="number" min={0} max={999} value={form.sortOrder} onChange={(e) => setForm({ ...form, sortOrder: Number(e.target.value) })} /></Field>
            <Field label="Active"><input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} /></Field>
          </div>
          {preview(form.imageUrl) && <img src={preview(form.imageUrl)!} alt="" style={{ maxWidth: 320, borderRadius: 10, margin: '0 22px 14px' }} />}
          <div style={{ padding: '0 22px 22px' }}>
            <button className="primaryButton" onClick={() => void save()} disabled={busy}>{busy ? 'Saving…' : 'Save ad'}</button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
