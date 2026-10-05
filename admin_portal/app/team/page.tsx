'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus, RefreshCw } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Loading, Stat } from '../components/ui';
import { apiFetch, when } from '../lib/admin-api';
import { usePermissions } from '../lib/permissions';
import { useCatalogAreas } from '../verification/area-select';
import {
  areasSummary,
  initials,
  isActive,
  isVerificationModule,
  modulesSummary,
  templateLabel,
  type TeamCatalog,
  type TeamUser,
} from './team-shared';

const subtext = { display: 'block', color: '#66796f', marginTop: 3 } as const;

const avatar = {
  width: 34,
  height: 34,
  borderRadius: 11,
  background: '#d4f4e6',
  color: '#087352',
  fontWeight: 850,
  display: 'grid',
  placeItems: 'center',
  flexShrink: 0,
} as const;

export default function TeamPage() {
  const { can } = usePermissions();
  const canEditTeam = can('team', 'edit');
  const { districts } = useCatalogAreas();

  const [users, setUsers] = useState<TeamUser[]>([]);
  const [catalog, setCatalog] = useState<TeamCatalog | null>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  // The user form sends people back here with what the server said.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const saved = params.get('saved');
    if (saved) {
      setSuccess(saved);
      window.history.replaceState(null, '', window.location.pathname);
    }
  }, []);

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      const [rows, modules] = await Promise.all([
        apiFetch<TeamUser[]>('/api/v1/admin/team'),
        apiFetch<TeamCatalog>('/api/v1/admin/team/catalog').catch(() => null),
      ]);
      setUsers(rows ?? []);
      setCatalog(modules);
    } catch (value) {
      setError(value instanceof Error ? value.message : 'The team could not be loaded.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const stats = useMemo(() => {
    const team = users.filter((user) => user.editable);
    const verifiers = team.filter((user) =>
      user.permissions.some(
        (grant) =>
          isVerificationModule(grant.module) &&
          (grant.view || grant.edit || grant.approve || grant.delete),
      ),
    ).length;

    // Districts with at least one active team user in them.
    const covered = new Set<string>();
    const activeTeam = team.filter(isActive);
    if (activeTeam.some((user) => user.allAreas)) {
      districts.forEach((district) => covered.add(district.id));
    } else {
      activeTeam.forEach((user) =>
        user.areas.forEach((area) => {
          if (area.kind === 'District') {
            covered.add(area.id);
            return;
          }
          const owner = districts.find((district) =>
            district.tehsils.some((tehsil) => tehsil.id === area.id),
          );
          if (owner) covered.add(owner.id);
        }),
      );
    }

    return {
      total: users.length,
      active: users.filter(isActive).length,
      verifiers,
      covered: districts.length > 0 ? `${covered.size} / ${districts.length}` : '—',
    };
  }, [users, districts]);

  return (
    <AdminFrame
      title="Team"
      subtitle="People who work in the admin portal. Each one sees only the modules and areas you give them."
      actions={
        <>
          <button className="secondaryButton" onClick={() => void load()} disabled={busy}>
            <RefreshCw className={busy ? 'spin' : ''} /> Refresh
          </button>
          {canEditTeam && (
            <Link className="primaryButton" href="/team/user">
              <Plus /> Add user
            </Link>
          )}
        </>
      }
    >
      {error && <ErrorBox message={error} />}
      {success && <div className="successBox" style={{ margin: '0 0 14px' }}>{success}</div>}

      <section className="statGrid">
        <Stat label="Users" value={stats.total} tone="emerald" />
        <Stat label="Active" value={stats.active} tone="blue" />
        <Stat label="Verifiers" value={stats.verifiers} tone="amber" />
        <Stat label="Areas covered" value={stats.covered} tone="violet" />
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Portal users</h2>
            <p>Admins have full access. Team users see only what is ticked on their page; the server checks every action too.</p>
          </div>
        </header>

        {busy ? (
          <Loading />
        ) : users.length === 0 ? (
          <Empty title="No team users yet" copy="Add a user and choose their modules and areas." />
        ) : (
          <div className="tableWrap">
            <table style={{ minWidth: 900 }}>
              <thead>
                <tr>
                  <th>User</th>
                  <th>Template</th>
                  <th>Modules</th>
                  <th>Areas</th>
                  <th>Last login</th>
                  <th>Status</th>
                  <th aria-label="Actions" />
                </tr>
              </thead>
              <tbody>
                {users.map((user) => (
                  <tr key={user.id}>
                    <td>
                      <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                        <span style={avatar}>{initials(user.fullName)}</span>
                        <div style={{ minWidth: 0 }}>
                          <strong style={{ display: 'block' }}>{user.fullName}</strong>
                          <small style={subtext}>
                            {user.phoneNumber}
                            {user.username && user.username !== user.phoneNumber ? ` · ${user.username}` : ''}
                          </small>
                        </div>
                      </div>
                    </td>
                    <td>{templateLabel(user, catalog)}</td>
                    <td style={{ color: '#41594f' }}>{modulesSummary(user, catalog)}</td>
                    <td>{areasSummary(user)}</td>
                    <td style={{ color: '#66796f' }}>{user.lastLoginAt ? when(user.lastLoginAt) : 'Never'}</td>
                    <td>
                      <Badge value={isActive(user) ? 'Active' : 'Disabled'} />
                    </td>
                    <td style={{ textAlign: 'right' }}>
                      <Link className="secondaryButton" href={`/team/user?id=${encodeURIComponent(user.id)}`}>
                        {canEditTeam && user.editable ? 'Edit' : 'View'}
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </AdminFrame>
  );
}
