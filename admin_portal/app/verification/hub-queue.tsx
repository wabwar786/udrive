'use client';

import {
  CheckCircle2,
  FileText,
  MapPin,
  MessageSquareText,
  Plus,
  RefreshCw,
  Search,
  XCircle,
} from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';

import { Badge, Empty, ErrorBox, Field, Loading, Modal } from '../components/ui';
import {
  API_BASE,
  apiAction,
  apiFetch,
  apiProtectedFile,
  readSession,
  when,
} from '../lib/admin-api';
import {
  LocationModal,
  TehsilSelect,
  type CatalogDistrict,
} from './area-select';

export type HubTab = 'tour' | 'rent' | 'hotels' | 'businesses';

type RowStatus = 'Waiting' | 'Approved' | 'Rejected' | 'Info';

type VerificationRow = {
  kind: HubTab;
  id: string;
  title: string;
  subtitle?: string | null;
  personName?: string | null;
  personPhone?: string | null;
  tehsilId: string | null;
  tehsilName: string | null;
  districtName: string | null;
  submittedAt?: string | null;
  status: RowStatus;
  note: string | null;
  checksDone: number;
  checksTotal: number;
  photoUrl: string | null;
  driversWaiting: number;
};

type DriverDocs = {
  cnicFront: string | null;
  cnicBack: string | null;
  selfie: string | null;
  licenceFront: string | null;
  licenceBack: string | null;
};

type FleetDriver = {
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
  docs?: DriverDocs | null;
};

type VerificationDetail = {
  row: VerificationRow;
  documents: { label: string; url: string | null }[];
  checks: { label: string; ok: boolean }[];
  facts: { label: string; value: string | number | null }[];
  drivers: FleetDriver[];
  canApprove: boolean;
  blockReason: string | null;
  canAskInfo: boolean;
};

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
  tehsilId: string;
};

type OwnerFiles = {
  front: File | null;
  registrationFront: File | null;
  registrationBack: File | null;
  cnicFront: File | null;
  cnicBack: File | null;
};

const EMPTY_FILES: OwnerFiles = {
  front: null,
  registrationFront: null,
  registrationBack: null,
  cnicFront: null,
  cnicBack: null,
};

function emptyForm(tab: HubTab): OwnerForm {
  return {
    ownerPhone: '',
    ownerName: '',
    category: 'Car',
    make: '',
    model: '',
    year: '',
    registrationNumber: '',
    seats: '',
    wantsRent: tab !== 'tour',
    wantsTour: tab === 'tour',
    withDriverDaily: '',
    selfDriveDaily: '',
    pickupPoint: '',
    tehsilId: '',
  };
}

const TAB_COPY: Record<
  HubTab,
  {
    title: string;
    hint: string;
    col1: string;
    col2: string;
    approveLabel: string;
    after: string;
    whereFrom: string;
    search: string;
  }
> = {
  tour: {
    title: 'Tour vehicles',
    hint: 'Owner, vehicle and the people who will drive it. Needs mountain score and an approved driver.',
    col1: 'Vehicle',
    col2: 'Owner',
    approveLabel: 'Approve for tours',
    after: 'Tours switch on. The owner can post daily departures right away. Rent is not changed.',
    whereFrom: 'Chosen by the owner in step 1; GPS pin matched it.',
    search: 'Name, phone or plate',
  },
  rent: {
    title: 'Rent-a-car vehicles',
    hint: 'Owner and vehicle. Needs a daily rate and the car photo.',
    col1: 'Vehicle',
    col2: 'Owner',
    approveLabel: 'Approve for rent',
    after: 'Shows in the customer rent list. Bookings go to the owner on WhatsApp. Tours are not changed.',
    whereFrom: 'Chosen by the owner in step 1; GPS pin matched it.',
    search: 'Name, phone or plate',
  },
  hotels: {
    title: 'Hotels',
    hint: 'Hotel and its owner. Approve puts it in customer search and turns on bookings.',
    col1: 'Hotel',
    col2: 'Owner',
    approveLabel: 'Approve hotel',
    after: 'Hotel shows to customers. Booking requests go to the hotel on WhatsApp.',
    whereFrom: 'From the hotel address and map pin.',
    search: 'Hotel, owner or phone',
  },
  businesses: {
    title: 'Businesses (Near me)',
    hint: 'Shops and places customers add. Approve shows them in Near me.',
    col1: 'Business',
    col2: 'Added by',
    approveLabel: 'Approve business',
    after: 'Shows in Near me for customers nearby.',
    whereFrom: 'Worked out from the map pin.',
    search: 'Business, person or phone',
  },
};

const subtext = { display: 'block', color: '#6d7e77', marginTop: 3 } as const;
const redText = { display: 'block', color: '#a62032', marginTop: 3 } as const;
const sectionTitle = { margin: '0 0 8px', fontSize: 12, color: '#465b53' } as const;

function absoluteUrl(value: string) {
  return /^https?:\/\//i.test(value) ? value : new URL(value, API_BASE).toString();
}

function isProtected(url: string) {
  return url.includes('/api/v1/admin/');
}

function errorText(value: unknown, fallback: string) {
  return value instanceof Error ? value.message : fallback;
}

function dateOnly(value?: string | null) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium' }).format(date);
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

function DocTile({ label, url, onOpen }: { label: string; url: string | null; onOpen: (url: string) => void }) {
  const ok = Boolean(url);
  return (
    <button
      type="button"
      disabled={!ok}
      title={ok ? `Open ${label}` : `${label} missing`}
      onClick={() => url && onOpen(url)}
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 6,
        padding: '12px 6px',
        minHeight: 64,
        borderRadius: 12,
        border: `1px solid ${ok ? '#cfe7dc' : '#f0d9b5'}`,
        background: ok ? '#f4faf7' : '#fff8ec',
        color: ok ? '#22594a' : '#8a5a00',
        fontSize: 11,
        fontWeight: 700,
        cursor: ok ? 'pointer' : 'default',
        textAlign: 'center',
      }}
    >
      <FileText size={18} />
      <span>{ok ? label : `${label} · missing`}</span>
    </button>
  );
}

export function HubQueue({
  tab,
  area,
  districts,
  onChanged,
}: {
  tab: HubTab;
  area: string;
  districts: CatalogDistrict[];
  onChanged: () => void;
}) {
  const copy = TAB_COPY[tab];
  const vehicleTab = tab === 'tour' || tab === 'rent';

  const [rows, setRows] = useState<VerificationRow[]>([]);
  const [status, setStatus] = useState('Waiting');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const [selectedId, setSelectedId] = useState('');
  const [detail, setDetail] = useState<VerificationDetail | null>(null);
  const [detailBusy, setDetailBusy] = useState(false);
  const [detailError, setDetailError] = useState('');
  const [note, setNote] = useState('');
  const [acting, setActing] = useState(false);
  const [moving, setMoving] = useState(false);

  const [driverTarget, setDriverTarget] = useState<FleetDriver | null>(null);
  const [reason, setReason] = useState('');

  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState<OwnerForm>(() => emptyForm(tab));
  const [files, setFiles] = useState<OwnerFiles>(EMPTY_FILES);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState('');

  // The search box filters on the server; wait for typing to pause.
  useEffect(() => {
    const timer = window.setTimeout(() => setQuery(search.trim()), 350);
    return () => window.clearTimeout(timer);
  }, [search]);

  const loadList = useCallback(async () => {
    setBusy(true);
    setError('');
    const params = new URLSearchParams();
    if (status) params.set('status', status);
    if (area) params.set('area', area);
    if (query) params.set('q', query);
    const text = params.toString();
    try {
      setRows(
        await apiFetch<VerificationRow[]>(
          `/api/v1/admin/verify/${tab}${text ? `?${text}` : ''}`,
        ),
      );
    } catch (value) {
      setError(errorText(value, 'The list could not be loaded.'));
    } finally {
      setBusy(false);
    }
  }, [tab, status, area, query]);

  const loadDetail = useCallback(async () => {
    if (!selectedId) {
      setDetail(null);
      return;
    }
    setDetailBusy(true);
    setDetailError('');
    try {
      setDetail(
        await apiFetch<VerificationDetail>(`/api/v1/admin/verify/${tab}/${selectedId}`),
      );
    } catch (value) {
      setDetail(null);
      setDetailError(errorText(value, 'The review could not be loaded.'));
    } finally {
      setDetailBusy(false);
    }
  }, [tab, selectedId]);

  useEffect(() => {
    void loadList();
  }, [loadList]);

  useEffect(() => {
    setNote('');
    void loadDetail();
  }, [loadDetail]);

  const reloadAll = useCallback(async () => {
    onChanged();
    await Promise.all([loadList(), loadDetail()]);
  }, [onChanged, loadList, loadDetail]);

  async function openDoc(url: string) {
    setDetailError('');
    if (!isProtected(url)) {
      window.open(absoluteUrl(url), '_blank', 'noopener,noreferrer');
      return;
    }
    // Open the tab first so the browser does not treat it as a pop-up.
    const win = window.open('', '_blank');
    try {
      const file = await apiProtectedFile(url);
      if (win) win.location.href = file.objectUrl;
      else window.open(file.objectUrl, '_blank', 'noopener,noreferrer');
    } catch (value) {
      win?.close();
      setDetailError(errorText(value, 'The document could not be opened.'));
    }
  }

  async function act(
    action: () => Promise<{ message: string }>,
    done: string,
    failed: string,
  ) {
    setActing(true);
    setDetailError('');
    setSuccess('');
    try {
      const result = await action();
      setSuccess(result.message || done);
      setNote('');
      setDriverTarget(null);
      setReason('');
      await reloadAll();
    } catch (value) {
      setDetailError(errorText(value, failed));
    } finally {
      setActing(false);
    }
  }

  function approve() {
    if (!detail) return;
    const row = detail.row;
    void act(
      () => apiAction(`/api/v1/admin/verify/${tab}/${row.id}/approve`, { method: 'POST' }),
      `${row.title} approved.`,
      'This could not be approved.',
    );
  }

  function reject() {
    if (!detail) return;
    if (!note.trim()) {
      setDetailError('Write a note to the applicant before rejecting.');
      return;
    }
    const row = detail.row;
    const text = note.trim();
    void act(
      () => apiAction(`/api/v1/admin/verify/${tab}/${row.id}/reject`, { method: 'POST', body: JSON.stringify({ note: text }) }),
      `${row.title} rejected.`,
      'This could not be rejected.',
    );
  }

  function askInfo() {
    if (!detail) return;
    if (!note.trim()) {
      setDetailError('Write what the applicant should add or fix.');
      return;
    }
    const row = detail.row;
    const text = note.trim();
    void act(
      () => apiAction(`/api/v1/admin/verify/${tab}/${row.id}/request-info`, { method: 'POST', body: JSON.stringify({ note: text }) }),
      `Note sent for ${row.title}.`,
      'The note could not be sent.',
    );
  }

  function approveDriver(driver: FleetDriver) {
    void act(
      () => apiAction(`/api/v1/admin/fleet-drivers/${driver.id}/approve`, { method: 'POST' }),
      `${driver.name} approved.`,
      'The driver could not be approved.',
    );
  }

  function confirmDriverReject() {
    if (!driverTarget || !reason.trim()) return;
    const driver = driverTarget;
    const text = reason.trim();
    void act(
      () => apiAction(`/api/v1/admin/fleet-drivers/${driver.id}/reject`, { method: 'POST', body: JSON.stringify({ reason: text }) }),
      `${driver.name} rejected.`,
      'The driver could not be rejected.',
    );
  }

  function openAdd() {
    setForm(emptyForm(tab));
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
    if (!form.tehsilId) {
      setFormError('Choose the district and tehsil the vehicle is based in.');
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
    body.append('tehsilId', form.tehsilId);
    (Object.keys(files) as (keyof OwnerFiles)[]).forEach((key) => {
      const file = files[key];
      if (file) body.append(key, file);
    });

    setSaving(true);
    try {
      const created = await postMultipart<{ name?: string } | null>('/api/v1/admin/listings/for-owner', body);
      setAdding(false);
      setSuccess(`${created?.name ?? 'Vehicle'} added for ${form.ownerName.trim()} and is live.`);
      onChanged();
      await loadList();
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

  const row = detail?.row ?? null;

  return (
    <>
      {error && <ErrorBox message={error} />}
      {success && <div className="successBox" style={{ margin: '0 0 14px' }}>{success}</div>}

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16, alignItems: 'flex-start' }}>
        <section className="panel hotelApprovalPanel" style={{ flex: '999 1 640px', minWidth: 0, marginBottom: 0 }}>
          <header className="panelHeader" style={{ flexWrap: 'wrap' }}>
            <div>
              <h2>{copy.title}</h2>
              <p>{copy.hint}</p>
            </div>
            <div className="tableTools" style={{ width: 'auto' }}>
              <label className="searchBox">
                <Search />
                <input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder={copy.search}
                  aria-label="Search"
                />
              </label>
              <select value={status} onChange={(event) => setStatus(event.target.value)} aria-label="Status">
                <option value="Waiting">Waiting</option>
                <option value="Approved">Approved</option>
                <option value="Rejected">Rejected</option>
                {vehicleTab && <option value="Info">Info asked</option>}
                <option value="All">All</option>
              </select>
              {vehicleTab && (
                <button type="button" className="primaryButton" onClick={openAdd}>
                  <Plus size={16} /> Add vehicle for an owner
                </button>
              )}
            </div>
          </header>

          {busy ? (
            <Loading />
          ) : rows.length === 0 ? (
            <Empty title="Nothing here" copy="Nothing matches this tab, status and area." />
          ) : (
            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>{copy.col1}</th>
                    <th>{copy.col2}</th>
                    <th>District · Tehsil</th>
                    <th>Waiting since</th>
                    <th>Checks</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((item) => {
                    const selected = item.id === selectedId;
                    const allOk = item.checksTotal > 0 && item.checksDone >= item.checksTotal;
                    return (
                      <tr
                        key={item.id}
                        tabIndex={0}
                        onClick={() => setSelectedId(item.id)}
                        onKeyDown={(event) => {
                          if (event.key === 'Enter' || event.key === ' ') {
                            event.preventDefault();
                            setSelectedId(item.id);
                          }
                        }}
                        style={{ cursor: 'pointer', background: selected ? '#eef8f3' : undefined }}
                      >
                        <td>
                          <strong>{item.title}</strong>
                          {item.subtitle && <small style={subtext}>{item.subtitle}</small>}
                        </td>
                        <td>
                          {item.personName || '—'}
                          {item.personPhone && <small style={subtext}>{item.personPhone}</small>}
                        </td>
                        <td>
                          {item.districtName ?? 'Unassigned'}
                          {item.tehsilName && <small style={subtext}>{item.tehsilName}</small>}
                        </td>
                        <td>{when(item.submittedAt)}</td>
                        <td>
                          <span style={{ fontWeight: 800, fontSize: 12, color: allOk ? '#087650' : '#a35a00' }}>
                            {item.checksDone} / {item.checksTotal}
                          </span>
                        </td>
                        <td>
                          <Badge value={item.status} />
                          {item.driversWaiting > 0 && (
                            <span
                              style={{
                                display: 'inline-flex',
                                marginTop: 4,
                                padding: '3px 8px',
                                borderRadius: 999,
                                background: '#fff2cf',
                                color: '#7a5300',
                                fontSize: 11,
                                fontWeight: 800,
                                whiteSpace: 'nowrap',
                              }}
                            >
                              {item.driversWaiting} {item.driversWaiting === 1 ? 'driver' : 'drivers'} waiting
                            </span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <section className="panel" style={{ flex: '1 1 380px', minWidth: 0, marginBottom: 0 }}>
          {!selectedId ? (
            <Empty title="Pick a row to review" copy="Documents, checks and actions for the selected item appear here." />
          ) : detailBusy && !detail ? (
            <Loading />
          ) : !detail || !row ? (
            <div style={{ padding: 16 }}>
              <ErrorBox message={detailError || 'The review could not be loaded.'} />
            </div>
          ) : (
            <>
              <header className="panelHeader" style={{ alignItems: 'flex-start' }}>
                <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', minWidth: 0 }}>
                  {row.photoUrl && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={absoluteUrl(row.photoUrl)}
                      alt={row.title}
                      style={{ width: 64, height: 48, objectFit: 'cover', borderRadius: 10, flexShrink: 0 }}
                    />
                  )}
                  <div style={{ minWidth: 0 }}>
                    <span style={{ fontSize: 10, letterSpacing: '0.14em', color: '#087650', fontWeight: 800 }}>REVIEW</span>
                    <h2 style={{ marginTop: 4 }}>{row.title}</h2>
                    <p>
                      {[row.personName, row.personPhone].filter(Boolean).join(' · ') || '—'}
                    </p>
                  </div>
                </div>
                <Badge value={row.status} />
              </header>

              <div style={{ padding: 16, display: 'flex', flexDirection: 'column', gap: 14 }}>
                {detailError && <ErrorBox message={detailError} />}
                {row.note && (
                  <small style={row.status === 'Rejected' ? redText : subtext}>Last note: {row.note}</small>
                )}

                <div
                  style={{
                    display: 'flex',
                    gap: 10,
                    alignItems: 'center',
                    background: '#f4f8f6',
                    borderRadius: 12,
                    padding: '10px 12px',
                  }}
                >
                  <MapPin size={18} color="#087650" style={{ flexShrink: 0 }} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <strong style={{ display: 'block' }}>
                      {row.districtName
                        ? `Based in ${row.districtName} district${row.tehsilName ? `, ${row.tehsilName} tehsil` : ''}`
                        : 'No area set yet'}
                    </strong>
                    <small style={{ color: '#66796f' }}>{copy.whereFrom}</small>
                  </div>
                  <button type="button" className="secondaryButton" onClick={() => setMoving(true)}>
                    Change
                  </button>
                </div>

                <div>
                  <h3 style={sectionTitle}>Documents (tap to open)</h3>
                  {detail.documents.length === 0 ? (
                    <small style={subtext}>No documents for this item.</small>
                  ) : (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))', gap: 8 }}>
                      {detail.documents.map((doc, index) => (
                        <DocTile key={`${doc.label}-${index}`} label={doc.label} url={doc.url} onOpen={(url) => void openDoc(url)} />
                      ))}
                    </div>
                  )}
                </div>

                {detail.checks.length > 0 && (
                  <div>
                    <h3 style={sectionTitle}>What approving this tab needs</h3>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      {detail.checks.map((check, index) => (
                        <div key={`${check.label}-${index}`} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                          <span
                            style={{
                              width: 9,
                              height: 9,
                              borderRadius: '50%',
                              flex: '0 0 9px',
                              background: check.ok ? '#16a878' : '#e0a100',
                            }}
                          />
                          <span style={{ color: check.ok ? '#24443a' : '#7a5300' }}>{check.label}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {detail.facts.length > 0 && (
                  <div>
                    <h3 style={sectionTitle}>Details</h3>
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: 8 }}>
                      {detail.facts.map((fact, index) => (
                        <div key={`${fact.label}-${index}`} style={{ background: '#f6f9f8', borderRadius: 10, padding: '8px 10px', minWidth: 0 }}>
                          <small style={{ display: 'block', color: '#66796f' }}>{fact.label}</small>
                          <strong style={{ overflowWrap: 'anywhere' }}>
                            {fact.value === null || fact.value === '' ? '—' : String(fact.value)}
                          </strong>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {vehicleTab && (
                  <div>
                    <h3 style={sectionTitle}>Owner&apos;s drivers</h3>
                    {detail.drivers.length === 0 ? (
                      <small style={subtext}>No drivers added yet.</small>
                    ) : (
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                        {detail.drivers.map((driver) => (
                          <div
                            key={driver.id}
                            style={{ background: '#f4f8f6', borderRadius: 11, padding: '9px 11px' }}
                          >
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                              <div style={{ minWidth: 0 }}>
                                <strong style={{ display: 'block' }}>
                                  {driver.name}{driver.isOwner ? ' (owner)' : ''}
                                </strong>
                                <small style={driver.licenceValid ? { color: '#66796f' } : { color: '#a62032' }}>
                                  {driver.licenceExpiry
                                    ? `Licence to ${dateOnly(driver.licenceExpiry)}`
                                    : 'No licence expiry'}
                                  {!driver.licenceValid ? ' · not valid' : ''}
                                  {driver.phone ? ` · ${driver.phone}` : ''}
                                </small>
                              </div>
                              <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
                                <Badge value={driver.status} />
                                {driver.status !== 'Approved' && (
                                  <button
                                    type="button"
                                    className="primaryButton"
                                    disabled={acting}
                                    onClick={() => approveDriver(driver)}
                                  >
                                    Approve
                                  </button>
                                )}
                                {driver.status !== 'Rejected' && (
                                  <button
                                    type="button"
                                    className="dangerButton"
                                    disabled={acting}
                                    onClick={() => {
                                      setDriverTarget(driver);
                                      setReason('');
                                    }}
                                  >
                                    Reject
                                  </button>
                                )}
                              </div>
                            </div>
                            {driver.docs && (
                              <div style={{ marginTop: 6 }}>
                                <DocChip label="CNIC front" url={driver.docs.cnicFront} onOpen={(url) => void openDoc(url)} />
                                <DocChip label="CNIC back" url={driver.docs.cnicBack} onOpen={(url) => void openDoc(url)} />
                                <DocChip label="Selfie" url={driver.docs.selfie} onOpen={(url) => void openDoc(url)} />
                                <DocChip label="Licence front" url={driver.docs.licenceFront} onOpen={(url) => void openDoc(url)} />
                                <DocChip label="Licence back" url={driver.docs.licenceBack} onOpen={(url) => void openDoc(url)} />
                              </div>
                            )}
                            {driver.reviewNote && (
                              <small style={driver.status === 'Rejected' ? redText : subtext}>{driver.reviewNote}</small>
                            )}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}

                <label style={{ display: 'grid', gap: 6 }}>
                  <span style={{ fontSize: 12, fontWeight: 750, color: '#465b53' }}>
                    Note to the applicant (needed for Reject{detail.canAskInfo ? ' or Ask for info' : ''})
                  </span>
                  <textarea
                    rows={2}
                    value={note}
                    onChange={(event) => setNote(event.target.value)}
                    placeholder="e.g. Registration book back photo is blurred"
                    style={{ border: '1px solid #d9e5e0', background: '#fbfdfc', borderRadius: 12, padding: 10, resize: 'vertical' }}
                  />
                </label>

                {!detail.canApprove && detail.blockReason && (
                  <small style={{ ...redText, marginTop: 0 }}>Approve is not available yet: {detail.blockReason}</small>
                )}

                <div className="hotelApprovalActions" style={{ borderTop: 0, marginTop: 0, paddingTop: 0 }}>
                  <button
                    type="button"
                    className="primaryButton"
                    disabled={acting || !detail.canApprove}
                    onClick={approve}
                  >
                    {acting ? <RefreshCw size={16} className="spin" /> : <CheckCircle2 size={16} />} {copy.approveLabel}
                  </button>
                  {detail.canAskInfo && (
                    <button
                      type="button"
                      className="secondaryButton"
                      disabled={acting || !note.trim()}
                      onClick={askInfo}
                    >
                      <MessageSquareText size={16} /> Ask for info
                    </button>
                  )}
                  <button
                    type="button"
                    className="dangerButton"
                    disabled={acting || !note.trim()}
                    onClick={reject}
                  >
                    <XCircle size={16} /> Reject
                  </button>
                </div>
                <p style={{ margin: 0, color: '#66796f', fontSize: 12 }}>{copy.after}</p>
              </div>
            </>
          )}
        </section>
      </div>

      {moving && row && (
        <LocationModal
          title={`Change area · ${row.title}`}
          path={`/api/v1/admin/verify/${tab}/${row.id}/location`}
          currentTehsilId={row.tehsilId}
          onClose={() => setMoving(false)}
          onSaved={async () => {
            setSuccess(`Area changed for ${row.title}.`);
            await reloadAll();
          }}
        />
      )}

      {driverTarget && (
        <Modal title={`Reject ${driverTarget.name}`} onClose={() => !acting && setDriverTarget(null)}>
          <div className="detailStack">
            <p>Tell them what to correct before sending it again.</p>
          </div>
          <Field label="Rejection reason">
            <textarea
              rows={5}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              placeholder="For example: the licence photo is not readable."
            />
          </Field>
          <div className="buttonRow">
            <button type="button" className="secondaryButton" onClick={() => setDriverTarget(null)} disabled={acting}>Cancel</button>
            <button
              type="button"
              className="dangerButton"
              disabled={!reason.trim() || acting}
              onClick={confirmDriverReject}
            >
              <XCircle size={16} /> Confirm rejection
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
            <Field label="District / Tehsil *">
              <TehsilSelect
                districts={districts}
                value={form.tehsilId}
                onChange={(value) => setField('tehsilId', value)}
              />
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
              {saving ? <RefreshCw size={16} className="spin" /> : <Plus size={16} />} Add vehicle
            </button>
          </div>
        </Modal>
      )}
    </>
  );
}
