'use client';

import {
  Plus,
  RefreshCw,
  Search,
  ShieldCheck,
  UserCog,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { AdminFrame } from '../components/admin-frame';
import {
  Badge,
  Empty,
  ErrorBox,
  Field,
  Loading,
  Modal,
} from '../components/ui';
import {
  apiFetch,
  isSuperAdmin,
  PORTAL_ROLES,
  type PortalRole,
  when,
} from '../lib/admin-api';

type UserRow = {
  id: string;
  fullName: string;
  phoneNumber: string;
  email?: string | null;
  status: string;
  preferredLanguage: string;
  roles: string[];
  lastLoginAt?: string | null;
  createdAt: string;
};

type CreateForm = {
  fullName: string;
  phoneNumber: string;
  email: string;
  role: PortalRole;
  preferredLanguage: 'en' | 'ur';
};

const emptyForm: CreateForm = {
  fullName: '',
  phoneNumber: '',
  email: '',
  role: 'Manager',
  preferredLanguage: 'en',
};

export default function UsersPage() {
  const [users, setUsers] = useState<UserRow[]>([]);
  const [selected, setSelected] = useState<UserRow | null>(null);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState<CreateForm>(emptyForm);
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const canManageAccess = isSuperAdmin();

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setUsers(await apiFetch<UserRow[]>('/api/v1/admin/operations/users'));
    } catch (loadError) {
      setError(
        loadError instanceof Error
          ? loadError.message
          : 'Users could not be loaded.',
      );
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(() => {
    const value = search.trim().toLowerCase();
    if (!value) return users;
    return users.filter((user) =>
      [user.fullName, user.phoneNumber, user.email, ...user.roles]
        .filter(Boolean)
        .some((field) => String(field).toLowerCase().includes(value)),
    );
  }, [search, users]);

  async function createUser() {
    if (!form.fullName.trim() || !form.phoneNumber.trim()) {
      setError('Full name and mobile number are required.');
      return;
    }

    setSaving(true);
    setError('');
    try {
      await apiFetch('/api/v1/admin/users', {
        method: 'POST',
        body: JSON.stringify({
          ...form,
          email: form.email.trim() || null,
        }),
      });
      setCreating(false);
      setForm(emptyForm);
      await load();
    } catch (createError) {
      setError(
        createError instanceof Error
          ? createError.message
          : 'The user could not be created.',
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <AdminFrame
      title="Users & access"
      subtitle="Create portal users and control SuperAdmin, Admin and Manager access."
      actions={
        canManageAccess ? (
          <button className="primaryButton" onClick={() => setCreating(true)}>
            <Plus size={16} />
            Create user
          </button>
        ) : null
      }
    >
      {error && <ErrorBox message={error} />}

      <section className="panel">
        <header className="panelHeader userAccessHeader">
          <div>
            <h2>Accounts</h2>
            <p>{filtered.length} accounts</p>
          </div>
          <div className="tableTools">
            <label className="searchBox">
              <Search size={16} />
              <input
                placeholder="Search name, phone, email or role"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
              />
            </label>
            <button className="secondaryButton" onClick={() => void load()}>
              <RefreshCw size={16} />
              Refresh
            </button>
          </div>
        </header>

        {busy ? (
          <Loading />
        ) : filtered.length === 0 ? (
          <Empty title="No users found" copy="Create a portal user or change the search." />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Phone</th>
                  <th>Portal role</th>
                  <th>All roles</th>
                  <th>Status</th>
                  <th>Last login</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((user) => {
                  const portalRole =
                    PORTAL_ROLES.find((role) => user.roles.includes(role)) ?? 'None';
                  return (
                    <tr
                      className="clickable"
                      key={user.id}
                      onClick={() => setSelected(user)}
                    >
                      <td>
                        <strong>{user.fullName}</strong>
                        <small className="tableSubtext">{user.email ?? 'No email'}</small>
                      </td>
                      <td>{user.phoneNumber}</td>
                      <td><Badge value={portalRole} /></td>
                      <td>{user.roles.join(', ') || '—'}</td>
                      <td><Badge value={user.status} /></td>
                      <td>{when(user.lastLoginAt)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {!canManageAccess && (
        <div className="permissionNote">
          <ShieldCheck size={18} />
          <div>
            <strong>SuperAdmin permission required</strong>
            <span>Only a SuperAdmin can create users or change portal roles.</span>
          </div>
        </div>
      )}

      {creating && (
        <Modal title="Create portal user" onClose={() => setCreating(false)}>
          <div className="detailStack compactForm">
            <Field label="Full name">
              <input
                value={form.fullName}
                maxLength={160}
                onChange={(event) =>
                  setForm((value) => ({ ...value, fullName: event.target.value }))
                }
              />
            </Field>
            <Field label="Mobile number">
              <input
                value={form.phoneNumber}
                placeholder="03001234567"
                maxLength={24}
                onChange={(event) =>
                  setForm((value) => ({ ...value, phoneNumber: event.target.value }))
                }
              />
            </Field>
            <Field label="Email (optional)">
              <input
                type="email"
                value={form.email}
                maxLength={320}
                onChange={(event) =>
                  setForm((value) => ({ ...value, email: event.target.value }))
                }
              />
            </Field>
            <Field label="Portal role">
              <select
                value={form.role}
                onChange={(event) =>
                  setForm((value) => ({
                    ...value,
                    role: event.target.value as PortalRole,
                  }))
                }
              >
                {PORTAL_ROLES.map((role) => (
                  <option key={role}>{role}</option>
                ))}
              </select>
            </Field>
            <Field label="Language">
              <select
                value={form.preferredLanguage}
                onChange={(event) =>
                  setForm((value) => ({
                    ...value,
                    preferredLanguage: event.target.value as 'en' | 'ur',
                  }))
                }
              >
                <option value="en">English</option>
                <option value="ur">Urdu</option>
              </select>
            </Field>
            <p className="formHint">
              The new user signs in with this mobile number and OTP. Development OTP remains 1234.
            </p>
            <div className="buttonRow">
              <button
                className="primaryButton"
                disabled={saving}
                onClick={() => void createUser()}
              >
                <UserCog size={16} />
                {saving ? 'Creating…' : 'Create user'}
              </button>
              <button className="secondaryButton" onClick={() => setCreating(false)}>
                Cancel
              </button>
            </div>
          </div>
        </Modal>
      )}

      {selected && (
        <UserDetails
          user={selected}
          canManageAccess={canManageAccess}
          onClose={() => setSelected(null)}
          onChanged={async () => {
            setSelected(null);
            await load();
          }}
        />
      )}
    </AdminFrame>
  );
}

function UserDetails({
  user,
  canManageAccess,
  onClose,
  onChanged,
}: {
  user: UserRow;
  canManageAccess: boolean;
  onClose: () => void;
  onChanged: () => Promise<void>;
}) {
  const currentPortalRole =
    PORTAL_ROLES.find((role) => user.roles.includes(role)) ?? 'None';
  const [portalRole, setPortalRole] = useState<string>(currentPortalRole);
  const [status, setStatus] = useState(user.status);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  async function saveStatus() {
    setSaving(true);
    setError('');
    try {
      await apiFetch(`/api/v1/admin/operations/users/${user.id}/status`, {
        method: 'PUT',
        body: JSON.stringify({
          status,
          reason: 'Updated from Users & access',
        }),
      });
      await onChanged();
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Status update failed.');
    } finally {
      setSaving(false);
    }
  }

  async function savePortalRole() {
    setSaving(true);
    setError('');
    try {
      await apiFetch(`/api/v1/admin/users/${user.id}/portal-role`, {
        method: 'PUT',
        body: JSON.stringify({ role: portalRole === 'None' ? null : portalRole }),
      });
      await onChanged();
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Role update failed.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal title={user.fullName} onClose={onClose}>
      <div className="detailStack compactForm">
        {error && <ErrorBox message={error} />}
        <div className="detailGrid">
          <div><span>Phone</span><strong>{user.phoneNumber}</strong></div>
          <div><span>Email</span><strong>{user.email ?? '—'}</strong></div>
          <div><span>All roles</span><strong>{user.roles.join(', ') || '—'}</strong></div>
          <div><span>Created</span><strong>{when(user.createdAt)}</strong></div>
        </div>
        {canManageAccess ? (
          <>
            <Field label="Account status">
              <select value={status} onChange={(event) => setStatus(event.target.value)}>
                {['Approved', 'Active', 'Suspended', 'Rejected'].map((value) => (
                  <option key={value}>{value}</option>
                ))}
              </select>
            </Field>
            <button className="secondaryButton" disabled={saving} onClick={() => void saveStatus()}>
              Update account status
            </button>
          </>
        ) : (
          <div className="detailGrid">
            <div><span>Account status</span><strong>{user.status}</strong></div>
          </div>
        )}

        {canManageAccess ? (
          <>
            <Field label="Portal role">
              <select value={portalRole} onChange={(event) => setPortalRole(event.target.value)}>
                <option value="None">No portal access</option>
                {PORTAL_ROLES.map((role) => <option key={role}>{role}</option>)}
              </select>
            </Field>
            <button className="primaryButton" disabled={saving} onClick={() => void savePortalRole()}>
              Save portal role
            </button>
          </>
        ) : (
          <div className="permissionNote compactPermission">
            <ShieldCheck size={17} />
            <span>Only SuperAdmin can change portal roles.</span>
          </div>
        )}
      </div>
    </Modal>
  );
}
