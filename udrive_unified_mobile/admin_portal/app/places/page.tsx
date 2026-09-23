'use client';

import { useEffect, useState } from 'react';
import { AdminFrame } from '../components/admin-frame';
import { ErrorBox, Loading } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

type Place = {
  id: string;
  name: string;
  district: string;
  aliases: string[];
  latitude: number;
  longitude: number;
  note: string;
  isActive: boolean;
};

const EMPTY = {
  name: '',
  district: '',
  aliases: '',
  latitude: '',
  longitude: '',
  note: '',
  isActive: true,
};

/**
 * Pulls coordinates out of anything you might paste.
 *
 * Getting a pin out of Google Maps means copying a link or a coordinate pair,
 * and both arrive in several shapes. Asking someone to hand-extract two numbers
 * from a URL is how transposed coordinates happen, so every common form is
 * handled here instead:
 *
 *   https://maps.google.com/...@34.5822,73.8992,15z
 *   https://maps.google.com/...!3d34.5822!4d73.8992
 *   https://maps.app.goo.gl/... ?q=34.5822,73.8992
 *   34.5822, 73.8992
 *
 * Short goo.gl links cannot be resolved here — they need a redirect the browser
 * will not follow cross-origin — so those are reported rather than silently
 * ignored.
 */
function extractCoordinates(
  input: string,
): { lat: number; lng: number } | { error: string } | null {
  const text = input.trim();
  if (!text) return null;

  if (/^https?:\/\/(maps\.app\.goo\.gl|goo\.gl)/i.test(text)) {
    return {
      error:
        'Short Google links cannot be read directly. Open it in a browser, ' +
        'then copy the full link from the address bar.',
    };
  }

  const patterns = [
    /@(-?\d+\.\d+),\s*(-?\d+\.\d+)/, // .../@lat,lng,zoom
    /!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/, // place data
    /[?&]q=(-?\d+\.\d+),\s*(-?\d+\.\d+)/, // ?q=lat,lng
    /^(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)$/, // plain pair
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      return { lat: parseFloat(match[1]), lng: parseFloat(match[2]) };
    }
  }

  return { error: 'No coordinates found in that text.' };
}

export default function Page() {
  const [places, setPlaces] = useState<Place[]>([]);
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [form, setForm] = useState({ ...EMPTY });
  const [paste, setPaste] = useState('');

  async function load() {
    setBusy(true);
    try {
      setPlaces(await apiFetch<Place[]>('/api/v1/admin/places'));
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load places.');
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  function applyPaste() {
    const result = extractCoordinates(paste);
    if (!result) return;
    if ('error' in result) {
      setError(result.error);
      return;
    }
    setError('');
    setForm((f) => ({
      ...f,
      latitude: String(result.lat),
      longitude: String(result.lng),
    }));
    setPaste('');
  }

  function edit(place: Place) {
    setEditingId(place.id);
    setForm({
      name: place.name,
      district: place.district,
      aliases: place.aliases.join(', '),
      latitude: String(place.latitude),
      longitude: String(place.longitude),
      note: place.note,
      isActive: place.isActive,
    });
    setNotice('');
    setError('');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function cancelEdit() {
    setEditingId(null);
    setForm({ ...EMPTY });
  }

  async function save() {
    setSaving(true);
    setError('');
    setNotice('');
    try {
      const body = JSON.stringify({
        name: form.name,
        district: form.district,
        aliases: form.aliases
          .split(',')
          .map((a) => a.trim())
          .filter(Boolean),
        latitude: parseFloat(form.latitude),
        longitude: parseFloat(form.longitude),
        note: form.note,
        isActive: form.isActive,
      });

      if (editingId) {
        await apiFetch(`/api/v1/admin/places/${editingId}`, {
          method: 'PUT',
          body,
        });
        setNotice(`Updated ${form.name}.`);
      } else {
        await apiFetch('/api/v1/admin/places', { method: 'POST', body });
        setNotice(`Added ${form.name}. It is searchable immediately.`);
      }

      cancelEdit();
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save.');
    } finally {
      setSaving(false);
    }
  }

  async function remove(place: Place) {
    if (!confirm(`Delete ${place.name}?`)) return;
    try {
      await apiFetch(`/api/v1/admin/places/${place.id}`, { method: 'DELETE' });
      setNotice(`Deleted ${place.name}.`);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not delete.');
    }
  }

  const canSave =
    form.name.trim().length > 0 &&
    Number.isFinite(parseFloat(form.latitude)) &&
    Number.isFinite(parseFloat(form.longitude));

  return (
    <AdminFrame
      title="Map places"
      subtitle="Villages and landmarks Google does not know, pinned by hand."
    >
      <section className="panel formPanel">
        {error && <ErrorBox message={error} />}
        {notice && <div className="successBox">{notice}</div>}

        <p
          style={{
            color: '#667085',
            fontSize: 13,
            lineHeight: 1.7,
            margin: '0 0 18px',
          }}
        >
          Anything added here appears in customer search ahead of Google&apos;s
          results, so a local name finds the local place. Use it for villages,
          valleys and landmarks Google has no entry for.
          <br />
          <br />
          <strong>One limit worth knowing:</strong> a pin makes a place findable,
          but the route to it still comes from Google. If the last stretch is an
          unpaved track Google has never mapped, the route will stop at the
          nearest mapped road. The customer and driver will still see the right
          destination — they will just agree the last part between themselves.
        </p>

        <h3 style={{ fontSize: 15, fontWeight: 500, margin: '0 0 12px' }}>
          {editingId ? 'Edit place' : 'Add a place'}
        </h3>

        <label style={{ display: 'block', marginBottom: 14 }}>
          <span
            style={{
              display: 'block',
              fontSize: 13,
              fontWeight: 500,
              marginBottom: 4,
            }}
          >
            Paste a Google Maps link or coordinates
          </span>
          <span
            style={{
              display: 'block',
              fontSize: 12,
              color: '#667085',
              marginBottom: 6,
            }}
          >
            Right-click the spot in Google Maps, copy the coordinates, and paste
            them here. Fills the two fields below.
          </span>
          <div style={{ display: 'flex', gap: 8 }}>
            <input
              value={paste}
              placeholder="https://www.google.com/maps/@34.5822,73.8992,15z  or  34.5822, 73.8992"
              onChange={(e) => setPaste(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && applyPaste()}
              style={{ flex: 1 }}
            />
            <button onClick={applyPaste} disabled={!paste.trim()}>
              Use
            </button>
          </div>
        </label>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            gap: 12,
            marginBottom: 14,
          }}
        >
          <label>
            <span style={{ display: 'block', fontSize: 13, marginBottom: 4 }}>
              Name
            </span>
            <input
              value={form.name}
              placeholder="Sharda"
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              style={{ width: '100%' }}
            />
          </label>
          <label>
            <span style={{ display: 'block', fontSize: 13, marginBottom: 4 }}>
              District
            </span>
            <input
              value={form.district}
              placeholder="Neelum"
              onChange={(e) => setForm({ ...form, district: e.target.value })}
              style={{ width: '100%' }}
            />
          </label>
          <label>
            <span style={{ display: 'block', fontSize: 13, marginBottom: 4 }}>
              Latitude
            </span>
            <input
              value={form.latitude}
              placeholder="34.7906"
              onChange={(e) => setForm({ ...form, latitude: e.target.value })}
              style={{ width: '100%' }}
            />
          </label>
          <label>
            <span style={{ display: 'block', fontSize: 13, marginBottom: 4 }}>
              Longitude
            </span>
            <input
              value={form.longitude}
              placeholder="74.1806"
              onChange={(e) => setForm({ ...form, longitude: e.target.value })}
              style={{ width: '100%' }}
            />
          </label>
        </div>

        <label style={{ display: 'block', marginBottom: 14 }}>
          <span style={{ display: 'block', fontSize: 13, marginBottom: 4 }}>
            Other spellings
          </span>
          <span
            style={{
              display: 'block',
              fontSize: 12,
              color: '#667085',
              marginBottom: 6,
            }}
          >
            Comma separated. People type what they say — &quot;shardi&quot;,
            &quot;sharda valley&quot;.
          </span>
          <input
            value={form.aliases}
            placeholder="shardi, sharda valley"
            onChange={(e) => setForm({ ...form, aliases: e.target.value })}
            style={{ width: '100%' }}
          />
        </label>

        <label style={{ display: 'block', marginBottom: 16 }}>
          <span style={{ display: 'block', fontSize: 13, marginBottom: 4 }}>
            Note (optional)
          </span>
          <input
            value={form.note}
            placeholder="Jeep track for the last 6 km"
            onChange={(e) => setForm({ ...form, note: e.target.value })}
            style={{ width: '100%' }}
          />
        </label>

        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <button className="primaryButton" onClick={save} disabled={!canSave || saving}>
            {saving ? 'Saving…' : editingId ? 'Save changes' : 'Add place'}
          </button>
          {editingId && <button onClick={cancelEdit}>Cancel</button>}
        </div>
      </section>

      <section className="panel" style={{ marginTop: 20 }}>
        {busy ? (
          <Loading />
        ) : places.length === 0 ? (
          <p style={{ color: '#667085', fontSize: 13 }}>No places added yet.</p>
        ) : (
          <table style={{ width: '100%', fontSize: 13 }}>
            <thead>
              <tr style={{ textAlign: 'left', color: '#667085' }}>
                <th style={{ padding: '8px 6px' }}>Name</th>
                <th style={{ padding: '8px 6px' }}>District</th>
                <th style={{ padding: '8px 6px' }}>Coordinates</th>
                <th style={{ padding: '8px 6px' }}>Also called</th>
                <th style={{ padding: '8px 6px' }} />
              </tr>
            </thead>
            <tbody>
              {places.map((place) => (
                <tr
                  key={place.id}
                  style={{
                    borderTop: '1px solid #E2E9EB',
                    opacity: place.isActive ? 1 : 0.5,
                  }}
                >
                  <td style={{ padding: '10px 6px', fontWeight: 500 }}>
                    {place.name}
                    {place.note && (
                      <span
                        style={{
                          display: 'block',
                          fontWeight: 400,
                          color: '#667085',
                          fontSize: 12,
                        }}
                      >
                        {place.note}
                      </span>
                    )}
                  </td>
                  <td style={{ padding: '10px 6px' }}>{place.district}</td>
                  <td
                    style={{
                      padding: '10px 6px',
                      fontFamily: 'monospace',
                      fontSize: 12,
                    }}
                  >
                    {place.latitude.toFixed(4)}, {place.longitude.toFixed(4)}
                  </td>
                  <td style={{ padding: '10px 6px', color: '#667085' }}>
                    {place.aliases.join(', ') || '—'}
                  </td>
                  <td style={{ padding: '10px 6px', textAlign: 'right' }}>
                    <button onClick={() => edit(place)}>Edit</button>{' '}
                    <button onClick={() => remove(place)}>Delete</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </AdminFrame>
  );
}
