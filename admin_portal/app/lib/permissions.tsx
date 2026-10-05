'use client';

import { useEffect, useMemo, useSyncExternalStore } from 'react';

import { apiFetch, hasFullAccessRole, readSession } from './admin-api';

/**
 * What the signed-in portal user may open and do.
 *
 * SuperAdmin, Admin and the older roles have full access. A team user (portal
 * role `Staff`) gets modules and areas on the Team page; this file reads them
 * once per session from `GET /api/v1/admin/team/me` and answers "may I show
 * this?" for the menu, the pages and their buttons. The server checks every
 * call anyway — hiding here is only so nobody is shown a button that will be
 * refused.
 */

export type PermissionAction = 'view' | 'edit' | 'approve' | 'delete';

export type ModuleGrant = {
  module: string;
  view: boolean;
  edit: boolean;
  approve: boolean;
  delete: boolean;
};

export type AreaKind = 'District' | 'Tehsil';

export type TeamArea = {
  id: string;
  name: string;
  kind: AreaKind;
  districtName: string | null;
};

export type TeamMe = {
  fullAccess: boolean;
  permissions: ModuleGrant[];
  allAreas: boolean;
  areas: TeamArea[];
};

export type ModuleKey =
  | 'verification.city'
  | 'verification.tour'
  | 'verification.rent'
  | 'verification.hotels'
  | 'verification.businesses'
  | 'operations'
  | 'rentals'
  | 'customers'
  | 'tourism'
  | 'finance'
  | 'pricing'
  | 'growth'
  | 'safety'
  | 'reports'
  | 'settings'
  | 'team'
  | 'data';

/**
 * Module → portal routes. Same table as the API contract; keep the two equal.
 * `/verification` is not listed under any one module: it opens when any
 * verification module can be viewed, and each tab is checked on its own.
 */
export const MODULE_ROUTES: Record<ModuleKey, readonly string[]> = {
  'verification.city': [],
  'verification.tour': [],
  'verification.rent': [],
  'verification.hotels': ['/hotels'],
  'verification.businesses': ['/businesses'],
  operations: [
    '/',
    '/ride-requests',
    '/bookings',
    '/operations',
    '/live-tracking',
    '/drivers',
    '/vehicles',
  ],
  rentals: ['/rentals'],
  customers: ['/customers'],
  tourism: ['/packages', '/destinations', '/routes', '/advisories'],
  finance: ['/finance', '/payments', '/wallet-topups'],
  pricing: ['/pricing', '/fare-zones', '/fuel-prices', '/rate-insights'],
  growth: [
    '/campaigns',
    '/launch-cities',
    '/partners',
    '/territories',
    '/driver-updates',
    '/fraud-flags',
  ],
  safety: ['/safety', '/disputes', '/support', '/notifications'],
  reports: ['/executive-operations', '/reports', '/audit'],
  settings: ['/services', '/settings', '/areas'],
  team: ['/team'],
  data: ['/data-management'],
};

export const VERIFICATION_MODULES = [
  'verification.city',
  'verification.tour',
  'verification.rent',
  'verification.hotels',
  'verification.businesses',
] as const satisfies readonly ModuleKey[];

const VERIFICATION_ROUTE = '/verification';

/** The module that owns a path, or null when the path is open to everyone. */
export function moduleForPath(pathname: string): ModuleKey | null {
  const path = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;
  for (const key of Object.keys(MODULE_ROUTES) as ModuleKey[]) {
    for (const route of MODULE_ROUTES[key]) {
      if (route === '/') {
        if (path === '/') return key;
      } else if (path === route || path.startsWith(`${route}/`)) {
        return key;
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// A tiny store shared by every component on the page: one request per session.

type Snapshot = {
  /** Which session the data belongs to. */
  key: string;
  loaded: boolean;
  me: TeamMe | null;
};

const EMPTY: Snapshot = { key: '', loaded: false, me: null };

let snapshot: Snapshot = EMPTY;
let pending: Promise<void> | null = null;
let pendingKey = '';
const listeners = new Set<() => void>();

function publish(next: Snapshot) {
  snapshot = next;
  listeners.forEach((listener) => listener());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function getSnapshot() {
  return snapshot;
}

function getServerSnapshot() {
  return EMPTY;
}

/** Identifies the signed-in person, so a different sign-in reloads. */
function sessionKey(): string {
  const session = readSession();
  if (!session) return '';
  const user = session.user;
  return [user.id ?? user.phoneNumber ?? user.fullName, ...[...user.roles].sort()].join('|');
}

/** Used when `/me` cannot be read: full access only for a full-access role. */
function fallback(): TeamMe {
  const full = hasFullAccessRole(readSession()?.user.roles);
  return { fullAccess: full, permissions: [], allAreas: full, areas: [] };
}

function ensureLoaded() {
  const key = sessionKey();
  if (!key) return;
  if (snapshot.key === key && snapshot.loaded) return;
  if (pending && pendingKey === key) return;

  // A different person signed in: drop what belonged to the last one.
  if (snapshot.key && snapshot.key !== key) publish(EMPTY);

  pendingKey = key;
  const request = apiFetch<TeamMe>('/api/v1/admin/team/me')
    .then((me) => normalise(me))
    .catch(() => fallback())
    .then((me) => {
      if (pendingKey !== key) return;
      publish({ key, loaded: true, me });
    })
    .finally(() => {
      if (pendingKey === key) {
        pending = null;
        pendingKey = '';
      }
    });
  pending = request;
}

function normalise(value: TeamMe | null | undefined): TeamMe {
  if (!value) return fallback();
  return {
    fullAccess: Boolean(value.fullAccess),
    permissions: Array.isArray(value.permissions) ? value.permissions : [],
    allAreas: Boolean(value.allAreas) || Boolean(value.fullAccess),
    areas: Array.isArray(value.areas) ? value.areas : [],
  };
}

/** Forget the loaded permissions (sign-out, or before another sign-in). */
export function clearPermissions() {
  pending = null;
  pendingKey = '';
  publish(EMPTY);
}

// ---------------------------------------------------------------------------

export type Permissions = {
  loaded: boolean;
  fullAccess: boolean;
  can: (module: string, action: PermissionAction) => boolean;
  canRoute: (pathname: string) => boolean;
  allAreas: boolean;
  areas: TeamArea[];
};

export function buildPermissions(me: TeamMe | null, loaded: boolean): Permissions {
  const fullAccess = Boolean(me?.fullAccess);
  const grants = new Map((me?.permissions ?? []).map((grant) => [grant.module, grant]));

  const can = (module: string, action: PermissionAction) => {
    if (!loaded || !me) return false;
    if (fullAccess) return true;
    const grant = grants.get(module);
    if (!grant) return false;
    if (action === 'view') {
      // Any other action implies view; the Team form ticks it too.
      return grant.view || grant.edit || grant.approve || grant.delete;
    }
    return Boolean(grant[action]);
  };

  const canRoute = (pathname: string) => {
    if (!loaded || !me) return false;
    if (fullAccess) return true;
    const path = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;
    if (path === VERIFICATION_ROUTE || path.startsWith(`${VERIFICATION_ROUTE}/`)) {
      return VERIFICATION_MODULES.some((module) => can(module, 'view'));
    }
    const module = moduleForPath(path);
    return module === null || can(module, 'view');
  };

  return {
    loaded,
    fullAccess,
    can,
    canRoute,
    allAreas: fullAccess || Boolean(me?.allAreas),
    areas: me?.areas ?? [],
  };
}

/**
 * `{ loaded, fullAccess, can(module, action), canRoute(pathname), allAreas, areas }`.
 *
 * Until `loaded` is true everything answers "no"; the admin frame shows its
 * loading screen in that time, so nothing flashes and then disappears.
 */
export function usePermissions(): Permissions {
  const current = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);

  useEffect(() => {
    ensureLoaded();
  });

  const key = typeof window === 'undefined' ? '' : sessionKey();
  const belongs = current.key !== '' && current.key === key;

  return useMemo(
    () => buildPermissions(belongs ? current.me : null, belongs && current.loaded),
    [current, belongs],
  );
}
