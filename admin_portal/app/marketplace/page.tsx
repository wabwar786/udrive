'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import {
  BadgeCheck,
  CalendarClock,
  Car,
  CheckCircle2,
  CircleDollarSign,
  Clock3,
  Loader2,
  LockKeyhole,
  LogOut,
  MapPin,
  RefreshCw,
  Route,
  ShieldCheck,
  UsersRound,
  XCircle,
} from 'lucide-react';
import styles from './marketplace.module.css';

const API = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'https://udrive-api-production.up.railway.app';

type TokenData = {
  accessToken: string;
  refreshToken: string;
  user: { fullName: string; roles: string[] };
};

type PackageItem = {
  id: string;
  vehicleId: string;
  destinationId: string;
  title: string;
  startingCity: string;
  pickupPoint: string;
  destination: string;
  departureAt: string;
  returnAt?: string;
  totalSeats: number;
  availableSeats: number;
  heldSeats: number;
  pricePerSeat: number;
  wholeVehiclePrice: number;
  familyOnly: boolean;
  womenOnly: boolean;
  customerOffersAllowed: boolean;
  status: string;
  description?: string;
  passengerPolicy: string;
  luggageAllowance?: string;
  itinerary: string[];
  inclusions: string[];
  driverName: string;
  driverRating: number;
  driverSafetyScore: number;
  vehicle: string;
  registrationNumber: string;
  mountainReadinessScore: number;
  reviewNotes?: string;
};

type ApiEnvelope<T> = { success: boolean; data: T; message?: string };

export default function MarketplacePage() {
  const [phone, setPhone] = useState('03000000099');
  const [code, setCode] = useState('1234');
  const [otpSent, setOtpSent] = useState(false);
  const [tokens, setTokens] = useState<TokenData | null>(null);
  const [packages, setPackages] = useState<PackageItem[]>([]);
  const [selected, setSelected] = useState<PackageItem | null>(null);
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    const saved = window.localStorage.getItem('udrive-admin-phase8');
    if (!saved) return;
    try { setTokens(JSON.parse(saved) as TokenData); }
    catch { window.localStorage.removeItem('udrive-admin-phase8'); }
  }, []);

  const persistTokens = useCallback((value: TokenData) => {
    setTokens(value);
    window.localStorage.setItem('udrive-admin-phase8', JSON.stringify(value));
  }, []);

  const refreshSession = useCallback(async (current: TokenData) => {
    const response = await fetch(`${API}/api/v1/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        refreshToken: current.refreshToken,
        deviceId: 'udrive-admin-web',
        deviceName: 'uDrive Admin Portal',
      }),
    });
    const body = await response.json().catch(() => ({})) as Partial<ApiEnvelope<TokenData>> & { detail?: string };
    if (!response.ok || !body.data) {
      window.localStorage.removeItem('udrive-admin-phase8');
      setTokens(null);
      throw new Error(body.message ?? body.detail ?? 'The Admin session has expired.');
    }
    if (!body.data.user.roles.some(role => ['Admin', 'Operations'].includes(role))) {
      throw new Error('This account does not have marketplace approval permission.');
    }
    persistTokens(body.data);
    return body.data;
  }, [persistTokens]);

  const authFetch = useCallback(async (path: string, init: RequestInit = {}) => {
    const execute = (access?: string) => fetch(`${API}${path}`, {
      ...init,
      headers: {
        Accept: 'application/json',
        ...(init.body ? { 'Content-Type': 'application/json' } : {}),
        ...(access ? { Authorization: `Bearer ${access}` } : {}),
        ...init.headers,
      },
    });
    let current = tokens;
    let response = await execute(current?.accessToken);
    if (response.status === 401 && current?.refreshToken) {
      current = await refreshSession(current);
      response = await execute(current.accessToken);
    }
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.message ?? body.detail ?? `Request failed (${response.status}).`);
    }
    return response;
  }, [refreshSession, tokens]);

  const loadPackages = useCallback(async () => {
    if (!tokens) return;
    setBusy(true); setError('');
    try {
      const response = await authFetch('/api/v1/admin/packages/pending');
      const body = await response.json() as ApiEnvelope<PackageItem[]>;
      setPackages(body.data);
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Could not load pending packages.');
    } finally { setBusy(false); }
  }, [authFetch, tokens]);

  useEffect(() => { void loadPackages(); }, [loadPackages]);

  const totals = useMemo(() => ({
    pending: packages.length,
    seats: packages.reduce((sum, item) => sum + item.totalSeats, 0),
    family: packages.filter(item => item.familyOnly).length,
  }), [packages]);

  async function requestOtp() {
    setBusy(true); setError('');
    try {
      const response = await fetch(`${API}/api/v1/auth/otp/request`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phoneNumber: phone, purpose: 'login' }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.message ?? 'OTP request failed.');
      setOtpSent(true);
    } catch (value) { setError(value instanceof Error ? value.message : 'OTP request failed.'); }
    finally { setBusy(false); }
  }

  async function verifyOtp() {
    setBusy(true); setError('');
    try {
      const response = await fetch(`${API}/api/v1/auth/otp/verify`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          phoneNumber: phone,
          code,
          fullName: 'uDrive Admin',
          language: 'en',
          deviceId: 'udrive-admin-web',
          deviceName: 'uDrive Admin Portal',
        }),
      });
      const body = await response.json() as ApiEnvelope<TokenData> & { message?: string };
      if (!response.ok) throw new Error(body.message ?? 'Login failed.');
      if (!body.data.user.roles.some(role => ['Admin', 'Operations'].includes(role))) {
        throw new Error('This account does not have marketplace permission.');
      }
      persistTokens(body.data);
    } catch (value) { setError(value instanceof Error ? value.message : 'Login failed.'); }
    finally { setBusy(false); }
  }

  async function review(decision: 'approve' | 'changes' | 'reject') {
    if (!selected) return;
    setBusy(true); setError('');
    try {
      await authFetch(`/api/v1/admin/packages/${selected.id}/review`, {
        method: 'PUT',
        body: JSON.stringify({ decision, notes }),
      });
      setSelected(null); setNotes('');
      await loadPackages();
    } catch (value) { setError(value instanceof Error ? value.message : 'Package review failed.'); }
    finally { setBusy(false); }
  }

  function logout() {
    window.localStorage.removeItem('udrive-admin-phase8');
    setTokens(null); setPackages([]); setSelected(null); setOtpSent(false);
  }

  if (!tokens) {
    return <main className={styles.loginPage}>
      <section className={styles.loginCard}>
        <div className={styles.logo}><ShieldCheck size={28}/><div><strong>uDrive</strong><span>Tourism marketplace</span></div></div>
        <h1>Package approvals</h1>
        <p>Sign in with an Admin or Operations account to review Driver-created tourism packages.</p>
        <label>Admin mobile<input value={phone} onChange={event => setPhone(event.target.value)} inputMode="tel"/></label>
        {otpSent && <label>OTP code<input value={code} onChange={event => setCode(event.target.value)} inputMode="numeric"/></label>}
        {error && <div className={styles.error}>{error}</div>}
        <button disabled={busy} onClick={otpSent ? verifyOtp : requestOtp}>{busy ? <Loader2 className={styles.spin}/> : <LockKeyhole size={18}/>} {otpSent ? 'Verify and sign in' : 'Request OTP'}</button>
      </section>
    </main>;
  }

  return <main className={styles.page}>
    <header className={styles.header}>
      <div className={styles.logo}><BadgeCheck size={25}/><div><strong>uDrive Marketplace</strong><span>{tokens.user.fullName}</span></div></div>
      <div className={styles.headerActions}>
        <button className={styles.secondaryButton} disabled={busy} onClick={loadPackages}><RefreshCw className={busy ? styles.spin : ''} size={17}/> Refresh</button>
        <button className={styles.dangerButton} onClick={logout}><LogOut size={17}/> Logout</button>
      </div>
    </header>

    <section className={styles.content}>
      <div className={styles.hero}>
        <div><span className={styles.eyebrow}>PHASE 9 · LIVE MARKETPLACE</span><h1>Tour package approval queue</h1><p>Review route quality, vehicle readiness, transparent pricing, passenger policy and safety before a package becomes visible to Customers.</p></div>
        <div className={styles.metrics}><div><strong>{totals.pending}</strong><span>Pending packages</span></div><div><strong>{totals.seats}</strong><span>Planned seats</span></div><div><strong>{totals.family}</strong><span>Family departures</span></div></div>
      </div>
      {error && <div className={styles.error}>{error}</div>}
      <section className={styles.panel}>
        <div className={styles.panelTitle}><div><h2>Pending Driver packages</h2><p>Only approved packages become active in the mobile marketplace.</p></div><Route size={23}/></div>
        <div className={styles.grid}>
          {packages.map(item => <button key={item.id} className={styles.packageCard} onClick={() => { setSelected(item); setNotes(item.reviewNotes ?? ''); }}>
            <div className={styles.cardTop}><span className={styles.iconBox}><MapPin size={21}/></span><span className={styles.status}>{item.status}</span></div>
            <h3>{item.title}</h3><p>{item.startingCity} → {item.destination}</p>
            <div className={styles.facts}><span><CalendarClock size={15}/>{new Date(item.departureAt).toLocaleString()}</span><span><UsersRound size={15}/>{item.availableSeats}/{item.totalSeats} seats</span><span><Car size={15}/>{item.vehicle}</span><span><ShieldCheck size={15}/>Safety {item.driverSafetyScore}/100</span></div>
            <div className={styles.prices}><span><small>Per seat</small><strong>PKR {item.pricePerSeat.toLocaleString()}</strong></span><span><small>Whole vehicle</small><strong>PKR {item.wholeVehiclePrice.toLocaleString()}</strong></span></div>
          </button>)}
          {!packages.length && !busy && <div className={styles.empty}>No packages are waiting for approval.</div>}
        </div>
      </section>
    </section>

    {selected && <div className={styles.backdrop} onMouseDown={() => setSelected(null)}>
      <section className={styles.modal} onMouseDown={event => event.stopPropagation()}>
        <div className={styles.modalHeader}><div><h2>{selected.title}</h2><p>{selected.driverName} · {selected.vehicle} · {selected.registrationNumber}</p></div><button className={styles.iconButton} onClick={() => setSelected(null)}><XCircle/></button></div>
        <div className={styles.detailGrid}>
          <Detail icon={<MapPin/>} label="Route" value={`${selected.startingCity} → ${selected.destination}`}/>
          <Detail icon={<Clock3/>} label="Departure" value={new Date(selected.departureAt).toLocaleString()}/>
          <Detail icon={<UsersRound/>} label="Inventory" value={`${selected.availableSeats}/${selected.totalSeats} available · ${selected.heldSeats} held`}/>
          <Detail icon={<CircleDollarSign/>} label="Pricing" value={`PKR ${selected.pricePerSeat.toLocaleString()} / seat · PKR ${selected.wholeVehiclePrice.toLocaleString()} vehicle`}/>
          <Detail icon={<ShieldCheck/>} label="Safety" value={`Driver ${selected.driverSafetyScore}/100 · Vehicle ${selected.mountainReadinessScore}/100`}/>
          <Detail icon={<Car/>} label="Passenger policy" value={selected.passengerPolicy}/>
        </div>
        {selected.description && <div className={styles.copy}><h3>Description</h3><p>{selected.description}</p></div>}
        <div className={styles.columns}>
          <div><h3>Itinerary</h3>{selected.itinerary.length ? <ol>{selected.itinerary.map(item => <li key={item}>{item}</li>)}</ol> : <p>No itinerary supplied.</p>}</div>
          <div><h3>Included facilities</h3>{selected.inclusions.length ? <ul>{selected.inclusions.map(item => <li key={item}>{item}</li>)}</ul> : <p>No inclusions supplied.</p>}</div>
        </div>
        <label className={styles.notes}>Admin review notes<textarea rows={3} value={notes} onChange={event => setNotes(event.target.value)} placeholder="Required when requesting changes or rejecting."/></label>
        <div className={styles.reviewActions}>
          <button disabled={busy} onClick={() => review('approve')}><CheckCircle2 size={18}/> Approve & activate</button>
          <button disabled={busy} className={styles.warningButton} onClick={() => review('changes')}><Route size={18}/> Request changes</button>
          <button disabled={busy} className={styles.dangerButton} onClick={() => review('reject')}><XCircle size={18}/> Reject</button>
        </div>
      </section>
    </div>}
  </main>;
}

function Detail({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return <div className={styles.detail}><span>{icon}</span><div><small>{label}</small><strong>{value}</strong></div></div>;
}
