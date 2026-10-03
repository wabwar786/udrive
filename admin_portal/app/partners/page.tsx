'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Check, ExternalLink, Handshake, X } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { apiFetch, money, when } from '../lib/admin-api';

type Application = {
  id: string;
  userId: string;
  fullName?: string | null;
  phoneNumber?: string | null;
  tierKey: string;
  tierName: string;
  territoryId: string;
  territoryName: string;
  territoryKind: string;
  applicantNote?: string | null;
  contactPhone?: string | null;
  status: string;
  decisionReason?: string | null;
  decidedAt?: string | null;
  decidedByName?: string | null;
  createdAt: string;
  customerSince?: string | null;
  completedRides: number;
  territoryAvailable: boolean;
};

type Partner = {
  id: string;
  fullName: string;
  phoneNumber?: string | null;
  tierName: string;
  territoryName: string;
  territoryKind: string;
  status: string;
  startedAt?: string | null;
  contractId?: string | null;
  contractReference?: string | null;
  contractStatus?: string | null;
  commissionSharePct: number;
  securityDeposit: number;
  commitmentsMet: number;
  commitmentsMissed: number;
  currentMonthShare: number;
};

/**
 * Territory partners: the queue of people asking, and the people who hold a
 * territory now.
 *
 * Two things on this screen are worth knowing before using it.
 *
 * **Approving creates a draft contract, not an active partner.** The partner
 * becomes Active only when they sign it themselves in the partner portal, with a
 * live photograph and a video. So an approval here is reversible right up to that
 * moment, and until then the territory is held but not earning.
 *
 * **"Area still free" is checked when this list loads, not when the application
 * was made.** An application can sit in the queue while somebody else signs for
 * the same place, and approving it then fails — the database refuses it, which is
 * the right place for that rule to live. The badge warns before the click.
 */
export default function Page() {
  const [applications, setApplications] = useState<Application[]>([]);
  const [partners, setPartners] = useState<Partner[]>([]);
  const [queueFilter, setQueueFilter] = useState('Pending');

  const [deciding, setDeciding] = useState<Application | null>(null);
  const [approve, setApprove] = useState(true);
  const [reason, setReason] = useState('');

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');

  const load = useCallback(async () => {
    const [queue, list] = await Promise.all([
      apiFetch<Application[]>(
        `/api/v1/admin/partners/applications${queueFilter ? `?status=${queueFilter}` : ''}`,
      ),
      apiFetch<Partner[]>('/api/v1/admin/partners'),
    ]);
    setApplications(queue);
    setPartners(list);
  }, [queueFilter]);

  useEffect(() => {
    setLoading(true);
    setError('');
    void load()
      .catch((e) =>
        setError(e instanceof Error ? e.message : 'This section is unavailable.'),
      )
      .finally(() => setLoading(false));
  }, [load]);

  const stats = useMemo(
    () => ({
      waiting: applications.filter((a) => a.status === 'Pending').length,
      active: partners.filter((p) => p.status === 'Active').length,
      unsigned: partners.filter(
        (p) => p.status === 'Pending' || p.contractStatus === 'Sent',
      ).length,
      thisMonth: partners.reduce((sum, p) => sum + p.currentMonthShare, 0),
    }),
    [applications, partners],
  );

  const open = (row: Application, yes: boolean) => {
    setDeciding(row);
    setApprove(yes);
    setReason('');
  };

  const decide = async () => {
    if (!deciding) return;
    setBusy(true);
    setError('');
    setNote('');
    try {
      await apiFetch<unknown>(
        `/api/v1/admin/partners/applications/${deciding.id}/decision`,
        {
          method: 'POST',
          body: JSON.stringify({ approve, reason: reason || null }),
        },
      );
      setNote(
        approve
          ? 'Approved. A draft contract has been written — open the partner, check the figures, then send it. They become active when they sign.'
          : 'Refused. The applicant is shown the reason you wrote.',
      );
      setDeciding(null);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be saved.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <AdminFrame
      title="Territory partners"
      subtitle="One partner per area, each bound to monthly commitments. Payment happens outside the app."
      actions={
        <Link className="secondaryButton" href="/territories">
          <Handshake /> Territories &amp; areas
        </Link>
      }
    >
      {error && <ErrorBox message={error} />}
      {note && (
        <div className="successBox">
          <strong>{note}</strong>
        </div>
      )}

      {loading ? (
        <Loading />
      ) : (
        <>
          <div className="statGrid">
            <Stat label="Requests waiting" value={stats.waiting} tone="amber" />
            <Stat label="Active partners" value={stats.active} tone="emerald" />
            <Stat
              label="Not signed yet"
              value={stats.unsigned}
              sub="Approved, contract unsigned"
              tone="slate"
            />
            <Stat
              label="This month's share"
              value={money(stats.thisMonth)}
              sub="All partners, so far"
              tone="blue"
            />
          </div>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Requests from the app</h2>
                <p>{applications.length} shown</p>
              </div>
              <select
                value={queueFilter}
                onChange={(e) => setQueueFilter(e.target.value)}
              >
                <option value="Pending">Waiting</option>
                <option value="Approved">Approved</option>
                <option value="Rejected">Refused</option>
                <option value="Withdrawn">Withdrawn</option>
                <option value="">All</option>
              </select>
            </header>

            {applications.length === 0 ? (
              <Empty
                title="No requests"
                copy="Customers ask through the app, under Become a partner. Requests land here."
              />
            ) : (
              <div className="tableWrap">
                <table>
                  <thead>
                    <tr>
                      <th>Who</th>
                      <th>Asking for</th>
                      <th>Their history with UDrive</th>
                      <th>Why</th>
                      <th>Asked</th>
                      <th />
                    </tr>
                  </thead>
                  <tbody>
                    {applications.map((row) => (
                      <tr key={row.id}>
                        <td>
                          <strong>{row.fullName ?? 'Unnamed'}</strong>
                          <small>{row.contactPhone ?? row.phoneNumber ?? '—'}</small>
                        </td>
                        <td>
                          <strong>{row.tierName}</strong>
                          <small>
                            {row.territoryName} ({row.territoryKind})
                          </small>
                          {row.status === 'Pending' && !row.territoryAvailable && (
                            <small style={{ color: '#a62032', fontWeight: 700 }}>
                              This area already has a partner — refuse, or ask for
                              another area.
                            </small>
                          )}
                        </td>
                        <td>
                          {row.completedRides} completed ride(s)
                          <small>
                            {row.customerSince
                              ? `customer since ${when(row.customerSince)}`
                              : '—'}
                          </small>
                        </td>
                        <td style={{ maxWidth: 260 }}>
                          {row.applicantNote ?? <span>—</span>}
                        </td>
                        <td>
                          {when(row.createdAt)}
                          {row.status !== 'Pending' && (
                            <small>
                              <Badge value={row.status} />{' '}
                              {row.decisionReason ?? ''}
                            </small>
                          )}
                        </td>
                        <td>
                          {row.status === 'Pending' && (
                            <>
                              <button
                                className="primaryButton"
                                disabled={busy}
                                onClick={() => open(row, true)}
                              >
                                <Check /> Approve
                              </button>{' '}
                              <button
                                className="dangerButton"
                                disabled={busy}
                                onClick={() => open(row, false)}
                              >
                                <X /> Refuse
                              </button>
                            </>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Partners</h2>
                <p>{partners.length} in all</p>
              </div>
            </header>

            {partners.length === 0 ? (
              <Empty
                title="No partners yet"
                copy="Approve a request above and the partner appears here with a draft contract."
              />
            ) : (
              <div className="tableWrap">
                <table>
                  <thead>
                    <tr>
                      <th>Partner</th>
                      <th>Area</th>
                      <th>Contract</th>
                      <th>Share</th>
                      <th>Commitments</th>
                      <th>This month</th>
                      <th />
                    </tr>
                  </thead>
                  <tbody>
                    {partners.map((row) => (
                      <tr key={row.id}>
                        <td>
                          <strong>{row.fullName}</strong>
                          <small>
                            {row.tierName} · {row.phoneNumber ?? '—'}
                          </small>
                        </td>
                        <td>
                          <strong>{row.territoryName}</strong>
                          <small>{row.territoryKind}</small>
                        </td>
                        <td>
                          <Badge value={row.contractStatus ?? 'none'} />
                          <small>{row.contractReference ?? 'no contract yet'}</small>
                        </td>
                        <td>
                          {row.commissionSharePct}%
                          <small>of UDrive&apos;s commission</small>
                          <small>deposit {money(row.securityDeposit)}</small>
                        </td>
                        <td>
                          {row.commitmentsMet} met
                          <small>
                            {row.commitmentsMissed > 0
                              ? `${row.commitmentsMissed} missed`
                              : 'none missed'}
                          </small>
                        </td>
                        <td>{money(row.currentMonthShare)}</td>
                        <td>
                          <Link className="secondaryButton" href={`/partners/${row.id}`}>
                            <ExternalLink /> Open
                          </Link>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        </>
      )}

      {deciding && (
        <Modal
          title={approve ? 'Approve this request' : 'Refuse this request'}
          onClose={() => setDeciding(null)}
        >
          <div className="detailGrid">
            <div>
              <span>Applicant</span>
              <strong>{deciding.fullName ?? 'Unnamed'}</strong>
            </div>
            <div>
              <span>Asking to be</span>
              <strong>
                {deciding.tierName} of {deciding.territoryName}
              </strong>
            </div>
            <div>
              <span>Rides taken as a customer</span>
              <strong>{deciding.completedRides}</strong>
            </div>
            <div>
              <span>Area free right now</span>
              <strong>{deciding.territoryAvailable ? 'Yes' : 'No'}</strong>
            </div>
          </div>

          <div style={{ margin: '0 22px 14px' }}>
            {approve ? (
              <p>
                This writes a <strong>draft contract</strong> from the tier&apos;s
                current terms and commitments. Nothing is binding and the partner
                earns nothing until they sign it themselves in the partner portal.
              </p>
            ) : (
              <p>
                The applicant sees this sentence in the app, so write it to be read
                by them.
              </p>
            )}
          </div>

          <Field label={approve ? 'Note (optional)' : 'Reason (required)'}>
            <textarea
              rows={3}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder={
                approve
                  ? 'Anything to record about this decision'
                  : 'Mirpur already has a City Head. Pattika is still open.'
              }
            />
          </Field>

          <div className="buttonRow">
            <button
              className={approve ? 'primaryButton' : 'dangerButton'}
              disabled={busy || (!approve && !reason.trim())}
              onClick={() => void decide()}
            >
              {approve ? 'Approve and write the draft' : 'Refuse'}
            </button>
            <button className="secondaryButton" onClick={() => setDeciding(null)}>
              Cancel
            </button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
