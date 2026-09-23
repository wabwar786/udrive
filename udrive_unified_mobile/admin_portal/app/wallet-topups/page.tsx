'use client';

import { useCallback, useEffect, useState } from 'react';
import { Check, RefreshCw, X } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Empty, ErrorBox, Field, Loading } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

type Topup = {
  id: string;
  driverName: string | null;
  amount: number;
  method: string;
  senderReference: string | null;
  status: string;
  adminNotes: string | null;
  createdAt: string;
};

/**
 * Confirming that Driver top-up money actually arrived.
 *
 * Approving here creates credit. If the money is not really in the company
 * account, the platform has just handed a Driver free commission — so the page
 * puts the transaction ID beside the amount, which is what gets matched against
 * the EasyPaisa statement, and refuses a rejection with no reason.
 */
export default function Page() {
  const [rows, setRows] = useState<Topup[]>([]);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [working, setWorking] = useState<string | null>(null);

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setRows(await apiFetch<Topup[]>('/api/v1/admin/wallet-topups/pending'));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load top-ups.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function review(topup: Topup, approve: boolean) {
    // A rejection with no reason leaves a Driver who may genuinely have sent
    // money with nowhere to go. The note reaches them in the app.
    if (!approve && !(notes[topup.id] ?? '').trim()) {
      setError('Write why this payment is being rejected. The driver sees it.');
      return;
    }

    setWorking(topup.id);
    setError('');
    try {
      await apiFetch(`/api/v1/admin/wallet-topups/${topup.id}/review`, {
        method: 'POST',
        body: JSON.stringify({ approve, notes: notes[topup.id] ?? null }),
      });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that decision.');
    } finally {
      setWorking(null);
    }
  }

  return (
    <AdminFrame
      title="Driver top-ups"
      subtitle="Confirm money has arrived before crediting a driver's commission balance."
    >
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Waiting for confirmation</h2>
            <p>
              Check each transaction ID against the EasyPaisa statement before
              approving. Approving credits the balance immediately.
            </p>
          </div>
          <div className="tableTools">
            <button className="secondaryButton" onClick={() => void load()}>
              <RefreshCw />
              Refresh
            </button>
          </div>
        </header>

        {error && <ErrorBox message={error} />}

        {busy ? (
          <Loading />
        ) : rows.length === 0 ? (
          <Empty
            title="Nothing waiting"
            copy="Every driver payment has been dealt with."
          />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Driver</th>
                  <th>Amount</th>
                  <th>Transaction ID</th>
                  <th>Sent</th>
                  <th>Note (required to reject)</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {rows.map((topup) => (
                  <tr key={topup.id}>
                    <td>{topup.driverName ?? '—'}</td>
                    <td>
                      <strong>PKR {topup.amount.toLocaleString()}</strong>
                    </td>
                    <td>{topup.senderReference ?? '— none given —'}</td>
                    <td>{new Date(topup.createdAt).toLocaleString()}</td>
                    <td>
                      <Field label="">
                        <input
                          value={notes[topup.id] ?? ''}
                          placeholder="Reason, if rejecting"
                          onChange={(e) =>
                            setNotes({ ...notes, [topup.id]: e.target.value })
                          }
                        />
                      </Field>
                    </td>
                    <td>
                      <div className="tableTools">
                        <button
                          className="primaryButton"
                          disabled={working === topup.id}
                          onClick={() => void review(topup, true)}
                        >
                          <Check />
                          Approve
                        </button>
                        <button
                          className="dangerButton"
                          disabled={working === topup.id}
                          onClick={() => void review(topup, false)}
                        >
                          <X />
                          Reject
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </AdminFrame>
  );
}
