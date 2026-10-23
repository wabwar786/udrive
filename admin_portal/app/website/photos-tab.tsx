'use client';

import { useCallback, useEffect, useState } from 'react';
import { RefreshCw, Search, Upload } from 'lucide-react';

import { Empty, ErrorBox, Field, Loading } from '../components/ui';
import { API_BASE, apiAction, apiFetch, apiUpload } from '../lib/admin-api';

/**
 * Website → Photos: destination pictures for the hero, picks and cards.
 * Found weekly on Wikimedia Commons by location (Azad Kashmir places only);
 * the team can hide any, upload its own (always shown first), and set what
 * kind of place each destination is and its drive time.
 */
type Place = { id: string; slug: string; name: string; district: string; hasLocation: boolean; kind: string | null; driveHours: number | null; photos: number };
type Photo = { id: string; destinationId: string; destination: string; source: string; url: string; pageUrl: string | null; author: string; license: string; season: string; takenMonth: number | null; hidden: boolean; createdAt: string };
type Data = { places: Place[]; photos: Photo[]; lastSearch: string | null; searching: boolean };

const SEASONS = ['any', 'snow', 'winter', 'spring', 'summer', 'autumn'];
const KINDS: [string, string][] = [['', 'Not set'], ['lake', 'Lake'], ['meadow', 'Meadow / high place'], ['river', 'River & town']];
const apiBase = API_BASE.replace(/\/$/, '');
const src = (u: string) => (u.startsWith('/') ? `${apiBase}${u}` : u);
const dt = (s: string) => new Date(s).toLocaleString('en-GB', { timeZone: 'Asia/Karachi', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

export function PhotosTab() {
  const [data, setData] = useState<Data | null>(null);
  const [place, setPlace] = useState('');
  const [season, setSeason] = useState('any');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [edit, setEdit] = useState<Record<string, { kind: string; hours: string }>>({});

  const load = useCallback(async () => {
    setError('');
    try { setData(await apiFetch<Data>('/api/v1/admin/web/photos')); } catch (e) { setError(e instanceof Error ? e.message : 'Could not load photos.'); }
  }, []);
  useEffect(() => { void load(); }, [load]);

  async function act<T>(fn: () => Promise<{ data: T; message: string }>, done: string) {
    setBusy(true); setError(''); setNotice('');
    try { const r = await fn(); if (r.data && typeof r.data === 'object' && 'photos' in (r.data as object)) setData(r.data as unknown as Data); setNotice(r.message || done); }
    catch (e) { setError(e instanceof Error ? e.message : 'Could not save.'); }
    finally { setBusy(false); }
  }

  async function upload(file: File | undefined) {
    if (!file || !place) return setError('Choose the place first, then the picture.');
    setBusy(true); setError('');
    try {
      const { url } = await apiUpload<{ url: string }>('/api/v1/admin/web/ads/image', file);
      const { data: d } = await apiAction<Data>('/api/v1/admin/web/photos', { method: 'POST', body: JSON.stringify({ destinationId: place, url, season }) });
      setData(d); setNotice('Photo added — it shows first for this place.');
    } catch (e) { setError(e instanceof Error ? e.message : 'Upload failed.'); } finally { setBusy(false); }
  }

  if (!data) return error ? <ErrorBox message={error} /> : <Loading />;
  const shown = data.photos.filter((p) => !place || p.destinationId === place);
  const hidden = data.photos.filter((p) => p.hidden).length;
  const noLocation = data.places.filter((p) => !p.hasLocation);

  return (
    <>
      {error && <ErrorBox message={error} />}
      {notice && <div className="successBox">{notice}</div>}
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Destination photos · {data.photos.length - hidden} showing · {hidden} hidden</h2>
            <p>Found weekly on Wikimedia Commons within 2 km of each Azad Kashmir place (1 km on the LoC). Last search: {data.lastSearch ? dt(data.lastSearch) : 'not yet since the last deploy'}.{data.searching ? ' Searching now…' : ''}</p>
          </div>
          <div className="tableTools">
            <button className="secondaryButton" disabled={busy || data.searching} onClick={() => void act(() => apiAction<boolean>('/api/v1/admin/web/photos/find', { method: 'POST' }), 'Search started.')}><Search /> Find new photos now</button>
            <button className="secondaryButton" onClick={() => void load()}><RefreshCw /> Refresh</button>
          </div>
        </header>
        <div className="formGrid" style={{ padding: '14px 17px 0' }}>
          <Field label="Place">
            <select value={place} onChange={(e) => setPlace(e.target.value)}>
              <option value="">All places</option>
              {data.places.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.district} ({p.photos})</option>)}
            </select>
          </Field>
          <Field label="Season of your photo">
            <select value={season} onChange={(e) => setSeason(e.target.value)}>{SEASONS.map((s) => <option key={s}>{s}</option>)}</select>
          </Field>
          <Field label="Upload own photo (landscape JPG, PNG or WebP)">
            <label className="primaryButton" style={{ cursor: place ? 'pointer' : 'not-allowed', opacity: place ? 1 : 0.6 }}>
              <Upload /> {busy ? 'Uploading…' : 'Upload'}
              <input type="file" accept="image/jpeg,image/png,image/webp" hidden disabled={!place || busy} onChange={(e) => { void upload(e.target.files?.[0]); e.target.value = ''; }} />
            </label>
          </Field>
        </div>
        {shown.length === 0 ? <Empty title="No photos yet" copy="Click “Find new photos now”, or upload your own." /> : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(240px,1fr))', gap: 14, padding: 17 }}>
            {shown.map((p) => (
              <div key={p.id} style={{ border: '1px solid #E6ECEA', borderRadius: 14, overflow: 'hidden', opacity: p.hidden ? 0.45 : 1 }}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={src(p.url)} alt="" loading="lazy" referrerPolicy="no-referrer" style={{ width: '100%', height: 150, objectFit: 'cover', display: 'block', background: '#EEF2F0' }} />
                <div style={{ padding: '10px 12px', fontSize: 12.5, color: '#4F5F58' }}>
                  <b style={{ color: '#0B1B33', fontSize: 14, display: 'block' }}>{p.destination}</b>
                  {p.source === 'Own' ? 'UDrive upload' : <>by {p.author} · {p.license}</>}
                  <div style={{ margin: '6px 0' }}><span className="badge">{p.season}</span>{p.takenMonth ? <span className="badge" style={{ marginLeft: 4 }}>month {p.takenMonth}</span> : null}</div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    {p.pageUrl ? <a href={p.pageUrl} target="_blank" rel="noopener noreferrer">Commons page</a> : <span>{p.source}</span>}
                    <button className="secondaryButton" disabled={busy} onClick={() => void act(() => apiAction<Data>(`/api/v1/admin/web/photos/${p.id}/${p.hidden ? 'show' : 'hide'}`, { method: 'POST' }), p.hidden ? 'Shown.' : 'Hidden from the website.')}>{p.hidden ? 'Show' : 'Hide'}</button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="panel">
        <header className="panelHeader"><div><h2>Places for “Where to go this week”</h2><p>What kind of place it is (for Lakes / Meadows / Rivers &amp; towns) and the drive from Muzaffarabad. Leave hours empty and the website estimates it from the map.</p></div></header>
        {noLocation.length > 0 && <p style={{ padding: '0 17px', color: '#B26B00', fontSize: 13 }}>No map location (no photos or drive time): {noLocation.map((p) => p.name).join(', ')} — set it under Tourism → Destinations.</p>}
        <div className="tableWrap"><table>
          <thead><tr><th>Place</th><th>District</th><th>Kind</th><th>Hours from Muzaffarabad</th><th>Photos</th><th /></tr></thead>
          <tbody>{data.places.map((p) => {
            const e = edit[p.id] ?? { kind: p.kind ?? '', hours: p.driveHours != null ? String(p.driveHours) : '' };
            const changed = e.kind !== (p.kind ?? '') || e.hours !== (p.driveHours != null ? String(p.driveHours) : '');
            return (
              <tr key={p.id}>
                <td><strong>{p.name}</strong></td><td>{p.district}</td>
                <td><select value={e.kind} onChange={(x) => setEdit({ ...edit, [p.id]: { ...e, kind: x.target.value } })}>{KINDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></td>
                <td><input type="number" min={0.5} max={24} step={0.5} value={e.hours} placeholder="auto" style={{ width: 90 }} onChange={(x) => setEdit({ ...edit, [p.id]: { ...e, hours: x.target.value } })} /></td>
                <td>{p.photos}</td>
                <td>{changed && <button className="primaryButton" disabled={busy} onClick={() => void act(() => apiAction<Data>(`/api/v1/admin/web/places/${p.id}`, { method: 'PUT', body: JSON.stringify({ kind: e.kind || null, driveHours: e.hours ? Number(e.hours) : null }) }), 'Saved.').then(() => { const n = { ...edit }; delete n[p.id]; setEdit(n); })}>Save</button>}</td>
              </tr>
            );
          })}</tbody>
        </table></div>
      </section>
    </>
  );
}
