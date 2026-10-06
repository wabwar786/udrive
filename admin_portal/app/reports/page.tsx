'use client';

import { Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { ArrowDown, ArrowUp, BarChart3, Download, Printer, RefreshCw, Search } from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Badge, ErrorBox, Loading } from '../components/ui';
import { apiFetch } from '../lib/admin-api';
import { ReportChart, type ChartData } from './report-chart';

/**
 * Reports Centre.
 *
 * One page for every report. The left column lists the reports this person
 * has been given (SuperAdmin: all of them); the right shows the chosen one in
 * the same shape every time — filters, tiles compared with the period before,
 * one chart, and the full table with totals, CSV export and print.
 *
 * The server decides what may be seen: the report list, the areas in the
 * picker and every row come from it already limited to this person's reports
 * and areas.
 */

type Filter = { key: string; label: string; options: string[]; default: string };
type CatalogItem = {
  key: string;
  category: string;
  title: string;
  description: string;
  usesDates: boolean;
  trend: boolean;
  filters: Filter[];
};
type AreaOption = { id: string; name: string; selectable: boolean; tehsils: { id: string; name: string }[] };
type Catalog = {
  superAdmin: boolean;
  allAreas: boolean;
  scopeLabel: string;
  categories: string[];
  reports: CatalogItem[];
  areas: AreaOption[];
};
type Tile = { key: string; label: string; format: string; value: number | null; previous: number | null };
type Column = { key: string; label: string; format: string; total: string | null };
type Result = {
  key: string;
  category: string;
  title: string;
  description: string;
  from: string;
  to: string;
  previousFrom: string;
  previousTo: string;
  scopeLabel: string;
  tiles: Tile[];
  chart: ChartData | null;
  columns: Column[];
  rows: Record<string, unknown>[];
  totals: Record<string, unknown>;
  truncated: boolean;
};

const PAGE = 50;
const NUMERIC = new Set(['int', 'money', 'pct', 'num', 'rating', 'minutes', 'hours']);

// ───────────────────────────────────────────── dates (Pakistan days)

function pkToday() {
  const now = new Date(Date.now() + 5 * 3600 * 1000);
  return now.toISOString().slice(0, 10);
}
function shift(day: string, days: number) {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
function monthStart(day: string, back = 0) {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() - back);
  return d.toISOString().slice(0, 10);
}
const PRESETS: { key: string; label: string; range: () => [string, string] }[] = [
  { key: 'today', label: 'Today', range: () => [pkToday(), pkToday()] },
  { key: 'yesterday', label: 'Yesterday', range: () => [shift(pkToday(), -1), shift(pkToday(), -1)] },
  { key: '7d', label: '7 days', range: () => [shift(pkToday(), -6), pkToday()] },
  { key: 'month', label: 'This month', range: () => [monthStart(pkToday()), pkToday()] },
  { key: 'last', label: 'Last month', range: () => [monthStart(pkToday(), 1), shift(monthStart(pkToday()), -1)] },
  { key: '90d', label: '90 days', range: () => [shift(pkToday(), -89), pkToday()] },
];
function niceDate(day: string) {
  const d = new Date(`${day}T00:00:00Z`);
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
}

// ───────────────────────────────────────────── formatting

function formatValue(value: unknown, format: string): string {
  if (value === null || value === undefined || value === '') return '—';
  if (format === 'hour') {
    const h = Number(value);
    return Number.isFinite(h) ? `${String(Math.round(h)).padStart(2, '0')}:00` : String(value);
  }
  if (!NUMERIC.has(format)) return String(value);
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n)) return String(value);
  switch (format) {
    case 'int':
      return Math.round(n).toLocaleString('en-PK');
    case 'money':
      return `PKR ${Math.round(n).toLocaleString('en-PK')}`;
    case 'pct':
      return `${n.toFixed(1)}%`;
    case 'rating':
      return `${n.toFixed(2)} ★`;
    case 'minutes':
      return n >= 60 ? `${Math.floor(n / 60)} h ${Math.round(n % 60)} min` : `${n.toFixed(n < 10 ? 1 : 0)} min`;
    case 'hours':
      return `${n.toFixed(1)} h`;
    default:
      return n.toLocaleString('en-PK', { maximumFractionDigits: 1 });
  }
}

/** Tiles: large money shortened so it fits on one line (PKR 3.42M). */
function tileValue(value: number | null, format: string) {
  if (format === 'money' && value !== null && Math.abs(value) >= 1_000_000) {
    return `PKR ${(value / 1_000_000).toFixed(2)}M`;
  }
  return formatValue(value, format);
}

/** Raw value for CSV: numbers unformatted so a spreadsheet can add them up. */
function csvValue(value: unknown, format: string) {
  if (value === null || value === undefined) return '';
  if (NUMERIC.has(format)) {
    const n = Number(value);
    return Number.isFinite(n) ? String(Math.round(n * 100) / 100) : '';
  }
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function change(tile: Tile) {
  if (tile.value === null || tile.previous === null || tile.format === 'hour') return null;
  if (tile.format === 'pct') {
    const diff = tile.value - tile.previous;
    return { up: diff > 0, flat: Math.abs(diff) < 0.05, text: `${Math.abs(diff).toFixed(1)} pt` };
  }
  if (tile.format === 'rating') {
    const diff = tile.value - tile.previous;
    return { up: diff > 0, flat: Math.abs(diff) < 0.005, text: Math.abs(diff).toFixed(2) };
  }
  if (tile.previous === 0) return tile.value === 0 ? { up: false, flat: true, text: '0%' } : { up: true, flat: false, text: 'new' };
  const pct = ((tile.value - tile.previous) / Math.abs(tile.previous)) * 100;
  return { up: pct > 0, flat: Math.abs(pct) < 0.5, text: `${Math.abs(pct).toFixed(Math.abs(pct) < 10 ? 1 : 0)}%` };
}

// ───────────────────────────────────────────── page

export default function ReportsPage() {
  return (
    <Suspense fallback={<AdminFrame title="Reports Centre"><Loading /></AdminFrame>}>
      <ReportsCentre />
    </Suspense>
  );
}

function ReportsCentre() {
  const router = useRouter();
  const params = useSearchParams();
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [catalogError, setCatalogError] = useState('');
  const [search, setSearch] = useState('');

  const [from, setFrom] = useState(() => monthStart(pkToday()));
  const [to, setTo] = useState(() => pkToday());
  const [preset, setPreset] = useState('month');
  const [area, setArea] = useState('');
  const [group, setGroup] = useState('day');
  const [filters, setFilters] = useState<Record<string, string>>({});

  const [result, setResult] = useState<Result | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const [tableSearch, setTableSearch] = useState('');
  const [sort, setSort] = useState<{ key: string; desc: boolean } | null>(null);
  const [page, setPage] = useState(0);

  useEffect(() => {
    apiFetch<Catalog>('/api/v1/admin/reports/catalog')
      .then(setCatalog)
      .catch((e) => setCatalogError(e instanceof Error ? e.message : 'Reports could not be loaded.'));
  }, []);

  const selectedKey = params.get('r') ?? catalog?.reports[0]?.key ?? '';
  const selected = catalog?.reports.find((r) => r.key === selectedKey) ?? catalog?.reports[0];

  function choose(key: string) {
    setFilters({});
    setSort(null);
    setTableSearch('');
    setPage(0);
    router.replace(`/reports?r=${encodeURIComponent(key)}`);
  }

  const run = useCallback(async () => {
    if (!selected) return;
    setLoading(true);
    setError('');
    const q = new URLSearchParams({ from, to });
    if (area) q.set('area', area);
    if (selected.trend) q.set('gb', group);
    for (const f of selected.filters) {
      const value = filters[f.key] ?? f.default;
      if (value) q.set(f.key, value);
    }
    try {
      setResult(await apiFetch<Result>(`/api/v1/admin/reports/run/${encodeURIComponent(selected.key)}?${q}`));
    } catch (e) {
      setResult(null);
      setError(e instanceof Error ? e.message : 'The report could not be run.');
    } finally {
      setLoading(false);
    }
  }, [selected, from, to, area, group, filters]);

  useEffect(() => {
    void run();
  }, [run]);

  useEffect(() => setPage(0), [tableSearch, sort, result]);

  const grouped = useMemo(() => {
    const term = search.trim().toLowerCase();
    const list = (catalog?.reports ?? []).filter(
      (r) => !term || r.title.toLowerCase().includes(term) || r.category.toLowerCase().includes(term),
    );
    return (catalog?.categories ?? []).map((c) => ({ category: c, reports: list.filter((r) => r.category === c) }))
      .filter((g) => g.reports.length);
  }, [catalog, search]);

  const formatOf = useCallback(
    (key: string) => result?.columns.find((c) => c.key === key)?.format ?? result?.tiles.find((t) => t.key === key)?.format ?? 'num',
    [result],
  );

  const rows = useMemo(() => {
    if (!result) return [];
    const term = tableSearch.trim().toLowerCase();
    let list = term
      ? result.rows.filter((r) => result.columns.some((c) => String(r[c.key] ?? '').toLowerCase().includes(term)))
      : result.rows;
    if (sort) {
      const col = result.columns.find((c) => c.key === sort.key);
      const numeric = col ? NUMERIC.has(col.format) : false;
      list = [...list].sort((a, b) => {
        const x = a[sort.key];
        const y = b[sort.key];
        if (x === null || x === undefined) return 1;
        if (y === null || y === undefined) return -1;
        const cmp = numeric ? Number(x) - Number(y) : String(x).localeCompare(String(y));
        return sort.desc ? -cmp : cmp;
      });
    }
    return list;
  }, [result, tableSearch, sort]);

  function exportCsv() {
    if (!result) return;
    const head = result.columns.map((c) => csvValue(c.label, 'text')).join(',');
    const body = rows.map((r) => result.columns.map((c) => csvValue(r[c.key], c.format)).join(','));
    const totals = result.columns.map((c) => csvValue(result.totals[c.key], c.format)).join(',');
    const meta = [
      csvValue(`${result.title} · ${result.scopeLabel} · ${result.from} to ${result.to}`, 'text'),
      '',
    ];
    const text = '﻿' + [...meta, head, ...body, totals].join('\r\n');
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' }));
    link.download = `udrive-${result.key.replace(/\./g, '-')}-${result.from}-to-${result.to}.csv`;
    link.click();
    URL.revokeObjectURL(link.href);
  }

  function pickPreset(key: string) {
    const p = PRESETS.find((x) => x.key === key);
    if (!p) return;
    const [a, b] = p.range();
    setPreset(key);
    setFrom(a);
    setTo(b);
  }

  // ─────────────── render

  if (catalogError) {
    return <AdminFrame title="Reports Centre"><ErrorBox message={catalogError} /></AdminFrame>;
  }
  if (!catalog) {
    return <AdminFrame title="Reports Centre"><section className="panel"><Loading /></section></AdminFrame>;
  }
  if (catalog.reports.length === 0) {
    return (
      <AdminFrame title="Reports Centre" subtitle="Reports given to you appear here.">
        <section className="panel">
          <div className="empty">
            <BarChart3 size={40} />
            <h3>No reports have been given to you yet</h3>
            <p>Ask an admin to tick the reports you need on your Team page.</p>
          </div>
        </section>
      </AdminFrame>
    );
  }

  const pageRows = rows.slice(page * PAGE, page * PAGE + PAGE);
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));

  return (
    <AdminFrame
      title="Reports Centre"
      subtitle={`${catalog.reports.length} reports · ${catalog.superAdmin ? 'SuperAdmin — every area' : catalog.scopeLabel}`}
    >
      <div className="reportsLayout">
        <aside className="reportsCatalog">
          <label className="searchBox">
            <Search />
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search reports…" />
          </label>
          {grouped.map((g) => (
            <section key={g.category}>
              <h4>{g.category}</h4>
              {g.reports.map((r) => (
                <button key={r.key} type="button" className={r.key === selected?.key ? 'active' : ''} onClick={() => choose(r.key)}>
                  {r.title}
                </button>
              ))}
            </section>
          ))}
          {grouped.length === 0 && <p className="reportsMuted">No report matches “{search}”.</p>}
        </aside>

        <main className="reportsMain">
          {selected && (
            <>
              <header className="reportsHead">
                <div>
                  <small>{selected.category}</small>
                  <h2>{selected.title}</h2>
                  <p>{selected.description}</p>
                </div>
                <div className="reportsActions">
                  <button type="button" className="secondaryButton" onClick={() => void run()} disabled={loading}>
                    <RefreshCw className={loading ? 'spin' : ''} /> Refresh
                  </button>
                  <button type="button" className="secondaryButton" onClick={() => window.print()} disabled={!result}>
                    <Printer /> Print
                  </button>
                  <button type="button" className="primaryButton" onClick={exportCsv} disabled={!result || rows.length === 0}>
                    <Download /> Export CSV
                  </button>
                </div>
              </header>

              <div className="reportsFilters">
                {selected.usesDates ? (
                  <>
                    {PRESETS.map((p) => (
                      <button key={p.key} type="button" className={`reportsChip ${preset === p.key ? 'on' : ''}`} onClick={() => pickPreset(p.key)}>
                        {p.label}
                      </button>
                    ))}
                    <label className="reportsDate">
                      <input type="date" value={from} max={to} onChange={(e) => { setPreset(''); setFrom(e.target.value); }} />
                      <span>–</span>
                      <input type="date" value={to} min={from} max={pkToday()} onChange={(e) => { setPreset(''); setTo(e.target.value); }} />
                    </label>
                  </>
                ) : (
                  <span className="reportsChip on">As of today</span>
                )}
                <select className="reportsSelect" value={area} onChange={(e) => setArea(e.target.value)} aria-label="Area">
                  <option value="">{catalog.allAreas ? 'All areas' : 'All my areas'}</option>
                  {catalog.areas.map((d) => (
                    <optgroup key={d.id} label={d.name}>
                      {d.selectable && <option value={d.id}>{d.name} — whole district</option>}
                      {d.tehsils.map((t) => (
                        <option key={t.id} value={t.id}>{d.name} › {t.name}</option>
                      ))}
                    </optgroup>
                  ))}
                </select>
                {selected.trend && (
                  <select className="reportsSelect" value={group} onChange={(e) => setGroup(e.target.value)} aria-label="Group by">
                    <option value="day">By day</option>
                    <option value="week">By week</option>
                    <option value="month">By month</option>
                  </select>
                )}
                {selected.filters.map((f) => (
                  <select key={f.key} className="reportsSelect" aria-label={f.label}
                    value={filters[f.key] ?? f.default}
                    onChange={(e) => setFilters((cur) => ({ ...cur, [f.key]: e.target.value }))}>
                    {!f.options.includes(f.default) && <option value="">{f.label}: all</option>}
                    {f.options.map((o) => (
                      <option key={o} value={o}>{f.label}: {o}</option>
                    ))}
                  </select>
                ))}
                <span className="reportsScope">Scope: {result?.scopeLabel ?? '…'}</span>
              </div>

              {error && <div className="errorBox" style={{ margin: '0 0 14px' }}>{error}</div>}
              {loading && !result && <section className="panel"><Loading /></section>}

              {result && result.key === selected.key && (
                <div className={loading ? 'reportsBusy' : ''}>
                  <section className="reportTiles">
                    {result.tiles.map((t) => {
                      const c = selected.usesDates ? change(t) : null;
                      return (
                        <article key={t.key} className="reportTile">
                          <span>{t.label}</span>
                          <strong title={formatValue(t.value, t.format)}>{tileValue(t.value, t.format)}</strong>
                          {c ? (
                            <small>
                              {c.flat ? '■' : c.up ? <ArrowUp size={12} /> : <ArrowDown size={12} />} {c.flat ? 'no change' : c.text}
                              <em> vs previous</em>
                            </small>
                          ) : (
                            <small>&nbsp;</small>
                          )}
                        </article>
                      );
                    })}
                  </section>
                  {selected.usesDates && (
                    <p className="reportsMuted reportsPeriod">
                      {niceDate(result.from)} – {niceDate(result.to)} · compared with {niceDate(result.previousFrom)} – {niceDate(result.previousTo)}
                    </p>
                  )}

                  {result.chart && (
                    <section className="panel">
                      <header className="panelHeader">
                        <div>
                          <h2>{result.chart.title}</h2>
                          <p>Hover for exact figures. The table below has every row.</p>
                        </div>
                      </header>
                      <ReportChart chart={result.chart} formatOf={formatOf} format={formatValue} />
                    </section>
                  )}

                  <section className="panel">
                    <header className="panelHeader">
                      <div>
                        <h2>{result.title}</h2>
                        <p>
                          {rows.length.toLocaleString('en-PK')} row{rows.length === 1 ? '' : 's'}
                          {result.truncated ? ' · showing the first 2,000 — narrow the dates or area for the rest' : ''}
                        </p>
                      </div>
                      <label className="searchBox">
                        <Search />
                        <input value={tableSearch} onChange={(e) => setTableSearch(e.target.value)} placeholder="Search in table" />
                      </label>
                    </header>
                    {rows.length === 0 ? (
                      <div className="empty"><h3>Nothing in this period</h3><p>Try a longer period or another area.</p></div>
                    ) : (
                      <div className="tableWrap">
                        <table className="reportTable">
                          <thead>
                            <tr>
                              {result.columns.map((c) => (
                                <th key={c.key} className={NUMERIC.has(c.format) ? 'n' : ''}
                                  onClick={() => setSort((s) => (s?.key === c.key ? { key: c.key, desc: !s.desc } : { key: c.key, desc: NUMERIC.has(c.format) }))}>
                                  {c.label}
                                  {sort?.key === c.key ? (sort.desc ? ' ↓' : ' ↑') : ''}
                                </th>
                              ))}
                            </tr>
                          </thead>
                          <tbody>
                            {pageRows.map((r, i) => (
                              <tr key={i}>
                                {result.columns.map((c) => (
                                  <td key={c.key} className={NUMERIC.has(c.format) ? 'n' : ''}>
                                    {c.format === 'badge' ? <Badge value={r[c.key]} /> : formatValue(r[c.key], c.format)}
                                  </td>
                                ))}
                              </tr>
                            ))}
                          </tbody>
                          <tfoot>
                            <tr>
                              {result.columns.map((c) => (
                                <td key={c.key} className={NUMERIC.has(c.format) ? 'n' : ''}>
                                  {result.totals[c.key] === undefined ? '' : NUMERIC.has(c.format)
                                    ? `${c.total === 'avg' ? 'avg ' : ''}${formatValue(result.totals[c.key], c.format)}`
                                    : String(result.totals[c.key] ?? '')}
                                </td>
                              ))}
                            </tr>
                          </tfoot>
                        </table>
                      </div>
                    )}
                    {pages > 1 && (
                      <div className="pager">
                        <span>{rows.length.toLocaleString('en-PK')} rows</span>
                        <div>
                          <button type="button" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>Previous</button>
                          <strong>Page {page + 1} of {pages}</strong>
                          <button type="button" disabled={page >= pages - 1} onClick={() => setPage((p) => p + 1)}>Next</button>
                        </div>
                      </div>
                    )}
                  </section>
                </div>
              )}
            </>
          )}
        </main>
      </div>
    </AdminFrame>
  );
}
