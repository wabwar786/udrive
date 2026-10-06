'use client';

import { useMemo, useState } from 'react';

/**
 * Charts for the Reports Centre — plain SVG and HTML, no chart library.
 *
 * Rules kept here (see the data-viz method this follows):
 *  - one scale per chart: every chart's series share a unit, so there is never
 *    a second y-axis;
 *  - series colours come from one validated categorical order and are given by
 *    series position, never cycled; anything past the fifth slice of a donut
 *    folds into "Other";
 *  - thin marks, rounded bar ends on the baseline, a 2px gap between stacked
 *    segments, a recessive grid;
 *  - values and labels are written in text colours, never in the series colour;
 *  - every chart has a hover read-out, and the table under it is the full data.
 */

export type ChartSeries = { key: string; label: string; kind: string };
export type ChartData = {
  type: string;
  title: string;
  labelKey: string;
  series: ChartSeries[];
  points: Record<string, unknown>[];
};

/** Validated categorical order (blue, orange, aqua, yellow, magenta) — light surface. */
const SERIES = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4'];
const OTHER = '#9aa6a1';
const INK = '#12231e';
const INK_2 = '#5d716a';
const GRID = '#e6eeeb';

export type Formatter = (value: unknown, format: string) => string;

function num(value: unknown): number {
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/** A round axis maximum: 1, 2, 2.5 or 5 times a power of ten. */
function niceMax(value: number) {
  if (value <= 0) return 1;
  const power = 10 ** Math.floor(Math.log10(value));
  for (const step of [1, 2, 2.5, 5, 10]) {
    if (value <= step * power) return step * power;
  }
  return 10 * power;
}

/** Short axis numbers: 1.2K, 3.4M. */
function shortNumber(value: number) {
  const abs = Math.abs(value);
  if (abs >= 1_000_000) return `${(value / 1_000_000).toFixed(abs >= 10_000_000 ? 0 : 1)}M`;
  if (abs >= 1_000) return `${(value / 1_000).toFixed(abs >= 10_000 ? 0 : 1)}K`;
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function label(point: Record<string, unknown>, key: string) {
  const value = point[key];
  return value === null || value === undefined || value === '' ? '—' : String(value);
}

export function ReportChart({
  chart,
  formatOf,
  format,
}: {
  chart: ChartData;
  /** The display format of a series (taken from the table column of the same key). */
  formatOf: (key: string) => string;
  format: Formatter;
}) {
  if (!chart.points.length) {
    return <div className="reportChartEmpty">Nothing to draw for this period.</div>;
  }
  switch (chart.type) {
    case 'donut':
      return <Donut chart={chart} formatOf={formatOf} format={format} />;
    case 'hbar':
      return <HBars chart={chart} formatOf={formatOf} format={format} />;
    case 'heatmap':
      return <Heatmap chart={chart} />;
    case 'line':
      return <Columns chart={chart} formatOf={formatOf} format={format} mode="line" />;
    case 'stacked':
      return <Columns chart={chart} formatOf={formatOf} format={format} mode="stacked" />;
    default:
      return <Columns chart={chart} formatOf={formatOf} format={format} mode="bar" />;
  }
}

function Legend({ series }: { series: ChartSeries[] }) {
  if (series.length < 2) return null;
  return (
    <div className="reportLegend">
      {series.map((s, i) => (
        <span key={s.key}>
          <i style={{ background: SERIES[i % SERIES.length] }} />
          {s.label}
        </span>
      ))}
    </div>
  );
}

// ─────────────────────────────────────────── vertical: line, bar, stacked

function Columns({
  chart,
  formatOf,
  format,
  mode,
}: {
  chart: ChartData;
  formatOf: (key: string) => string;
  format: Formatter;
  mode: 'line' | 'bar' | 'stacked';
}) {
  const [hover, setHover] = useState<number | null>(null);
  const W = 960;
  const H = 260;
  const pad = { l: 56, r: 16, t: 14, b: 44 };
  const plotW = W - pad.l - pad.r;
  const plotH = H - pad.t - pad.b;
  const points = chart.points;
  const series = chart.series;
  const unit = formatOf(series[0]?.key ?? '');

  const max = useMemo(() => {
    let m = 0;
    for (const p of points) {
      if (mode === 'stacked') m = Math.max(m, series.reduce((sum, s) => sum + Math.max(0, num(p[s.key])), 0));
      else for (const s of series) m = Math.max(m, num(p[s.key]));
    }
    return niceMax(m);
  }, [points, series, mode]);

  const band = plotW / Math.max(points.length, 1);
  const y = (v: number) => pad.t + plotH - (Math.max(0, v) / max) * plotH;
  const x = (i: number) => pad.l + band * i + band / 2;
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => f * max);
  const labelEvery = Math.max(1, Math.ceil(points.length / 12));

  const barGroupW = Math.min(band * 0.72, 56);
  const barW = mode === 'bar' ? Math.max(3, (barGroupW - (series.length - 1) * 2) / series.length) : barGroupW;

  function roundedTop(x0: number, y0: number, w: number, h: number) {
    const r = Math.min(4, w / 2, h);
    if (h <= 0) return '';
    return `M${x0},${y0 + h} V${y0 + r} Q${x0},${y0} ${x0 + r},${y0} H${x0 + w - r} Q${x0 + w},${y0} ${x0 + w},${y0 + r} V${y0 + h} Z`;
  }

  return (
    <div className="reportChart">
      <Legend series={series} />
      <div className="reportChartPlot" onMouseLeave={() => setHover(null)}>
        <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={chart.title} preserveAspectRatio="none">
          {ticks.map((t) => (
            <g key={t}>
              <line x1={pad.l} x2={W - pad.r} y1={y(t)} y2={y(t)} stroke={GRID} strokeWidth={1} />
              <text x={pad.l - 8} y={y(t) + 4} textAnchor="end" fontSize={11} fill={INK_2}>
                {shortNumber(t)}
              </text>
            </g>
          ))}
          {points.map((p, i) =>
            i % labelEvery === 0 ? (
              <text key={i} x={x(i)} y={H - pad.b + 18} textAnchor="middle" fontSize={11} fill={INK_2}>
                {label(p, chart.labelKey).length > 14 ? `${label(p, chart.labelKey).slice(0, 13)}…` : label(p, chart.labelKey)}
              </text>
            ) : null,
          )}
          {hover !== null && (
            <rect x={pad.l + band * hover} y={pad.t} width={band} height={plotH} fill="#0b1b330a" />
          )}

          {mode === 'line' &&
            series.map((s, si) => {
              const path = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i)},${y(num(p[s.key]))}`).join(' ');
              return (
                <g key={s.key}>
                  <path d={path} fill="none" stroke={SERIES[si % SERIES.length]} strokeWidth={2} strokeLinejoin="round" />
                  {points.length <= 40 &&
                    points.map((p, i) => (
                      <circle key={i} cx={x(i)} cy={y(num(p[s.key]))} r={hover === i ? 5 : 3.5}
                        fill={SERIES[si % SERIES.length]} stroke="#fff" strokeWidth={2} />
                    ))}
                </g>
              );
            })}

          {mode === 'bar' &&
            points.map((p, i) =>
              series.map((s, si) => {
                const v = num(p[s.key]);
                const x0 = x(i) - barGroupW / 2 + si * (barW + 2);
                return (
                  <path key={`${i}-${s.key}`} d={roundedTop(x0, y(v), barW, pad.t + plotH - y(v))}
                    fill={SERIES[si % SERIES.length]} />
                );
              }),
            )}

          {mode === 'stacked' &&
            points.map((p, i) => {
              let base = 0;
              return series.map((s, si) => {
                const v = Math.max(0, num(p[s.key]));
                const top = y(base + v);
                const h = y(base) - top - (si > 0 ? 2 : 0);
                base += v;
                const last = si === series.length - 1;
                return h > 0 ? (
                  last ? (
                    <path key={`${i}-${s.key}`} d={roundedTop(x(i) - barW / 2, top, barW, h)} fill={SERIES[si % SERIES.length]} />
                  ) : (
                    <rect key={`${i}-${s.key}`} x={x(i) - barW / 2} y={top} width={barW} height={h} fill={SERIES[si % SERIES.length]} />
                  )
                ) : null;
              });
            })}

          {points.map((_, i) => (
            <rect key={`hit-${i}`} x={pad.l + band * i} y={pad.t} width={band} height={plotH} fill="transparent"
              onMouseEnter={() => setHover(i)} />
          ))}
        </svg>
        {hover !== null && points[hover] && (
          <div className="reportTooltip" style={{ left: `${(x(hover) / W) * 100}%` }}>
            <strong>{label(points[hover], chart.labelKey)}</strong>
            {series.map((s, si) => (
              <span key={s.key}>
                <i style={{ background: SERIES[si % SERIES.length] }} />
                {s.label}: <b>{format(points[hover][s.key], formatOf(s.key) || unit)}</b>
              </span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────── horizontal bars (ranked)

function HBars({ chart, formatOf, format }: { chart: ChartData; formatOf: (key: string) => string; format: Formatter }) {
  const s = chart.series[0];
  const max = Math.max(...chart.points.map((p) => num(p[s.key])), 0) || 1;
  return (
    <div className="reportHBars">
      {chart.points.map((p, i) => (
        <div key={i} className="reportHBar" title={`${label(p, chart.labelKey)}: ${format(p[s.key], formatOf(s.key))}`}>
          <span className="reportHBarLabel">{label(p, chart.labelKey)}</span>
          <span className="reportHBarTrack">
            <i style={{ width: `${(Math.max(0, num(p[s.key])) / max) * 100}%`, background: SERIES[0] }} />
          </span>
          <span className="reportHBarValue">{format(p[s.key], formatOf(s.key))}</span>
        </div>
      ))}
    </div>
  );
}

// ─────────────────────────────────────────── donut (part of a whole)

function Donut({ chart, formatOf, format }: { chart: ChartData; formatOf: (key: string) => string; format: Formatter }) {
  const [hover, setHover] = useState<number | null>(null);
  const s = chart.series[0];
  const sorted = [...chart.points].sort((a, b) => num(b[s.key]) - num(a[s.key]));
  const top = sorted.slice(0, 5).map((p) => ({ name: label(p, chart.labelKey), value: Math.max(0, num(p[s.key])) }));
  const rest = sorted.slice(5).reduce((sum, p) => sum + Math.max(0, num(p[s.key])), 0);
  const slices = rest > 0 ? [...top, { name: 'Other', value: rest }] : top;
  const total = slices.reduce((sum, x) => sum + x.value, 0) || 1;

  const R = 90;
  const r = 58;
  const C = 110;
  let angle = -Math.PI / 2;
  const arcs = slices.map((slice, i) => {
    const sweep = (slice.value / total) * Math.PI * 2;
    const a0 = angle;
    const a1 = angle + Math.max(sweep - 0.02, 0.0001);
    angle += sweep;
    const large = a1 - a0 > Math.PI ? 1 : 0;
    const p = (rad: number, radius: number) => `${C + radius * Math.cos(rad)},${C + radius * Math.sin(rad)}`;
    const d = slices.length === 1
      ? `M${C - R},${C} A${R},${R} 0 1 1 ${C + R},${C} A${R},${R} 0 1 1 ${C - R},${C} M${C - r},${C} A${r},${r} 0 1 0 ${C + r},${C} A${r},${r} 0 1 0 ${C - r},${C} Z`
      : `M${p(a0, R)} A${R},${R} 0 ${large} 1 ${p(a1, R)} L${p(a1, r)} A${r},${r} 0 ${large} 0 ${p(a0, r)} Z`;
    return { d, color: slice.name === 'Other' ? OTHER : SERIES[i % SERIES.length], slice };
  });

  const shown = hover === null ? null : arcs[hover]?.slice;
  return (
    <div className="reportDonut">
      <svg viewBox="0 0 220 220" role="img" aria-label={chart.title} onMouseLeave={() => setHover(null)}>
        {arcs.map((a, i) => (
          <path key={i} d={a.d} fill={a.color} fillRule="evenodd" opacity={hover === null || hover === i ? 1 : 0.45}
            onMouseEnter={() => setHover(i)} />
        ))}
        <text x={C} y={C - 4} textAnchor="middle" fontSize={20} fontWeight={800} fill={INK}>
          {format(shown ? shown.value : total, formatOf(s.key))}
        </text>
        <text x={C} y={C + 16} textAnchor="middle" fontSize={11} fill={INK_2}>
          {shown ? shown.name : 'Total'}
        </text>
      </svg>
      <ul>
        {arcs.map((a, i) => (
          <li key={i} onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)}>
            <i style={{ background: a.color }} />
            <span>{a.slice.name}</span>
            <b>{format(a.slice.value, formatOf(s.key))}</b>
            <small>{((a.slice.value / total) * 100).toFixed(1)}%</small>
          </li>
        ))}
      </ul>
    </div>
  );
}

// ─────────────────────────────────────────── heatmap (day × hour)

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/** One hue, light to dark: magnitude only. */
function heat(f: number) {
  const from = [236, 243, 252];
  const to = [21, 76, 145];
  const c = from.map((v, i) => Math.round(v + (to[i] - v) * f));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

function Heatmap({ chart }: { chart: ChartData }) {
  const grid = new Map<string, number>();
  let max = 0;
  for (const p of chart.points) {
    const value = num(p.value);
    grid.set(`${num(p.dow)}-${num(p.hour)}`, value);
    max = Math.max(max, value);
  }
  return (
    <div className="reportHeatmap">
      <div className="reportHeatHours">
        <span />
        {Array.from({ length: 24 }, (_, h) => (
          <span key={h}>{h % 3 === 0 ? h : ''}</span>
        ))}
      </div>
      {DAYS.map((day, d) => (
        <div key={day} className="reportHeatRow">
          <span>{day}</span>
          {Array.from({ length: 24 }, (_, h) => {
            const v = grid.get(`${d + 1}-${h}`) ?? 0;
            return <i key={h} style={{ background: v === 0 ? '#f4f7f6' : heat(max ? 0.15 + 0.85 * (v / max) : 0) }}
              title={`${day} ${String(h).padStart(2, '0')}:00 — ${v} requests`} />;
          })}
        </div>
      ))}
      <div className="reportHeatScale">
        <span>Fewer</span>
        {[0.15, 0.36, 0.57, 0.78, 1].map((f) => <i key={f} style={{ background: heat(f) }} />)}
        <span>More</span>
      </div>
    </div>
  );
}
