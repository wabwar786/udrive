'use client';

import { useCallback, useEffect, useState } from 'react';
import { MapPin, RefreshCw } from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Empty, ErrorBox, Loading, Stat } from '../components/ui';
import { apiFetch, isSuperAdmin, hasRole, when } from '../lib/admin-api';

type Count = { name: string; count: number };
type Summary = {
  days: number;
  devices: number;
  activeToday: number;
  newInstalls: number;
  sessions: number;
  guestPercent: number;
  geoConfigured: boolean;
  cities: Count[];
  versions: Count[];
  phones: Count[];
  networks: Count[];
};
type Device = {
  installId: string;
  userId?: string | null;
  userName?: string | null;
  userPhone?: string | null;
  role?: string | null;
  manufacturer?: string | null;
  model?: string | null;
  osVersion?: string | null;
  sdk?: number | null;
  appVersion?: string | null;
  buildNumber?: string | null;
  flavor?: string | null;
  locale?: string | null;
  timezone?: string | null;
  screen?: string | null;
  lastIp?: string | null;
  lastCity?: string | null;
  lastNetwork?: string | null;
  firstSeenAt: string;
  lastSeenAt: string;
  sessions: number;
};
type Session = {
  startedAt: string;
  lastSeenAt: string;
  ip?: string | null;
  city?: string | null;
  region?: string | null;
  country?: string | null;
  org?: string | null;
  network?: string | null;
  appVersion?: string | null;
  userName?: string | null;
  pings: number;
};
type Detail = { device: Device; sessions: Session[] };

const DAYS = [1, 7, 30, 90];
const ROLES = [
  ['', 'Sab'],
  ['Customer', 'Customer'],
  ['Driver', 'Driver'],
  ['other', 'Owner / staff'],
  ['guest', 'Login ke baghair'],
] as const;

function message(value: unknown, fallback: string) {
  return value instanceof Error ? value.message : fallback;
}

function ago(value: string) {
  const mins = Math.round((Date.now() - new Date(value).getTime()) / 60000);
  if (mins < 1) return 'abhi';
  if (mins < 60) return `${mins} min pehle`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} ghante pehle`;
  const days = Math.round(hours / 24);
  return days === 1 ? 'Kal' : `${days} din pehle`;
}

function Bars({ title, items, onPick, picked }: { title: string; items: Count[]; onPick?: (name: string) => void; picked?: string }) {
  const max = Math.max(1, ...items.map((i) => i.count));
  return (
    <section className="panel" style={{ margin: 0, padding: 0, overflow: 'hidden' }}>
      <div style={{ padding: '12px 14px', fontWeight: 800, fontSize: 14, borderBottom: '1px solid #EDF2F0' }}>{title}</div>
      {items.length === 0 && <p style={{ padding: '10px 14px', fontSize: 12.5, color: '#5D7068' }}>Abhi kuch nahi.</p>}
      {items.map((item) => (
        <button
          key={item.name}
          type="button"
          onClick={onPick ? () => onPick(item.name) : undefined}
          style={{
            display: 'grid', gridTemplateColumns: '1fr 54px 110px', gap: 8, padding: '8px 14px', width: '100%',
            border: 'none', borderTop: '1px solid #F1F4F3', fontSize: 12.5, alignItems: 'center', textAlign: 'left',
            background: picked === item.name ? '#EEF8F3' : '#FFFFFF', cursor: onPick ? 'pointer' : 'default', color: '#12251E',
          }}
        >
          <span>{item.name}</span>
          <b>{item.count.toLocaleString()}</b>
          <span style={{ height: 8, borderRadius: 4, background: '#E6F5EE', overflow: 'hidden' }}>
            <span style={{ display: 'block', height: 8, background: '#0b8b62', width: `${Math.max(3, (item.count / max) * 100)}%` }} />
          </span>
        </button>
      ))}
    </section>
  );
}

export default function AppUsagePage() {
  const [days, setDays] = useState(7);
  const [role, setRole] = useState('');
  const [city, setCity] = useState('');
  const [q, setQ] = useState('');
  const [summary, setSummary] = useState<Summary | null>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [error, setError] = useState('');
  const [token, setToken] = useState('');
  const [tokenNote, setTokenNote] = useState('');
  const canSetToken = isSuperAdmin() || hasRole('Admin');

  const load = useCallback(async () => {
    setError('');
    try {
      const params = new URLSearchParams({ days: String(days), role, q, city, limit: '150' });
      const [s, d] = await Promise.all([
        apiFetch<Summary>(`/api/v1/admin/usage?days=${days}&role=${encodeURIComponent(role)}`),
        apiFetch<Device[]>(`/api/v1/admin/usage/devices?${params}`),
      ]);
      setSummary(s);
      setDevices(d);
    } catch (value) {
      setError(message(value, 'App usage nahi mil saka.'));
    }
  }, [days, role, q, city]);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), q ? 350 : 0);
    return () => window.clearTimeout(timer);
  }, [load, q]);

  async function open(device: Device) {
    try {
      setDetail(await apiFetch<Detail>(`/api/v1/admin/usage/devices/${encodeURIComponent(device.installId)}`));
    } catch (value) {
      setError(message(value, 'Device nahi khula.'));
    }
  }

  async function saveToken() {
    try {
      const result = await apiFetch<boolean>('/api/v1/admin/usage/geo-token', { method: 'POST', body: JSON.stringify({ token }) });
      setTokenNote(result ? 'Token save ho gaya. Shehar 1–2 minute mein aane lagenge.' : 'Shehar ka pata lagana band.');
      setToken('');
      await load();
    } catch (value) {
      setError(message(value, 'Token save nahi hua.'));
    }
  }

  const d = detail?.device;

  return (
    <AdminFrame
      title="App usage"
      subtitle="App kahan kahan se, kis device se chal rahi hai. Shehar IP se andazan hai (GPS nahi)."
      actions={
        <>
          <select value={days} onChange={(e) => setDays(Number(e.target.value))} aria-label="Din">
            {DAYS.map((n) => (
              <option key={n} value={n}>
                {n === 1 ? 'Aaj / 24 ghante' : `Pichle ${n} din`}
              </option>
            ))}
          </select>
          <select value={role} onChange={(e) => setRole(e.target.value)} aria-label="Kaun">
            {ROLES.map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
          <button className="secondaryButton" onClick={() => void load()}>
            <RefreshCw /> Refresh
          </button>
        </>
      }
    >
      {error && <ErrorBox message={error} />}
      {!summary ? (
        <Loading />
      ) : (
        <>
          {!summary.geoConfigured && (
            <section className="panel">
              <header className="panelHeader">
                <div>
                  <h2>
                    <MapPin style={{ width: 16, height: 16, verticalAlign: -2 }} /> Shehar dekhne ke liye ipinfo.io token
                  </h2>
                  <p>
                    ipinfo.io par muft account banayein (50,000 look-ups / mahina), token yahan daalein. Token ke baghair device,
                    IP aur network sab dikhta hai, sirf shehar &quot;Na-maloom&quot; rehta hai.
                  </p>
                </div>
              </header>
              {canSetToken && (
                <div className="topActions">
                  <input type="password" value={token} onChange={(e) => setToken(e.target.value)} placeholder="ipinfo token" aria-label="ipinfo token" style={{ width: 260 }} />
                  <button className="primaryButton" onClick={() => void saveToken()} disabled={!token.trim()}>
                    Save token
                  </button>
                </div>
              )}
            </section>
          )}
          {tokenNote && <div className="successBox">{tokenNote}</div>}

          <section className="statGrid">
            <Stat label={`Devices (${summary.days} din)`} value={summary.devices.toLocaleString()} sub="install id se" />
            <Stat label="Aaj active" value={summary.activeToday.toLocaleString()} sub="kam se kam 1 session" tone="blue" />
            <Stat label="Naye installs" value={summary.newInstalls.toLocaleString()} sub="pehli dafa khuli" tone="violet" />
            <Stat label="Sessions" value={summary.sessions.toLocaleString()} sub="app khulna" tone="slate" />
            <Stat label="Login ke baghair" value={`${summary.guestPercent}%`} sub="sirf dekha" tone="amber" />
          </section>

          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(280px, 360px) 1fr', gap: 14, alignItems: 'start' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <Bars title={city ? `Shehar (IP se) — ${city} chuna` : 'Shehar (IP se)'} items={summary.cities} picked={city} onPick={(name) => setCity(city === name ? '' : name)} />
              <Bars title="App version / build" items={summary.versions} />
              <Bars title="Phone company" items={summary.phones} />
              <Bars title="Network" items={summary.networks} />
            </div>

            <section className="panel" style={{ margin: 0, padding: 0, overflow: 'hidden' }}>
              <div style={{ padding: '12px 14px', display: 'flex', gap: 8, alignItems: 'center', borderBottom: '1px solid #EDF2F0' }}>
                <b style={{ fontSize: 14, flexGrow: 1 }}>Devices ({devices.length})</b>
                <input type="search" aria-label="Search" placeholder="Naam, phone, model, IP" value={q} onChange={(e) => setQ(e.target.value)} style={{ width: 220 }} />
              </div>
              {devices.length === 0 ? (
                <Empty title="Koi device nahi" copy="App ka naya version phones par aane ke baad yahan nazar aayenge." />
              ) : (
                <div className="tableWrap" style={{ margin: 0 }}>
                  <table>
                    <thead>
                      <tr>
                        <th>User</th>
                        <th>Device</th>
                        <th>IP · Shehar</th>
                        <th>Network</th>
                        <th>App</th>
                        <th>Aakhri dafa</th>
                      </tr>
                    </thead>
                    <tbody>
                      {devices.map((row) => (
                        <tr key={row.installId} onClick={() => void open(row)} style={{ cursor: 'pointer', background: d?.installId === row.installId ? '#EEF8F3' : undefined }}>
                          <td>
                            <strong>{row.userName ?? '— (login nahi)'}</strong>
                            <br />
                            <small>{row.userName ? `${row.role ?? ''} · ${row.userPhone ?? ''}` : 'Mehman'}</small>
                          </td>
                          <td>
                            {[row.manufacturer, row.model].filter(Boolean).join(' ') || '—'}
                            <br />
                            <small>Android {row.osVersion ?? '?'}</small>
                          </td>
                          <td>
                            {row.lastIp ?? '—'}
                            <br />
                            <small>{row.lastCity ?? 'Na-maloom'}</small>
                          </td>
                          <td>{row.lastNetwork ?? '—'}</td>
                          <td>
                            {row.appVersion ?? '—'}
                            <br />
                            <small>{row.flavor ?? ''}</small>
                          </td>
                          <td>{ago(row.lastSeenAt)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              {d && (
                <div style={{ padding: '12px 14px', borderTop: '1px solid #EDF2F0', background: '#F8FBFA', fontSize: 12.5, lineHeight: 1.6 }}>
                  <b>
                    {d.userName ?? 'Mehman'} — {[d.manufacturer, d.model].filter(Boolean).join(' ')}
                  </b>{' '}
                  · install id {d.installId} · Android {d.osVersion ?? '?'} (SDK {d.sdk ?? '?'}) · screen {d.screen ?? '?'} · zubaan{' '}
                  {d.locale ?? '?'} · timezone {d.timezone ?? '?'} · app {d.appVersion ?? '?'} ({d.buildNumber ?? '?'}, {d.flavor ?? '?'}) ·
                  pehli dafa {when(d.firstSeenAt)} · {d.sessions} sessions
                  <div className="tableWrap" style={{ marginTop: 8 }}>
                    <table>
                      <thead>
                        <tr>
                          <th>Shuru</th>
                          <th>Shehar</th>
                          <th>IP · ISP</th>
                          <th>Network</th>
                          <th>App</th>
                          <th>User</th>
                        </tr>
                      </thead>
                      <tbody>
                        {detail!.sessions.map((s) => (
                          <tr key={s.startedAt + (s.ip ?? '')}>
                            <td>
                              {when(s.startedAt)}
                              <br />
                              <small>{s.pings} ping · {ago(s.lastSeenAt)}</small>
                            </td>
                            <td>{[s.city, s.region].filter(Boolean).join(', ') || 'Na-maloom'}</td>
                            <td>
                              {s.ip ?? '—'}
                              <br />
                              <small>{s.org ?? ''}</small>
                            </td>
                            <td>{s.network ?? '—'}</td>
                            <td>{s.appVersion ?? '—'}</td>
                            <td>{s.userName ?? 'Mehman'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </section>
          </div>
        </>
      )}
    </AdminFrame>
  );
}
