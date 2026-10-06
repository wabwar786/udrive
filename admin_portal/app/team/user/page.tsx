'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Fragment, Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowLeft, Power, RefreshCw, Save, ShieldCheck } from 'lucide-react';

import { AdminFrame } from '../../components/admin-frame';
import { ErrorBox, Loading } from '../../components/ui';
import { apiAction, apiFetch, when } from '../../lib/admin-api';
import {
  usePermissions,
  type ModuleGrant,
  type PermissionAction,
} from '../../lib/permissions';
import { useCatalogAreas, type CatalogDistrict } from '../../verification/area-select';
import { ReportsAccess } from '../reports-access';
import {
  ACTIONS,
  ACTION_LABELS,
  isActive,
  isVerificationModule,
  localMobile,
  type CatalogModule,
  type TeamCatalog,
  type TeamUser,
} from '../team-shared';

type Grants = Record<string, ModuleGrant>;

type FormState = {
  fullName: string;
  phoneNumber: string;
  username: string;
  password: string;
  isActive: boolean;
  template: string;
  allAreas: boolean;
  areaIds: string[];
  permissions: Grants;
};

const CUSTOM = 'custom';

const EMPTY_FORM: FormState = {
  fullName: '',
  phoneNumber: '',
  username: '',
  password: '',
  isActive: true,
  template: CUSTOM,
  allAreas: false,
  areaIds: [],
  permissions: {},
};

const muted = { color: '#66796f' } as const;
const sectionBody = { padding: 18, display: 'flex', flexDirection: 'column', gap: 14 } as const;
const checkbox = { width: 18, height: 18, accentColor: '#0b8b62', margin: 0 } as const;
const cell = { padding: '10px 12px', textAlign: 'center' } as const;

function emptyGrant(module: string): ModuleGrant {
  return { module, view: false, edit: false, approve: false, delete: false };
}

function hasAny(grant: ModuleGrant | undefined) {
  return Boolean(grant && (grant.view || grant.edit || grant.approve || grant.delete));
}

/** Grants keyed by module, limited to the actions each module supports. */
function grantsFrom(list: ModuleGrant[], modules: CatalogModule[]): Grants {
  const result: Grants = {};
  for (const module of modules) {
    const source = list.find((grant) => grant.module === module.key);
    const grant = emptyGrant(module.key);
    if (source) {
      for (const action of ACTIONS) {
        grant[action] = module.actions.includes(action) && Boolean(source[action]);
      }
      if (grant.edit || grant.approve || grant.delete) grant.view = module.actions.includes('view');
    }
    result[module.key] = grant;
  }
  return result;
}

function tehsilPill(on: boolean) {
  return {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 6,
    minHeight: 36,
    padding: '0 10px',
    borderRadius: 10,
    fontSize: 12,
    fontWeight: 700,
    border: `1px solid ${on ? '#9fdcc3' : '#dde9e4'}`,
    background: on ? '#eef9f4' : '#fff',
    cursor: 'pointer',
  } as const;
}

export default function TeamUserPage() {
  return (
    <Suspense
      fallback={
        <AdminFrame title="Team user">
          <Loading />
        </AdminFrame>
      }
    >
      <TeamUserScreen />
    </Suspense>
  );
}

function TeamUserScreen() {
  const router = useRouter();
  const params = useSearchParams();
  const id = params.get('id') ?? '';
  const isNew = !id;

  const { can } = usePermissions();
  const canEditTeam = can('team', 'edit');
  const { districts, error: areasError } = useCatalogAreas();

  const [catalog, setCatalog] = useState<TeamCatalog | null>(null);
  const [user, setUser] = useState<TeamUser | null>(null);
  const [form, setForm] = useState<FormState>(EMPTY_FORM);
  const [usernameTouched, setUsernameTouched] = useState(false);
  const [busy, setBusy] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setBusy(true);
    setLoadError('');
    try {
      const [modules, existing] = await Promise.all([
        apiFetch<TeamCatalog>('/api/v1/admin/team/catalog'),
        id ? apiFetch<TeamUser>(`/api/v1/admin/team/${encodeURIComponent(id)}`) : Promise.resolve(null),
      ]);
      const safeCatalog: TeamCatalog = {
        modules: modules?.modules ?? [],
        templates: modules?.templates ?? [],
      };
      setCatalog(safeCatalog);
      setUser(existing);

      if (existing) {
        setForm({
          fullName: existing.fullName,
          phoneNumber: existing.phoneNumber,
          username: existing.username ?? localMobile(existing.phoneNumber),
          password: '',
          isActive: isActive(existing),
          template: existing.template || CUSTOM,
          allAreas: existing.allAreas,
          areaIds: existing.areas.map((area) => area.id),
          permissions: grantsFrom(existing.permissions, safeCatalog.modules),
        });
        setUsernameTouched(Boolean(existing.username));
      } else {
        const first =
          safeCatalog.templates.find((item) => item.key === 'verification_officer') ??
          safeCatalog.templates.find((item) => item.key !== CUSTOM);
        setForm({
          ...EMPTY_FORM,
          template: first?.key ?? CUSTOM,
          permissions: grantsFrom(first?.permissions ?? [], safeCatalog.modules),
        });
        setUsernameTouched(false);
      }
    } catch (value) {
      setLoadError(value instanceof Error ? value.message : 'This user could not be loaded.');
    } finally {
      setBusy(false);
    }
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  const fullAccessUser = Boolean(user && !user.editable);
  const readOnly = !canEditTeam || fullAccessUser;

  function setField<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function setPhone(value: string) {
    setForm((current) => ({
      ...current,
      phoneNumber: value,
      username: usernameTouched ? current.username : localMobile(value),
    }));
  }

  // ---- Permissions -------------------------------------------------------

  function chooseTemplate(key: string) {
    if (!catalog) return;
    if (key === CUSTOM) {
      setField('template', CUSTOM);
      return;
    }
    const template = catalog.templates.find((item) => item.key === key);
    setForm((current) => ({
      ...current,
      template: key,
      permissions: grantsFrom(template?.permissions ?? [], catalog.modules),
    }));
  }

  function toggle(module: CatalogModule, action: PermissionAction, checked: boolean) {
    setForm((current) => {
      const grant = { ...(current.permissions[module.key] ?? emptyGrant(module.key)) };
      if (action === 'view' && !checked) {
        grant.view = false;
        grant.edit = false;
        grant.approve = false;
        grant.delete = false;
      } else {
        grant[action] = checked;
        if (checked && action !== 'view' && module.actions.includes('view')) grant.view = true;
      }
      return {
        ...current,
        template: CUSTOM,
        permissions: { ...current.permissions, [module.key]: grant },
      };
    });
  }

  /** The "Verification" header row: view on every verification tab, or none. */
  function toggleAllVerification(modules: CatalogModule[], checked: boolean) {
    setForm((current) => {
      const next = { ...current.permissions };
      for (const module of modules) {
        const grant = { ...(next[module.key] ?? emptyGrant(module.key)) };
        if (checked) {
          grant.view = module.actions.includes('view');
        } else {
          grant.view = false;
          grant.edit = false;
          grant.approve = false;
          grant.delete = false;
        }
        next[module.key] = grant;
      }
      return { ...current, template: CUSTOM, permissions: next };
    });
  }

  // ---- Areas -------------------------------------------------------------

  function toggleDistrict(district: CatalogDistrict, checked: boolean) {
    setForm((current) => {
      const tehsilIds = new Set(district.tehsils.map((tehsil) => tehsil.id));
      const rest = current.areaIds.filter((value) => value !== district.id && !tehsilIds.has(value));
      return { ...current, areaIds: checked ? [...rest, district.id] : rest };
    });
  }

  function toggleTehsil(tehsilId: string, checked: boolean) {
    setForm((current) => {
      const rest = current.areaIds.filter((value) => value !== tehsilId);
      return { ...current, areaIds: checked ? [...rest, tehsilId] : rest };
    });
  }

  // ---- Save / status -----------------------------------------------------

  const permissionList = useMemo(
    () => Object.values(form.permissions).filter((grant) => hasAny(grant)),
    [form.permissions],
  );

  async function save() {
    setError('');
    setSuccess('');
    if (!form.fullName.trim()) {
      setError('Enter the full name.');
      return;
    }
    if (!form.phoneNumber.trim()) {
      setError('Enter the mobile number.');
      return;
    }
    if (isNew && !form.password) {
      setError('Enter a password for the new user.');
      return;
    }

    const body = {
      fullName: form.fullName.trim(),
      phoneNumber: form.phoneNumber.trim(),
      username: form.username.trim() || null,
      password: form.password ? form.password : null,
      isActive: form.isActive,
      template: form.template || CUSTOM,
      allAreas: form.allAreas,
      areaIds: form.allAreas ? [] : form.areaIds,
      permissions: permissionList,
    };

    setSaving(true);
    try {
      const result = await apiAction<TeamUser>(
        isNew ? '/api/v1/admin/team' : `/api/v1/admin/team/${encodeURIComponent(id)}`,
        { method: isNew ? 'POST' : 'PUT', body: JSON.stringify(body) },
      );
      const message =
        result.message || `${result.data?.fullName ?? body.fullName} ${isNew ? 'added' : 'saved'}.`;
      router.push(`/team?saved=${encodeURIComponent(message)}`);
    } catch (value) {
      setError(value instanceof Error ? value.message : 'The user could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  async function changeStatus(active: boolean) {
    if (!user) return;
    if (
      !active &&
      !window.confirm(`Disable ${user.fullName}? They are signed out everywhere and cannot sign in until enabled again.`)
    ) {
      return;
    }
    setError('');
    setSuccess('');
    setSaving(true);
    try {
      const result = await apiAction<TeamUser>(
        `/api/v1/admin/team/${encodeURIComponent(user.id)}/status`,
        { method: 'POST', body: JSON.stringify({ isActive: active }) },
      );
      const updated = result.data ?? { ...user, status: active ? 'Approved' : 'Suspended' };
      setUser(updated);
      setField('isActive', isActive(updated));
      setSuccess(result.message || `${user.fullName} ${active ? 'enabled' : 'disabled'}.`);
    } catch (value) {
      setError(value instanceof Error ? value.message : 'The status could not be changed.');
    } finally {
      setSaving(false);
    }
  }

  // ---- Render ------------------------------------------------------------

  const title = isNew ? 'Add user' : user?.fullName ?? 'Team user';
  const subtitle = isNew
    ? 'A team user signs in with a username and password and sees only what you give them here.'
    : user
      ? `${fullAccessUser ? 'Full access' : 'Team user'} · created ${when(user.createdAt)} · last login ${
          user.lastLoginAt ? when(user.lastLoginAt) : 'never'
        }`
      : undefined;

  const modules = catalog?.modules ?? [];
  const verificationModules = modules.filter((module) => isVerificationModule(module.key));
  const firstVerification = modules.findIndex((module) => isVerificationModule(module.key));
  const verificationAllView =
    verificationModules.length > 0 &&
    verificationModules.every((module) => form.permissions[module.key]?.view);
  const verificationSomeView = verificationModules.some((module) => form.permissions[module.key]?.view);

  return (
    <AdminFrame
      title={title}
      subtitle={subtitle}
      actions={
        <Link className="secondaryButton" href="/team">
          <ArrowLeft /> Back to team
        </Link>
      }
    >
      {busy ? (
        <section className="panel">
          <Loading />
        </section>
      ) : loadError ? (
        <ErrorBox message={loadError} />
      ) : !isNew && !user ? (
        <ErrorBox message="This user was not found." />
      ) : (
        <>
          {error && <div className="errorBox" style={{ margin: '0 0 14px' }}>{error}</div>}
          {success && <div className="successBox" style={{ margin: '0 0 14px' }}>{success}</div>}
          {!canEditTeam && !fullAccessUser && (
            <div className="permissionNote" style={{ margin: '0 0 14px' }}>
              <ShieldCheck size={18} />
              <div>
                <strong>Read only</strong>
                <span>You can see this user, but changing the team needs Team · Edit.</span>
              </div>
            </div>
          )}

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>1. Who</h2>
                <p>The mobile number is the default username.</p>
              </div>
            </header>
            <div style={sectionBody}>
              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
                  gap: 12,
                }}
              >
                <label className="field">
                  <span>Full name</span>
                  <input
                    value={form.fullName}
                    disabled={readOnly}
                    onChange={(event) => setField('fullName', event.target.value)}
                  />
                </label>
                <label className="field">
                  <span>Mobile (login)</span>
                  <input
                    value={form.phoneNumber}
                    disabled={readOnly}
                    inputMode="tel"
                    placeholder="03001234567"
                    onChange={(event) => setPhone(event.target.value)}
                  />
                </label>
                <label className="field">
                  <span>Username</span>
                  <input
                    value={form.username}
                    disabled={readOnly}
                    autoComplete="off"
                    placeholder="03001234567"
                    onChange={(event) => {
                      setUsernameTouched(true);
                      setField('username', event.target.value);
                    }}
                  />
                </label>
                {!fullAccessUser && (
                  <label className="field">
                    <span>Password{isNew ? '' : ' (optional)'}</span>
                    <input
                      type="password"
                      autoComplete="new-password"
                      value={form.password}
                      disabled={readOnly}
                      placeholder={isNew ? '' : 'Leave empty to keep'}
                      onChange={(event) => setField('password', event.target.value)}
                    />
                    <small style={muted}>Letters and numbers, not a common word.</small>
                  </label>
                )}
              </div>
              {!fullAccessUser && (
                <label style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <input
                    type="checkbox"
                    style={checkbox}
                    checked={form.isActive}
                    disabled={readOnly}
                    onChange={(event) => setField('isActive', event.target.checked)}
                  />
                  <span style={{ fontWeight: 700 }}>Active</span>
                  <small style={muted}>Turn off to block login at once (signs the user out everywhere).</small>
                </label>
              )}
            </div>
          </section>

          {fullAccessUser ? (
            <div className="permissionNote" style={{ margin: '0 0 20px' }}>
              <ShieldCheck size={18} />
              <div>
                <strong>Full access</strong>
                <span>
                  {user?.roles.length ? `${user.roles.join(', ')} · ` : ''}
                  This person sees every module and every area. Their access is not set on this page.
                </span>
              </div>
            </div>
          ) : (
            <>
              <section className="panel">
                <header className="panelHeader" style={{ flexWrap: 'wrap' }}>
                  <div>
                    <h2>2. Areas</h2>
                    <p>Tick a whole district, or only some tehsils inside it. The user sees and verifies only these.</p>
                  </div>
                  <label
                    style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 8,
                      minHeight: 44,
                      padding: '0 14px',
                      borderRadius: 12,
                      border: '1px solid #dde9e4',
                      fontWeight: 700,
                    }}
                  >
                    <input
                      type="checkbox"
                      style={checkbox}
                      checked={form.allAreas}
                      disabled={readOnly}
                      onChange={(event) => setField('allAreas', event.target.checked)}
                    />
                    <span>All areas (head office)</span>
                  </label>
                </header>
                <div style={sectionBody}>
                  {areasError && <ErrorBox message={areasError} />}
                  {districts.length === 0 && !areasError ? (
                    <small style={muted}>No districts yet. Add them in Settings → Areas.</small>
                  ) : (
                    <div
                      style={{
                        display: 'grid',
                        gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))',
                        gap: 10,
                        opacity: form.allAreas ? 0.5 : 1,
                      }}
                    >
                      {districts.map((district) => (
                        <DistrictCard
                          key={district.id}
                          district={district}
                          areaIds={form.areaIds}
                          disabled={readOnly || form.allAreas}
                          onDistrict={(checked) => toggleDistrict(district, checked)}
                          onTehsil={toggleTehsil}
                        />
                      ))}
                    </div>
                  )}
                  <p style={{ margin: 0, ...muted, fontSize: 12 }}>
                    District ticked = all its tehsils, including ones added later. The district and tehsil list is kept in Settings → Areas.
                  </p>
                </div>
              </section>

              <section className="panel">
                <header className="panelHeader" style={{ flexWrap: 'wrap', alignItems: 'flex-end' }}>
                  <div>
                    <h2>3. What they can do</h2>
                    <p>Pick a template, then change any box. No View = the menu is hidden. The server checks every action too.</p>
                  </div>
                  <label className="field" style={{ minWidth: 240 }}>
                    <span>Template</span>
                    <select
                      value={form.template}
                      disabled={readOnly}
                      onChange={(event) => chooseTemplate(event.target.value)}
                    >
                      {(catalog?.templates ?? []).map((template) => (
                        <option key={template.key} value={template.key}>
                          {template.label}
                        </option>
                      ))}
                      {!(catalog?.templates ?? []).some((template) => template.key === CUSTOM) && (
                        <option value={CUSTOM}>Custom</option>
                      )}
                    </select>
                  </label>
                </header>
                <div className="tableWrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Module</th>
                        {ACTIONS.map((action) => (
                          <th key={action} style={{ textAlign: 'center' }}>
                            {ACTION_LABELS[action]}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {modules.map((module, index) => {
                        const child = isVerificationModule(module.key);
                        const grant = form.permissions[module.key] ?? emptyGrant(module.key);
                        return (
                          <Fragment key={module.key}>
                            {index === firstVerification && (
                              <tr style={{ background: '#fbfdfc' }}>
                                <td style={{ fontWeight: 800 }}>Verification</td>
                                <td style={cell}>
                                  <input
                                    type="checkbox"
                                    aria-label="View all verification"
                                    style={checkbox}
                                    checked={verificationAllView}
                                    ref={(element) => {
                                      if (element) {
                                        element.indeterminate = !verificationAllView && verificationSomeView;
                                      }
                                    }}
                                    disabled={readOnly}
                                    onChange={(event) =>
                                      toggleAllVerification(verificationModules, event.target.checked)
                                    }
                                  />
                                </td>
                                <td style={cell} />
                                <td style={cell} />
                                <td style={cell} />
                              </tr>
                            )}
                            <tr style={child ? undefined : { background: '#fbfdfc' }}>
                              <td
                                style={
                                  child
                                    ? { paddingLeft: 38, color: '#41594f' }
                                    : { fontWeight: 800 }
                                }
                              >
                                {module.label}
                              </td>
                              {ACTIONS.map((action) => (
                                <td key={action} style={cell}>
                                  {module.actions.includes(action) && (
                                    <input
                                      type="checkbox"
                                      aria-label={`${module.label} · ${ACTION_LABELS[action]}`}
                                      style={checkbox}
                                      checked={grant[action]}
                                      disabled={readOnly}
                                      onChange={(event) => toggle(module, action, event.target.checked)}
                                    />
                                  )}
                                </td>
                              ))}
                            </tr>
                          </Fragment>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </section>
            </>
          )}

          {!isNew && user ? (
            <ReportsAccess userId={user.id} readOnly={!canEditTeam} number={fullAccessUser ? undefined : 4} />
          ) : (
            <div className="permissionNote" style={{ margin: '0 0 20px' }}>
              <ShieldCheck size={18} />
              <div>
                <strong>Reports</strong>
                <span>Save the user first; then open them again to choose which reports they may see.</span>
              </div>
            </div>
          )}

          <div
            style={{
              display: 'flex',
              gap: 10,
              flexWrap: 'wrap',
              justifyContent: 'space-between',
              alignItems: 'center',
            }}
          >
            <div>
              {!isNew && !readOnly && user && (
                <button
                  type="button"
                  className={isActive(user) ? 'dangerButton' : 'secondaryButton'}
                  style={{ minHeight: 44, padding: '0 14px' }}
                  disabled={saving}
                  onClick={() => void changeStatus(!isActive(user))}
                >
                  <Power size={16} /> {isActive(user) ? 'Disable user' : 'Enable user'}
                </button>
              )}
            </div>
            <div style={{ display: 'flex', gap: 10 }}>
              <Link className="secondaryButton" href="/team" style={{ minHeight: 44, padding: '0 16px' }}>
                {readOnly ? 'Back' : 'Cancel'}
              </Link>
              {!readOnly && (
                <button
                  type="button"
                  className="primaryButton"
                  style={{ minHeight: 44, padding: '0 18px' }}
                  disabled={saving}
                  onClick={() => void save()}
                >
                  {saving ? <RefreshCw className="spin" /> : <Save />} Save user
                </button>
              )}
            </div>
          </div>
        </>
      )}
    </AdminFrame>
  );
}

function DistrictCard({
  district,
  areaIds,
  disabled,
  onDistrict,
  onTehsil,
}: {
  district: CatalogDistrict;
  areaIds: string[];
  disabled: boolean;
  onDistrict: (checked: boolean) => void;
  onTehsil: (tehsilId: string, checked: boolean) => void;
}) {
  const whole = areaIds.includes(district.id);
  const picked = whole
    ? district.tehsils.length
    : district.tehsils.filter((tehsil) => areaIds.includes(tehsil.id)).length;
  const any = whole || picked > 0;
  const count = whole ? 'all' : picked > 0 ? `${picked} of ${district.tehsils.length}` : '';

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 8,
        padding: 12,
        borderRadius: 14,
        border: `1px solid ${any ? '#9fdcc3' : '#e3ece8'}`,
        background: any ? '#f6fcf9' : '#fff',
      }}
    >
      <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 800, cursor: disabled ? 'default' : 'pointer' }}>
        <input
          type="checkbox"
          style={checkbox}
          checked={whole}
          disabled={disabled}
          onChange={(event) => onDistrict(event.target.checked)}
        />
        <span>{district.name} district</span>
        {count && <small style={{ marginLeft: 'auto', color: '#087650', fontWeight: 800 }}>{count}</small>}
      </label>
      {district.tehsils.length > 0 && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, paddingLeft: 26 }}>
          {district.tehsils.map((tehsil) => {
            const on = whole || areaIds.includes(tehsil.id);
            return (
              <label key={tehsil.id} style={tehsilPill(on)}>
                <input
                  type="checkbox"
                  style={checkbox}
                  checked={on}
                  disabled={disabled || whole}
                  onChange={(event) => onTehsil(tehsil.id, event.target.checked)}
                />
                <span>{tehsil.name}</span>
              </label>
            );
          })}
        </div>
      )}
    </div>
  );
}
