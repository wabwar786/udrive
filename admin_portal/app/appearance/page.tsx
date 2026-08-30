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
 * The four Home services, in the order they appear in the app.
 * `key` matches the system_settings key the mobile app reads.
 */
const SERVICES = [
  { id: 'bus', label: 'Coaster / Bus' },
  { id: 'car', label: 'Car' },
  { id: 'bike', label: 'Bike' },
  { id: 'hotel', label: 'Hotel' },
] as const;

const keyFor = (id: string) => `home.hero.${id}.imageUrl`;

/** Server-side Google Places key. Never sent to clients — see PlacesController. */
const PLACES_KEY = 'places.google.apiKey';

/** system_settings stores jsonb, so a URL arrives wrapped in quotes. */
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
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [placesKey, setPlacesKey] = useState('');
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState('');

  useEffect(() => {
    apiFetch<Setting[]>('/api/v1/admin/operations/settings')
      .then((rows) => {
        const next: Record<string, string> = {};
        for (const service of SERVICES) {
          const row = rows.find((r) => r.key === keyFor(service.id));
          next[service.id] = unwrap(row?.valueJson);
        }
        setUrls(next);
        setPlacesKey(unwrap(rows.find((r) => r.key === PLACES_KEY)?.valueJson));
      })
      .catch((e) => setError(e.message))
      .finally(() => setBusy(false));
  }, []);

  async function save() {
    setSaving(true);
    setError('');
    setSaved('');
    try {
      const values: Record<string, string> = {};
      for (const service of SERVICES) {
        values[keyFor(service.id)] = (urls[service.id] ?? '').trim();
      }
      values[PLACES_KEY] = placesKey.trim();
      await apiFetch('/api/v1/admin/operations/settings', {
        method: 'PUT',
        body: JSON.stringify({ values }),
      });
      setSaved(
        'Saved. Customers will see the new artwork the next time the app ' +
          'loads its home screen — no app update is needed.',
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <AdminFrame
      title="Maps and artwork"
      subtitle="Address search key, and the artwork shown for each service."
    >
      <section className="panel formPanel">
        {busy ? (
          <Loading />
        ) : (
          <>
            {error && <ErrorBox message={error} />}
            {saved && <div className="successBox">{saved}</div>}

            <p style={{ color: '#667085', fontSize: 13, marginBottom: 18 }}>
              Paste a direct image URL (must start with <code>https://</code>).
              Leave a field empty to use the app&rsquo;s built-in illustration.
              Landscape images around 1200&times;800 with a transparent or plain
              background work best, because the app fades the bottom edge into
              the page.
            </p>

            <div className="settingsList">
              {SERVICES.map((service) => (
                <label key={service.id}>
                  <div>
                    <strong>{service.label}</strong>
                    <span>{keyFor(service.id)}</span>
                  </div>
                  <input
                    value={urls[service.id] ?? ''}
                    placeholder="https://… (empty = built-in illustration)"
                    onChange={(e) =>
                      setUrls({ ...urls, [service.id]: e.target.value })
                    }
                  />
                </label>
              ))}
            </div>

            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
                gap: 14,
                margin: '22px 0',
              }}
            >
              {SERVICES.map((service) => {
                const url = (urls[service.id] ?? '').trim();
                return (
                  <div
                    key={service.id}
                    style={{
                      border: '1px solid #E2E9EB',
                      borderRadius: 14,
                      padding: 10,
                      background: '#F6F8FA',
                    }}
                  >
                    <div
                      style={{
                        fontSize: 12,
                        fontWeight: 700,
                        marginBottom: 8,
                        color: '#101828',
                      }}
                    >
                      {service.label}
                    </div>
                    {url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={url}
                        alt={`${service.label} hero preview`}
                        style={{
                          width: '100%',
                          height: 110,
                          objectFit: 'contain',
                          borderRadius: 10,
                        }}
                      />
                    ) : (
                      <div
                        style={{
                          height: 110,
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          color: '#98A2B3',
                          fontSize: 12,
                          textAlign: 'center',
                          padding: 8,
                        }}
                      >
                        Using the app&rsquo;s built-in illustration
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            <div
              style={{
                borderTop: '1px solid #E2E9EB',
                paddingTop: 20,
                marginBottom: 20,
              }}
            >
              <p style={{ fontSize: 15, fontWeight: 500, margin: '0 0 6px' }}>
                Google Places API key
              </p>
              <p
                style={{
                  color: '#667085',
                  fontSize: 13,
                  margin: '0 0 12px',
                  lineHeight: 1.6,
                }}
              >
                Used server-side for address search and reverse geocoding. It is
                never sent to the app, so it cannot be extracted from the web
                bundle or the APK. Leave it empty and search falls back to
                OpenStreetMap, which needs no key.
              </p>
              <input
                type="password"
                value={placesKey}
                placeholder="AIza… (empty = use OpenStreetMap)"
                onChange={(e) => setPlacesKey(e.target.value)}
                style={{ width: '100%' }}
              />
            </div>

            <button
              className="primaryButton"
              onClick={save}
              disabled={saving}
            >
              {saving ? 'Saving…' : 'Save home screen artwork'}
            </button>
          </>
        )}
      </section>
    </AdminFrame>
  );
}
