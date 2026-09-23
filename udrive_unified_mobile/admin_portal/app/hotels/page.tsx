'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Building2,
  CheckCircle2,
  Eye,
  EyeOff,
  RefreshCw,
  Search,
  XCircle,
} from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { API_BASE, apiFetch, when } from '../lib/admin-api';

type HotelRow = {
  id: string;
  name: string;
  description: string;
  address: string;
  city: string;
  district: string;
  latitude: number;
  longitude: number;
  contactPhone: string;
  rating: number;
  mainImageUrl: string;
  transportAvailable: boolean;
  approvalStatus: string;
  rejectionReason?: string | null;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
  ownerName: string;
  ownerPhone: string;
  roomTypes: number;
  totalRooms: number;
};

function imageUrl(value: string) {
  if (!value) return '';
  return /^https?:\/\//i.test(value) ? value : new URL(value, API_BASE).toString();
}

export default function HotelsPage() {
  const [rows, setRows] = useState<HotelRow[]>([]);
  const [busy, setBusy] = useState(true);
  const [workingId, setWorkingId] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('All');
  const [rejecting, setRejecting] = useState<HotelRow | null>(null);
  const [reason, setReason] = useState('');

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setRows(await apiFetch<HotelRow[]>('/api/v1/hotels/admin'));
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Hotels could not be loaded.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();
    return rows.filter((item) => {
      const matchesStatus = status === 'All' || item.approvalStatus === status;
      const matchesQuery = !normalizedQuery || `${item.name} ${item.city} ${item.district} ${item.address} ${item.ownerName} ${item.ownerPhone}`
        .toLowerCase()
        .includes(normalizedQuery);
      return matchesStatus && matchesQuery;
    });
  }, [query, rows, status]);

  const counts = useMemo(
    () => ({
      pending: rows.filter((item) => item.approvalStatus === 'Pending').length,
      approved: rows.filter((item) => item.approvalStatus === 'Approved').length,
      rejected: rows.filter((item) => item.approvalStatus === 'Rejected').length,
      visible: rows.filter((item) => item.approvalStatus === 'Approved' && item.isActive).length,
    }),
    [rows],
  );

  async function review(item: HotelRow, approve: boolean, rejectionReason?: string) {
    setWorkingId(item.id);
    setError('');
    setSuccess('');
    try {
      await apiFetch(`/api/v1/hotels/admin/${item.id}/review`, {
        method: 'POST',
        body: JSON.stringify({ approve, reason: rejectionReason ?? null }),
      });
      setRejecting(null);
      setReason('');
      setSuccess(approve ? `${item.name} approved and published.` : `${item.name} rejected.`);
      await load();
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Hotel review could not be saved.');
    } finally {
      setWorkingId('');
    }
  }

  async function setActive(item: HotelRow, isActive: boolean) {
    setWorkingId(item.id);
    setError('');
    setSuccess('');
    try {
      await apiFetch(`/api/v1/hotels/admin/${item.id}/active`, {
        method: 'PATCH',
        body: JSON.stringify({ isActive }),
      });
      setSuccess(`${item.name} is now ${isActive ? 'visible' : 'hidden'} for customers.`);
      await load();
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Hotel visibility could not be updated.');
    } finally {
      setWorkingId('');
    }
  }

  return (
    <AdminFrame
      title="Hotels & stays approval"
      subtitle="Review customer-submitted hotels. Only approved and active properties appear in the mobile app."
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
        <Stat label="Visible to customers" value={counts.visible} tone="blue" />
        <Stat label="Rejected" value={counts.rejected} tone="rose" />
      </section>

      <section className="panel hotelApprovalPanel">
        <header className="panelHeader">
          <div>
            <h2>Hotel submissions</h2>
            <p>Approve, reject, publish or temporarily hide a hotel.</p>
          </div>
          <div className="tableTools">
            <label className="searchBox">
              <Search />
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                onKeyDown={(event) => event.key === 'Enter' && void load()}
                placeholder="Hotel, owner or city…"
              />
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
          <Empty title="No hotel submissions" copy="New hotels submitted by customers will appear here." />
        ) : (
          <div className="hotelApprovalGrid">
            {filtered.map((item) => (
              <article className="hotelApprovalCard" key={item.id}>
                <div className="hotelApprovalImage">
                  {item.mainImageUrl ? (
                    <img src={imageUrl(item.mainImageUrl)} alt={item.name} />
                  ) : (
                    <div><Building2 /></div>
                  )}
                  <span><Badge value={item.approvalStatus} /></span>
                </div>
                <div className="hotelApprovalBody">
                  <div className="hotelApprovalTitle">
                    <div>
                      <h3>{item.name}</h3>
                      <p>{item.city}{item.district ? `, ${item.district}` : ''}</p>
                    </div>
                    <Badge value={item.isActive ? 'Active' : 'Hidden'} />
                  </div>
                  <p className="hotelApprovalDescription">{item.description || 'No description provided.'}</p>
                  <dl className="hotelApprovalFacts">
                    <div><dt>Owner</dt><dd>{item.ownerName}</dd></div>
                    <div><dt>Phone</dt><dd>{item.ownerPhone || item.contactPhone || '—'}</dd></div>
                    <div><dt>Rooms</dt><dd>{item.totalRooms} rooms · {item.roomTypes} types</dd></div>
                    <div><dt>Submitted</dt><dd>{when(item.createdAt)}</dd></div>
                    <div className="hotelApprovalAddress"><dt>Address</dt><dd>{item.address}</dd></div>
                  </dl>
                  {item.rejectionReason && (
                    <div className="hotelRejectionReason"><strong>Rejection reason</strong>{item.rejectionReason}</div>
                  )}
                  <div className="hotelApprovalActions">
                    {item.approvalStatus !== 'Approved' && (
                      <button
                        className="primaryButton"
                        disabled={workingId === item.id}
                        onClick={() => void review(item, true)}
                      >
                        <CheckCircle2 /> Approve
                      </button>
                    )}
                    {item.approvalStatus !== 'Rejected' && (
                      <button
                        className="dangerButton"
                        disabled={workingId === item.id}
                        onClick={() => { setRejecting(item); setReason(''); }}
                      >
                        <XCircle /> Reject
                      </button>
                    )}
                    {item.approvalStatus === 'Approved' && (
                      <button
                        className="secondaryButton"
                        disabled={workingId === item.id}
                        onClick={() => void setActive(item, !item.isActive)}
                      >
                        {item.isActive ? <EyeOff /> : <Eye />}
                        {item.isActive ? 'Hide' : 'Publish'}
                      </button>
                    )}
                  </div>
                </div>
              </article>
            ))}
          </div>
        )}
      </section>

      {rejecting && (
        <Modal title={`Reject ${rejecting.name}`} onClose={() => setRejecting(null)}>
          <div className="detailStack">
            <p>Explain what the hotel owner needs to correct before submitting again.</p>
          </div>
          <Field label="Rejection reason">
            <textarea
              rows={5}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              placeholder="For example: hotel contact details or address could not be verified."
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
