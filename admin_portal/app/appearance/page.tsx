'use client';

import { useEffect, useState } from 'react';
import { AdminFrame } from '../components/admin-frame';
import { ErrorBox, Loading } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

type Setting = {
  key: string;
  valueJson: string;
  description?: string;
  isPublic: boolean;
  updatedAt: string;
};

/**
 * Server-side Google Places key.
 *
 * Read only by PlacesController when proxying address search and reverse
 * geocoding. It is never returned to a client, so it cannot be extracted from
 * the web bundle or the APK.
 */
const PLACES_KEY = 'places.google.apiKey';

/** system_settings stores jsonb, so a string arrives wrapped in quotes. */
function unwrap(valueJson: string | undefined): string {
  if (!valueJson) return '';
  try {
    const parsed = JSON.parse(valueJson);
    return typeof parsed === 'string' ? parsed : '';
  } catch {
    return valueJson;
  }
}

export default function Page() {
  const [placesKey, setPlacesKey] = useState('');
  const [hadKey, setHadKey] = useState(false);
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState('');

  useEffect(() => {
    apiFetch<Setting[]>('/api/v1/admin/operations/settings')
      .then((rows) => {
        const current = unwrap(rows.find((r) => r.key === PLACES_KEY)?.valueJson);
        setPlacesKey(current);
        setHadKey(current.length > 0);
      })
      .catch((e) => setError(e.message))
      .finally(() => setBusy(false));
  }, []);

  async function save() {
    setSaving(true);
    setError('');
    setSaved('');
    try {
      await apiFetch('/api/v1/admin/operations/settings', {
        method: 'PUT',
        body: JSON.stringify({ values: { [PLACES_KEY]: placesKey.trim() } }),
      });
      setHadKey(placesKey.trim().length > 0);
      setSaved(
        placesKey.trim().length > 0
          ? 'Key saved. Address search now uses Google Places — takes effect on the next search, no app update needed.'
          : 'Key cleared. Address search falls back to OpenStreetMap.',
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <AdminFrame
      title="Address search"
      subtitle="The Google key used for From / To autocomplete and reverse geocoding."
    >
      <section className="panel formPanel">
        {busy ? (
          <Loading />
        ) : (
          <>
            {error && <ErrorBox message={error} />}
            {saved && <div className="successBox">{saved}</div>}

            <div
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 8,
                padding: '6px 12px',
                borderRadius: 999,
                fontSize: 13,
                marginBottom: 18,
                background: hadKey ? '#EAF7F1' : '#FEF3C7',
                color: hadKey ? '#0F5132' : '#92600A',
              }}
            >
              <span
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: '50%',
                  background: hadKey ? '#16A36A' : '#F59E0B',
                }}
              />
              {hadKey
                ? 'Google Places is active'
                : 'No key set — using OpenStreetMap'}
            </div>

            <p
              style={{
                color: '#667085',
                fontSize: 13,
                lineHeight: 1.7,
                margin: '0 0 16px',
              }}
            >
              Used server-side only, so the key never reaches the app and cannot
              be lifted out of the web bundle or the APK. Leave it empty and
              search falls back to OpenStreetMap, which needs no key but does not
              know most Pakistani colony, sector and street names.
              <br />
              <br />
              Use a key restricted to <strong>Places API</strong> and{' '}
              <strong>Geocoding API</strong>. Do not reuse the browser key —
              server requests send no referrer, so a key restricted to websites
              will be rejected.
            </p>

            <label style={{ display: 'block', marginBottom: 20 }}>
              <span
                style={{
                  display: 'block',
                  fontSize: 13,
                  fontWeight: 500,
                  marginBottom: 6,
                }}
              >
                Google Places API key
              </span>
              <input
                type="password"
                value={placesKey}
                placeholder="AIza… (empty = use OpenStreetMap)"
                onChange={(e) => setPlacesKey(e.target.value)}
                style={{ width: '100%' }}
              />
            </label>

            <button className="primaryButton" onClick={save} disabled={saving}>
              {saving ? 'Saving…' : 'Save key'}
            </button>
          </>
        )}
      </section>
    </AdminFrame>
  );
}
