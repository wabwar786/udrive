'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  ArrowDownToLine,
  ArrowUpRight,
  BadgeDollarSign,
  Banknote,
  CircleDollarSign,
  RefreshCw,
  Search,
  ShieldCheck,
  WalletCards,
} from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { apiFetch, isSuperAdmin, money, when } from '../lib/admin-api';

type Row = Record<string, unknown>;
type Tab = 'transactions' | 'earnings' | 'wallets' | 'payouts' | 'refunds' | 'rules';

const tabs: { key: Tab; label: string }[] = [
  { key: 'transactions', label: 'Transactions' },
  { key: 'earnings', label: 'Driver earnings' },
  { key: 'wallets', label: 'Wallets' },
  { key: 'payouts', label: 'Payouts' },
  { key: 'refunds', label: 'Refunds' },
  { key: 'rules', label: 'Commission rules' },
];

export default function FinancePage() {
  const [tab, setTab] = useState<Tab>('transactions');
  const [data, setData] = useState<Row[]>([]);
  const [dash, setDash] = useState<Row>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [search, setSearch] = useState('');

  async function load() {
    setLoading(true);
    setError('');
    try {
      const [dashboard, rows] = await Promise.all([
        apiFetch<Row>('/api/v1/admin/finance/dashboard'),
        apiFetch<Row[]>(`/api/v1/admin/finance/${tab}`),
      ]);
      setDash(dashboard);
      setData(rows);
    } catch (value) {
      setData([]);
      setError(value instanceof Error ? value.message : 'Finance data could not be loaded.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, [tab]);

  const filtered = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return needle
      ? data.filter((row) => JSON.stringify(row).toLowerCase().includes(needle))
      : data;
  }, [data, search]);

  const metrics = [
    { label: 'Gross payments', value: money(Number(dash.grossPayments ?? 0)), icon: CircleDollarSign, tone: 'emerald' },
    { label: 'Platform commission', value: money(Number(dash.platformCommission ?? 0)), icon: BadgeDollarSign, tone: 'blue' },
    { label: 'Driver payable', value: money(Number(dash.driverPayable ?? 0)), icon: WalletCards, tone: 'violet' },
    { label: 'Refunded', value: money(Number(dash.refunded ?? 0)), icon: ArrowDownToLine, tone: 'orange' },
    { label: 'Pending payouts', value: String(dash.pendingPayouts ?? 0), icon: Banknote, tone: 'amber' },
    { label: 'Pending refunds', value: String(dash.pendingRefunds ?? 0), icon: ShieldCheck, tone: 'red' },
  ];

  return (
    <AdminFrame
      title="Finance & settlements"
      subtitle="A compact finance workspace for collections, commission, Driver wallets, payouts and refunds."
    >
      <section className="financeHero panel">
        <div>
          <span className="eyebrow">FINANCE CONTROL</span>
          <h2>Money movement at a glance</h2>
          <p>Review collections, Driver liabilities and settlement queues without switching between separate modules.</p>
        </div>
        <button className="secondaryButton" onClick={() => void load()} disabled={loading}>
          <RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh
        </button>
      </section>

      <div className="financeMetricGrid">
        {metrics.map(({ label, value, icon: Icon, tone }) => (
          <article className={`financeMetric financeMetric--${tone}`} key={label}>
            <div className="financeMetricIcon"><Icon size={18} /></div>
            <div><span>{label}</span><strong>{value}</strong></div>
          </article>
        ))}
      </div>

      <section className="panel financeWorkspace">
        <div className="financeToolbar">
          <div className="financeTabs" role="tablist" aria-label="Finance sections">
            {tabs.map((item) => (
              <button
                key={item.key}
                className={tab === item.key ? 'active' : ''}
                onClick={() => setTab(item.key)}
              >
                {item.label}
              </button>
            ))}
          </div>
          <label className="financeSearch">
            <Search size={15} />
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search current section" />
          </label>
        </div>

        {error && <div className="errorPanel">{error}</div>}
        {loading ? (
          <div className="financeLoading">Loading finance records…</div>
        ) : (
          <FinanceTable tab={tab} rows={filtered} reload={load} />
        )}
      </section>
    </AdminFrame>
  );
}

function FinanceTable({ tab, rows, reload }: { tab: Tab; rows: Row[]; reload: () => void }) {
  if (!rows.length) {
    return <div className="financeEmpty"><ArrowUpRight size={20} /><strong>No finance records found</strong><span>Records will appear here as transactions are created.</span></div>;
  }

  const columns: Record<Tab, [string, string][]> = {
    transactions: [['reference', 'Reference'], ['type', 'Type'], ['party', 'Party'], ['bookingReference', 'Booking'], ['amount', 'Amount'], ['status', 'Status'], ['createdAt', 'Date']],
    earnings: [['bookingReference', 'Booking'], ['driverName', 'Driver'], ['grossAmount', 'Gross'], ['commissionPercentage', 'Commission %'], ['commissionAmount', 'Commission'], ['netAmount', 'Net'], ['status', 'Status']],
    wallets: [['driverName', 'Driver'], ['pendingBalance', 'Pending'], ['availableBalance', 'Available'], ['paidBalance', 'Paid'], ['currency', 'Currency']],
    payouts: [['driverName', 'Driver'], ['amount', 'Amount'], ['payoutMethod', 'Method'], ['destinationMasked', 'Destination'], ['status', 'Status'], ['requestedAt', 'Requested']],
    refunds: [['bookingReference', 'Booking'], ['customerName', 'Customer'], ['amount', 'Refund'], ['cancellationFee', 'Fee'], ['reason', 'Reason'], ['status', 'Status']],
    rules: [['name', 'Rule'], ['percentage', 'Commission %'], ['bookingType', 'Booking type'], ['city', 'City'], ['isActive', 'Active'], ['effectiveFrom', 'Effective from']],
  };

  return (
    <div className="financeTableWrap">
      <table>
        <thead><tr>{columns[tab].map(([, label]) => <th key={label}>{label}</th>)}{(['payouts', 'refunds'] as Tab[]).includes(tab) && <th>Action</th>}</tr></thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={String(row.id ?? index)}>
              {columns[tab].map(([key]) => <td key={key}>{format(key, row[key])}</td>)}
              {tab === 'payouts' && <td><ReviewButton kind="payouts" row={row} reload={reload} /></td>}
              {tab === 'refunds' && <td><ReviewButton kind="refunds" row={row} reload={reload} /></td>}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ReviewButton({ kind, row, reload }: { kind: 'payouts' | 'refunds'; row: Row; reload: () => void }) {
  const [busy, setBusy] = useState(false);
  async function review(status: string) {
    setBusy(true);
    try {
      await apiFetch(`/api/v1/admin/finance/${kind}/${row.id}`, {
        method: 'PUT',
        body: JSON.stringify({ status, providerReference: null, reviewNotes: `${status} from Finance portal`, expectedVersion: Number(row.version) }),
      });
      reload();
    } finally {
      setBusy(false);
    }
  }
  if (!['Pending', 'Approved', 'Processing'].includes(String(row.status))) return <span className="finalTag">Final</span>;
  return (
    <div className="financeActions">
      <button disabled={busy} onClick={() => void review('Approved')}>Approve</button>
      <button disabled={busy} className="dangerText" onClick={() => void review('Rejected')}>Reject</button>
      {isSuperAdmin() && kind === 'payouts' && String(row.status) !== 'Paid' && <button disabled={busy} onClick={() => void review('Paid')}>Mark paid</button>}
      {isSuperAdmin() && kind === 'refunds' && String(row.status) !== 'Completed' && <button disabled={busy} onClick={() => void review('Completed')}>Complete</button>}
    </div>
  );
}

function format(key: string, value: unknown) {
  if (value == null) return '—';
  if (['amount', 'grossAmount', 'commissionAmount', 'netAmount', 'pendingBalance', 'availableBalance', 'paidBalance', 'cancellationFee'].includes(key)) return money(Number(value));
  if (key.toLowerCase().includes('at') || key === 'effectiveFrom') return when(String(value));
  if (key === 'status') return <span className={`financeStatus financeStatus--${String(value).toLowerCase()}`}>{String(value)}</span>;
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  return String(value);
}
