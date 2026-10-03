'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus, Save, Trash2 } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { apiFetch, when } from '../lib/admin-api';

type City = {
  id: string;
  name: string;
  isActive: boolean;
  launchStatus: string;
  customerCampaignActive: boolean;
  foundingEnabled: boolean;
  foundingLimit?: number | null;
  foundingWindowEndsAt?: string | null;
  supportPhone?: string | null;
  communityUrl?: string | null;
  activatedAt?: string | null;
  driverCount: number;
  foundingCount: number;
};

type Zone = { id: string; name: string; cityId?: string | null };

type Driver = {
  driverProfileId: string;
  fullName: string;
  phoneNumber: string;
  verificationStatus: string;
  completedTrips: number;
};

type DemandWindow = {
  id: string;
  cityId?: string | null;
  cityName?: string | null;
  zoneId: string;
  zoneName: string;
  level: string;
  reason?: string | null;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  validFrom?: string | null;
  validTo?: string | null;
  isActive: boolean;
};

/**
 * The four the database will accept.
 *
 * `launch_cities_status_check` rejects anything else outright, so a free-text
 * box here would produce a save that fails with a constraint name an admin
 * cannot act on. "Live" is the one people reach for and it is not one of them.
 */
const STATUSES = [
  'BuildingNetwork',
  'CampaignSoon',
  'CampaignActive',
  'PublicLaunch',
] as const;

const LEVELS = ['Low', 'Medium', 'High'] as const;

const DAYS = [
  [1, 'Mon'],
  [2, 'Tue'],
  [3, 'Wed'],
  [4, 'Thu'],
  [5, 'Fri'],
  [6, 'Sat'],
  [0, 'Sun'],
] as const;

const EMPTY_CITY: City = {
  id: '',
  name: '',
  isActive: true,
  launchStatus: 'BuildingNetwork',
  customerCampaignActive: false,
  foundingEnabled: false,
  foundingLimit: 50,
  foundingWindowEndsAt: null,
  supportPhone: '',
  communityUrl: '',
  driverCount: 0,
  foundingCount: 0,
};

const EMPTY_WINDOW: DemandWindow = {
  id: '',
  cityId: null,
  zoneId: '',
  zoneName: '',
  level: 'High',
  reason: '',
  daysOfWeek: [],
  startTime: '07:00',
  endTime: '11:00',
  isActive: true,
};

/**
 * Launch cities, and what each one is currently promising.
 *
 * Two things live here because they are the same question — what this city
 * looks like to a driver who opens the app in it. The city row decides whether
 * the launch card appears and whether founding numbers are still being handed
 * out; the demand windows decide what the home screen says is about to get
 * busy. Splitting them across two pages would mean checking two screens to
 * answer one question.
 */
export default function Page() {
  const [cities, setCities] = useState<City[]>([]);
  const [zones, setZones] = useState<Zone[]>([]);
  const [windows, setWindows] = useState<DemandWindow[]>([]);
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [grantTo, setGrantTo] = useState('');
  const [focusCity, setFocusCity] = useState('');

  const [editing, setEditing] = useState<City | null>(null);
  const [editingWindow, setEditingWindow] = useState<DemandWindow | null>(null);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');

  const load = useCallback(async () => {
    try {
      const list = await apiFetch<City[]>('/api/v1/admin/growth/cities');
      setCities(list);
      if (!focusCity && list.length > 0) setFocusCity(list[0].id);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'This section is unavailable.');
    }

    // Zones and the demand list come from the operational side of the API and
    // may legitimately be empty on a fresh install, so a failure here must not
    // take the city list down with it.
    try {
      setZones(await apiFetch<Zone[]>('/api/v1/admin/fare/zones'));
    } catch {
      setZones([]);
    }
    try {
      setWindows(await apiFetch<DemandWindow[]>('/api/v1/admin/growth/demand-windows'));
    } catch {
      setWindows([]);
    }
    try {
      setDrivers(await apiFetch<Driver[]>('/api/v1/admin/operations/drivers'));
    } catch {
      setDrivers([]);
    }
  }, [focusCity]);

  useEffect(() => {
    setLoading(true);
    void load().finally(() => setLoading(false));
    // Intentionally once: `load` closes over focusCity only to seed it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const cityWindows = useMemo(
    () => windows.filter((w) => !focusCity || w.cityId === focusCity),
    [windows, focusCity],
  );

  const stats = useMemo(
    () => ({
      live: cities.filter((c) => c.isActive).length,
      drivers: cities.reduce((sum, c) => sum + c.driverCount, 0),
      founding: cities.reduce((sum, c) => sum + c.foundingCount, 0),
      openWindows: cities.filter((c) => c.foundingEnabled).length,
    }),
    [cities],
  );

  const saveCity = async () => {
    if (!editing) return;
    setBusy(true);
    setError('');
    setNote('');
    try {
      await apiFetch<string>(
        editing.id
          ? `/api/v1/admin/growth/cities/${editing.id}`
          : '/api/v1/admin/growth/cities',
        {
          method: editing.id ? 'PUT' : 'POST',
          body: JSON.stringify({
            name: editing.name.trim(),
            isActive: editing.isActive,
            launchStatus: editing.launchStatus,
            customerCampaignActive: editing.customerCampaignActive,
            foundingEnabled: editing.foundingEnabled,
            foundingLimit: editing.foundingLimit ?? null,
            foundingWindowEndsAt: editing.foundingWindowEndsAt || null,
            supportPhone: editing.supportPhone || null,
            communityUrl: editing.communityUrl || null,
          }),
        },
      );
      setEditing(null);
      setNote('Saved.');
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be saved.');
    } finally {
      setBusy(false);
    }
  };

  const saveWindow = async () => {
    if (!editingWindow) return;
    setBusy(true);
    setError('');
    try {
      await apiFetch<string>(
        editingWindow.id
          ? `/api/v1/admin/growth/demand-windows/${editingWindow.id}`
          : '/api/v1/admin/growth/demand-windows',
        {
          method: editingWindow.id ? 'PUT' : 'POST',
          body: JSON.stringify({
            cityId: focusCity || null,
            zoneId: editingWindow.zoneId,
            level: editingWindow.level,
            reason: editingWindow.reason || null,
            daysOfWeek: editingWindow.daysOfWeek,
            startTime: editingWindow.startTime,
            endTime: editingWindow.endTime,
            validFrom: editingWindow.validFrom || null,
            validTo: editingWindow.validTo || null,
            campaignId: null,
            isActive: editingWindow.isActive,
          }),
        },
      );
      setEditingWindow(null);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be saved.');
    } finally {
      setBusy(false);
    }
  };

  const removeWindow = async (row: DemandWindow) => {
    setBusy(true);
    try {
      await apiFetch<boolean>(
        `/api/v1/admin/growth/demand-windows/${row.id}`,
        { method: 'DELETE' },
      );
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be removed.');
    } finally {
      setBusy(false);
    }
  };

  /**
   * Gives one driver the next founding number in their city.
   *
   * The endpoint has existed since the growth system shipped with nothing
   * calling it, so no founding number has ever been granted from the portal.
   * It is here rather than on the Drivers page because the window it counts
   * against — how many, until when — is the row directly above.
   *
   * The number itself comes from a single statement in the API that reads the
   * current maximum and inserts in one go, so two admins pressing this at the
   * same moment produce #74 and #75 rather than two #74s.
   */
  const grantFounding = async () => {
    if (!grantTo) return;
    setBusy(true);
    setError('');
    setNote('');
    try {
      const number = await apiFetch<number>(
        `/api/v1/admin/growth/founding/${grantTo}`,
        { method: 'POST' },
      );
      const who = drivers.find((d) => d.driverProfileId === grantTo);
      setGrantTo('');
      setNote(
        `${who?.fullName ?? 'That driver'} is now founding driver #${number}.`,
      );
      await load();
    } catch (e) {
      setError(
        e instanceof Error ? e.message : 'That number could not be given.',
      );
    } finally {
      setBusy(false);
    }
  };

  const toggleDay = (day: number) =>
    setEditingWindow((w) =>
      w
        ? {
            ...w,
            daysOfWeek: w.daysOfWeek.includes(day)
              ? w.daysOfWeek.filter((d) => d !== day)
              : [...w.daysOfWeek, day],
          }
        : w,
    );

  return (
    <AdminFrame
      title="Launch cities"
      subtitle="Where UDrive is running, how far along each city is, and when demand is expected."
      actions={
        <button
          className="primaryButton"
          onClick={() => setEditing({ ...EMPTY_CITY })}
          disabled={busy}
        >
          <Plus /> Add city
        </button>
      }
    >
      {error && <ErrorBox message={error} />}
      {note && (
        <section className="panel">
          <p>{note}</p>
        </section>
      )}

      {loading ? (
        <Loading />
      ) : (
        <>
          <div className="statGrid">
            <Stat label="Cities switched on" value={stats.live} tone="emerald" />
            <Stat label="Drivers" value={stats.drivers} tone="blue" />
            <Stat
              label="Founding numbers given"
              value={stats.founding}
              tone="violet"
            />
            <Stat
              label="Founding windows open"
              value={stats.openWindows}
              sub="Still handing out numbers"
              tone="amber"
            />
          </div>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Cities</h2>
                <p>Click a row to edit it.</p>
              </div>
            </header>
            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>City</th>
                    <th>Stage</th>
                    <th>Drivers</th>
                    <th>Founding</th>
                    <th>Customer campaign</th>
                    <th>Support</th>
                    <th>On</th>
                  </tr>
                </thead>
                <tbody>
                  {cities.map((row) => (
                    <tr
                      key={row.id}
                      className="clickable"
                      onClick={() => setEditing({ ...row })}
                    >
                      <td>
                        <strong>{row.name}</strong>
                        <small>
                          {row.activatedAt
                            ? `switched on ${when(row.activatedAt)}`
                            : 'not switched on yet'}
                        </small>
                      </td>
                      <td>
                        <Badge value={row.launchStatus} />
                      </td>
                      <td>{row.driverCount}</td>
                      <td>
                        <strong>
                          {row.foundingCount}
                          {row.foundingLimit ? ` / ${row.foundingLimit}` : ''}
                        </strong>
                        <small>
                          {row.foundingEnabled
                            ? row.foundingWindowEndsAt
                              ? `until ${when(row.foundingWindowEndsAt)}`
                              : 'open'
                            : 'closed'}
                        </small>
                      </td>
                      <td>{row.customerCampaignActive ? 'Yes' : 'No'}</td>
                      <td>{row.supportPhone ?? '—'}</td>
                      <td>
                        <Badge value={row.isActive ? 'Active' : 'Off'} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Founding numbers</h2>
                <p>
                  The badge a driver keeps. Numbers run per city and cannot be
                  given twice.
                </p>
              </div>
              <button
                className="primaryButton"
                onClick={() => void grantFounding()}
                disabled={busy || !grantTo}
              >
                <Plus /> Give the next number
              </button>
            </header>
            <div className="toolbar">
              <select
                value={grantTo}
                onChange={(e) => setGrantTo(e.target.value)}
              >
                <option value="">Choose an approved driver</option>
                {drivers
                  .filter((d) => d.verificationStatus === 'Approved')
                  .map((d) => (
                    <option key={d.driverProfileId} value={d.driverProfileId}>
                      {d.fullName} · {d.phoneNumber} · {d.completedTrips} trip(s)
                    </option>
                  ))}
              </select>
            </div>
          </section>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Expected demand</h2>
                <p>
                  This is where &ldquo;High demand — Domel&rdquo; on the driver&rsquo;s
                  home screen comes from.
                </p>
              </div>
              <button
                className="secondaryButton"
                onClick={() => setEditingWindow({ ...EMPTY_WINDOW })}
                disabled={busy || zones.length === 0}
              >
                <Plus /> Add window
              </button>
            </header>

            <div className="toolbar">
              <select
                value={focusCity}
                onChange={(e) => setFocusCity(e.target.value)}
              >
                {cities.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
              <span>{cityWindows.length} window(s)</span>
            </div>

            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Zone</th>
                    <th>Level</th>
                    <th>Days</th>
                    <th>Time</th>
                    <th>Reason</th>
                    <th>Runs until</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {cityWindows.map((row) => (
                    <tr key={row.id}>
                      <td>
                        <strong>{row.zoneName}</strong>
                      </td>
                      <td>
                        <Badge value={row.level} />
                      </td>
                      <td>
                        {row.daysOfWeek.length === 0
                          ? 'Every day'
                          : row.daysOfWeek
                              .map(
                                (d) =>
                                  DAYS.find((x) => x[0] === d)?.[1] ?? String(d),
                              )
                              .join(' · ')}
                      </td>
                      <td>
                        {row.startTime} – {row.endTime}
                      </td>
                      <td>{row.reason ?? '—'}</td>
                      <td>{row.validTo ? when(row.validTo) : '—'}</td>
                      <td>
                        <button
                          className="iconButton"
                          disabled={busy}
                          onClick={() => void removeWindow(row)}
                        >
                          <Trash2 />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {zones.length === 0 && (
              <p style={{ padding: '14px 18px' }}>
                No pricing zones exist yet, so there is nothing to attach a
                demand window to. Create zones under Fare zones first.
              </p>
            )}
          </section>
        </>
      )}

      {editing && (
        <Modal
          title={editing.id ? `Edit ${editing.name}` : 'Add city'}
          onClose={() => setEditing(null)}
        >
          <div className="formGrid">
            <Field label="Name">
              <input
                value={editing.name}
                onChange={(e) =>
                  setEditing({ ...editing, name: e.target.value })
                }
                maxLength={120}
              />
            </Field>
            <Field label="Stage">
              <select
                value={editing.launchStatus}
                onChange={(e) =>
                  setEditing({ ...editing, launchStatus: e.target.value })
                }
              >
                {STATUSES.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
            </Field>
          </div>

          <div className="formGrid">
            <Field label="City switched on">
              <select
                value={editing.isActive ? 'yes' : 'no'}
                onChange={(e) =>
                  setEditing({ ...editing, isActive: e.target.value === 'yes' })
                }
              >
                <option value="yes">Yes — drivers here are measured</option>
                <option value="no">No</option>
              </select>
            </Field>
            <Field label="Customer-side campaign">
              <select
                value={editing.customerCampaignActive ? 'yes' : 'no'}
                onChange={(e) =>
                  setEditing({
                    ...editing,
                    customerCampaignActive: e.target.value === 'yes',
                  })
                }
              >
                <option value="no">Off</option>
                <option value="yes">On</option>
              </select>
            </Field>
          </div>

          <div className="formGrid">
            <Field label="Founding numbers">
              <select
                value={editing.foundingEnabled ? 'yes' : 'no'}
                onChange={(e) =>
                  setEditing({
                    ...editing,
                    foundingEnabled: e.target.value === 'yes',
                  })
                }
              >
                <option value="no">Closed</option>
                <option value="yes">Still being given out</option>
              </select>
            </Field>
            <Field label="How many at most">
              <input
                type="number"
                min={1}
                value={editing.foundingLimit ?? ''}
                onChange={(e) =>
                  setEditing({
                    ...editing,
                    foundingLimit:
                      e.target.value === '' ? null : Number(e.target.value),
                  })
                }
              />
            </Field>
          </div>

          <Field label="Founding window closes (leave blank for no end)">
            <input
              type="date"
              value={(editing.foundingWindowEndsAt ?? '').slice(0, 10)}
              onChange={(e) =>
                setEditing({
                  ...editing,
                  foundingWindowEndsAt: e.target.value || null,
                })
              }
            />
          </Field>

          <div className="formGrid">
            <Field label="Support number shown to drivers">
              <input
                value={editing.supportPhone ?? ''}
                onChange={(e) =>
                  setEditing({ ...editing, supportPhone: e.target.value })
                }
                placeholder="0342 5095104"
              />
            </Field>
            <Field label="Community group link">
              <input
                value={editing.communityUrl ?? ''}
                onChange={(e) =>
                  setEditing({ ...editing, communityUrl: e.target.value })
                }
                placeholder="https://chat.whatsapp.com/…"
              />
            </Field>
          </div>

          <div className="buttonRow">
            <button
              className="secondaryButton"
              onClick={() => setEditing(null)}
              disabled={busy}
            >
              Cancel
            </button>
            <button
              className="primaryButton"
              onClick={() => void saveCity()}
              disabled={busy || editing.name.trim().length === 0}
            >
              <Save /> Save
            </button>
          </div>
        </Modal>
      )}

      {editingWindow && (
        <Modal title="Expected demand" onClose={() => setEditingWindow(null)}>
          <div className="formGrid">
            <Field label="Zone">
              <select
                value={editingWindow.zoneId}
                onChange={(e) =>
                  setEditingWindow({
                    ...editingWindow,
                    zoneId: e.target.value,
                  })
                }
              >
                <option value="">Choose a zone</option>
                {zones.map((z) => (
                  <option key={z.id} value={z.id}>
                    {z.name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="How busy">
              <select
                value={editingWindow.level}
                onChange={(e) =>
                  setEditingWindow({ ...editingWindow, level: e.target.value })
                }
              >
                {LEVELS.map((l) => (
                  <option key={l} value={l}>
                    {l}
                  </option>
                ))}
              </select>
            </Field>
          </div>

          <div className="formGrid">
            <Field label="From (HH:MM)">
              <input
                value={editingWindow.startTime}
                onChange={(e) =>
                  setEditingWindow({
                    ...editingWindow,
                    startTime: e.target.value,
                  })
                }
              />
            </Field>
            <Field label="To (HH:MM)">
              <input
                value={editingWindow.endTime}
                onChange={(e) =>
                  setEditingWindow({
                    ...editingWindow,
                    endTime: e.target.value,
                  })
                }
              />
            </Field>
          </div>

          {/* No day chosen means every day, which is what the driver API does
              with an empty list — so the label says so rather than leaving an
              admin to discover it. */}
          <Field label="Days — choose none for every day">
            <div className="buttonRow" style={{ padding: 0 }}>
              {DAYS.map(([value, label]) => (
                <button
                  key={value}
                  className={
                    editingWindow.daysOfWeek.includes(value)
                      ? 'primaryButton'
                      : 'secondaryButton'
                  }
                  onClick={() => toggleDay(value)}
                >
                  {label}
                </button>
              ))}
            </div>
          </Field>

          <Field label="Reason — the driver reads this">
            <input
              value={editingWindow.reason ?? ''}
              onChange={(e) =>
                setEditingWindow({ ...editingWindow, reason: e.target.value })
              }
              placeholder="Neelum valley tourists"
              maxLength={160}
            />
          </Field>

          <div className="formGrid">
            <Field label="Valid from">
              <input
                type="date"
                value={editingWindow.validFrom ?? ''}
                onChange={(e) =>
                  setEditingWindow({
                    ...editingWindow,
                    validFrom: e.target.value || null,
                  })
                }
              />
            </Field>
            <Field label="Valid to">
              <input
                type="date"
                value={editingWindow.validTo ?? ''}
                onChange={(e) =>
                  setEditingWindow({
                    ...editingWindow,
                    validTo: e.target.value || null,
                  })
                }
              />
            </Field>
          </div>

          <div className="buttonRow">
            <button
              className="secondaryButton"
              onClick={() => setEditingWindow(null)}
              disabled={busy}
            >
              Cancel
            </button>
            <button
              className="primaryButton"
              onClick={() => void saveWindow()}
              disabled={busy || editingWindow.zoneId.length === 0}
            >
              <Save /> Save
            </button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
