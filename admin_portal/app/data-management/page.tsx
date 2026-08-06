'use client';

import { useCallback, useEffect, useState } from 'react';
import {
  Database,
  FlaskConical,
  RefreshCw,
  ShieldAlert,
  Trash2,
} from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { ErrorBox, Loading, Stat } from '../components/ui';
import { apiFetch, hasRole } from '../lib/admin-api';

type DataStatus = {
  users: number;
  drivers: number;
  vehicles: number;
  hotels: number;
  pendingHotels: number;
  rideBookings: number;
  hotelBookings: number;
  tourPackages: number;
  destinations: number;
  demoUsers: number;
};

const emptyStatus: DataStatus = {
  users: 0,
  drivers: 0,
  vehicles: 0,
  hotels: 0,
  pendingHotels: 0,
  rideBookings: 0,
  hotelBookings: 0,
  tourPackages: 0,
  destinations: 0,
  demoUsers: 0,
};

export default function DataManagementPage() {
  const [status, setStatus] = useState<DataStatus>(emptyStatus);
  const [busy, setBusy] = useState(true);
  const [action, setAction] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [canReset, setCanReset] = useState(false);

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setStatus(await apiFetch<DataStatus>('/api/v1/admin/data/status'));
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Data summary could not be loaded.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    setCanReset(hasRole('SuperAdmin') || hasRole('Admin'));
    void load();
  }, [load]);

  async function seedDemo() {
    if (!window.confirm('Add or refresh demo vehicles, destinations, tour packages and hotels? Existing real records will not be deleted.')) return;
    setAction('demo');
    setError('');
    setSuccess('');
    try {
      const result = await apiFetch<{ message: string; status: DataStatus }>('/api/v1/admin/data/demo', { method: 'POST' });
      setStatus(result.status);
      setSuccess(result.message);
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Demo data could not be added.');
    } finally {
      setAction('');
    }
  }

  async function resetData() {
    if (!canReset || confirmation !== 'DELETE ALL DATA') return;
    if (!window.confirm('This will permanently delete operational, customer, driver, vehicle, booking, tourism and hotel records. Continue?')) return;
    setAction('reset');
    setError('');
    setSuccess('');
    try {
      const result = await apiFetch<{ message: string; after: DataStatus }>('/api/v1/admin/data/reset', {
        method: 'POST',
        body: JSON.stringify({ confirmation }),
      });
      setStatus(result.after);
      setConfirmation('');
      setSuccess(result.message);
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Application data could not be reset.');
    } finally {
      setAction('');
    }
  }

  return (
    <AdminFrame
      title="Data management"
      subtitle="Reset old application records or add a complete demonstration catalogue."
      actions={
        <button className="secondaryButton" onClick={() => void load()} disabled={busy || !!action}>
          <RefreshCw className={busy ? 'spin' : ''} /> Refresh counts
        </button>
      }
    >
      {error && <ErrorBox message={error} />}
      {success && <div className="successBox">{success}</div>}

      {busy ? (
        <Loading />
      ) : (
        <>
          <section className="statGrid dataStatusGrid">
            <Stat label="Users" value={status.users} tone="blue" />
            <Stat label="Drivers" value={status.drivers} tone="violet" />
            <Stat label="Vehicles" value={status.vehicles} tone="emerald" />
            <Stat label="Hotels" value={status.hotels} tone="amber" />
            <Stat label="Ride bookings" value={status.rideBookings} tone="slate" />
            <Stat label="Tour packages" value={status.tourPackages} tone="rose" />
          </section>

          <section className="dataManagementGrid">
            <article className="panel dataActionCard demoDataCard">
              <div className="dataActionIcon"><FlaskConical /></div>
              <span className="dataEyebrow">SAFE / REPEATABLE</span>
              <h2>Add demo data</h2>
              <p>
                Adds Kashmir destinations, verified drivers, cars, coasters, bikes, rickshaws,
                tour packages, approved hotels, hotel rooms and one pending hotel for approval testing.
              </p>
              <div className="dataMiniStats">
                <span><strong>{status.demoUsers}</strong> demo users</span>
                <span><strong>{status.destinations}</strong> destinations</span>
                <span><strong>{status.pendingHotels}</strong> pending hotels</span>
              </div>
              <button className="primaryButton wide" disabled={!!action} onClick={() => void seedDemo()}>
                <Database /> {action === 'demo' ? 'Adding demo data…' : 'Add / refresh demo data'}
              </button>
            </article>

            <article className="panel dataActionCard dangerDataCard">
              <div className="dataActionIcon danger"><Trash2 /></div>
              <span className="dataEyebrow danger">DESTRUCTIVE / PERMANENT</span>
              <h2>Delete all old data</h2>
              <p>
                Deletes customer, driver, vehicle, booking, finance, tourism, support and hotel records.
                Admin portal accounts and system settings are preserved so you can sign in again.
              </p>
              <div className="dataWarning"><ShieldAlert /> This action cannot be undone.</div>
              <label className="field">
                <span>Type DELETE ALL DATA to confirm</span>
                <input
                  value={confirmation}
                  onChange={(event) => setConfirmation(event.target.value)}
                  placeholder="DELETE ALL DATA"
                  disabled={!canReset || !!action}
                />
              </label>
              {!canReset && <div className="dataPermissionNote">Only an Admin or SuperAdmin can run the complete reset.</div>}
              <button
                className="dangerButton wide"
                disabled={!canReset || confirmation !== 'DELETE ALL DATA' || !!action}
                onClick={() => void resetData()}
              >
                <Trash2 /> {action === 'reset' ? 'Deleting data…' : 'Delete all old data'}
              </button>
            </article>
          </section>
        </>
      )}
    </AdminFrame>
  );
}
