'use client';

import { useCallback, useEffect, useState } from 'react';
import { Save } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { ErrorBox, Field, Loading } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

type Service = {
  serviceKey: string;
  isOpen: boolean;
  badgeLabel: string;
  closedMessage: string;
};

/**
 * Which services customers may open.
 *
 * Closing one does **not** touch the driver app: vehicles can still be
 * registered and verified for a closed service, so it has a fleet on the day it
 * opens. Without that the platform deadlocks — closed because there are no
 * vehicles, and no vehicles because it is closed.
 */
const NAMES: Record<string, string> = {
  cityRides: 'City rides',
  tour: 'Tour',
  cityToCity: 'City to city',
  hotels: 'Hotels',
  coster: 'Coster',
  explore: 'Explore',
  carRental: 'Car rental',
};

export default function Page() {
  const [rows, setRows] = useState<Service[]>([]);
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState('');

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setRows(await apiFetch<Service[]>('/api/v1/admin/services'));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load services.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  function edit(key: string, patch: Partial<Service>) {
    setRows((current) =>
      current.map((row) =>
        row.serviceKey === key ? { ...row, ...patch } : row,
      ),
    );
  }

  async function save(row: Service) {
    setSaving(row.serviceKey);
    setError('');
    setSaved('');
    try {
      await apiFetch(`/api/v1/admin/services/${row.serviceKey}`, {
        method: 'PUT',
        body: JSON.stringify({
          isOpen: row.isOpen,
          badgeLabel: row.badgeLabel,
          closedMessage: row.closedMessage,
        }),
      });
      setSaved(`${NAMES[row.serviceKey] ?? row.serviceKey} updated.`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that change.');
    } finally {
      setSaving(null);
    }
  }

  return (
    <AdminFrame
      title="Services"
      subtitle="Turn a service off for customers without hiding it from drivers."
    >
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Customer availability</h2>
            <p>
              A closed service still appears on the home screen, dimmed and
              badged, and cannot be opened. Drivers are unaffected — vehicles
              can be registered and verified while it is closed, so it has a
              fleet on the day you open it.
            </p>
          </div>
        </header>

        {error && <ErrorBox message={error} />}
        {saved && <p className="successNote">{saved}</p>}

        {busy ? (
          <Loading />
        ) : (
          <div style={{ padding: '4px 18px 18px' }}>
            {rows.map((row) => (
              <div key={row.serviceKey} className="serviceRow">
                <div className="serviceRowHead">
                  <div>
                    <strong>{NAMES[row.serviceKey] ?? row.serviceKey}</strong>
                    <small>
                      {row.isOpen
                        ? 'Open to customers'
                        : 'Coming soon — customers see the label'}
                    </small>
                  </div>

                  <label className="serviceToggle">
                    <input
                      type="checkbox"
                      checked={row.isOpen}
                      onChange={(e) =>
                        edit(row.serviceKey, { isOpen: e.target.checked })
                      }
                    />
                    <span>{row.isOpen ? 'Open' : 'Closed'}</span>
                  </label>
                </div>

                {/*
                  Only shown when closed. The label and the message describe a
                  state the service is not in while it is open, and editing them
                  then is editing something invisible.
                */}
                {!row.isOpen && (
                  <div className="serviceRowBody">
                    <Field label="Badge on the tile">
                      <input
                        value={row.badgeLabel}
                        maxLength={24}
                        onChange={(e) =>
                          edit(row.serviceKey, { badgeLabel: e.target.value })
                        }
                      />
                    </Field>
                    <Field label="What a customer is told on tapping">
                      <input
                        value={row.closedMessage}
                        maxLength={200}
                        onChange={(e) =>
                          edit(row.serviceKey, {
                            closedMessage: e.target.value,
                          })
                        }
                      />
                    </Field>
                    <p className="serviceNote">
                      Drivers can still register vehicles for this service.
                    </p>
                  </div>
                )}

                <div className="serviceRowFoot">
                  <button
                    className="primaryButton"
                    disabled={saving === row.serviceKey}
                    onClick={() => void save(row)}
                  >
                    <Save size={15} />
                    {saving === row.serviceKey ? 'Saving…' : 'Save'}
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </AdminFrame>
  );
}
