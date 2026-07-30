'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  CalendarDays,
  CarFront,
  CircleDollarSign,
  MapPinned,
  RefreshCw,
  Search,
  ShieldCheck,
  TicketCheck,
  UsersRound,
} from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Loading, Modal } from '../components/ui';
import { apiFetch, money, when } from '../lib/admin-api';

type PackageRow = {
  id: string; title: string; startingCity: string; destination: string;
  departureAt: string; returnAt?: string | null; status: string;
  totalSeats: number; availableSeats: number; pricePerSeat: number;
  wholeVehiclePrice: number; driverName: string; vehicle: string;
  registrationNumber: string; bookingCount: number; seatsBooked: number;
  grossRevenue: number;
};

type PendingRow = PackageRow & { driverSafetyScore?: number; mountainReadinessScore?: number; reviewNotes?: string | null };

export default function Page() {
  const [rows, setRows] = useState<PackageRow[]>([]);
  const [pending, setPending] = useState<PendingRow[]>([]);
  const [selected, setSelected] = useState<PendingRow | null>(null);
  const [status, setStatus] = useState('');
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(true);

  async function load() {
    setBusy(true);
    setError('');
    const suffix = status ? `?status=${encodeURIComponent(status)}` : '';
    const [inventoryResult, pendingResult] = await Promise.allSettled([
      apiFetch<PackageRow[]>(`/api/v1/admin/tour-marketplace/packages${suffix}`),
      apiFetch<PendingRow[]>('/api/v1/admin/packages/pending'),
    ]);
    if (inventoryResult.status === 'fulfilled') setRows(inventoryResult.value); else setRows([]);
    if (pendingResult.status === 'fulfilled') setPending(pendingResult.value); else setPending([]);
    const failures = [inventoryResult, pendingResult].filter((item) => item.status === 'rejected') as PromiseRejectedResult[];
    if (failures.length) setError(failures[0].reason instanceof Error ? failures[0].reason.message : 'Some marketplace data could not be loaded.');
    setBusy(false);
  }

  useEffect(() => { void load(); }, [status]);

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return needle ? rows.filter((row) => `${row.title} ${row.startingCity} ${row.destination} ${row.driverName} ${row.registrationNumber}`.toLowerCase().includes(needle)) : rows;
  }, [rows, query]);

  const gross = rows.reduce((sum, row) => sum + Number(row.grossRevenue || 0), 0);
  const seats = rows.reduce((sum, row) => sum + Number(row.seatsBooked || 0), 0);
  const capacity = rows.reduce((sum, row) => sum + Number(row.totalSeats || 0), 0);
  const occupancy = capacity ? Math.round((seats / capacity) * 100) : 0;

  return (
    <AdminFrame title="Tourism marketplace" subtitle="Approve quality packages and monitor inventory, departures, occupancy and revenue.">
      <section className="tourHero panel">
        <div>
          <span className="eyebrow">TOURISM OPERATIONS</span>
          <h2>Marketplace control centre</h2>
          <p>Route-first package review with clear Driver, vehicle, seat and booking performance.</p>
        </div>
        <button className="secondaryButton" onClick={() => void load()} disabled={busy}><RefreshCw size={15} className={busy ? 'spin' : ''} /> Refresh</button>
      </section>

      {error && <ErrorBox message={error} />}

      <div className="tourMetricGrid">
        <TourMetric icon={MapPinned} label="Total packages" value={String(rows.length)} tone="green" />
        <TourMetric icon={ShieldCheck} label="Pending review" value={String(pending.length)} tone="amber" />
        <TourMetric icon={UsersRound} label="Seats booked" value={String(seats)} tone="blue" />
        <TourMetric icon={TicketCheck} label="Occupancy" value={`${occupancy}%`} tone="violet" />
        <TourMetric icon={CircleDollarSign} label="Gross value" value={money(gross)} tone="emerald" />
      </div>

      <section className="panel tourWorkspace">
        <div className="tourToolbar">
          <label className="tourSearch"><Search size={15} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search route, package, Driver or registration" /></label>
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option value="">All statuses</option><option>Draft</option><option>PendingApproval</option><option>Active</option><option>Paused</option><option>Rejected</option><option>Suspended</option>
          </select>
          <span className="resultCount">{filtered.length} result(s)</span>
        </div>

        {pending.length > 0 && (
          <div className="tourReviewSection">
            <div className="sectionHeading"><div><span>REVIEW QUEUE</span><h3>Packages awaiting approval</h3></div><strong>{pending.length}</strong></div>
            <div className="tourReviewGrid">
              {pending.map((row) => (
                <button className="tourReviewCard" key={row.id} onClick={() => setSelected(row)}>
                  <div className="tourRoute"><MapPinned size={16} /><strong>{row.startingCity}</strong><span>→</span><strong>{row.destination}</strong></div>
                  <h4>{row.title}</h4>
                  <div className="tourReviewMeta"><span><CalendarDays size={14} /> {when(row.departureAt)}</span><span><CarFront size={14} /> {row.registrationNumber}</span></div>
                  <div className="tourReviewBottom"><Badge value={row.status} /><strong>{money(row.pricePerSeat)} / seat</strong></div>
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="sectionHeading inventoryHeading"><div><span>LIVE INVENTORY</span><h3>Marketplace packages</h3></div></div>
        {busy ? <Loading /> : filtered.length === 0 ? <Empty title="No packages found" /> : (
          <div className="tourTableWrap">
            <table>
              <thead><tr><th>Route & package</th><th>Departure</th><th>Status</th><th>Driver & vehicle</th><th>Seat inventory</th><th>Bookings</th><th>Revenue</th></tr></thead>
              <tbody>{filtered.map((row) => {
                const freePct = row.totalSeats ? Math.round((row.availableSeats / row.totalSeats) * 100) : 0;
                return <tr key={row.id}>
                  <td><div className="routePrimary"><MapPinned size={15} /><strong>{row.startingCity} → {row.destination}</strong></div><small>{row.title}</small></td>
                  <td>{when(row.departureAt)}{row.returnAt && <small>Return {when(row.returnAt)}</small>}</td>
                  <td><Badge value={row.status} /></td>
                  <td><strong>{row.driverName}</strong><small>{row.vehicle} · {row.registrationNumber}</small></td>
                  <td><div className="seatLine"><strong>{row.availableSeats} free</strong><span>{row.totalSeats} total</span></div><div className="seatBar"><i style={{ width: `${freePct}%` }} /></div></td>
                  <td><strong>{row.bookingCount}</strong><small>{row.seatsBooked} seats sold</small></td>
                  <td><strong>{money(row.grossRevenue)}</strong><small>{money(row.pricePerSeat)} / seat</small></td>
                </tr>;
              })}</tbody>
            </table>
          </div>
        )}
      </section>

      {selected && <Review row={selected} close={() => setSelected(null)} reload={load} />}
    </AdminFrame>
  );
}

function TourMetric({ icon: Icon, label, value, tone }: { icon: typeof MapPinned; label: string; value: string; tone: string }) {
  return <article className={`tourMetric tourMetric--${tone}`}><div><Icon size={18} /></div><span>{label}</span><strong>{value}</strong></article>;
}

function Review({ row, close, reload }: { row: PendingRow; close: () => void; reload: () => void }) {
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  async function review(decision: string) {
    setBusy(true);
    try {
      await apiFetch(`/api/v1/admin/packages/${row.id}/review`, { method: 'PUT', body: JSON.stringify({ decision, notes }) });
      close();
      await reload();
    } finally { setBusy(false); }
  }
  return <Modal title={row.title} onClose={close}><div className="detailGrid"><div><span>Route</span><strong>{row.startingCity} → {row.destination}</strong></div><div><span>Departure</span><strong>{when(row.departureAt)}</strong></div><div><span>Inventory</span><strong>{row.availableSeats}/{row.totalSeats} seats</strong></div><div><span>Per seat</span><strong>{money(row.pricePerSeat)}</strong></div><div><span>Whole vehicle</span><strong>{money(row.wholeVehiclePrice)}</strong></div><div><span>Driver</span><strong>{row.driverName}</strong></div></div><label className="field"><span>Review notes</span><textarea rows={4} value={notes} onChange={(event) => setNotes(event.target.value)} /></label><div className="buttonRow"><button disabled={busy} className="primaryButton" onClick={() => void review('approve')}>Approve & activate</button><button disabled={busy} className="secondaryButton" onClick={() => void review('changes')}>Request changes</button><button disabled={busy} className="dangerButton" onClick={() => void review('reject')}>Reject</button></div></Modal>;
}
