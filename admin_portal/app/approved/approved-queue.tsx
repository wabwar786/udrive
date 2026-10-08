'use client';

import { FileText, PauseCircle, PlayCircle, RefreshCw, RotateCcw, Search, XCircle } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';

import { Empty, ErrorBox, Loading } from '../components/ui';
import { API_BASE, apiAction, apiFetch, apiProtectedFile, when } from '../lib/admin-api';
import { usePermissions } from '../lib/permissions';
import type { HubTab } from '../verification/hub-queue';

type Row = {
  kind: HubTab;
  id: string;
  title: string;
  subtitle?: string | null;
  personName?: string | null;
  personPhone?: string | null;
  tehsilName: string | null;
  districtName: string | null;
  submittedAt?: string | null;
  photoUrl: string | null;
};

type ApprovedRow = {
  row: Row;
  state: 'Live' | 'Suspended';
  holdReason: string | null;
  heldAt: string | null;
  claimWaiting: boolean;
};

type HoldDoc = { key: string; label: string; uploaded: boolean };

type Claim = {
  id: string;
  type: 'WrongReason' | 'Fixed';
  message: string;
  photos: string[];
  status: 'Pending' | 'Accepted' | 'Rejected';
  adminNote: string | null;
  createdAt: string;
  decidedAt: string | null;
};

type Hold = {
  id: string;
  type: 'Review' | 'Suspend';
  reason: string;
  documents: HoldDoc[];
  createdAt: string;
  createdBy: string | null;
  claim: Claim | null;
};

type Detail = {
  detail: {
    row: Row;
    documents: { label: string; url: string | null }[];
    facts: { label: string; value: string | number | null }[];
  };
  state: 'Live' | 'Suspended' | 'Review';
  hold: Hold | null;
  requestable: HoldDoc[];
};

const COPY: Record<HubTab, { title: string; col1: string; col2: string; search: string }> = {
  city: { title: 'City rides — approved', col1: 'Gaari', col2: 'Driver', search: 'Naam, phone, number plate' },
  tour: { title: 'Tour vehicles — approved', col1: 'Vehicle', col2: 'Owner', search: 'Name, phone or plate' },
  rent: { title: 'Rent-a-car — approved', col1: 'Vehicle', col2: 'Owner', search: 'Name, phone or plate' },
  hotels: { title: 'Hotels — approved', col1: 'Hotel', col2: 'Owner', search: 'Hotel, owner or phone' },
  businesses: { title: 'Businesses — approved', col1: 'Business', col2: 'Added by', search: 'Business, person or phone' },
};

const subtext = { display: 'block', color: '#6d7e77', marginTop: 3 } as const;
const sectionTitle = { margin: '0 0 8px', fontSize: 12, color: '#465b53' } as const;

function absoluteUrl(value: string) {
  return /^https?:\/\//i.test(value) ? value : new URL(value, API_BASE).toString();
}

function errorText(value: unknown, fallback: string) {
  return value instanceof Error ? value.message : fallback;
}

function StateBadge({ state }: { state: string }) {
  const live = state === 'Live';
  return (
    <span
      style={{
        display: 'inline-flex',
        padding: '4px 9px',
        borderRadius: 8,
        fontSize: 11,
        fontWeight: 800,
        background: live ? '#e6f5ee' : state === 'Review' ? '#fff2cf' : '#ffe1e5',
        color: live ? '#0a7a58' : state === 'Review' ? '#7a5300' : '#a62032',
      }}
    >
      {state.toUpperCase()}
    </span>
  );
}

export function ApprovedQueue({ tab, area, onChanged }: { tab: HubTab; area: string; onChanged: () => void }) {
  const copy = COPY[tab];
  const { can } = usePermissions();
  const canAct = can(`verification.${tab}`, 'approve');

  const [rows, setRows] = useState<ApprovedRow[]>([]);
  const [state, setState] = useState('All');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const [selectedId, setSelectedId] = useState('');
  const [detail, setDetail] = useState<Detail | null>(null);
  const [detailBusy, setDetailBusy] = useState(false);
  const [detailError, setDetailError] = useState('');
  const [note, setNote] = useState('');
  const [docs, setDocs] = useState<string[]>([]);
  const [acting, setActing] = useState(false);

  useEffect(() => {
    const timer = window.setTimeout(() => setQuery(search.trim()), 350);
    return () => window.clearTimeout(timer);
  }, [search]);

  const loadList = useCallback(async () => {
    setBusy(true);
    setError('');
    const params = new URLSearchParams();
    if (state !== 'All') params.set('state', state);
    if (area) params.set('area', area);
    if (query) params.set('q', query);
    const text = params.toString();
    try {
      setRows(await apiFetch<ApprovedRow[]>(`/api/v1/admin/verify/${tab}/approved${text ? `?${text}` : ''}`));
    } catch (value) {
      setError(errorText(value, 'The list could not be loaded.'));
    } finally {
      setBusy(false);
    }
  }, [tab, state, area, query]);

  const loadDetail = useCallback(async () => {
    if (!selectedId) {
      setDetail(null);
      return;
    }
    setDetailBusy(true);
    setDetailError('');
    try {
      setDetail(await apiFetch<Detail>(`/api/v1/admin/verify/${tab}/${selectedId}/approved`));
    } catch (value) {
      setDetail(null);
      setDetailError(errorText(value, 'This could not be loaded.'));
    } finally {
      setDetailBusy(false);
    }
  }, [tab, selectedId]);

  useEffect(() => {
    void loadList();
  }, [loadList]);

  useEffect(() => {
    setNote('');
    setDocs([]);
    void loadDetail();
  }, [loadDetail]);

  async function openFile(url: string) {
    setDetailError('');
    if (!url.includes('/api/v1/admin/')) {
      window.open(absoluteUrl(url), '_blank', 'noopener,noreferrer');
      return;
    }
    const win = window.open('', '_blank');
    try {
      const file = await apiProtectedFile(url);
      if (win) win.location.href = file.objectUrl;
      else window.open(file.objectUrl, '_blank', 'noopener,noreferrer');
    } catch (value) {
      win?.close();
      setDetailError(errorText(value, 'The file could not be opened.'));
    }
  }

  async function act(action: string, body: object, needsNote: boolean) {
    if (!detail) return;
    if (needsNote && !note.trim()) {
      setDetailError('Wajah saaf likhein — yeh driver / owner ko jayegi.');
      return;
    }
    setActing(true);
    setDetailError('');
    setSuccess('');
    try {
      const result = await apiAction<Detail>(`/api/v1/admin/verify/${tab}/${detail.detail.row.id}/${action}`, {
        method: 'POST',
        body: JSON.stringify(body),
      });
      setSuccess(result.message || 'Ho gaya.');
      setNote('');
      setDocs([]);
      onChanged();
      await loadList();
      if (action === 'review-again') {
        // It has gone back to Verification; nothing more to do here.
        setSelectedId('');
      } else {
        setDetail(result.data);
      }
    } catch (value) {
      setDetailError(errorText(value, 'This could not be done.'));
    } finally {
      setActing(false);
    }
  }

  const row = detail?.detail.row ?? null;
  const hold = detail?.hold ?? null;
  const claim = hold?.claim ?? null;
  const suspended = detail?.state === 'Suspended';

  return (
    <>
      {error && <ErrorBox message={error} />}
      {success && <div className="successBox" style={{ margin: '0 0 14px' }}>{success}</div>}

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16, alignItems: 'flex-start' }}>
        <section className="panel" style={{ flex: '999 1 640px', minWidth: 0, marginBottom: 0 }}>
          <header className="panelHeader" style={{ flexWrap: 'wrap' }}>
            <div>
              <h2>{copy.title}</h2>
              <p>Row par click karein: details, Review again ya Suspend.</p>
            </div>
            <div className="tableTools" style={{ width: 'auto' }}>
              <label className="searchBox">
                <Search />
                <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder={copy.search} aria-label="Search" />
              </label>
              <select value={state} onChange={(event) => setState(event.target.value)} aria-label="State">
                <option value="All">Live + Suspended</option>
                <option value="Live">Live</option>
                <option value="Suspended">Suspended</option>
              </select>
            </div>
          </header>

          {busy ? (
            <Loading />
          ) : rows.length === 0 ? (
            <Empty title="Nothing here" copy="Is tab, status aur area mein kuch nahi." />
          ) : (
            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>{copy.col1}</th>
                    <th>{copy.col2}</th>
                    <th>District · Tehsil</th>
                    <th>Approved</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((item) => {
                    const selected = item.row.id === selectedId;
                    return (
                      <tr
                        key={item.row.id}
                        tabIndex={0}
                        onClick={() => setSelectedId(item.row.id)}
                        onKeyDown={(event) => {
                          if (event.key === 'Enter' || event.key === ' ') {
                            event.preventDefault();
                            setSelectedId(item.row.id);
                          }
                        }}
                        style={{ cursor: 'pointer', background: selected ? '#eef8f3' : undefined }}
                      >
                        <td>
                          <strong>{item.row.title}</strong>
                          {item.row.subtitle && <small style={subtext}>{item.row.subtitle}</small>}
                        </td>
                        <td>
                          {item.row.personName || '—'}
                          {item.row.personPhone && <small style={subtext}>{item.row.personPhone}</small>}
                        </td>
                        <td>
                          {item.row.districtName ?? 'Unassigned'}
                          {item.row.tehsilName && <small style={subtext}>{item.row.tehsilName}</small>}
                        </td>
                        <td>{when(item.row.submittedAt)}</td>
                        <td>
                          <StateBadge state={item.state} />
                          {item.claimWaiting && (
                            <span
                              style={{
                                display: 'inline-flex',
                                marginLeft: 6,
                                padding: '3px 8px',
                                borderRadius: 999,
                                background: '#fff2cf',
                                color: '#7a5300',
                                fontSize: 11,
                                fontWeight: 800,
                              }}
                            >
                              Re-claim
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
            <Empty title="Row chunein" copy="Details aur actions yahan aayenge." />
          ) : detailBusy && !detail ? (
            <Loading />
          ) : !detail || !row ? (
            <div style={{ padding: 16 }}>
              <ErrorBox message={detailError || 'This could not be loaded.'} />
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
                    <h2>{row.title}</h2>
                    <p>{[row.personName, row.personPhone].filter(Boolean).join(' · ') || '—'}</p>
                  </div>
                </div>
                <StateBadge state={detail.state} />
              </header>

              <div style={{ padding: 16, display: 'flex', flexDirection: 'column', gap: 14 }}>
                {detailError && <ErrorBox message={detailError} />}

                {suspended && hold && (
                  <div
                    style={{
                      background: '#fef3f2',
                      border: '1px solid #f6c7c2',
                      borderRadius: 12,
                      padding: '10px 12px',
                      color: '#8c1d18',
                      lineHeight: 1.5,
                    }}
                  >
                    <b>Suspend hai</b> — {when(hold.createdAt)}
                    {hold.createdBy ? `, ${hold.createdBy} ne` : ''}. Wajah: &quot;{hold.reason}&quot;. Koi ride ya booking nahi mil rahi.
                  </div>
                )}

                {suspended && claim && (
                  <div
                    style={{
                      background: claim.status === 'Pending' ? '#fff8eb' : '#f6f9f8',
                      border: `1px solid ${claim.status === 'Pending' ? '#f2d49b' : '#e3ece8'}`,
                      borderRadius: 12,
                      padding: '10px 12px',
                      lineHeight: 1.5,
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 4,
                    }}
                  >
                    <span>
                      <b>Driver ka re-claim</b> · {when(claim.createdAt)} ·{' '}
                      <b>{claim.type === 'WrongReason' ? 'Wajah galat hai' : 'Masla hal kar diya'}</b>
                      {claim.status !== 'Pending' && ` · ${claim.status === 'Rejected' ? 'Reject kiya' : 'Mana gaya'}`}
                    </span>
                    <span>&quot;{claim.message}&quot;</span>
                    {claim.photos.length > 0 && (
                      <span style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                        {claim.photos.map((photo, index) => (
                          <button key={photo} type="button" className="secondaryButton" onClick={() => void openFile(photo)}>
                            <FileText size={14} /> Photo {index + 1}
                          </button>
                        ))}
                      </span>
                    )}
                    {claim.adminNote && <small style={{ color: '#66796f' }}>Admin: {claim.adminNote}</small>}
                  </div>
                )}

                {detail.detail.facts.length > 0 && (
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))', gap: 8 }}>
                    {detail.detail.facts.map((fact, index) => (
                      <div key={`${fact.label}-${index}`} style={{ background: '#f6f9f8', borderRadius: 10, padding: '8px 10px', minWidth: 0 }}>
                        <small style={{ display: 'block', color: '#66796f' }}>{fact.label}</small>
                        <strong style={{ overflowWrap: 'anywhere' }}>
                          {fact.value === null || fact.value === '' ? '—' : String(fact.value)}
                        </strong>
                      </div>
                    ))}
                  </div>
                )}

                {detail.detail.documents.length > 0 && (
                  <div>
                    <h3 style={sectionTitle}>Documents (tap to open)</h3>
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))', gap: 8 }}>
                      {detail.detail.documents.map((doc, index) => (
                        <button
                          key={`${doc.label}-${index}`}
                          type="button"
                          disabled={!doc.url}
                          onClick={() => doc.url && void openFile(doc.url)}
                          style={{
                            display: 'flex',
                            flexDirection: 'column',
                            alignItems: 'center',
                            gap: 6,
                            padding: '10px 6px',
                            borderRadius: 12,
                            border: `1px solid ${doc.url ? '#cfe7dc' : '#f0d9b5'}`,
                            background: doc.url ? '#f4faf7' : '#fff8ec',
                            color: doc.url ? '#22594a' : '#8a5a00',
                            fontSize: 11,
                            fontWeight: 700,
                            cursor: doc.url ? 'pointer' : 'default',
                          }}
                        >
                          <FileText size={16} />
                          <span>{doc.url ? doc.label : `${doc.label} · missing`}</span>
                        </button>
                      ))}
                    </div>
                  </div>
                )}

                {canAct && (
                  <>
                    {!suspended && detail.requestable.length > 0 && (
                      <div>
                        <h3 style={sectionTitle}>Review again par yeh dobara maangein (optional)</h3>
                        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                          {detail.requestable.map((doc) => {
                            const on = docs.includes(doc.key);
                            return (
                              <button
                                key={doc.key}
                                type="button"
                                onClick={() =>
                                  setDocs((current) => (on ? current.filter((k) => k !== doc.key) : [...current, doc.key]))
                                }
                                style={{
                                  padding: '6px 10px',
                                  borderRadius: 999,
                                  fontSize: 11.5,
                                  fontWeight: 800,
                                  cursor: 'pointer',
                                  border: on ? '1px solid #e0a93a' : '1px solid #d3dfda',
                                  background: on ? '#fff2cf' : '#fff',
                                  color: on ? '#7a5300' : '#31564a',
                                }}
                              >
                                {on ? '✓ ' : ''}
                                {doc.label}
                              </button>
                            );
                          })}
                        </div>
                      </div>
                    )}

                    <label style={{ display: 'grid', gap: 6 }}>
                      <span style={{ fontSize: 12, fontWeight: 750, color: '#465b53' }}>
                        {suspended ? 'Note (re-claim reject ke liye zaroori)' : 'Wajah saaf likhein (driver ko jayegi) — zaroori'}
                      </span>
                      <textarea
                        rows={2}
                        value={note}
                        onChange={(event) => setNote(event.target.value)}
                        placeholder={suspended ? 'e.g. Ride ke receipt mein extra charge hai' : 'e.g. Customer ki shikayat: tay kiraye se Rs 500 zyada liye'}
                        style={{ border: '1px solid #d9e5e0', background: '#fbfdfc', borderRadius: 12, padding: 10, resize: 'vertical' }}
                      />
                    </label>

                    {!suspended ? (
                      <>
                        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                          <button
                            type="button"
                            className="secondaryButton"
                            disabled={acting || !note.trim()}
                            onClick={() => void act('review-again', { note: note.trim(), documents: docs }, true)}
                          >
                            {acting ? <RefreshCw size={16} className="spin" /> : <RotateCcw size={16} />} Review again
                          </button>
                          <button
                            type="button"
                            className="dangerButton"
                            disabled={acting || !note.trim()}
                            onClick={() => void act('suspend', { note: note.trim() }, true)}
                          >
                            <PauseCircle size={16} /> Suspend
                          </button>
                        </div>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 12, color: '#66796f', lineHeight: 1.5 }}>
                          <span>
                            <b>Review again:</b> rides / bookings foran band, wapas Verification mein. Documents maange to driver dashboard se
                            upload karega; approve hote hi khud chalu.
                          </span>
                          <span>
                            <b>Suspend:</b> rides / bookings foran band, yahin &quot;Suspended&quot; mein. Sirf admin &quot;Unsuspend&quot; se chalu.
                          </span>
                          <span>Dono mein driver ko app notification + WhatsApp, aur dashboard par saaf message.</span>
                        </div>
                      </>
                    ) : (
                      <>
                        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                          <button
                            type="button"
                            className="primaryButton"
                            disabled={acting}
                            onClick={() => void act('unsuspend', { note: note.trim() || null }, false)}
                          >
                            {acting ? <RefreshCw size={16} className="spin" /> : <PlayCircle size={16} />} Unsuspend — rides chalu
                          </button>
                          {claim?.status === 'Pending' && (
                            <button
                              type="button"
                              className="dangerButton"
                              disabled={acting || !note.trim()}
                              onClick={() => void act('claim-reject', { note: note.trim() }, true)}
                            >
                              <XCircle size={16} /> Re-claim reject
                            </button>
                          )}
                          <button
                            type="button"
                            className="secondaryButton"
                            disabled={acting || !note.trim()}
                            onClick={() => void act('review-again', { note: note.trim(), documents: docs }, true)}
                          >
                            <RotateCcw size={16} /> Review again
                          </button>
                        </div>
                        <span style={{ fontSize: 12, color: '#66796f' }}>
                          Reject par note driver ko jaata hai; woh dobara re-claim kar sakta hai.
                        </span>
                      </>
                    )}
                  </>
                )}
              </div>
            </>
          )}
        </section>
      </div>
    </>
  );
}
