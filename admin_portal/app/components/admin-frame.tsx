'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';
import {
  Activity,
  BadgeCheck,
  BookOpenCheck,
  Car,
  ChevronLeft,
  ChevronRight,
  CircleDollarSign,
  ClipboardList,
  BarChart3,
  Building2,
  Database,
  Stethoscope,
  Compass,
  Headphones,
  CircleHelp,
  Image as ImageIcon,
  LayoutDashboard,
  LogOut,
  MapPinned,
  Megaphone,
  MessageSquareWarning,
  Menu,
  PackageCheck,
  Route,
  Settings,
  ShieldAlert,
  Users,
  UsersRound,
  X,
} from 'lucide-react';
import {
  readSession,
  saveSession,
  type AdminSession,
} from '../lib/admin-api';
import { BrandMark, BrandWordmark } from './brand';

const groups = [
  {
    label: 'OPERATIONS',
    items: [
      ['/', 'Overview', LayoutDashboard],
      ['/bookings', 'Bookings', BookOpenCheck],
      ['/operations', 'Operations & dispatch', Activity],
      ['/executive-operations', 'Executive operations', Activity],
      ['/live-tracking', 'Live tracking', MapPinned],
      ['/ride-requests', 'Ride requests', Activity],
      ['/packages', 'Tour packages', PackageCheck],
    ],
  },
  {
    label: 'PEOPLE & FLEET',
    items: [
      ['/verification', 'Verification', BadgeCheck],
      ['/customers', 'Users & access', Users],
      ['/drivers', 'Drivers', UsersRound],
      ['/vehicles', 'Vehicles', Car],
    ],
  },
  {
    label: 'TOURISM',
    items: [
      ['/destinations', 'Destinations', Compass],
      ['/hotels', 'Hotels & approvals', Building2],
      ['/routes', 'Routes', Route],
      ['/advisories', 'Road advisories', MapPinned],
    ],
  },
  {
    label: 'CONTROL CENTRE',
    items: [
      ['/safety', 'Safety incidents', ShieldAlert],
      ['/disputes', 'Complaints & disputes', MessageSquareWarning],
      ['/pricing', 'Pricing & fares', CircleDollarSign],
      ['/finance', 'Finance & settlements', CircleDollarSign],
      ['/payments', 'Legacy payments', CircleDollarSign],
      ['/support', 'Support tickets', Headphones],
      ['/notifications', 'Notifications', Megaphone],
      ['/reports', 'Reports & reconciliation', BarChart3],
      ['/audit', 'Audit log', ClipboardList],
      ['/diagnostics', 'Diagnostics', Stethoscope],
      ['/help', 'Help / How to use', CircleHelp],
      ['/appearance', 'Address search', ImageIcon],
      ['/places', 'Map places', MapPinned],
      ['/vehicles', 'Vehicle pictures', ImageIcon],
      ['/settings', 'Settings', Settings],
      ['/data-management', 'Data management', Database],
    ],
  },
] as const;

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

  useEffect(() => {
    const value = readSession();
    if (!value) {
      router.replace('/login');
      return;
    }
    setSession(value);
  }, [router]);

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
          {groups.map((group) => (
            <section key={group.label}>
              <p>{group.label}</p>
              {group.items.map(([href, label, Icon]) => (
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
          ))}
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
