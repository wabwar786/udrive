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

  /**
   * How often a driver publishes their position.
   *
   * Here rather than in code because the right answer changes without a
   * release: fast makes the map smooth and costs battery and data, slow makes
   * the car jump a block at a time. Which trade is right depends on how many
   * drivers are online and what a megabyte costs them.
   */
  const [ping, setPing] = useState(2);

  /**
   * How far a request reaches, and how far customers see.
   *
   * Two numbers, not one. The request radius is about reach — how far a driver
   * may be and still be offered the job. The nearby radius is about honesty —
   * only showing cars that would realistically come. Tying them together would
   * mean widening the map every time you widened the search.
   */
  const [requestKm, setRequestKm] = useState(5);
  const [nearbyKm, setNearbyKm] = useState(1);

  /**
   * The platform's cut of each fare.
   *
   * Taken from the driver's prepaid balance the moment a trip starts — not
   * when it ends, because a driver who loses signal after dropping someone off
   * never sends the completion, and the platform was carrying rides it was not
   * paid for.
   */
  const [commission, setCommission] = useState(10);
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState('');

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setRows(await apiFetch<Service[]>('/api/v1/admin/services'));
      const ops = await apiFetch<{
        pingSeconds: number;
        requestRadiusKm: number;
        nearbyRadiusKm: number;
        commissionPercentage: number;
      }>('/api/v1/settings/operations');
      setPing(ops.pingSeconds);
      setRequestKm(ops.requestRadiusKm);
      setNearbyKm(ops.nearbyRadiusKm);
      setCommission(ops.commissionPercentage);
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

  async function savePing(seconds: number) {
    setPing(seconds);
    setError('');
    setSaved('');
    try {
      await apiFetch('/api/v1/admin/settings/tracking', {
        method: 'PUT',
        body: JSON.stringify({ pingSeconds: seconds }),
      });
      setSaved(`Drivers will now report every ${seconds} second${seconds === 1 ? '' : 's'}.`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that.');
    }
  }

  async function saveRadius(request: number, nearby: number) {
    setRequestKm(request);
    setNearbyKm(nearby);
    setError('');
    setSaved('');
    try {
      await apiFetch('/api/v1/admin/settings/radius', {
        method: 'PUT',
        body: JSON.stringify({
          requestRadiusKm: request,
          nearbyRadiusKm: nearby,
        }),
      });
      setSaved(
        `Requests now reach ${request} km; customers see ${nearby} km around them.`,
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that.');
    }
  }

  async function saveCommission(percentage: number) {
    setCommission(percentage);
    setError('');
    setSaved('');
    try {
      await apiFetch('/api/v1/admin/settings/commission', {
        method: 'PUT',
        body: JSON.stringify({ percentage }),
      });
      setSaved(`Commission is now ${percentage}% of each fare.`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that.');
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
            <h2>Commission</h2>
            <p>
              The platform&apos;s cut of each fare, taken from the
              driver&apos;s prepaid balance the moment a trip starts — when the
              passenger is in the vehicle and has read out the code. Not at the
              end: a driver who loses signal after a drop-off never sends the
              completion, and that ride would go uncharged.
            </p>
          </div>
        </header>
        <div className="pingRow">
          {[0, 5, 8, 10, 12, 15, 20, 25].map((pct) => (
            <button
              key={pct}
              type="button"
              className={pct === commission ? 'pingOn' : 'pingOff'}
              onClick={() => void saveCommission(pct)}
            >
              {pct}%
            </button>
          ))}
        </div>
        <p className="pingNote">
          Currently {commission}% of each fare. Drivers see every charge in
          their wallet, with the ride it came from — changing this does not
          alter what was already taken.
        </p>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Driver location updates</h2>
            <p>
              How often a driver&apos;s phone reports its position while a trip
              is live. The customer&apos;s map polls at the same rate.
              Faster is smoother and costs the driver battery and data; slower
              makes the car appear to jump between fixes.
            </p>
          </div>
        </header>

        <div className="pingRow">
          {[1, 2, 3, 5, 10, 15, 30].map((seconds) => (
            <button
              key={seconds}
              type="button"
              className={seconds === ping ? 'pingOn' : 'pingOff'}
              onClick={() => void savePing(seconds)}
            >
              {seconds}s
            </button>
          ))}
        </div>
        <p className="pingNote">
          Currently every {ping} second{ping === 1 ? '' : 's'}. Drivers pick this
          up when their next trip starts, so a change does not interrupt a trip
          already under way.
        </p>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>How far a request travels</h2>
            <p>
              A driver further than this from the pickup is never offered the
              job. Wider reaches more drivers and sends more of them a request
              they will not take; narrower is quieter and can leave a customer
              with nobody at all.
            </p>
          </div>
        </header>
        <div className="pingRow">
          {[1, 2, 3, 5, 8, 12, 20].map((km) => (
            <button
              key={km}
              type="button"
              className={km === requestKm ? 'pingOn' : 'pingOff'}
              onClick={() => void saveRadius(km, nearbyKm)}
            >
              {km} km
            </button>
          ))}
        </div>
        <p className="pingNote">Currently {requestKm} km.</p>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>How far customers see vehicles</h2>
            <p>
              What the home map shows around the customer. Keep it tighter than
              the request radius — a car shown eight kilometres away is a car
              nobody is waiting for, and an empty-looking map is more honest
              than a busy one that produces no driver.
            </p>
          </div>
        </header>
        <div className="pingRow">
          {[0.5, 1, 2, 3, 5, 8].map((km) => (
            <button
              key={km}
              type="button"
              className={km === nearbyKm ? 'pingOn' : 'pingOff'}
              onClick={() => void saveRadius(requestKm, km)}
            >
              {km} km
            </button>
          ))}
        </div>
        <p className="pingNote">Currently {nearbyKm} km.</p>
      </section>

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
