'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity,
  BadgeCheck,
  BarChart3,
  BookOpenCheck,
  Building2,
  Car,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  CircleDollarSign,
  CircleHelp,
  ClipboardList,
  Compass,
  Database,
  Fuel,
  Headphones,
  Landmark,
  LayoutDashboard,
  ListChecks,
  LogOut,
  MapPinned,
  Megaphone,
  Menu,
  MessageSquareWarning,
  Mountain,
  Navigation,
  PackageCheck,
  Radar,
  Route,
  Search,
  Settings,
  ShieldAlert,
  Stethoscope,
  ToggleLeft,
  TrendingUp,
  TriangleAlert,
  Users,
  UsersRound,
  Wallet,
  Workflow,
  X,
} from 'lucide-react';
import {
  readSession,
  saveSession,
  type AdminSession,
} from '../lib/admin-api';
import { BrandMark, BrandWordmark } from './brand';
import { GuideButton } from './guide-button';

/**
 * The menu, in seven groups.
 *
 * Ordered by how often a screen is opened rather than by which table it reads.
 * DAILY OPERATIONS comes first and holds exactly the screens an admin works
 * every morning, in the order the queues should be cleared; everything that is
 * configured once and left alone is at the bottom under SETUP. Before this,
 * twenty of the thirty-five screens sat in one group called CONTROL CENTRE,
 * which meant the two screens somebody needs daily were nineteen rows apart
 * from each other.
 *
 * Labels are English on purpose — the portal is English, the guide is Roman
 * Urdu — and every label here is repeated word for word in
 * `app/lib/guide-content.ts`, so the guide can be read as a map of this menu.
 * Renaming a group or an item means renaming it in both files in one edit.
 *
 * Each route appears exactly once. `/vehicles` used to be listed twice, under
 * two names, and both rows highlighted as active at the same time.
 */
const groups = [
  {
    label: 'DAILY OPERATIONS',
    items: [
      ['/', 'Overview', LayoutDashboard],
      ['/ride-requests', 'Ride requests', Activity],
      ['/bookings', 'Bookings', BookOpenCheck],
      ['/operations', 'Operations & dispatch', Workflow],
      ['/live-tracking', 'Live tracking', Navigation],
      ['/verification', 'Verification', BadgeCheck],
      ['/wallet-topups', 'Driver top-ups', Wallet],
    ],
  },
  {
    label: 'PEOPLE & FLEET',
    items: [
      ['/drivers', 'Drivers', UsersRound],
      ['/customers', 'Customers', Users],
      ['/vehicles', 'Vehicles', Car],
    ],
  },
  {
    label: 'TOURISM',
    items: [
      ['/packages', 'Tour packages', PackageCheck],
      ['/destinations', 'Destinations', Compass],
      ['/hotels', 'Hotels & approvals', Building2],
      ['/routes', 'Routes', Route],
      ['/advisories', 'Road advisories', TriangleAlert],
    ],
  },
  {
    label: 'PRICING & MONEY',
    items: [
      ['/pricing', 'Pricing & fares', CircleDollarSign],
      ['/fare-zones', 'Fare zones', Mountain],
      ['/fuel-prices', 'Fuel prices', Fuel],
      ['/rate-insights', 'Route insights', TrendingUp],
      ['/finance', 'Finance & settlements', Landmark],
      ['/payments', 'Legacy payments', ClipboardList],
    ],
  },
  {
    label: 'TRUST & SAFETY',
    items: [
      ['/safety', 'Safety incidents', ShieldAlert],
      ['/disputes', 'Complaints & disputes', MessageSquareWarning],
      ['/support', 'Support tickets', Headphones],
    ],
  },
  {
    label: 'REPORTS',
    items: [
      ['/executive-operations', 'Executive operations', Radar],
      ['/reports', 'Reports & reconciliation', BarChart3],
      ['/audit', 'Audit log', ListChecks],
    ],
  },
  {
    label: 'SETUP',
    items: [
      ['/services', 'Services', ToggleLeft],
      ['/notifications', 'Notifications', Megaphone],
      ['/settings', 'Settings', Settings],
      ['/places', 'Map places', MapPinned],
      ['/appearance', 'Address search', Search],
      ['/data-management', 'Data management', Database],
      ['/diagnostics', 'Diagnostics', Stethoscope],
      ['/help', 'Help / How to use', CircleHelp],
    ],
  },
] as const;

const FOLDED_KEY = 'udrive.nav.folded';

export function AdminFrame({
  children,
  title,
  subtitle,
  actions,
}: {
  children: React.ReactNode;
  title: string;
  subtitle?: string;
  actions?: React.ReactNode;
}) {
  const path = usePathname();
  const router = useRouter();
  const [session, setSession] = useState<AdminSession | null>(null);
  const [open, setOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);
  const [folded, setFolded] = useState<string[]>([]);

  useEffect(() => {
    const value = readSession();
    if (!value) {
      router.replace('/login');
      return;
    }
    setSession(value);
  }, [router]);

  // Read after mount rather than in the initial state, so the server-rendered
  // markup and the first client render agree. Reading localStorage during
  // render makes them differ and React replaces the whole menu.
  useEffect(() => {
    try {
      const saved = JSON.parse(window.localStorage.getItem(FOLDED_KEY) ?? 'null');
      // Checked rather than cast. Anything else under this key — a stray
      // value, an older format — would otherwise reach `folded.includes` on
      // the next render and throw, and since AdminFrame wraps every page that
      // is a blank portal that survives a reload.
      if (Array.isArray(saved)) {
        setFolded(saved.filter((entry): entry is string => typeof entry === 'string'));
      }
    } catch {
      // A blocked or full localStorage is not a reason to fail to draw a menu.
    }
  }, []);

  const applyFolded = useCallback((next: string[]) => {
    setFolded(next);
    try {
      window.localStorage.setItem(FOLDED_KEY, JSON.stringify(next));
    } catch {
      // Folding still works for this visit; it just will not be remembered.
    }
  }, []);

  const toggleGroup = useCallback(
    (label: string) => {
      applyFolded(
        folded.includes(label)
          ? folded.filter((entry) => entry !== label)
          : [...folded, label],
      );
    },
    [applyFolded, folded],
  );

  // Opening a page inside a folded group unfolds it, so you can always see
  // where you are. Keyed on the path alone: re-running this when `folded`
  // changes would make folding the group you are standing in impossible —
  // the effect would undo the click immediately.
  useEffect(() => {
    const owner = groups.find((group) =>
      group.items.some(([href]) => href === path),
    );
    if (!owner) return;
    setFolded((current) => {
      if (!current.includes(owner.label)) return current;
      const next = current.filter((entry) => entry !== owner.label);
      try {
        window.localStorage.setItem(FOLDED_KEY, JSON.stringify(next));
      } catch {
        // As above.
      }
      return next;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [path]);

  const initials = useMemo(
    () =>
      session?.user.fullName
        .split(' ')
        .map((value) => value[0])
        .slice(0, 2)
        .join('')
        .toUpperCase() ?? 'UD',
    [session],
  );

  const displayedRole = useMemo(() => {
    if (!session) return '';
    return (
      ['SuperAdmin', 'Admin', 'Manager'].find((role) =>
        session.user.roles.includes(role),
      ) ?? session.user.roles[0] ?? 'User'
    );
  }, [session]);

  if (!session) {
    return <div className="boot">Securing operations workspace…</div>;
  }

  return (
    <div className={`adminShell ${collapsed ? 'collapsed' : ''}`}>
      <aside className={`sidebar ${open ? 'sidebarOpen' : ''}`}>
        <div className="brand">
          {collapsed ? (
            <BrandMark className="brandMarkCollapsed" size={44} />
          ) : (
            <div className="brandText">
              <BrandWordmark height={46} />
              <span>Tourism Operations</span>
            </div>
          )}
          <button className="mobileClose" onClick={() => setOpen(false)}>
            <X />
          </button>
        </div>
        <nav>
          {groups.map((group) => {
            // Never fold anything while the rail is collapsed to icons: there
            // the headings are hidden, so a folded group would be a menu with
            // rows missing and nothing on screen to explain why. Otherwise the
            // fold state is the only thing that decides, so a click on a
            // heading always does what it appears to do. The group holding the
            // current page is kept visible by the effect above, which unfolds
            // it on arrival rather than by overriding it here.
            const isOpen = collapsed || !folded.includes(group.label);

            return (
              <section key={group.label}>
                <button
                  type="button"
                  className={`navGroupHead ${isOpen ? '' : 'navGroupFolded'}`}
                  onClick={() => toggleGroup(group.label)}
                  aria-expanded={isOpen}
                >
                  <span>{group.label}</span>
                  <ChevronDown size={13} />
                </button>
                {isOpen &&
                  group.items.map(([href, label, Icon]) => (
                    <Link
                      key={href}
                      href={href}
                      onClick={() => setOpen(false)}
                      className={path === href ? 'active' : ''}
                    >
                      <Icon size={17} />
                      <span>{label}</span>
                    </Link>
                  ))}
              </section>
            );
          })}
        </nav>
        <button
          className="collapseButton"
          onClick={() => setCollapsed((value) => !value)}
        >
          {collapsed ? <ChevronRight /> : <ChevronLeft />}
          <span>Collapse menu</span>
        </button>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <button className="menuButton" onClick={() => setOpen(true)}>
            <Menu />
          </button>
          <div className="pageTitle">
            <h1>{title}</h1>
            {subtitle && <p>{subtitle}</p>}
          </div>
          <div className="topActions">
            {actions}
            {/*
              Sits on every screen, top right, before the identity block.
              Help that lives only on its own page is help nobody reads at the
              moment they are stuck.
            */}
            <GuideButton />
            <div className="adminIdentity">
              <span>{initials}</span>
              <div>
                <strong>{session.user.fullName}</strong>
                <small>{displayedRole}</small>
              </div>
            </div>
            <button
              className="iconButton"
              title="Sign out"
              onClick={() => {
                saveSession(null);
                router.replace('/login');
              }}
            >
              <LogOut />
            </button>
          </div>
        </header>
        <main className="content">{children}</main>
      </div>
      {open && <button className="drawerShade" onClick={() => setOpen(false)} />}
    </div>
  );
}
