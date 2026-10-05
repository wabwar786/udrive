import type { ModuleGrant, PermissionAction, TeamArea } from '../lib/permissions';

/** One portal user as `GET /api/v1/admin/team` returns it. */
export type TeamUser = {
  id: string;
  fullName: string;
  phoneNumber: string;
  username: string | null;
  status: string;
  /** false = a full-access user (SuperAdmin, Admin, older roles): read-only here. */
  editable: boolean;
  template: string;
  allAreas: boolean;
  areas: TeamArea[];
  permissions: ModuleGrant[];
  roles: string[];
  lastLoginAt: string | null;
  createdAt: string;
};

export type CatalogModule = {
  key: string;
  label: string;
  group: string;
  actions: string[];
  portalRoutes: string[];
};

export type CatalogTemplate = {
  key: string;
  label: string;
  permissions: ModuleGrant[];
};

export type TeamCatalog = {
  modules: CatalogModule[];
  templates: CatalogTemplate[];
};

export const ACTIONS: readonly PermissionAction[] = ['view', 'edit', 'approve', 'delete'];

export const ACTION_LABELS: Record<PermissionAction, string> = {
  view: 'View',
  edit: 'Edit',
  approve: 'Approve',
  delete: 'Delete',
};

/** Short names used in the "Modules" column for the verification tabs. */
const VERIFICATION_SHORT: Record<string, string> = {
  'verification.city': 'City rides',
  'verification.tour': 'Tour',
  'verification.rent': 'Rent',
  'verification.hotels': 'Hotels',
  'verification.businesses': 'Businesses',
};

export function isVerificationModule(key: string) {
  return key.startsWith('verification.');
}

export function isActive(user: TeamUser) {
  return user.status !== 'Suspended';
}

export function initials(name: string) {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .map((part) => part[0])
      .slice(0, 2)
      .join('')
      .toUpperCase() || 'U'
  );
}

/** "verification_officer" → "Verification officer" when the catalog has no label. */
export function prettyKey(key: string) {
  const text = key.replace(/[._-]+/g, ' ').trim();
  return text ? text[0].toUpperCase() + text.slice(1) : '—';
}

export function templateLabel(user: TeamUser, catalog: TeamCatalog | null) {
  if (!user.editable) return 'Full access';
  const template = catalog?.templates.find((item) => item.key === user.template);
  return template?.label ?? prettyKey(user.template || 'custom');
}

function hasAny(grant: ModuleGrant) {
  return grant.view || grant.edit || grant.approve || grant.delete;
}

function viewOnly(grant: ModuleGrant) {
  return grant.view && !grant.edit && !grant.approve && !grant.delete;
}

/** "Verification: City rides, Rent · Rentals (view)". */
export function modulesSummary(user: TeamUser, catalog: TeamCatalog | null) {
  if (!user.editable) return 'Everything';
  const label = (key: string) =>
    catalog?.modules.find((item) => item.key === key)?.label ?? prettyKey(key);
  const order = (key: string) => {
    const index = catalog?.modules.findIndex((item) => item.key === key) ?? -1;
    return index < 0 ? 999 : index;
  };
  const granted = user.permissions
    .filter(hasAny)
    .sort((a, b) => order(a.module) - order(b.module));

  const verification = granted
    .filter((grant) => isVerificationModule(grant.module))
    .map((grant) => VERIFICATION_SHORT[grant.module] ?? label(grant.module));
  const others = granted
    .filter((grant) => !isVerificationModule(grant.module))
    .map((grant) => `${label(grant.module)}${viewOnly(grant) ? ' (view)' : ''}`);

  const parts: string[] = [];
  if (verification.length > 0) parts.push(`Verification: ${verification.join(', ')}`);
  if (others.length > 0) parts.push(others.join(', '));
  return parts.length > 0 ? parts.join(' · ') : 'Nothing yet';
}

export function areasSummary(user: TeamUser) {
  if (!user.editable || user.allAreas) return 'All areas';
  if (user.areas.length === 0) return '—';
  return user.areas.map((area) => area.name).join(', ');
}

/**
 * A Pakistani mobile in the 03XXXXXXXXX form used as the default username.
 * Returns the trimmed input unchanged when it does not look like one.
 */
export function localMobile(value: string) {
  const digits = value.replace(/\D/g, '');
  if (/^923\d{9}$/.test(digits)) return `0${digits.slice(2)}`;
  if (/^00923\d{9}$/.test(digits)) return `0${digits.slice(4)}`;
  if (/^3\d{9}$/.test(digits)) return `0${digits}`;
  if (/^03\d{9}$/.test(digits)) return digits;
  return value.trim();
}
