'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  BadgeCheck,
  Car,
  CheckCircle2,
  FileText,
  Loader2,
  LockKeyhole,
  LogOut,
  RefreshCw,
  ShieldCheck,
  UserRoundCheck,
  XCircle,
} from 'lucide-react';
import styles from './verification.module.css';

const API = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'https://udrive-api-production.up.railway.app';

type DriverItem = {
  driverProfileId: string;
  userId: string;
  fullName: string;
  phoneNumber: string;
  verificationStatus: string;
  cnicMasked?: string;
  drivingLicenceMasked?: string;
  submittedAt?: string;
  documentCount: number;
  vehicleCount: number;
};

type DocumentItem = {
  id: string;
  documentType: string;
  fileUrl: string;
  expiryDate?: string;
  status: string;
  reviewNotes?: string;
};

type VehicleItem = {
  vehicleId: string;
  driverProfileId: string;
  driverName: string;
  registrationNumber: string;
  vehicle: string;
  status: string;
  mountainReadinessScore: number;
  documentCount: number;
};

type VehicleDetail = { vehicle: VehicleItem; documents: DocumentItem[] };

type DriverDetail = {
  driver: DriverItem;
  profile: {
    verificationStatus: string;
    cnicMasked?: string;
    drivingLicenceMasked?: string;
    address?: string;
    emergencyContactName?: string;
    emergencyContactPhone?: string;
    languages: string[];
    serviceAreas: string[];
    reviewNotes?: string;
  };
  documents: DocumentItem[];
  vehicles: VehicleItem[];
};

type TokenData = {
  accessToken: string;
  refreshToken: string;
  user: { fullName: string; roles: string[] };
};

type ApiEnvelope<T> = { success: boolean; data: T; message?: string };

export default function VerificationPage() {
  const [phone, setPhone] = useState('03000000099');
  const [code, setCode] = useState('1234');
  const [otpSent, setOtpSent] = useState(false);
  const [tokens, setTokens] = useState<TokenData | null>(null);
  const [drivers, setDrivers] = useState<DriverItem[]>([]);
  const [vehicles, setVehicles] = useState<VehicleItem[]>([]);
  const [selected, setSelected] = useState<DriverDetail | null>(null);
  const [selectedVehicle, setSelectedVehicle] = useState<VehicleDetail | null>(null);
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    const saved = window.localStorage.getItem('udrive-admin-phase8');
    if (saved) {
      try { setTokens(JSON.parse(saved) as TokenData); } catch { window.localStorage.removeItem('udrive-admin-phase8'); }
    }
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
      throw new Error(body.message ?? body.detail ?? 'The Admin session has expired. Sign in again.');
    }
    if (!body.data.user.roles.some(role => ['Admin', 'Operations'].includes(role))) {
      throw new Error('This account no longer has verification permission.');
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

  const loadQueues = useCallback(async () => {
    if (!tokens) return;
    setBusy(true); setError('');
    try {
      const [driverResponse, vehicleResponse] = await Promise.all([
        authFetch('/api/v1/admin/verification/drivers'),
        authFetch('/api/v1/admin/verification/vehicles'),
      ]);
      const driverBody = await driverResponse.json() as ApiEnvelope<DriverItem[]>;
      const vehicleBody = await vehicleResponse.json() as ApiEnvelope<VehicleItem[]>;
      setDrivers(driverBody.data);
      setVehicles(vehicleBody.data);
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Could not load verification queues.');
    } finally { setBusy(false); }
  }, [authFetch, tokens]);

  useEffect(() => { void loadQueues(); }, [loadQueues]);

  const pendingDrivers = useMemo(
    () => drivers.filter(item => item.verificationStatus !== 'Approved'),
    [drivers],
  );

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
        throw new Error('This account does not have Admin verification permission.');
      }
      persistTokens(body.data);
    } catch (value) { setError(value instanceof Error ? value.message : 'Login failed.'); }
    finally { setBusy(false); }
  }

  async function openDriver(id: string) {
    setBusy(true); setError('');
    try {
      const response = await authFetch(`/api/v1/admin/verification/drivers/${id}`);
      const body = await response.json() as ApiEnvelope<DriverDetail>;
      setSelected(body.data); setNotes(body.data.profile.reviewNotes ?? '');
    } catch (value) { setError(value instanceof Error ? value.message : 'Could not open driver.'); }
    finally { setBusy(false); }
  }

  async function openVehicle(id: string) {
    setBusy(true); setError('');
    try {
      const response = await authFetch(`/api/v1/admin/verification/vehicles/${id}`);
      const body = await response.json() as ApiEnvelope<VehicleDetail>;
      setSelectedVehicle(body.data); setNotes('');
    } catch (value) { setError(value instanceof Error ? value.message : 'Could not open vehicle.'); }
    finally { setBusy(false); }
  }

  async function reviewVehicle(decision: 'Verified' | 'ChangesRequired' | 'Suspended' | 'Expired') {
    if (!selectedVehicle) return;
    setBusy(true); setError('');
    try {
      await authFetch(`/api/v1/admin/verification/vehicles/${selectedVehicle.vehicle.vehicleId}`, {
        method: 'PUT', body: JSON.stringify({ decision, notes }),
      });
      setSelectedVehicle(null); setNotes('');
      await loadQueues();
    } catch (value) { setError(value instanceof Error ? value.message : 'Vehicle review failed.'); }
    finally { setBusy(false); }
  }

  async function review(decision: 'Approved' | 'ChangesRequired' | 'Rejected' | 'Suspended') {
    if (!selected) return;
    setBusy(true); setError('');
    try {
      await authFetch(`/api/v1/admin/verification/drivers/${selected.driver.driverProfileId}`, {
        method: 'PUT', body: JSON.stringify({ decision, notes }),
      });
      setSelected(null); setNotes('');
      await loadQueues();
    } catch (value) { setError(value instanceof Error ? value.message : 'Review failed.'); }
    finally { setBusy(false); }
  }

  async function openProtectedFile(url: string) {
    setError('');
    try {
      const response = await authFetch(url);
      const blob = await response.blob();
      const objectUrl = URL.createObjectURL(blob);
      window.open(objectUrl, '_blank', 'noopener,noreferrer');
      window.setTimeout(() => URL.revokeObjectURL(objectUrl), 60_000);
    } catch (value) { setError(value instanceof Error ? value.message : 'Could not open document.'); }
  }

  function logout() {
    window.localStorage.removeItem('udrive-admin-phase8');
    setTokens(null); setSelected(null); setSelectedVehicle(null); setDrivers([]); setVehicles([]); setOtpSent(false);
  }

  if (!tokens) {
    return <main className={styles.loginPage}>
      <section className={styles.loginCard}>
        <div className={styles.logo}><ShieldCheck size={28}/><div><strong>uDrive</strong><span>Secure verification console</span></div></div>
        <h1>Admin sign in</h1>
        <p>Use the seeded Phase 8 Admin account while testing. The development OTP is <strong>1234</strong>.</p>
        <label>Admin mobile number<input value={phone} onChange={event => setPhone(event.target.value)} /></label>
        {otpSent && <label>Verification code<input value={code} onChange={event => setCode(event.target.value)} inputMode="numeric" /></label>}
        {error && <div className={styles.error}>{error}</div>}
        <button disabled={busy} onClick={otpSent ? verifyOtp : requestOtp}>
          {busy ? <Loader2 className={styles.spin}/> : <LockKeyhole size={18}/>} {otpSent ? 'Verify and open console' : 'Request OTP'}
        </button>
        {otpSent && <button className={styles.secondaryButton} disabled={busy} onClick={requestOtp}>Request another code</button>}
      </section>
    </main>;
  }

  return <main className={styles.page}>
    <header className={styles.header}>
      <div className={styles.logo}><ShieldCheck size={27}/><div><strong>uDrive Verification</strong><span>{tokens.user.fullName}</span></div></div>
      <div className={styles.headerActions}>
        <button className={styles.secondaryButton} onClick={loadQueues}><RefreshCw size={17}/> Refresh</button>
        <button className={styles.dangerButton} onClick={logout}><LogOut size={17}/> Logout</button>
      </div>
    </header>

    <section className={styles.content}>
      <div className={styles.hero}>
        <div><span className={styles.eyebrow}>PHASE 8 · LIVE DATABASE</span><h1>Driver & vehicle verification</h1><p>Review masked identity data, protected documents, service areas and vehicle readiness before approval.</p></div>
        <div className={styles.metrics}><Metric label="Pending drivers" value={pendingDrivers.length}/><Metric label="All vehicles" value={vehicles.length}/><Metric label="Approved" value={drivers.filter(item => item.verificationStatus === 'Approved').length}/></div>
      </div>
      {error && <div className={styles.error}>{error}</div>}
      <div className={styles.grid}>
        <section className={styles.panel}>
          <div className={styles.panelTitle}><div><h2>Driver applications</h2><p>Open an application for evidence and decision controls.</p></div>{busy && <Loader2 className={styles.spin}/>}</div>
          <div className={styles.list}>
            {drivers.map(driver => <button key={driver.driverProfileId} className={styles.listItem} onClick={() => openDriver(driver.driverProfileId)}>
              <span className={styles.itemIcon}><UserRoundCheck size={21}/></span>
              <span><strong>{driver.fullName}</strong><small>{driver.phoneNumber} · {driver.documentCount} documents · {driver.vehicleCount} vehicles</small></span>
              <Status value={driver.verificationStatus}/>
            </button>)}
            {!drivers.length && !busy && <div className={styles.empty}>No driver applications found.</div>}
          </div>
        </section>

        <section className={styles.panel}>
          <div className={styles.panelTitle}><div><h2>Vehicle queue</h2><p>Mountain-readiness and document completion.</p></div><Car size={22}/></div>
          <div className={styles.list}>
            {vehicles.map(vehicle => <button key={vehicle.vehicleId} className={styles.listItem} onClick={() => openVehicle(vehicle.vehicleId)}>
              <span className={styles.itemIcon}><Car size={21}/></span>
              <span><strong>{vehicle.vehicle}</strong><small>{vehicle.registrationNumber} · {vehicle.driverName} · readiness {vehicle.mountainReadinessScore}%</small></span>
              <Status value={vehicle.status}/>
            </button>)}
            {!vehicles.length && !busy && <div className={styles.empty}>No vehicles found.</div>}
          </div>
        </section>
      </div>
    </section>

    {selected && <div className={styles.modalBackdrop} onMouseDown={() => setSelected(null)}>
      <section className={styles.modal} onMouseDown={event => event.stopPropagation()}>
        <div className={styles.modalHeader}><div><h2>{selected.driver.fullName}</h2><p>{selected.driver.phoneNumber} · {selected.driver.verificationStatus}</p></div><button className={styles.iconButton} onClick={() => setSelected(null)}><XCircle/></button></div>
        <div className={styles.detailGrid}>
          <Detail label="CNIC" value={selected.profile.cnicMasked ?? 'Not provided'}/>
          <Detail label="Licence" value={selected.profile.drivingLicenceMasked ?? 'Not provided'}/>
          <Detail label="Emergency contact" value={`${selected.profile.emergencyContactName ?? '—'} · ${selected.profile.emergencyContactPhone ?? '—'}`}/>
          <Detail label="Service areas" value={selected.profile.serviceAreas.join(', ') || '—'}/>
          <Detail label="Languages" value={selected.profile.languages.join(', ') || '—'}/>
          <Detail label="Address" value={selected.profile.address ?? '—'}/>
        </div>
        <h3>Protected documents</h3>
        <div className={styles.documents}>{selected.documents.map(document => <button key={document.id} onClick={() => openProtectedFile(document.fileUrl)}><FileText size={18}/><span><strong>{document.documentType}</strong><small>{document.status}{document.expiryDate ? ` · expires ${document.expiryDate}` : ''}</small></span></button>)}</div>
        <h3>Registered vehicles</h3>
        <div className={styles.documents}>{selected.vehicles.map(vehicle => <div key={vehicle.vehicleId}><Car size={18}/><span><strong>{vehicle.vehicle}</strong><small>{vehicle.registrationNumber} · {vehicle.status} · readiness {vehicle.mountainReadinessScore}%</small></span></div>)}</div>
        <label className={styles.notes}>Review notes<textarea value={notes} onChange={event => setNotes(event.target.value)} rows={3}/></label>
        <div className={styles.reviewActions}>
          <button disabled={busy} onClick={() => review('Approved')}><CheckCircle2 size={18}/> Approve driver</button>
          <button disabled={busy} className={styles.warningButton} onClick={() => review('ChangesRequired')}><FileText size={18}/> Request changes</button>
          <button disabled={busy} className={styles.dangerButton} onClick={() => review('Rejected')}><XCircle size={18}/> Reject</button>
        </div>
      </section>
    </div>}

    {selectedVehicle && <div className={styles.modalBackdrop} onMouseDown={() => setSelectedVehicle(null)}>
      <section className={styles.modal} onMouseDown={event => event.stopPropagation()}>
        <div className={styles.modalHeader}><div><h2>{selectedVehicle.vehicle.vehicle}</h2><p>{selectedVehicle.vehicle.registrationNumber} · {selectedVehicle.vehicle.driverName}</p></div><button className={styles.iconButton} onClick={() => setSelectedVehicle(null)}><XCircle/></button></div>
        <div className={styles.detailGrid}>
          <Detail label="Current status" value={selectedVehicle.vehicle.status}/>
          <Detail label="Mountain readiness" value={`${selectedVehicle.vehicle.mountainReadinessScore}%`}/>
          <Detail label="Driver" value={selectedVehicle.vehicle.driverName}/>
          <Detail label="Documents" value={`${selectedVehicle.documents.length} uploaded`}/>
        </div>
        <h3>Protected vehicle documents</h3>
        <div className={styles.documents}>{selectedVehicle.documents.map(document => <button key={document.id} onClick={() => openProtectedFile(document.fileUrl)}><FileText size={18}/><span><strong>{document.documentType}</strong><small>{document.status}{document.expiryDate ? ` · expires ${document.expiryDate}` : ''}</small></span></button>)}</div>
        <label className={styles.notes}>Review notes<textarea value={notes} onChange={event => setNotes(event.target.value)} rows={3}/></label>
        <div className={styles.reviewActions}>
          <button disabled={busy} onClick={() => reviewVehicle('Verified')}><CheckCircle2 size={18}/> Verify vehicle</button>
          <button disabled={busy} className={styles.warningButton} onClick={() => reviewVehicle('ChangesRequired')}><FileText size={18}/> Request changes</button>
          <button disabled={busy} className={styles.dangerButton} onClick={() => reviewVehicle('Suspended')}><XCircle size={18}/> Suspend</button>
        </div>
      </section>
    </div>}
  </main>;
}

function Metric({label, value}:{label:string;value:number}) { return <div><strong>{value}</strong><span>{label}</span></div>; }
function Detail({label, value}:{label:string;value:string}) { return <div><span>{label}</span><strong>{value}</strong></div>; }
function Status({value}:{value:string}) { return <span className={styles.status} data-state={value.toLowerCase()}><BadgeCheck size={14}/>{value}</span>; }
