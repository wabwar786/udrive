'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import {
  ArrowLeft,
  Ban,
  Eye,
  RefreshCw,
  Save,
  Send,
  ShieldAlert,
  Trash2,
} from 'lucide-react';

import { AdminFrame } from '../../components/admin-frame';
import { ContractText } from '../../components/contract-text';
import { Badge, Empty, ErrorBox, Field, Loading, Modal, Stat } from '../../components/ui';
import {
  apiFetch,
  apiProtectedFile,
  isSuperAdmin,
  money,
  when,
} from '../../lib/admin-api';

type Contract = {
  id: string;
  reference: string;
  status: string;
  renderedText: string;
  videoScript: string;
  securityDeposit: number;
  commissionSharePct: number;
  termMonths: number;
  sentAt?: string | null;
  signedAt?: string | null;
  endsAt?: string | null;
  terminatedAt?: string | null;
  terminationReason?: string | null;
};

type Commitment = {
  id: string;
  metricKey: string;
  targetValue: number;
  label: string;
  currentValue: number;
  currentStatus: string;
  isManual: boolean;
  caveat?: string | null;
};

type Period = {
  id: string;
  metricKey: string;
  label: string;
  periodStart: string;
  periodEnd: string;
  targetValue: number;
  actualValue: number;
  status: string;
  note?: string | null;
};

type Statement = {
  id: string;
  periodStart: string;
  periodEnd: string;
  completedRides: number;
  grossFares: number;
  commissionBase: number;
  sharePct: number;
  shareAmount: number;
  status: string;
  paidReference?: string | null;
  paidAt?: string | null;
};

type Evidence = {
  exists: boolean;
  signedAtServer?: string | null;
  phoneNumber?: string | null;
  ipAddress?: string | null;
  deviceInfo?: string | null;
  purgeAfter?: string | null;
  purgedAt?: string | null;
  canView: boolean;
};

type Detail = {
  partner: {
    id: string;
    fullName: string;
    phoneNumber?: string | null;
    tierName: string;
    territoryName: string;
    territoryKind: string;
    status: string;
    startedAt?: string | null;
    securityDeposit: number;
    commissionSharePct: number;
  };
  contract: Contract | null;
  commitments: Commitment[];
  periods: Period[];
  statements: Statement[];
  evidence: Evidence | null;
};

const monthOf = (value: string) =>
  new Intl.DateTimeFormat('en-GB', { month: 'long', year: 'numeric' }).format(
    new Date(value),
  );

/**
 * One partner: their contract, what they owe each month, what the territory
 * earned, and the signature behind it all.
 *
 * The screen is ordered the way the questions actually come up — is the contract
 * signed, are they doing the work, what do we owe them, and can we prove they
 * agreed.
 *
 * Three rules it enforces visibly rather than by hiding buttons:
 *
 * - The contract text can only be edited while it is a **Draft**. Once sent, it
 *   is in front of the partner; once signed, it is settled.
 * - A month can only be **agreed** after it has finished, and only **marked paid**
 *   after it has been agreed. Money moves outside the app; this is the record of
 *   it, so the order matters.
 * - The photograph and the video are **SuperAdmin only**, and every single view
 *   writes a line to the audit log naming who looked. The panel says so to the
 *   person about to click.
 */
export default function Page() {
  const params = useParams<{ id: string }>();
  const id = params?.id;

  const [data, setData] = useState<Detail | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');

  const [editing, setEditing] = useState(false);
  const [text, setText] = useState('');
  const [script, setScript] = useState('');
  const [deposit, setDeposit] = useState(0);
  const [share, setShare] = useState(0);
  const [term, setTerm] = useState(24);

  const [terminating, setTerminating] = useState(false);
  const [terminateReason, setTerminateReason] = useState('');

  const [paying, setPaying] = useState<Statement | null>(null);
  const [payReference, setPayReference] = useState('');

  const [recording, setRecording] = useState<Period | null>(null);
  const [recordStatus, setRecordStatus] = useState('Waived');
  const [recordValue, setRecordValue] = useState('');
  const [recordNote, setRecordNote] = useState('');

  const [evidenceOpen, setEvidenceOpen] = useState(false);
  const [selfieUrl, setSelfieUrl] = useState('');
  const [videoUrl, setVideoUrl] = useState('');
  const [evidenceScript, setEvidenceScript] = useState('');

  const load = useCallback(async () => {
    if (!id) return;
    const detail = await apiFetch<Detail>(`/api/v1/admin/partners/${id}`);
    setData(detail);
    if (detail.contract) {
      setText(detail.contract.renderedText);
      setScript(detail.contract.videoScript);
      setDeposit(detail.contract.securityDeposit);
      setShare(detail.contract.commissionSharePct);
      setTerm(detail.contract.termMonths);
    }
  }, [id]);

  useEffect(() => {
    setLoading(true);
    setError('');
    void load()
      .catch((e) =>
        setError(e instanceof Error ? e.message : 'This partner is unavailable.'),
      )
      .finally(() => setLoading(false));
  }, [load]);

  const act = async (run: () => Promise<unknown>, message: string) => {
    setBusy(true);
    setError('');
    setNote('');
    try {
      await run();
      setNote(message);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be saved.');
    } finally {
      setBusy(false);
    }
  };

  const openEvidence = async () => {
    if (!data?.contract) return;
    setBusy(true);
    setError('');
    try {
      const evidence = await apiFetch<{
        selfieUrl: string;
        videoUrl: string;
        scriptShown: string;
      }>(`/api/v1/admin/partners/contracts/${data.contract.id}/evidence`);

      // Both files come through the authorised fetch as blobs: the routes need a
      // bearer token, so an <img src> pointing straight at them would render a
      // broken image and look like missing data rather than a missing header.
      const [selfie, video] = await Promise.all([
        apiProtectedFile(evidence.selfieUrl),
        apiProtectedFile(evidence.videoUrl),
      ]);

      setSelfieUrl(selfie.objectUrl);
      setVideoUrl(video.objectUrl);
      setEvidenceScript(evidence.scriptShown);
      setEvidenceOpen(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The signature record could not be opened.');
    } finally {
      setBusy(false);
    }
  };

  const closeEvidence = () => {
    // Blob URLs stay alive for the life of the document unless revoked, which
    // means a photograph and a video of somebody sitting in browser memory long
    // after the panel is shut.
    if (selfieUrl) URL.revokeObjectURL(selfieUrl);
    if (videoUrl) URL.revokeObjectURL(videoUrl);
    setSelfieUrl('');
    setVideoUrl('');
    setEvidenceOpen(false);
  };

  if (loading) {
    return (
      <AdminFrame title="Partner" subtitle="Loading">
        <Loading />
      </AdminFrame>
    );
  }

  if (!data) {
    return (
      <AdminFrame title="Partner" subtitle="Not available">
        {error && <ErrorBox message={error} />}
        <Link className="secondaryButton" href="/partners">
          <ArrowLeft /> Back to partners
        </Link>
      </AdminFrame>
    );
  }

  const { partner, contract, commitments, periods, statements, evidence } = data;
  const isDraft = contract?.status === 'Draft';

  return (
    <AdminFrame
      title={partner.fullName}
      subtitle={`${partner.tierName} · ${partner.territoryName} (${partner.territoryKind})`}
      actions={
        <Link className="secondaryButton" href="/partners">
          <ArrowLeft /> All partners
        </Link>
      }
    >
      {error && <ErrorBox message={error} />}
      {note && (
        <div className="successBox">
          <strong>{note}</strong>
        </div>
      )}

      <div className="statGrid">
        <Stat label="Partner status" value={partner.status} tone="emerald" />
        <Stat
          label="Contract"
          value={contract?.status ?? 'none'}
          sub={contract?.reference ?? 'not written yet'}
          tone="blue"
        />
        <Stat
          label="Share"
          value={`${contract?.commissionSharePct ?? partner.commissionSharePct}%`}
          sub="of UDrive's commission in this area"
          tone="violet"
        />
        <Stat
          label="Security deposit"
          value={money(contract?.securityDeposit ?? partner.securityDeposit)}
          sub="Refundable, no return paid on it"
          tone="slate"
        />
      </div>

      {/* ───────────────────────────────────────────── the contract */}

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Contract</h2>
            <p>
              {contract
                ? `${contract.reference} · ${contract.status}`
                : 'No contract has been written yet.'}
            </p>
          </div>
          {contract && (
            <div className="tableTools">
              {isDraft && (
                <>
                  <button
                    className="secondaryButton"
                    disabled={busy}
                    onClick={() => setEditing(!editing)}
                  >
                    {editing ? 'Stop editing' : 'Edit'}
                  </button>
                  <button
                    className="primaryButton"
                    disabled={busy}
                    onClick={() =>
                      void act(
                        () =>
                          apiFetch(
                            `/api/v1/admin/partners/contracts/${contract.id}/send`,
                            { method: 'POST' },
                          ),
                        'Sent. The partner has been notified and can now read and sign it.',
                      )
                    }
                  >
                    <Send /> Send to partner
                  </button>
                </>
              )}
              {contract.status !== 'Terminated' && (
                <button
                  className="dangerButton"
                  disabled={busy}
                  onClick={() => setTerminating(true)}
                >
                  <Ban /> Terminate
                </button>
              )}
            </div>
          )}
        </header>

        {!contract ? (
          <Empty
            title="No contract"
            copy="Approving the application normally writes one. Use the button below if it is missing."
          />
        ) : editing ? (
          <>
            <div className="formGrid">
              <Field label="Security deposit (PKR)">
                <input
                  type="number"
                  value={deposit}
                  onChange={(e) => setDeposit(Number(e.target.value))}
                />
              </Field>
              <Field label="Share of UDrive's commission (%)">
                <input
                  type="number"
                  step="0.5"
                  value={share}
                  onChange={(e) => setShare(Number(e.target.value))}
                />
              </Field>
              <Field label="Term (months)">
                <input
                  type="number"
                  value={term}
                  onChange={(e) => setTerm(Number(e.target.value))}
                />
              </Field>
            </div>
            <div style={{ padding: '0 22px 10px' }}>
              <Field label="The agreement, as the partner will read it">
                <textarea
                  rows={18}
                  value={text}
                  onChange={(e) => setText(e.target.value)}
                />
              </Field>
            </div>
            <div style={{ padding: '0 22px 10px' }}>
              <Field label="The words the partner reads on camera">
                <textarea
                  rows={4}
                  value={script}
                  onChange={(e) => setScript(e.target.value)}
                />
              </Field>
              <p style={{ color: '#71827b', margin: '8px 0 0' }}>
                Leave <code>{'{{sign_date}}'}</code> in place — it is filled with the
                date on the day they sign. One fixed wording for every partner is
                what makes the video worth keeping; a hundred different sentences
                cannot be compared with anything.
              </p>
            </div>
            <div className="buttonRow">
              <button
                className="primaryButton"
                disabled={busy}
                onClick={() =>
                  void act(async () => {
                    await apiFetch(
                      `/api/v1/admin/partners/contracts/${contract.id}`,
                      {
                        method: 'PUT',
                        body: JSON.stringify({
                          renderedText: text,
                          videoScript: script,
                          securityDeposit: deposit,
                          commissionSharePct: share,
                          termMonths: term,
                          commitments: null,
                        }),
                      },
                    );
                    setEditing(false);
                  }, 'Saved. Read it once more, then send it.')
                }
              >
                <Save /> Save draft
              </button>
            </div>
          </>
        ) : (
          <>
            <div className="detailGrid">
              <div>
                <span>Sent</span>
                <strong>{when(contract.sentAt)}</strong>
              </div>
              <div>
                <span>Signed</span>
                <strong>{when(contract.signedAt)}</strong>
              </div>
              <div>
                <span>Runs until</span>
                <strong>{when(contract.endsAt)}</strong>
              </div>
              <div>
                <span>Term</span>
                <strong>{contract.termMonths} months</strong>
              </div>
            </div>
            {contract.terminationReason && (
              <div className="errorBox">
                <strong>Terminated {when(contract.terminatedAt)}</strong>
                <span>{contract.terminationReason}</span>
              </div>
            )}
            <div style={{ padding: '0 22px 22px' }}>
              <div className="contractText">
                <ContractText text={contract.renderedText} />
              </div>
            </div>
          </>
        )}

        {!contract && (
          <div className="buttonRow">
            <button
              className="primaryButton"
              disabled={busy}
              onClick={() =>
                void act(
                  () =>
                    apiFetch(`/api/v1/admin/partners/${partner.id}/contract`, {
                      method: 'POST',
                      body: JSON.stringify({}),
                    }),
                  'Draft written from the tier’s current terms.',
                )
              }
            >
              Write a draft contract
            </button>
          </div>
        )}
      </section>

      {/* ──────────────────────────────────── commitments this month */}

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>This month</h2>
            <p>What they committed to, and where it stands right now</p>
          </div>
          {contract && (
            <button
              className="secondaryButton"
              disabled={busy}
              onClick={() =>
                void act(
                  () =>
                    apiFetch(
                      `/api/v1/admin/partners/contracts/${contract.id}/recompute`,
                      { method: 'POST' },
                    ),
                  'Recalculated. Months already agreed are never changed.',
                )
              }
            >
              <RefreshCw /> Recalculate
            </button>
          )}
        </header>

        {commitments.length === 0 ? (
          <Empty
            title="No commitments recorded"
            copy="They come from the tier's defaults when the contract is written."
          />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Commitment</th>
                  <th>Target</th>
                  <th>So far this month</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {commitments.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <strong>{row.label}</strong>
                      <small>
                        {row.metricKey}
                        {row.isManual ? ' · recorded by an admin' : ' · measured'}
                      </small>
                      {row.caveat && (
                        <small style={{ color: '#895e00', fontWeight: 650 }}>
                          {row.caveat}
                        </small>
                      )}
                    </td>
                    <td>{row.targetValue}</td>
                    <td>
                      <strong>{row.currentValue}</strong>
                    </td>
                    <td>
                      <Badge value={row.currentStatus} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* ───────────────────────────────────────── month by month */}

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Record, month by month</h2>
            <p>What was agreed each month and whether it was met</p>
          </div>
        </header>

        {periods.length === 0 ? (
          <Empty
            title="Nothing recorded yet"
            copy="Months appear here once the contract is signed."
          />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Month</th>
                  <th>Commitment</th>
                  <th>Target</th>
                  <th>Actual</th>
                  <th>Status</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {periods.map((row) => (
                  <tr key={row.id}>
                    <td>{monthOf(row.periodStart)}</td>
                    <td>{row.label}</td>
                    <td>{row.targetValue}</td>
                    <td>{row.actualValue}</td>
                    <td>
                      <Badge value={row.status} />
                      {row.note && <small>{row.note}</small>}
                    </td>
                    <td>
                      <button
                        className="secondaryButton"
                        disabled={busy}
                        onClick={() => {
                          setRecording(row);
                          setRecordStatus(row.status === 'Missed' ? 'Waived' : row.status);
                          setRecordValue(String(row.actualValue));
                          setRecordNote(row.note ?? '');
                        }}
                      >
                        Record
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* ───────────────────────────────────────────── statements */}

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Monthly statements</h2>
            <p>
              Share of UDrive&apos;s commission in this area. Payment happens outside
              the app — this is the agreed record of what is owed.
            </p>
          </div>
        </header>

        {statements.length === 0 ? (
          <Empty
            title="No statements yet"
            copy="A statement is built for each month once the contract is signed."
          />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Month</th>
                  <th>Rides</th>
                  <th>Fares</th>
                  <th>UDrive&apos;s commission</th>
                  <th>Share</th>
                  <th>Owed</th>
                  <th>Status</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {statements.map((row) => (
                  <tr key={row.id}>
                    <td>{monthOf(row.periodStart)}</td>
                    <td>{row.completedRides}</td>
                    <td>{money(row.grossFares)}</td>
                    <td>{money(row.commissionBase)}</td>
                    <td>{row.sharePct}%</td>
                    <td>
                      <strong>{money(row.shareAmount)}</strong>
                    </td>
                    <td>
                      <Badge value={row.status} />
                      {row.paidReference && <small>{row.paidReference}</small>}
                    </td>
                    <td>
                      {row.status === 'Open' && (
                        <button
                          className="secondaryButton"
                          disabled={busy}
                          onClick={() =>
                            void act(
                              () =>
                                apiFetch(
                                  `/api/v1/admin/partners/statements/${row.id}/close`,
                                  { method: 'POST' },
                                ),
                              'Agreed. The partner now sees this month as final.',
                            )
                          }
                        >
                          Agree
                        </button>
                      )}
                      {row.status === 'Closed' && (
                        <button
                          className="primaryButton"
                          disabled={busy}
                          onClick={() => {
                            setPaying(row);
                            setPayReference('');
                          }}
                        >
                          Record payment
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* ───────────────────────────────────────── the signature */}

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Signature record</h2>
            <p>
              The photograph and the video are personal data. SuperAdmin only, and
              every view is written to the audit log.
            </p>
          </div>
        </header>

        {!evidence?.exists ? (
          <Empty
            title="Not signed yet"
            copy="The partner signs in their own portal, with a live photograph and a video reading the words on screen."
          />
        ) : (
          <>
            <div className="detailGrid">
              <div>
                <span>Signed (server time)</span>
                <strong>{when(evidence.signedAtServer)}</strong>
              </div>
              <div>
                <span>Phone (proven by OTP at sign-in)</span>
                <strong>{evidence.phoneNumber ?? '—'}</strong>
              </div>
              <div>
                <span>From IP</span>
                <strong>{evidence.ipAddress ?? '—'}</strong>
              </div>
              <div>
                <span>Device</span>
                <strong>{evidence.deviceInfo ?? '—'}</strong>
              </div>
              <div>
                <span>Delete after</span>
                <strong>
                  {evidence.purgeAfter
                    ? new Date(evidence.purgeAfter).toLocaleDateString('en-GB')
                    : '—'}
                </strong>
              </div>
              <div>
                <span>Already deleted</span>
                <strong>{evidence.purgedAt ? when(evidence.purgedAt) : 'No'}</strong>
              </div>
            </div>

            <div className="buttonRow">
              {evidence.canView ? (
                <button
                  className="secondaryButton"
                  disabled={busy}
                  onClick={() => void openEvidence()}
                >
                  <Eye /> View photograph and video
                </button>
              ) : (
                <p style={{ color: '#71827b', margin: 0 }}>
                  <ShieldAlert style={{ width: 15, verticalAlign: '-2px' }} />{' '}
                  {evidence.purgedAt
                    ? 'These files have been deleted. The record of the signature stays.'
                    : 'Only a SuperAdmin can open these files.'}
                </p>
              )}
              {isSuperAdmin() && !evidence.purgedAt && contract && (
                <button
                  className="dangerButton"
                  disabled={busy}
                  onClick={() =>
                    void act(
                      () =>
                        apiFetch(
                          `/api/v1/admin/partners/contracts/${contract.id}/evidence/purge`,
                          { method: 'POST' },
                        ),
                      'Deleted. The photograph and video are gone; when and from where the contract was signed stays recorded.',
                    )
                  }
                >
                  <Trash2 /> Delete the files
                </button>
              )}
            </div>
          </>
        )}
      </section>

      {/* ──────────────────────────────────────────────── modals */}

      {terminating && contract && (
        <Modal title="Terminate this contract" onClose={() => setTerminating(false)}>
          <div style={{ margin: '0 22px 14px' }}>
            <p>
              This ends the contract and <strong>frees the territory</strong>, so
              somebody else can be appointed to {partner.territoryName}. The record of
              what was agreed, every month of it, stays.
            </p>
          </div>
          <Field label="Reason (required, and kept on the record)">
            <textarea
              rows={3}
              value={terminateReason}
              onChange={(e) => setTerminateReason(e.target.value)}
            />
          </Field>
          <div className="buttonRow">
            <button
              className="dangerButton"
              disabled={busy || !terminateReason.trim()}
              onClick={() =>
                void act(async () => {
                  await apiFetch(
                    `/api/v1/admin/partners/contracts/${contract.id}/terminate`,
                    {
                      method: 'POST',
                      body: JSON.stringify({ reason: terminateReason }),
                    },
                  );
                  setTerminating(false);
                }, 'Terminated. The area is free again.')
              }
            >
              Terminate
            </button>
            <button className="secondaryButton" onClick={() => setTerminating(false)}>
              Cancel
            </button>
          </div>
        </Modal>
      )}

      {paying && (
        <Modal title="Record a payment" onClose={() => setPaying(null)}>
          <div className="detailGrid">
            <div>
              <span>Month</span>
              <strong>{monthOf(paying.periodStart)}</strong>
            </div>
            <div>
              <span>Owed</span>
              <strong>{money(paying.shareAmount)}</strong>
            </div>
          </div>
          <div style={{ margin: '0 22px 14px' }}>
            <p>
              This does not move any money. It records that the payment was made
              outside the app, so the partner&apos;s statement and yours agree.
            </p>
          </div>
          <Field label="Reference (bank transfer number, or how it was paid)">
            <input
              value={payReference}
              onChange={(e) => setPayReference(e.target.value)}
              placeholder="e.g. HBL transfer 889201, 5 Nov"
            />
          </Field>
          <div className="buttonRow">
            <button
              className="primaryButton"
              disabled={busy || !payReference.trim()}
              onClick={() =>
                void act(async () => {
                  await apiFetch(
                    `/api/v1/admin/partners/statements/${paying.id}/paid`,
                    {
                      method: 'POST',
                      body: JSON.stringify({ reference: payReference, note: null }),
                    },
                  );
                  setPaying(null);
                }, 'Recorded.')
              }
            >
              Record it
            </button>
            <button className="secondaryButton" onClick={() => setPaying(null)}>
              Cancel
            </button>
          </div>
        </Modal>
      )}

      {recording && (
        <Modal
          title={`${recording.label} — ${monthOf(recording.periodStart)}`}
          onClose={() => setRecording(null)}
        >
          <div style={{ margin: '0 22px 14px' }}>
            <p>
              Use this to report a commitment the system cannot measure, or to waive a
              month that was missed for a reason worth writing down.
            </p>
          </div>
          <div className="formGrid">
            <Field label="Status">
              <select
                value={recordStatus}
                onChange={(e) => setRecordStatus(e.target.value)}
              >
                <option value="Open">Still open</option>
                <option value="Met">Met</option>
                <option value="Missed">Missed</option>
                <option value="Waived">Waived</option>
              </select>
            </Field>
            <Field label="Actual value">
              <input
                type="number"
                value={recordValue}
                onChange={(e) => setRecordValue(e.target.value)}
              />
            </Field>
          </div>
          <Field label={recordStatus === 'Waived' ? 'Reason (required)' : 'Note'}>
            <textarea
              rows={3}
              value={recordNote}
              onChange={(e) => setRecordNote(e.target.value)}
            />
          </Field>
          <div className="buttonRow">
            <button
              className="primaryButton"
              disabled={
                busy || (recordStatus === 'Waived' && !recordNote.trim())
              }
              onClick={() =>
                void act(async () => {
                  await apiFetch(
                    `/api/v1/admin/partners/periods/${recording.id}/record`,
                    {
                      method: 'POST',
                      body: JSON.stringify({
                        actualValue:
                          recordValue === '' ? null : Number(recordValue),
                        status: recordStatus,
                        note: recordNote || null,
                      }),
                    },
                  );
                  setRecording(null);
                }, 'Recorded.')
              }
            >
              Save
            </button>
            <button className="secondaryButton" onClick={() => setRecording(null)}>
              Cancel
            </button>
          </div>
        </Modal>
      )}

      {evidenceOpen && (
        <Modal title="Signature record" onClose={closeEvidence}>
          <div style={{ padding: '18px 22px 0' }}>
            <p style={{ color: '#71827b', marginTop: 0 }}>
              Your name and the time have been written to the audit log.
            </p>
            <p>
              <strong>The words that were on screen:</strong>
            </p>
            <p
              style={{
                background: '#f4f8f6',
                borderRadius: 12,
                padding: 14,
                lineHeight: 1.7,
              }}
            >
              {evidenceScript}
            </p>
          </div>
          <div style={{ padding: '0 22px 22px', display: 'grid', gap: 14 }}>
            {selfieUrl && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={selfieUrl}
                alt="Signature photograph"
                style={{ width: '100%', borderRadius: 14 }}
              />
            )}
            {videoUrl && (
              <video src={videoUrl} controls style={{ width: '100%', borderRadius: 14 }} />
            )}
          </div>
          <div className="buttonRow">
            <button className="secondaryButton" onClick={closeEvidence}>
              Close
            </button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
