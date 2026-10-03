'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Download, Save } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { apiFetch, money, when } from '../lib/admin-api';

type Summary = {
  carsOutNow: number;
  selfDriveOutNow: number;
  withDriverOutNow: number;
  startingThisWeek: number;
  handoversToday: number;
  advanceThisMonth: number;
  cancellationsLast30Days: number;
};

type Row = {
  id: string;
  bookingReference: string;
  rentalMode: string;
  vehicleName: string;
  registrationNumber: string;
  customerName: string;
  customerPhone?: string;
  ownerName: string;
  ownerPhone?: string;
  startDate: string;
  endDate: string;
  days: number;
  advanceAmount: number;
  balanceDue: number;
  securityDeposit: number;
  status: string;
  cancelledBy?: string;
};

type Detail = Row & {
  dailyRate: number;
  subtotal: number;
  kmPerDay?: number;
  fuelIncluded: boolean;
  pickupPoint?: string;
  cancelledAt?: string;
  cancelReason?: string;
  disclaimerVersion: number;
  disclaimerAcceptedAt: string;
  cnicFront: boolean;
  cnicBack: boolean;
  drivingLicence: boolean;
  selfie: boolean;
};

type FleetRow = {
  vehicleId: string;
  name: string;
  registrationNumber: string;
  ownerName: string;
  ownerPhone?: string;
  withDriverDaily?: number;
  selfDriveDaily?: number;
  securityDeposit: number;
  minimumDays: number;
  hasPhoto: boolean;
  bookingCount: number;
  listed: boolean;
  hiddenReason?: string;
};

type Settings = {
  advancePercent: number;
  freeCancelHours: number;
  maximumDeposit: number;
  disclaimerVersion: number;
  disclaimerTextEn: string;
  disclaimerTextUr: string;
};

const SCOPES = ['live', 'upcoming', 'finished', 'cancelled', 'all'] as const;
const SCOPE_LABELS: Record<string, string> = {
  live: 'Live',
  upcoming: 'Upcoming',
  finished: 'Finished',
  cancelled: 'Cancelled',
  all: 'All',
};

const day = (value: string) =>
  new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });

/**
 * Car rentals.
 *
 * Three questions an Admin actually asks of renting, and nothing else: which
 * car is out today, who owes whom what, and is anything going wrong. The fourth
 * section — the rentable fleet — exists for one support call: "my car is set to
 * rent and it is not showing", whose answer is almost always the photograph.
 *
 * What is deliberately **not** here: editing somebody's booking. Its dates,
 * rate and deposit are an agreement between two other people, and an Admin
 * rewriting it afterwards would do so without either of them knowing.
 */
export default function Page() {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [fleet, setFleet] = useState<FleetRow[]>([]);
  const [settings, setSettings] = useState<Settings | null>(null);

  const [scope, setScope] = useState<string>('live');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<Detail | null>(null);
  const [reason, setReason] = useState('');

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');

  const loadList = useCallback(async () => {
    const query = new URLSearchParams({ scope });
    if (search.trim()) query.set('search', search.trim());
    try {
      setRows(await apiFetch<Row[]>(`/api/v1/admin/rentals?${query}`));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'This section is unavailable.');
    }
  }, [scope, search]);

  const loadRest = useCallback(async () => {
    try {
      const [s, f, cfg] = await Promise.all([
        apiFetch<Summary>('/api/v1/admin/rentals/summary'),
        apiFetch<FleetRow[]>('/api/v1/admin/rentals/fleet'),
        apiFetch<Settings>('/api/v1/admin/rentals/settings'),
      ]);
      setSummary(s);
      setFleet(f);
      setSettings(cfg);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'This section is unavailable.');
    }
  }, []);

  useEffect(() => {
    setLoading(true);
    void Promise.all([loadList(), loadRest()]).finally(() => setLoading(false));
    // loadRest is stable; the list reloads on its own below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const id = setTimeout(() => void loadList(), 250);
    return () => clearTimeout(id);
  }, [loadList]);

  const open = async (row: Row) => {
    setReason('');
    try {
      setSelected(await apiFetch<Detail>(`/api/v1/admin/rentals/${row.id}`));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That booking could not be opened.');
    }
  };

  const cancel = async () => {
    if (!selected) return;
    setBusy(true);
    setError('');
    try {
      await apiFetch<Detail>(`/api/v1/admin/rentals/${selected.id}/cancel`, {
        method: 'POST',
        body: JSON.stringify({ reason }),
      });
      setSelected(null);
      setNote('Cancelled. The advance goes back to the customer.');
      await Promise.all([loadList(), loadRest()]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be cancelled.');
    } finally {
      setBusy(false);
    }
  };

  const saveSettings = async () => {
    if (!settings) return;
    setBusy(true);
    setError('');
    setNote('');
    try {
      const saved = await apiFetch<Settings>('/api/v1/admin/rentals/settings', {
        method: 'PUT',
        body: JSON.stringify(settings),
      });
      setSettings(saved);
      setNote(
        `Saved. Terms are at version ${saved.disclaimerVersion} — bookings made ` +
          'before a change keep the version their customer accepted.',
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Those settings were not saved.');
    } finally {
      setBusy(false);
    }
  };

  /**
   * CSV from the rows already on screen.
   *
   * Built here rather than asking the server for a second rendering of the same
   * query: whatever the Admin is looking at is what they want to take away, and
   * an export that quietly differs from the table above it is worse than none.
   */
  const exportCsv = () => {
    const header = [
      'Reference', 'Mode', 'Vehicle', 'Registration', 'Customer', 'Customer phone',
      'Owner', 'Owner phone', 'From', 'To', 'Days', 'Advance (platform)',
      'Balance (to owner)', 'Deposit (with owner)', 'Status', 'Cancelled by',
    ];
    const lines = rows.map((r) => [
      r.bookingReference, r.rentalMode, r.vehicleName, r.registrationNumber,
      r.customerName, r.customerPhone ?? '', r.ownerName, r.ownerPhone ?? '',
      r.startDate, r.endDate, r.days, r.advanceAmount, r.balanceDue,
      r.securityDeposit, r.status, r.cancelledBy ?? '',
    ]);
    const csv = [header, ...lines]
      .map((line) => line.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(','))
      .join('\n');

    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = `udrive-rentals-${scope}-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  };

  const hiddenCount = useMemo(() => fleet.filter((v) => !v.listed).length, [fleet]);

  return (
    <AdminFrame
      title="Car rentals"
      subtitle="Who has which car, what is owed, and which vehicles are on offer."
      actions={
        <button className="secondaryButton" onClick={exportCsv} disabled={rows.length === 0}>
          <Download /> Export CSV
        </button>
      }
    >
      {error && <ErrorBox message={error} />}
      {note && <section className="panel"><p>{note}</p></section>}

      {loading ? (
        <Loading />
      ) : (
        <>
          {summary && (
            <section className="statGrid">
              <Stat
                label="Cars out right now"
                value={summary.carsOutNow}
                sub={`${summary.selfDriveOutNow} self-drive · ${summary.withDriverOutNow} with driver`}
              />
              <Stat
                label="Starting this week"
                value={summary.startingThisWeek}
                sub={`${summary.handoversToday} handover(s) today`}
                tone="blue"
              />
              {/* Only the advance. The balance and the deposit never reach the
                  platform, so showing them as money we hold would be a figure
                  somebody eventually acts on. */}
              <Stat
                label="Advance collected · this month"
                value={money(summary.advanceThisMonth)}
                sub="What the platform holds"
                tone="violet"
              />
              <Stat
                label="Cancellations · 30 days"
                value={summary.cancellationsLast30Days}
                sub="Both sides"
                tone="amber"
              />
            </section>
          )}

          <section className="panel">
            <div className="toolbar">
              <select value={scope} onChange={(e) => setScope(e.target.value)}>
                {SCOPES.map((s) => (
                  <option key={s} value={s}>{SCOPE_LABELS[s]}</option>
                ))}
              </select>
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Reference, registration, customer or owner"
              />
              <span>{rows.length} rental(s)</span>
            </div>
          </section>

          <section className="panel">
            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Reference</th>
                    <th>Vehicle</th>
                    <th>Customer</th>
                    <th>Owner</th>
                    <th>Dates</th>
                    <th>Advance</th>
                    <th>On collection</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.id} className="clickable" onClick={() => void open(r)}>
                      <td>
                        <strong>{r.bookingReference}</strong>
                        <small>{r.rentalMode === 'SelfDrive' ? 'Self-drive' : 'With driver'}</small>
                      </td>
                      <td>
                        <strong>{r.vehicleName}</strong>
                        <small>{r.registrationNumber}</small>
                      </td>
                      <td>{r.customerName}<small>{r.customerPhone ?? '—'}</small></td>
                      <td>{r.ownerName}<small>{r.ownerPhone ?? '—'}</small></td>
                      <td>
                        <strong>{day(r.startDate)} — {day(r.endDate)}</strong>
                        <small>{r.days} day(s)</small>
                      </td>
                      <td><strong>{money(r.advanceAmount)}</strong><small>paid</small></td>
                      {/* The deposit is never shown as paid: it does not reach
                          the platform, and an Admin hunting a refund we never
                          took is a long and pointless afternoon. */}
                      <td>
                        {money(r.balanceDue)}
                        <small>+ {money(r.securityDeposit)} deposit, with the owner</small>
                      </td>
                      <td>
                        <Badge value={r.status} />
                        {r.cancelledBy && <small>by {r.cancelledBy}</small>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          {settings && (
            <section className="panel">
              <header className="panelHeader">
                <div>
                  <h2>Rental settings</h2>
                  <p>Terms are at version {settings.disclaimerVersion}.</p>
                </div>
                <button className="primaryButton" onClick={() => void saveSettings()} disabled={busy}>
                  <Save /> Save
                </button>
              </header>

              <div className="formGrid">
                <Field label="Advance taken at booking (%)">
                  <input
                    type="number"
                    min={0}
                    max={100}
                    value={settings.advancePercent}
                    onChange={(e) =>
                      setSettings({ ...settings, advancePercent: Number(e.target.value) })}
                  />
                </Field>
                <Field label="Free cancellation window (hours)">
                  <input
                    type="number"
                    min={0}
                    value={settings.freeCancelHours}
                    onChange={(e) =>
                      setSettings({ ...settings, freeCancelHours: Number(e.target.value) })}
                  />
                </Field>
                <Field label="Largest deposit an owner may ask (PKR, 0 = no limit)">
                  <input
                    type="number"
                    min={0}
                    value={settings.maximumDeposit}
                    onChange={(e) =>
                      setSettings({ ...settings, maximumDeposit: Number(e.target.value) })}
                  />
                </Field>
              </div>

              <Field label="Terms shown to the customer — English">
                <textarea
                  rows={5}
                  value={settings.disclaimerTextEn}
                  onChange={(e) =>
                    setSettings({ ...settings, disclaimerTextEn: e.target.value })}
                />
              </Field>
              <Field label="Terms shown to the customer — Urdu">
                <textarea
                  rows={5}
                  value={settings.disclaimerTextUr}
                  onChange={(e) =>
                    setSettings({ ...settings, disclaimerTextUr: e.target.value })}
                />
              </Field>
              <p>
                Changing either text raises the version by itself. Bookings made before the
                change keep pointing at the wording their customer actually read — which is the
                only reason storing a version is worth anything.
              </p>
            </section>
          )}

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Vehicles on offer for rent</h2>
                <p>
                  {fleet.length} vehicle(s)
                  {hiddenCount > 0 && ` · ${hiddenCount} not showing to customers`}
                </p>
              </div>
            </header>
            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Vehicle</th>
                    <th>Owner</th>
                    <th>With driver</th>
                    <th>Self-drive</th>
                    <th>Deposit</th>
                    <th>Photo</th>
                    <th>Listing</th>
                  </tr>
                </thead>
                <tbody>
                  {fleet.map((v) => (
                    <tr key={v.vehicleId}>
                      <td>
                        <strong>{v.name}</strong>
                        <small>{v.registrationNumber} · {v.bookingCount} booking(s)</small>
                      </td>
                      <td>{v.ownerName}<small>{v.ownerPhone ?? '—'}</small></td>
                      <td>{v.withDriverDaily ? money(v.withDriverDaily) : '—'}</td>
                      <td>{v.selfDriveDaily ? money(v.selfDriveDaily) : '—'}</td>
                      <td>{money(v.securityDeposit)}<small>min {v.minimumDays} day(s)</small></td>
                      <td><Badge value={v.hasPhoto ? 'Yes' : 'No'} /></td>
                      {/* The reason, in the words a support agent can repeat
                          down the phone. "Hidden" on its own starts the call
                          again from the beginning. */}
                      <td>
                        <Badge value={v.listed ? 'Listed' : 'Hidden'} />
                        {v.hiddenReason && <small>{v.hiddenReason}</small>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}

      {selected && (
        <Modal
          title={`${selected.bookingReference} · ${selected.vehicleName} · ${selected.registrationNumber}`}
          onClose={() => setSelected(null)}
        >
          <div className="tableWrap">
            <table>
              <tbody>
                <tr>
                  <td>Customer</td>
                  <td><strong>{selected.customerName}</strong><small>{selected.customerPhone ?? '—'}</small></td>
                </tr>
                <tr>
                  <td>Owner</td>
                  <td><strong>{selected.ownerName}</strong><small>{selected.ownerPhone ?? '—'}</small></td>
                </tr>
                <tr>
                  <td>Dates</td>
                  <td>
                    <strong>{day(selected.startDate)} — {day(selected.endDate)}</strong>
                    <small>
                      {selected.days} day(s) ·{' '}
                      {selected.rentalMode === 'SelfDrive' ? 'self-drive' : 'with a driver'}
                      {selected.pickupPoint ? ` · from ${selected.pickupPoint}` : ''}
                    </small>
                  </td>
                </tr>
                <tr>
                  <td>{selected.days} × {money(selected.dailyRate)}</td>
                  <td><strong>{money(selected.subtotal)}</strong></td>
                </tr>
                <tr>
                  <td>Advance — the platform took this</td>
                  <td><strong>{money(selected.advanceAmount)}</strong><small>ours to refund</small></td>
                </tr>
                <tr>
                  <td>Balance — cash to the owner</td>
                  <td>{money(selected.balanceDue)}<small>never reached us</small></td>
                </tr>
                <tr>
                  <td>Security deposit — held by the owner</td>
                  <td>{money(selected.securityDeposit)}<small>the owner returns it</small></td>
                </tr>
                <tr>
                  <td>Terms accepted</td>
                  <td>
                    <strong>Version {selected.disclaimerVersion}</strong>
                    <small>{when(selected.disclaimerAcceptedAt)}</small>
                  </td>
                </tr>
                {selected.rentalMode === 'SelfDrive' && (
                  <tr>
                    <td>Customer documents</td>
                    <td>
                      <strong>
                        {[
                          selected.cnicFront && 'CNIC front',
                          selected.cnicBack && 'CNIC back',
                          selected.drivingLicence && 'Licence',
                          selected.selfie && 'Photo',
                        ].filter(Boolean).join(' · ') || 'None provided'}
                      </strong>
                      {/* Ticks, not pictures. Looking at a CNIC here would make
                          the platform a party to a check its own terms say it
                          does not perform — and the check that matters is the
                          owner holding the card next to the face in front of
                          them, which no screenshot reproduces. */}
                      <small>The owner sees the images. We see only whether they were given.</small>
                    </td>
                  </tr>
                )}
                {selected.cancelledAt && (
                  <tr>
                    <td>Cancelled</td>
                    <td>
                      <strong>by {selected.cancelledBy}</strong>
                      <small>{when(selected.cancelledAt)} · {selected.cancelReason ?? 'no reason given'}</small>
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {!selected.cancelledAt && (
            <>
              <Field label="Why are you cancelling this? Both sides will see it.">
                <input
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="The owner's car broke down and he cannot reach the customer"
                />
              </Field>
              <p>
                Recorded as cancelled by <strong>Admin</strong>, so it counts against neither
                side, and the advance goes back to the customer.
              </p>
              <button
                className="dangerButton"
                onClick={() => void cancel()}
                disabled={busy || reason.trim().length === 0}
              >
                Cancel this rental
              </button>
            </>
          )}
        </Modal>
      )}
    </AdminFrame>
  );
}
