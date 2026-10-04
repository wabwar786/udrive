'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { CheckCircle2, Eye, EyeOff, MapPin, RefreshCw, Search, XCircle } from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { apiFetch, when } from '../lib/admin-api';

type BusinessRow = {
  id: string;
  name: string;
  category: string;
  address: string;
  phone: string;
  description: string;
  latitude: number;
  longitude: number;
  open24Hours: boolean;
  opensAt?: string | null;
  closesAt?: string | null;
  status: string;
  rejectionReason?: string | null;
  isActive: boolean;
  ownerName: string;
  ownerPhone: string;
  createdAt: string;
  isDemo: boolean;
};

const categoryLabel: Record<string, string> = {
  Restaurant: 'Restaurant',
  Grocery: 'Grocery',
  MedicalStore: 'Medical store',
  Hospital: 'Hospital',
  Bank: 'ATM / Bank',
  Fuel: 'Fuel',
  Mosque: 'Mosque',
};

function hours(row: BusinessRow) {
  if (row.open24Hours) return 'Open 24 hours';
  if (row.opensAt && row.closesAt) return `${row.opensAt} – ${row.closesAt}`;
  return 'Not given';
}

export default function BusinessesPage() {
  const [rows, setRows] = useState<BusinessRow[]>([]);
  const [busy, setBusy] = useState(true);
  const [workingId, setWorkingId] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('All');
  const [rejecting, setRejecting] = useState<BusinessRow | null>(null);
  const [reason, setReason] = useState('');

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setRows(await apiFetch<BusinessRow[]>('/api/v1/admin/businesses'));
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Businesses could not be loaded.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return rows.filter((row) => {
      const statusOk = status === 'All' || row.status === status;
      const queryOk = !needle || `${row.name} ${row.address} ${row.ownerName} ${row.ownerPhone} ${row.phone}`
        .toLowerCase()
        .includes(needle);
      return statusOk && queryOk;
    });
  }, [query, rows, status]);

  const counts = useMemo(() => ({
    pending: rows.filter((row) => row.status === 'Pending').length,
    approved: rows.filter((row) => row.status === 'Approved').length,
    visible: rows.filter((row) => row.status === 'Approved' && row.isActive).length,
    rejected: rows.filter((row) => row.status === 'Rejected').length,
  }), [rows]);

  async function review(row: BusinessRow, approve: boolean, rejectionReason?: string) {
    setWorkingId(row.id);
    setError('');
    setSuccess('');
    try {
      await apiFetch(`/api/v1/admin/businesses/${row.id}/review`, {
        method: 'POST',
        body: JSON.stringify({ approve, reason: rejectionReason ?? null }),
      });
      setRejecting(null);
      setReason('');
      setSuccess(approve ? `${row.name} approved — it now shows in Near me.` : `${row.name} rejected.`);
      await load();
    } catch (value) {
      setError(value instanceof Error ? value.message : 'The review could not be saved.');
    } finally {
      setWorkingId('');
    }
  }

  async function setActive(row: BusinessRow, isActive: boolean) {
    setWorkingId(row.id);
    setError('');
    setSuccess('');
    try {
      await apiFetch(`/api/v1/admin/businesses/${row.id}/active`, {
        method: 'PATCH',
        body: JSON.stringify({ isActive }),
      });
      setSuccess(`${row.name} is now ${isActive ? 'visible' : 'hidden'} in Near me.`);
      await load();
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Visibility could not be updated.');
    } finally {
      setWorkingId('');
    }
  }

  return (
    <AdminFrame
      title="Near me businesses"
      subtitle="Shops, restaurants and services that listed themselves. Only approved and visible ones appear in the app."
      actions={
        <button className="secondaryButton" onClick={() => void load()} disabled={busy}>
          <RefreshCw className={busy ? 'spin' : ''} /> Refresh
        </button>
      }
    >
      {error && <ErrorBox message={error} />}
      {success && <div className="successBox">{success}</div>}

      <section className="statGrid hotelApprovalStats">
        <Stat label="Pending approval" value={counts.pending} tone="amber" />
        <Stat label="Approved" value={counts.approved} tone="emerald" />
        <Stat label="Visible in app" value={counts.visible} tone="blue" />
        <Stat label="Rejected" value={counts.rejected} tone="rose" />
      </section>

      <section className="panel hotelApprovalPanel">
        <header className="panelHeader">
          <div>
            <h2>Listings</h2>
            <p>Approve, reject, or hide a business. An owner&apos;s edit comes back here as Pending.</p>
          </div>
          <div className="tableTools">
            <label className="searchBox">
              <Search />
              <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Name, owner or phone…" />
            </label>
            <select value={status} onChange={(event) => setStatus(event.target.value)}>
              <option>All</option>
              <option>Pending</option>
              <option>Approved</option>
              <option>Rejected</option>
            </select>
          </div>
        </header>

        {busy ? (
          <Loading />
        ) : filtered.length === 0 ? (
          <Empty title="No businesses" copy="Businesses listed from the app will appear here." />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Business</th>
                  <th>Category</th>
                  <th>Hours</th>
                  <th>Owner</th>
                  <th>Submitted</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <strong>{row.name}</strong>{row.isDemo && <> <Badge value="Demo" /></>}
                      <small style={{ display: 'block', color: '#6d7e77', marginTop: 3 }}>{row.address}</small>
                      <a
                        className="textLink"
                        href={`https://www.google.com/maps/search/?api=1&query=${row.latitude},${row.longitude}`}
                        target="_blank"
                        rel="noreferrer"
                      >
                        <MapPin /> Check pin
                      </a>
                      {row.rejectionReason && (
                        <small style={{ display: 'block', color: '#a62032', marginTop: 3 }}>Rejected: {row.rejectionReason}</small>
                      )}
                    </td>
                    <td>{categoryLabel[row.category] ?? row.category}</td>
                    <td>{hours(row)}</td>
                    <td>
                      {row.ownerName}
                      <small style={{ display: 'block', color: '#6d7e77', marginTop: 3 }}>{row.ownerPhone || row.phone}</small>
                    </td>
                    <td>{when(row.createdAt)}</td>
                    <td>
                      <Badge value={row.status} />{' '}
                      {row.status === 'Approved' && <Badge value={row.isActive ? 'Active' : 'Hidden'} />}
                    </td>
                    <td>
                      <div className="hotelApprovalActions" style={{ border: 0, margin: 0, padding: 0 }}>
                        {row.status !== 'Approved' && (
                          <button className="primaryButton" disabled={workingId === row.id} onClick={() => void review(row, true)}>
                            <CheckCircle2 /> Approve
                          </button>
                        )}
                        {row.status !== 'Rejected' && (
                          <button
                            className="dangerButton"
                            disabled={workingId === row.id}
                            onClick={() => { setRejecting(row); setReason(''); }}
                          >
                            <XCircle /> Reject
                          </button>
                        )}
                        {row.status === 'Approved' && (
                          <button className="secondaryButton" disabled={workingId === row.id} onClick={() => void setActive(row, !row.isActive)}>
                            {row.isActive ? <EyeOff /> : <Eye />} {row.isActive ? 'Hide' : 'Show'}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {rejecting && (
        <Modal title={`Reject ${rejecting.name}`} onClose={() => setRejecting(null)}>
          <div className="detailStack">
            <p>Tell the owner what to correct before listing again.</p>
          </div>
          <Field label="Rejection reason">
            <textarea
              rows={5}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              placeholder="For example: the location pin is not at the shop."
            />
          </Field>
          <div className="buttonRow">
            <button className="secondaryButton" onClick={() => setRejecting(null)}>Cancel</button>
            <button
              className="dangerButton"
              disabled={!reason.trim() || workingId === rejecting.id}
              onClick={() => void review(rejecting, false, reason.trim())}
            >
              <XCircle /> Confirm rejection
            </button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
