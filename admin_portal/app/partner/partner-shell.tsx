'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import type { ReactNode } from 'react';
import { FileText, LayoutDashboard, LogOut } from 'lucide-react';

import { readPartnerSession, savePartnerSession } from '../lib/partner-api';

/**
 * The frame around the partner's own pages.
 *
 * Nothing in common with `AdminFrame` on purpose. A partner must never see the
 * admin menu — not greyed out, not collapsed, not there at all — because the way
 * a partner would find out that /drivers exists is by seeing it in a sidebar and
 * trying it. Two frames is the cheap way to make that impossible.
 *
 * Two pages, so the navigation is two links.
 */
export function PartnerShell({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const session = readPartnerSession();

  const signOut = () => {
    savePartnerSession(null);
    router.replace('/partner/login');
  };

  return (
    <div className="partnerShell">
      <header className="partnerBar">
        <div className="partnerBrand">
          <span>UD</span>
          <div>
            <strong>UDrive Partner</strong>
            <small>{session?.user?.fullName ?? ''}</small>
          </div>
        </div>

        <nav className="partnerNav">
          <Link
            href="/partner"
            className={pathname === '/partner' ? 'active' : undefined}
          >
            <LayoutDashboard /> <span>Dashboard</span>
          </Link>
          <Link
            href="/partner/contract"
            className={pathname?.startsWith('/partner/contract') ? 'active' : undefined}
          >
            <FileText /> <span>Contract</span>
          </Link>
        </nav>

        <button className="secondaryButton" onClick={signOut}>
          <LogOut /> Sign out
        </button>
      </header>

      <main className="partnerContent">
        <div className="partnerHead">
          <h1>{title}</h1>
          {subtitle && <p>{subtitle}</p>}
        </div>
        {children}
      </main>
    </div>
  );
}
