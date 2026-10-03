'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { FileSignature } from 'lucide-react';

import { Badge, Empty, ErrorBox, Loading, Stat } from '../components/ui';
import {
  money,
  monthName,
  partnerFetch,
  readPartnerSession,
  when,
} from '../lib/partner-api';
import { PartnerShell } from './partner-shell';

type Commitment = {
  id: string;
  label: string;
  metricKey: string;
  targetValue: number;
  currentValue: number;
  currentStatus: string;
  isManual: boolean;
  caveat?: string | null;
};

type Period = {
  id: string;
  label: string;
  periodStart: string;
  targetValue: number;
  actualValue: number;
  status: string;
  note?: string | null;
};

type Statement = {
  id: string;
  periodStart: string;
  completedRides: number;
  commissionBase: number;
  sharePct: number;
  shareAmount: number;
  status: string;
  paidReference?: string | null;
  paidAt?: string | null;
};

type Portal = {
  fullName: string;
  tierName: string;
  territoryName: string;
  territoryKind: string;
  partnerStatus: string;
  contract: {
    id: string;
    reference: string;
    status: string;
    commissionSharePct: number;
    securityDeposit: number;
    termMonths: number;
    signedAt?: string | null;
    endsAt?: string | null;
  } | null;
  commitments: Commitment[];
  recentPeriods: Period[];
  statements: Statement[];
  totals: {
    driversInTerritory: number;
    newDriversThisMonth: number;
    activeDriversThisMonth: number;
    completedRidesThisMonth: number;
    commissionBaseThisMonth: number;
    shareThisMonth: number;
    shareOwedUnpaid: number;
    sharePaidToDate: number;
  };
  payoutNote: string;
};

/**
 * What the partner sees: their area, their commitments, their statements.
 *
 * The numbers here come from the same queries the admin screen uses, not from a
 * second set written for this page. That is the one thing that matters about this
 * screen: when a partner rings the office about March, both of them are reading
 * the same row.
 *
 * Two distinctions the layout is careful about, because getting them wrong is how
 * a partner comes to believe they are being short-paid:
 *
 * - **This month is not owed.** It is still running. Only a month UDrive has
 *   agreed appears as owed.
 * - **Owed is not paid.** Payment happens outside the app, and a month shows as
 *   paid only once somebody has recorded the reference.
 */
export default function Page() {
  const router = useRouter();
  const [data, setData] = useState<Portal | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setData(await partnerFetch<Portal>('/api/v1/partner/me'));
  }, []);

  useEffect(() => {
    if (!readPartnerSession()) {
      router.replace('/partner/login');
      return;
    }

    setLoading(true);
    void load()
      .catch((e) =>
        setError(e instanceof Error ? e.message : 'This is not available right now.'),
      )
      .finally(() => setLoading(false));
  }, [load, router]);

  if (loading) {
    return (
      <PartnerShell title="Loading">
        <Loading />
      </PartnerShell>
    );
  }

  if (!data) {
    return (
      <PartnerShell title="Partner portal">
        {error && <ErrorBox message={error} />}
        <section className="panel">
          <Empty
            title="Nothing to show yet"
            copy="If you have applied to be a partner, you will see your contract here once UDrive has prepared it."
          />
        </section>
      </PartnerShell>
    );
  }

  const awaitingSignature = data.contract?.status === 'Sent';

  return (
    <PartnerShell
      title={`${data.tierName} · ${data.territoryName}`}
      subtitle={`${data.territoryKind} · ${data.partnerStatus}${
        data.contract ? ` · contract ${data.contract.reference}` : ''
      }`}
    >
      {error && <ErrorBox message={error} />}

      {awaitingSignature && (
        <section className="panel" style={{ borderColor: '#14a878' }}>
          <header className="panelHeader">
            <div>
              <h2>Your contract is ready to sign</h2>
              <p>
                Read it, then confirm with a live photograph and a short video. Your
                area is yours from that moment.
              </p>
            </div>
            <Link className="primaryButton" href="/partner/contract">
              <FileSignature /> Read and sign
            </Link>
          </header>
        </section>
      )}

      <div className="statGrid">
        <Stat
          label="This month's share"
          value={money(data.totals.shareThisMonth)}
          sub="Still running — not final"
          tone="blue"
        />
        <Stat
          label="Agreed and unpaid"
          value={money(data.totals.shareOwedUnpaid)}
          sub="Months UDrive has agreed"
          tone="amber"
        />
        <Stat
          label="Paid to you so far"
          value={money(data.totals.sharePaidToDate)}
          tone="emerald"
        />
        <Stat
          label="Drivers in your area"
          value={data.totals.driversInTerritory}
          sub={`${data.totals.activeDriversThisMonth} drove this month`}
          tone="violet"
        />
        <Stat
          label="Rides this month"
          value={data.totals.completedRidesThisMonth}
          tone="slate"
        />
        <Stat
          label="New drivers this month"
          value={data.totals.newDriversThisMonth}
          tone="emerald"
        />
      </div>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>What you committed to, this month</h2>
            <p>
              Updated daily. UDrive sees exactly these numbers — there is only one
              record.
            </p>
          </div>
        </header>

        {data.commitments.length === 0 ? (
          <Empty
            title="No commitments recorded"
            copy="They appear here once your contract is signed."
          />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Commitment</th>
                  <th>Target</th>
                  <th>So far</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {data.commitments.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <strong>{row.label}</strong>
                      {row.isManual && <small>Recorded by UDrive</small>}
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

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Your monthly statements</h2>
            <p>{data.payoutNote}</p>
          </div>
        </header>

        {data.statements.length === 0 ? (
          <Empty
            title="No statements yet"
            copy="A statement is built for each month once your contract is signed."
          />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Month</th>
                  <th>Rides in your area</th>
                  <th>UDrive&apos;s commission</th>
                  <th>Your share</th>
                  <th>Amount</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {data.statements.map((row) => (
                  <tr key={row.id}>
                    <td>{monthName(row.periodStart)}</td>
                    <td>{row.completedRides}</td>
                    <td>{money(row.commissionBase)}</td>
                    <td>{row.sharePct}%</td>
                    <td>
                      <strong>{money(row.shareAmount)}</strong>
                    </td>
                    <td>
                      <Badge
                        value={
                          row.status === 'Open'
                            ? 'Still running'
                            : row.status === 'Closed'
                              ? 'Agreed'
                              : 'Paid'
                        }
                      />
                      {row.paidReference && <small>{row.paidReference}</small>}
                      {row.paidAt && <small>{when(row.paidAt)}</small>}
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
            <h2>Your record, month by month</h2>
            <p>What was agreed each month, and whether it was met</p>
          </div>
        </header>

        {data.recentPeriods.length === 0 ? (
          <Empty title="Nothing recorded yet" copy="Months appear here as they finish." />
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
                </tr>
              </thead>
              <tbody>
                {data.recentPeriods.map((row) => (
                  <tr key={row.id}>
                    <td>{monthName(row.periodStart)}</td>
                    <td>{row.label}</td>
                    <td>{row.targetValue}</td>
                    <td>{row.actualValue}</td>
                    <td>
                      <Badge value={row.status} />
                      {row.note && <small>{row.note}</small>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </PartnerShell>
  );
}
