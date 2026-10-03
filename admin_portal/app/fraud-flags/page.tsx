'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Check, ShieldX } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { apiFetch, money, when } from '../lib/admin-api';

type Flag = {
  id: string;
  driverProfileId: string;
  driverName: string;
  flagType: string;
  detail?: string | null;
  severity: string;
  status: string;
  createdAt: string;
  reviewedAt?: string | null;
  reviewNotes?: string | null;
  cityName?: string | null;
  completedRides: number;
  heldAmount: number;
};

/** What each signal actually means, so a decision is not a guess. */
const EXPLAIN: Record<string, string> = {
  MockLocation:
    'The phone told the server its position was being faked. Android reports this itself — it is not an inference.',
  ImpossibleSpeed:
    'Two heartbeats in the same session put the driver further apart than any road allows. The gap and distance are in the detail.',
};

/**
 * The fraud review queue.
 *
 * The growth engine deliberately decides nothing on its own: a mocked position
 * or an impossible jump writes a row and an admin rules on it. That rule is
 * right — an incentive system that bans people by itself will eventually ban an
 * honest driver, and that driver tells every other driver in the city — but it
 * only works if somebody can actually rule. There was no screen, so every flag
 * ever raised has sat Open and meant nothing.
 *
 * Confirming now holds the driver's rewards that have not yet been paid.
 * Clearing releases them. Money already in a wallet is never taken back, and
 * nobody is blocked from driving either way.
 */
export default function Page() {
  const [rows, setRows] = useState<Flag[]>([]);
  const [status, setStatus] = useState('Open');
  const [search, setSearch] = useState('');
  const [deciding, setDeciding] = useState<Flag | null>(null);
  const [decision, setDecision] = useState<'Cleared' | 'Confirmed'>('Confirmed');
  const [notes, setNotes] = useState('');

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');

  const load = useCallback(async () => {
    try {
      setRows(
        await apiFetch<Flag[]>(
          `/api/v1/admin/growth/fraud-flags${status ? `?status=${status}` : ''}`,
        ),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'This section is unavailable.');
    }
  }, [status]);

  useEffect(() => {
    setLoading(true);
    void load().finally(() => setLoading(false));
  }, [load]);

  const visible = useMemo(() => {
    const term = search.trim().toLowerCase();
    return term
      ? rows.filter((r) => r.driverName.toLowerCase().includes(term))
      : rows;
  }, [rows, search]);

  const stats = useMemo(
    () => ({
      open: rows.filter((r) => r.status === 'Open').length,
      severe: rows.filter((r) => r.severity === 'Severe').length,
      held: rows
        .filter((r) => r.status === 'Confirmed')
        .reduce((sum, r) => sum + r.heldAmount, 0),
      drivers: new Set(rows.map((r) => r.driverProfileId)).size,
    }),
    [rows],
  );

  const open = (row: Flag, which: 'Cleared' | 'Confirmed') => {
    setDeciding(row);
    setDecision(which);
    setNotes(row.reviewNotes ?? '');
  };

  const decide = async () => {
    if (!deciding) return;
    setBusy(true);
    setError('');
    setNote('');
    try {
      await apiFetch<boolean>(
        `/api/v1/admin/growth/fraud-flags/${deciding.id}/review`,
        {
          method: 'POST',
          body: JSON.stringify({ status: decision, notes: notes || null }),
        },
      );
      setDeciding(null);
      setNote(
        decision === 'Confirmed'
          ? 'Confirmed. Any reward this driver had earned but not yet been paid is now on hold.'
          : 'Cleared. Rewards held for this reason are released, unless another confirmed flag is still open.',
      );
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be saved.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <AdminFrame
      title="Fraud review"
      subtitle="Signals the system raised. Nothing happens to a driver until somebody here decides."
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
            <Stat label="Waiting for a decision" value={stats.open} tone="amber" />
            <Stat label="Marked severe" value={stats.severe} tone="rose" />
            <Stat
              label="Rewards on hold"
              value={money(stats.held)}
              sub="Not paid while confirmed"
              tone="slate"
            />
            <Stat label="Drivers involved" value={stats.drivers} tone="blue" />
          </div>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Flags</h2>
                <p>{visible.length} shown</p>
              </div>
            </header>

            <div className="toolbar">
              <select value={status} onChange={(e) => setStatus(e.target.value)}>
                <option value="Open">Waiting</option>
                <option value="Confirmed">Confirmed</option>
                <option value="Cleared">Cleared</option>
                <option value="">All</option>
              </select>
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Driver name"
              />
            </div>

            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Driver</th>
                    <th>What happened</th>
                    <th>Severity</th>
                    <th>Raised</th>
                    <th>On hold</th>
                    <th>Status</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {visible.map((row) => (
                    <tr key={row.id}>
                      <td>
                        <strong>{row.driverName}</strong>
                        <small>
                          {row.cityName ?? 'no city'} · {row.completedRides}{' '}
                          completed ride(s)
                        </small>
                      </td>
                      <td>
                        <strong>{row.flagType}</strong>
                        <small>{row.detail ?? EXPLAIN[row.flagType] ?? '—'}</small>
                      </td>
                      <td>
                        <Badge value={row.severity} />
                      </td>
                      <td>{when(row.createdAt)}</td>
                      <td>{row.heldAmount > 0 ? money(row.heldAmount) : '—'}</td>
                      <td>
                        <Badge value={row.status} />
                        {row.reviewNotes && <small>{row.reviewNotes}</small>}
                      </td>
                      <td>
                        {row.status !== 'Cleared' && (
                          <button
                            className="secondaryButton"
                            disabled={busy}
                            onClick={() => open(row, 'Cleared')}
                          >
                            <Check /> Clear
                          </button>
                        )}
                        {row.status !== 'Confirmed' && (
                          <button
                            className="dangerButton"
                            disabled={busy}
                            onClick={() => open(row, 'Confirmed')}
                          >
                            <ShieldX /> Confirm
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {visible.length === 0 && (
              <p style={{ padding: '18px' }}>
                Nothing to review. The system raises a flag when a phone reports
                a faked position, or when two heartbeats in one session are
                further apart than any road allows.
              </p>
            )}
          </section>
        </>
      )}

      {deciding && (
        <Modal
          title={
            decision === 'Confirmed'
              ? `Confirm — ${deciding.driverName}`
              : `Clear — ${deciding.driverName}`
          }
          onClose={() => setDeciding(null)}
        >
          <div className="detailGrid">
            <div>
              <span>Signal</span>
              <strong>{deciding.flagType}</strong>
            </div>
            <div>
              <span>Raised</span>
              <strong>{when(deciding.createdAt)}</strong>
            </div>
            <div>
              <span>City</span>
              <strong>{deciding.cityName ?? '—'}</strong>
            </div>
            <div>
              <span>Completed rides</span>
              <strong>{deciding.completedRides}</strong>
            </div>
          </div>

          <p>{deciding.detail ?? EXPLAIN[deciding.flagType] ?? ''}</p>

          {/* Said plainly rather than left for somebody to discover. An admin
              pressing Confirm is deciding about money, and the sentence below
              is the whole of what that decision does. */}
          <p>
            {decision === 'Confirmed'
              ? 'Confirming holds every reward this driver has earned but not yet been paid. Money already in their wallet is not taken back, and they can keep driving and keep earning fares.'
              : 'Clearing releases the rewards held for this reason. If another confirmed flag is still open against this driver, nothing is released yet.'}
          </p>

          <Field label="Why — this is kept with the flag">
            <textarea
              rows={3}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder={
                decision === 'Confirmed'
                  ? 'Rang the driver — no answer. Third flag this week.'
                  : 'Old phone with a broken GPS. Checked the trip, it was real.'
              }
            />
          </Field>

          <div className="buttonRow">
            <button
              className="secondaryButton"
              onClick={() => setDeciding(null)}
              disabled={busy}
            >
              Cancel
            </button>
            <button
              className={
                decision === 'Confirmed' ? 'dangerButton' : 'primaryButton'
              }
              onClick={() => void decide()}
              disabled={busy}
            >
              {decision === 'Confirmed' ? 'Confirm the flag' : 'Clear the flag'}
            </button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
