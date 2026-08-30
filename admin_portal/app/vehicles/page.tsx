'use client';

import { useEffect, useState } from 'react';
import { AdminFrame } from '../components/admin-frame';
import { ErrorBox, Loading } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

type Setting = { key: string; valueJson: string };

/**
 * The vehicle types the customer app can show a picture for.
 *
 * Kept in step with `VehicleOptionsRepository._catalogue` in the app. Adding a
 * vehicle there means adding a row here and a seed line in the migration.
 */
const VEHICLES = [
  { key: 'vehicle.image.bike', label: 'Bike', hint: 'One passenger' },
  { key: 'vehicle.image.car', label: 'Car', hint: 'Up to 4 passengers' },
  { key: 'vehicle.image.ac_car', label: 'Car with AC', hint: 'Up to 4, air conditioned' },
  { key: 'vehicle.image.hiace', label: 'Hiace', hint: 'Up to 12 passengers' },
  { key: 'vehicle.image.coaster', label: 'Coaster', hint: 'Up to 22 passengers' },
];

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
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  useEffect(() => {
    apiFetch<Setting[]>('/api/v1/admin/operations/settings')
      .then((rows) => {
        const next: Record<string, string> = {};
        for (const vehicle of VEHICLES) {
          next[vehicle.key] = unwrap(
            rows.find((row) => row.key === vehicle.key)?.valueJson,
          );
        }
        setUrls(next);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Could not load.'))
      .finally(() => setBusy(false));
  }, []);

  async function save() {
    setSaving(true);
    setError('');
    setNotice('');
    try {
      const values: Record<string, string> = {};
      for (const vehicle of VEHICLES) {
        values[vehicle.key] = (urls[vehicle.key] ?? '').trim();
      }
      await apiFetch('/api/v1/admin/operations/settings', {
        method: 'PUT',
        body: JSON.stringify({ values }),
      });
      setNotice(
        'Saved. Customers see the new pictures the next time they open the ' +
          'vehicle picker — no app update needed.',
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <AdminFrame
      title="Vehicle pictures"
      subtitle="The photograph shown for each vehicle type when a customer is choosing."
    >
      <section className="panel formPanel">
        {busy ? (
          <Loading />
        ) : (
          <>
            {error && <ErrorBox message={error} />}
            {notice && <div className="successBox">{notice}</div>}

            <p
              style={{
                color: '#667085',
                fontSize: 13,
                lineHeight: 1.7,
                margin: '0 0 20px',
              }}
            >
              The app ships stock illustrations. Photographs of the vehicles
              actually on the road will do more for customer trust than anything
              else on that screen, and only you can supply those.
              <br />
              <br />
              Paste a direct image URL — it must start with <code>https://</code>
              and end at the image itself, not a page containing it. Leave a
              field empty to keep the built-in illustration.
              <br />
              <br />
              <strong>What works best:</strong> the vehicle at a three-quarter
              angle on a plain or transparent background, roughly 800×500, no
              text or watermark. The app shows it at 168px tall against a dark
              panel, so a white background will appear as a bright rectangle.
            </p>

            {VEHICLES.map((vehicle) => (
              <div
                key={vehicle.key}
                style={{
                  display: 'flex',
                  gap: 16,
                  alignItems: 'center',
                  padding: '14px 0',
                  borderTop: '1px solid #E2E9EB',
                }}
              >
                <div style={{ width: 150, flexShrink: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500 }}>
                    {vehicle.label}
                  </div>
                  <div style={{ fontSize: 12, color: '#667085' }}>
                    {vehicle.hint}
                  </div>
                </div>

                <input
                  value={urls[vehicle.key] ?? ''}
                  placeholder="https://…  (empty = built-in illustration)"
                  onChange={(e) =>
                    setUrls({ ...urls, [vehicle.key]: e.target.value })
                  }
                  style={{ flex: 1 }}
                />

                <div
                  style={{
                    width: 104,
                    height: 66,
                    flexShrink: 0,
                    borderRadius: 8,
                    background: '#16232D',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    overflow: 'hidden',
                  }}
                >
                  {(urls[vehicle.key] ?? '').trim().startsWith('http') ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={urls[vehicle.key]}
                      alt={`${vehicle.label} preview`}
                      style={{
                        maxWidth: '100%',
                        maxHeight: '100%',
                        objectFit: 'contain',
                      }}
                    />
                  ) : (
                    <span style={{ fontSize: 10, color: '#667085' }}>
                      built-in
                    </span>
                  )}
                </div>
              </div>
            ))}

            <button
              className="primaryButton"
              onClick={save}
              disabled={saving}
              style={{ marginTop: 20 }}
            >
              {saving ? 'Saving…' : 'Save pictures'}
            </button>
          </>
        )}
      </section>
    </AdminFrame>
  );
}
