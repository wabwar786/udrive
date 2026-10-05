'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Car,
  CheckCircle2,
  MessageSquareText,
  Plus,
  RefreshCw,
  Search,
  XCircle,
} from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { API_BASE, apiFetch, apiProtectedFile, readSession, when } from '../lib/admin-api';

type ListingDocs = {
  front: string | null;
  registrationFront: string | null;
  registrationBack: string | null;
  cnicFront: string | null;
  cnicBack: string | null;
  selfie: string | null;
  licenceFront: string | null;
  licenceBack: string | null;
};

type ListingRow = {
  vehicleId: string;
  name: string;
  year: number;
  category: string;
  registrationNumber: string;
  seats: number;
  photoUrl?: string | null;
  wantsRent: boolean;
  wantsTour: boolean;
  withDriverDaily?: number | null;
  selfDriveDaily?: number | null;
  readinessScore?: number | null;
  status: string;
  reviewNote?: string | null;
  submittedAt?: string | null;
  listedVia: 'Listing' | 'Staff';
  ownerUserId: string;
  ownerName: string;
  ownerPhone: string;
  ownerVehicles: number;
  drivesSelf: boolean;
  licenceNumber?: string | null;
  licenceExpiry?: string | null;
  docs: ListingDocs;
};

type DriverDocs = {
  cnicFront: string | null;
  cnicBack: string | null;
  selfie: string | null;
  licenceFront: string | null;
  licenceBack: string | null;
};

type FleetDriverRow = {
  id: string;
  name: string;
  phone: string;
  isOwner: boolean;
  ownerName?: string | null;
  ownerPhone?: string | null;
  status: string;
  licenceNumber?: string | null;
  licenceExpiry?: string | null;
  licenceValid: boolean;
  submittedAt?: string | null;
  reviewNote?: string | null;
  docs: DriverDocs;
};

type ReasonTarget =
  | { kind: 'reject'; row: ListingRow }
  | { kind: 'info'; row: ListingRow }
  | { kind: 'driver'; row: FleetDriverRow };

type OwnerForm = {
  ownerPhone: string;
  ownerName: string;
  category: string;
  make: string;
  model: string;
  year: string;
  registrationNumber: string;
  seats: string;
  wantsRent: boolean;
  wantsTour: boolean;
  withDriverDaily: string;
  selfDriveDaily: string;
  pickupPoint: string;
};

type OwnerFiles = {
  front: File | null;
  registrationFront: File | null;
  registrationBack: File | null;
  cnicFront: File | null;
  cnicBack: File | null;
};

const EMPTY_FORM: OwnerForm = {
  ownerPhone: '',
  ownerName: '',
  category: 'Car',
  make: '',
  model: '',
  year: '',
  registrationNumber: '',
  seats: '',
  wantsRent: true,
  wantsTour: false,
  withDriverDaily: '',
  selfDriveDaily: '',
  pickupPoint: '',
};

const EMPTY_FILES: OwnerFiles = {
  front: null,
  registrationFront: null,
  registrationBack: null,
  cnicFront: null,
  cnicBack: null,
};

const subtext = { display: 'block', color: '#6d7e77', marginTop: 3 } as const;
const redText = { display: 'block', color: '#a62032', marginTop: 3 } as const;

function imageUrl(value?: string | null) {
  if (!value) return '';
  return /^https?:\/\//i.test(value) ? value : new URL(value, API_BASE).toString();
}

function daysUntil(value?: string | null) {
  if (!value) return null;
  const time = new Date(value).getTime();
  if (Number.isNaN(time)) return null;
  return Math.floor((time - Date.now()) / 86_400_000);
}

function errorText(value: unknown, fallback: string) {
  return value instanceof Error ? value.message : fallback;
}

/**
 * Multipart POST with the admin token. `apiUpload` only sends one file, and
 * this form sends several plus fields, so it is built here. The browser sets
 * the multipart content type itself.
 */
async function postMultipart<T>(path: string, body: FormData): Promise<T> {
  const token = readSession()?.accessToken;
  const response = await fetch(new URL(path, API_BASE).toString(), {
    method: 'POST',
    cache: 'no-store',
    headers: {
      Accept: 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body,
  });
  const payload = (await response.json().catch(() => ({}))) as {
    data?: T;
    message?: unknown;
  };
  if (!response.ok) {
    const message = typeof payload.message === 'string' && !/traceid|request could not be completed/i.test(payload.message)
      ? payload.message
      : '';
    if (response.status === 401) throw new Error('Your session has expired. Please sign in again.');
    if (response.status === 403) throw new Error('You do not have permission to do this.');
    if (response.status === 400 || response.status === 422) {
      throw new Error(message || 'Some information is invalid. Please review the form and try again.');
    }
    if (response.status >= 500) throw new Error('This section is temporarily unavailable. Please try again after a moment.');
    throw new Error(message || 'This action is temporarily unavailable. Please try again.');
  }
  return payload.data as T;
}

function DocChip({ label, url, onOpen }: { label: string; url: string | null; onOpen: (url: string) => void }) {
  const base = {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 4,
    padding: '3px 8px',
    margin: '0 4px 4px 0',
    borderRadius: 999,
    fontSize: 11,
    fontWeight: 700,
    border: 0,
    whiteSpace: 'nowrap',
  } as const;
  if (!url) {
    return <span style={{ ...base, background: '#fdecee', color: '#a62032' }}>{label} · missing</span>;
  }
  return (
    <button
      type="button"
      title={`Open ${label}`}
      style={{ ...base, background: '#e6f5ee', color: '#0a7a58', cursor: 'pointer' }}
      onClick={() => onOpen(url)}
    >
      {label} ✓
    </button>
  );
}

export default function VehicleListingsPage() {
  const [tab, setTab] = useState<'vehicles' | 'drivers'>('vehicles');

  const [allListings, setAllListings] = useState<ListingRow[]>([]);
  const [listings, setListings] = useState<ListingRow[]>([]);
  const [listingStatus, setListingStatus] = useState('PendingReview');
  const [drivers, setDrivers] = useState<FleetDriverRow[]>([]);
  const [driverStatus, setDriverStatus] = useState('Submitted');

  const [busy, setBusy] = useState(true);
  const [workingId, setWorkingId] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [query, setQuery] = useState('');

  const [target, setTarget] = useState<ReasonTarget | null>(null);
  const [reason, setReason] = useState('');

  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState<OwnerForm>(EMPTY_FORM);
  const [files, setFiles] = useState<OwnerFiles>(EMPTY_FILES);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState('');

  const loadStats = useCallback(async () => {
    try {
      setAllListings(await apiFetch<ListingRow[]>('/api/v1/admin/listings?status=All'));
    } catch {
      // The stat row is secondary; the main list shows its own error.
    }
  }, []);

  const loadListings = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setListings(await apiFetch<ListingRow[]>(`/api/v1/admin/listings?status=${encodeURIComponent(listingStatus)}`));
    } catch (value) {
      setError(errorText(value, 'Vehicle listings could not be loaded.'));
    } finally {
      setBusy(false);
    }
  }, [listingStatus]);

  const loadDrivers = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setDrivers(await apiFetch<FleetDriverRow[]>(`/api/v1/admin/fleet-drivers?status=${encodeURIComponent(driverStatus)}`));
    } catch (value) {
      setError(errorText(value, 'Drivers could not be loaded.'));
    } finally {
      setBusy(false);
    }
  }, [driverStatus]);

  const reload = useCallback(async () => {
    await Promise.all([tab === 'vehicles' ? loadListings() : loadDrivers(), loadStats()]);
  }, [tab, loadListings, loadDrivers, loadStats]);

  useEffect(() => {
    void loadStats();
  }, [loadStats]);

  useEffect(() => {
    if (tab === 'vehicles') void loadListings();
  }, [tab, loadListings]);

  useEffect(() => {
    if (tab === 'drivers') void loadDrivers();
  }, [tab, loadDrivers]);

  const counts = useMemo(
    () => ({
      waiting: allListings.filter((item) => item.status === 'PendingReview').length,
      rent: allListings.filter((item) => item.status === 'Verified' && item.wantsRent).length,
      tours: allListings.filter((item) => item.status === 'Verified' && item.wantsTour).length,
      staff: allListings.filter((item) => item.listedVia === 'Staff').length,
    }),
    [allListings],
  );

  const filteredListings = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return listings;
    return listings.filter((item) =>
      `${item.name} ${item.registrationNumber} ${item.ownerName} ${item.ownerPhone}`.toLowerCase().includes(q),
    );
  }, [listings, query]);

  const filteredDrivers = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return drivers;
    return drivers.filter((item) =>
      `${item.name} ${item.phone} ${item.ownerName ?? ''} ${item.ownerPhone ?? ''} ${item.licenceNumber ?? ''}`.toLowerCase().includes(q),
    );
  }, [drivers, query]);

  async function openDoc(url: string) {
    setError('');
    // Open the tab first so the browser does not treat it as a pop-up.
    const win = window.open('', '_blank');
    try {
      const file = await apiProtectedFile(url);
      if (win) win.location.href = file.objectUrl;
      else window.open(file.objectUrl, '_blank', 'noopener,noreferrer');
    } catch (value) {
      win?.close();
      setError(errorText(value, 'The document could not be opened.'));
    }
  }

  async function run(id: string, action: () => Promise<unknown>, done: string, failed: string) {
    setWorkingId(id);
    setError('');
    setSuccess('');
    try {
      await action();
      setTarget(null);
      setReason('');
      setSuccess(done);
      await reload();
    } catch (value) {
      setError(errorText(value, failed));
    } finally {
      setWorkingId('');
    }
  }

  function approveListing(row: ListingRow) {
    void run(
      row.vehicleId,
      () => apiFetch(`/api/v1/admin/listings/${row.vehicleId}/approve`, { method: 'POST' }),
      `${row.name} approved and live.`,
      'The vehicle could not be approved.',
    );
  }

  function approveDriver(row: FleetDriverRow) {
    void run(
      row.id,
      () => apiFetch(`/api/v1/admin/fleet-drivers/${row.id}/approve`, { method: 'POST' }),
      `${row.name} approved.`,
      'The driver could not be approved.',
    );
  }

  function confirmTarget() {
    if (!target || !reason.trim()) return;
    const text = reason.trim();
    if (target.kind === 'reject') {
      const row = target.row;
      void run(
        row.vehicleId,
        () => apiFetch(`/api/v1/admin/listings/${row.vehicleId}/reject`, { method: 'POST', body: JSON.stringify({ reason: text }) }),
        `${row.name} rejected.`,
        'The vehicle could not be rejected.',
      );
    } else if (target.kind === 'info') {
      const row = target.row;
      void run(
        row.vehicleId,
        () => apiFetch(`/api/v1/admin/listings/${row.vehicleId}/request-info`, { method: 'POST', body: JSON.stringify({ note: text }) }),
        `Note sent to the owner of ${row.name}.`,
        'The note could not be sent.',
      );
    } else {
      const row = target.row;
      void run(
        row.id,
        () => apiFetch(`/api/v1/admin/fleet-drivers/${row.id}/reject`, { method: 'POST', body: JSON.stringify({ reason: text }) }),
        `${row.name} rejected.`,
        'The driver could not be rejected.',
      );
    }
  }

  function openAdd() {
    setForm(EMPTY_FORM);
    setFiles(EMPTY_FILES);
    setFormError('');
    setAdding(true);
  }

  async function submitAdd() {
    setFormError('');
    if (!form.ownerPhone.trim() || !form.ownerName.trim()) {
      setFormError('Enter the owner name and phone.');
      return;
    }
    if (!form.wantsRent && !form.wantsTour) {
      setFormError('Choose rent, tours or both.');
      return;
    }
    if (!files.front || !files.registrationFront || !files.registrationBack) {
      setFormError('Add the car photo and both sides of the registration book.');
      return;
    }
    const body = new FormData();
    body.append('ownerPhone', form.ownerPhone.trim());
    body.append('ownerName', form.ownerName.trim());
    body.append('category', form.category);
    body.append('make', form.make.trim());
    body.append('model', form.model.trim());
    body.append('year', form.year.trim());
    body.append('registrationNumber', form.registrationNumber.trim());
    body.append('seats', form.seats.trim());
    body.append('wantsRent', String(form.wantsRent));
    body.append('wantsTour', String(form.wantsTour));
    if (form.withDriverDaily.trim()) body.append('withDriverDaily', form.withDriverDaily.trim());
    if (form.selfDriveDaily.trim()) body.append('selfDriveDaily', form.selfDriveDaily.trim());
    body.append('pickupPoint', form.pickupPoint.trim());
    (Object.keys(files) as (keyof OwnerFiles)[]).forEach((key) => {
      const file = files[key];
      if (file) body.append(key, file);
    });

    setSaving(true);
    try {
      const created = await postMultipart<ListingRow>('/api/v1/admin/listings/for-owner', body);
      setAdding(false);
      setSuccess(`${created?.name ?? 'Vehicle'} added for ${form.ownerName.trim()} and is live.`);
      await reload();
    } catch (value) {
      setFormError(errorText(value, 'The vehicle could not be added.'));
    } finally {
      setSaving(false);
    }
  }

  function setField<K extends keyof OwnerForm>(key: K, value: OwnerForm[K]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function fileInput(key: keyof OwnerFiles, label: string) {
    return (
      <Field label={label}>
        <input
          type="file"
          accept="image/*"
          onChange={(event) => {
            const file = event.target.files?.[0] ?? null;
            setFiles((current) => ({ ...current, [key]: file }));
          }}
        />
      </Field>
    );
  }

  const targetTitle = !target
    ? ''
    : target.kind === 'info'
      ? `Ask for info · ${target.row.name}`
      : `Reject ${target.row.name}`;

  return (
    <AdminFrame
      title="Vehicle listings"
      subtitle="One review per vehicle: documents, owner and listing together. Approve makes it live."
      actions={
        <>
          <button className="secondaryButton" onClick={() => void reload()} disabled={busy}>
            <RefreshCw className={busy ? 'spin' : ''} /> Refresh
          </button>
          <button className="primaryButton" onClick={openAdd}>
            <Plus /> Add vehicle for an owner
          </button>
        </>
      }
    >
      {error && <ErrorBox message={error} />}
      {success && <div className="successBox">{success}</div>}

      <section className="statGrid hotelApprovalStats">
        <Stat label="Waiting for review" value={counts.waiting} tone="amber" />
        <Stat label="Live for rent" value={counts.rent} tone="emerald" />
        <Stat label="Live for tours" value={counts.tours} tone="blue" />
        <Stat label="Added by staff" value={counts.staff} tone="violet" />
      </section>

      <section className="panel hotelApprovalPanel">
        <header className="panelHeader">
          <div>
            <div className="financeTabs" style={{ marginBottom: 8 }}>
              <button className={tab === 'vehicles' ? 'active' : ''} onClick={() => setTab('vehicles')}>Vehicles</button>
              <button className={tab === 'drivers' ? 'active' : ''} onClick={() => setTab('drivers')}>Drivers</button>
            </div>
            {tab === 'vehicles' ? (
              <>
                <h2>Vehicles</h2>
                <p>Check the documents, then approve, reject or ask the owner for more.</p>
              </>
            ) : (
              <>
                <h2>Drivers</h2>
                <p>Owners who drive and invited drivers. Nobody gets a booking until approved here; an expired licence blocks them automatically.</p>
              </>
            )}
          </div>
          <div className="tableTools">
            <label className="searchBox">
              <Search />
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder={tab === 'vehicles' ? 'Vehicle, plate, owner or phone…' : 'Driver, phone, owner or licence…'}
              />
            </label>
            {tab === 'vehicles' ? (
              <select value={listingStatus} onChange={(event) => setListingStatus(event.target.value)}>
                <option value="All">All</option>
                <option value="PendingReview">Pending review</option>
                <option value="Verified">Verified</option>
                <option value="Draft">Draft</option>
                <option value="Rejected">Rejected</option>
              </select>
            ) : (
              <select value={driverStatus} onChange={(event) => setDriverStatus(event.target.value)}>
                <option value="All">All</option>
                <option value="Submitted">Submitted</option>
                <option value="Approved">Approved</option>
                <option value="Rejected">Rejected</option>
              </select>
            )}
          </div>
        </header>

        {busy ? (
          <Loading />
        ) : tab === 'vehicles' ? (
          filteredListings.length === 0 ? (
            <Empty title="No vehicles" copy="Vehicles listed from the app will appear here." />
          ) : (
            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Vehicle</th>
                    <th>For</th>
                    <th>Owner</th>
                    <th>Documents</th>
                    <th>Submitted</th>
                    <th>Status</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredListings.map((row) => {
                    const working = workingId === row.vehicleId;
                    return (
                      <tr key={row.vehicleId}>
                        <td>
                          <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                            {row.photoUrl ? (
                              <img
                                src={imageUrl(row.photoUrl)}
                                alt={row.name}
                                style={{ width: 56, height: 40, objectFit: 'cover', borderRadius: 8, flexShrink: 0 }}
                              />
                            ) : (
                              <Car style={{ width: 22, height: 22, color: '#6d7e77', flexShrink: 0 }} />
                            )}
                            <div>
                              <strong>{row.name} {row.year}</strong>
                              <small style={subtext}>{row.registrationNumber} · {row.seats} seats</small>
                            </div>
                          </div>
                        </td>
                        <td>
                          {row.wantsRent && <Badge value="Rent" />}{' '}
                          {row.wantsTour && <Badge value="Tour" />}
                          {!row.wantsRent && !row.wantsTour && '—'}
                        </td>
                        <td>
                          {row.ownerName}
                          <small style={subtext}>{row.ownerPhone}</small>
                          <small style={subtext}>{row.ownerVehicles} {row.ownerVehicles === 1 ? 'vehicle' : 'vehicles'}</small>
                          {row.listedVia === 'Staff' && <small style={subtext}>Added by staff</small>}
                          {row.drivesSelf && <small style={subtext}>Drives himself</small>}
                        </td>
                        <td style={{ maxWidth: 300 }}>
                          <DocChip label="Car photo" url={row.docs?.front ?? null} onOpen={openDoc} />
                          <DocChip label="Reg. book front" url={row.docs?.registrationFront ?? null} onOpen={openDoc} />
                          <DocChip label="Reg. book back" url={row.docs?.registrationBack ?? null} onOpen={openDoc} />
                          <DocChip label="CNIC front" url={row.docs?.cnicFront ?? null} onOpen={openDoc} />
                          <DocChip label="CNIC back" url={row.docs?.cnicBack ?? null} onOpen={openDoc} />
                          <DocChip label="Selfie" url={row.docs?.selfie ?? null} onOpen={openDoc} />
                          {row.drivesSelf && (
                            <>
                              <DocChip label="Licence front" url={row.docs?.licenceFront ?? null} onOpen={openDoc} />
                              <DocChip label="Licence back" url={row.docs?.licenceBack ?? null} onOpen={openDoc} />
                            </>
                          )}
                        </td>
                        <td>{when(row.submittedAt)}</td>
                        <td>
                          <Badge value={row.status} />
                          {row.reviewNote && (
                            <small style={row.status === 'Rejected' ? redText : subtext}>{row.reviewNote}</small>
                          )}
                        </td>
                        <td>
                          <div className="hotelApprovalActions" style={{ border: 0, margin: 0, padding: 0 }}>
                            {row.status !== 'Verified' && (
                              <button className="primaryButton" disabled={working} onClick={() => approveListing(row)}>
                                <CheckCircle2 /> Approve
                              </button>
                            )}
                            {row.status !== 'Rejected' && (
                              <button
                                className="dangerButton"
                                disabled={working}
                                onClick={() => { setTarget({ kind: 'reject', row }); setReason(''); }}
                              >
                                <XCircle /> Reject
                              </button>
                            )}
                            {row.status !== 'Draft' && (
                              <button
                                className="secondaryButton"
                                disabled={working}
                                onClick={() => { setTarget({ kind: 'info', row }); setReason(''); }}
                              >
                                <MessageSquareText /> Ask for info
                              </button>
                            )}
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )
        ) : filteredDrivers.length === 0 ? (
          <Empty title="No drivers" copy="Owners who drive and invited drivers will appear here." />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Driver</th>
                  <th>Drives for</th>
                  <th>Licence</th>
                  <th>Documents</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredDrivers.map((row) => {
                  const working = workingId === row.id;
                  const days = daysUntil(row.licenceExpiry);
                  const licenceWarning = !row.licenceValid || (days !== null && days <= 30);
                  const expiryText = days === null
                    ? 'No expiry date'
                    : days < 0
                      ? `Expired ${when(row.licenceExpiry)}`
                      : days <= 30
                        ? `Expires in ${days} ${days === 1 ? 'day' : 'days'}`
                        : `Expires ${when(row.licenceExpiry)}`;
                  return (
                    <tr key={row.id}>
                      <td>
                        <strong>{row.name}</strong>
                        <small style={subtext}>{row.phone}</small>
                        {row.isOwner && <small style={subtext}>Owner who drives</small>}
                      </td>
                      <td>
                        {row.isOwner ? 'Own vehicles' : row.ownerName || '—'}
                        {!row.isOwner && row.ownerPhone && <small style={subtext}>{row.ownerPhone}</small>}
                      </td>
                      <td>
                        {row.licenceNumber || '—'}
                        <small style={licenceWarning ? redText : subtext}>
                          {!row.licenceValid && days !== null && days >= 0 ? `Not valid · ${expiryText}` : expiryText}
                        </small>
                      </td>
                      <td style={{ maxWidth: 260 }}>
                        <DocChip label="CNIC front" url={row.docs?.cnicFront ?? null} onOpen={openDoc} />
                        <DocChip label="CNIC back" url={row.docs?.cnicBack ?? null} onOpen={openDoc} />
                        <DocChip label="Selfie" url={row.docs?.selfie ?? null} onOpen={openDoc} />
                        <DocChip label="Licence front" url={row.docs?.licenceFront ?? null} onOpen={openDoc} />
                        <DocChip label="Licence back" url={row.docs?.licenceBack ?? null} onOpen={openDoc} />
                      </td>
                      <td>
                        <Badge value={row.status} />
                        {row.submittedAt && <small style={subtext}>{when(row.submittedAt)}</small>}
                        {row.reviewNote && (
                          <small style={row.status === 'Rejected' ? redText : subtext}>{row.reviewNote}</small>
                        )}
                      </td>
                      <td>
                        <div className="hotelApprovalActions" style={{ border: 0, margin: 0, padding: 0 }}>
                          {row.status !== 'Approved' && (
                            <button className="primaryButton" disabled={working} onClick={() => approveDriver(row)}>
                              <CheckCircle2 /> Approve
                            </button>
                          )}
                          {row.status !== 'Rejected' && (
                            <button
                              className="dangerButton"
                              disabled={working}
                              onClick={() => { setTarget({ kind: 'driver', row }); setReason(''); }}
                            >
                              <XCircle /> Reject
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {target && (
        <Modal title={targetTitle} onClose={() => setTarget(null)}>
          <div className="detailStack">
            <p>
              {target.kind === 'info'
                ? 'Tell the owner what to add or fix. The listing goes back to draft and the owner sees this note.'
                : 'Tell them what to correct before sending it again.'}
            </p>
          </div>
          <Field label={target.kind === 'info' ? 'Note to the owner' : 'Rejection reason'}>
            <textarea
              rows={5}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              placeholder={
                target.kind === 'info'
                  ? 'For example: please upload a clear photo of the back of the registration book.'
                  : 'For example: the CNIC name does not match the registration book.'
              }
            />
          </Field>
          <div className="buttonRow">
            <button className="secondaryButton" onClick={() => setTarget(null)}>Cancel</button>
            <button
              className={target.kind === 'info' ? 'primaryButton' : 'dangerButton'}
              disabled={!reason.trim() || workingId !== ''}
              onClick={confirmTarget}
            >
              {target.kind === 'info' ? <><MessageSquareText /> Send note</> : <><XCircle /> Confirm rejection</>}
            </button>
          </div>
        </Modal>
      )}

      {adding && (
        <Modal title="Add vehicle for an owner" onClose={() => !saving && setAdding(false)}>
            <div className="detailStack">
              <p>For owners who came to the office. Staff checked the vehicle in person, so it goes live straight away.</p>
            </div>
            {formError && <ErrorBox message={formError} />}
            <div className="formGrid">
              <Field label="Owner phone *">
                <input value={form.ownerPhone} onChange={(event) => setField('ownerPhone', event.target.value)} placeholder="03xx xxxxxxx" />
              </Field>
              <Field label="Owner name *">
                <input value={form.ownerName} onChange={(event) => setField('ownerName', event.target.value)} />
              </Field>
              <Field label="Category">
                <select value={form.category} onChange={(event) => setField('category', event.target.value)}>
                  <option>Car</option>
                  <option>Jeep</option>
                  <option>Hiace</option>
                  <option>Coster</option>
                </select>
              </Field>
              <Field label="Make">
                <input value={form.make} onChange={(event) => setField('make', event.target.value)} placeholder="Toyota" />
              </Field>
              <Field label="Model">
                <input value={form.model} onChange={(event) => setField('model', event.target.value)} placeholder="Corolla" />
              </Field>
              <Field label="Year">
                <input type="number" value={form.year} onChange={(event) => setField('year', event.target.value)} />
              </Field>
              <Field label="Registration number">
                <input value={form.registrationNumber} onChange={(event) => setField('registrationNumber', event.target.value)} />
              </Field>
              <Field label="Seats">
                <input type="number" min={1} value={form.seats} onChange={(event) => setField('seats', event.target.value)} />
              </Field>
              <Field label="Daily rate with driver (PKR)">
                <input type="number" min={0} value={form.withDriverDaily} onChange={(event) => setField('withDriverDaily', event.target.value)} />
              </Field>
              <Field label="Daily rate self-drive (PKR)">
                <input type="number" min={0} value={form.selfDriveDaily} onChange={(event) => setField('selfDriveDaily', event.target.value)} />
              </Field>
              <Field label="Pickup point">
                <input value={form.pickupPoint} onChange={(event) => setField('pickupPoint', event.target.value)} />
              </Field>
              <div>
                <label className="check">
                  <input type="checkbox" checked={form.wantsRent} onChange={(event) => setField('wantsRent', event.target.checked)} /> For rent
                </label>
                <label className="check">
                  <input type="checkbox" checked={form.wantsTour} onChange={(event) => setField('wantsTour', event.target.checked)} /> For tours
                </label>
              </div>
              {fileInput('front', 'Car photo *')}
              {fileInput('registrationFront', 'Registration book front *')}
              {fileInput('registrationBack', 'Registration book back *')}
              {fileInput('cnicFront', 'CNIC front')}
              {fileInput('cnicBack', 'CNIC back')}
            </div>
            <div className="buttonRow">
              <button type="button" className="secondaryButton" onClick={() => setAdding(false)} disabled={saving}>Cancel</button>
              <button type="button" className="primaryButton" disabled={saving} onClick={() => void submitAdd()}>
                {saving ? <RefreshCw className="spin" /> : <Plus />} Add vehicle
              </button>
            </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
