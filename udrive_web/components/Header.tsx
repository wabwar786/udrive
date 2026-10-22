'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState } from 'react';

import { PLAY_URL, WHATSAPP, whatsappLabel, whatsappLink } from '@/lib/config';

const LINKS = [
  ['/tours/', 'Tours'],
  ['/hotels/', 'Hotels'],
  ['/rides/', 'City rides'],
  ['/list-your-hotel/', 'List your hotel'],
  ['/drive/', 'Drive with us'],
] as const;

export function Header() {
  const path = usePathname() ?? '/';
  const [open, setOpen] = useState(false);
  return (
    <header className="top">
      <div className="wrap">
        <Link href="/" className="logo" aria-label="UDrive home">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="UDrive" width={101} height={38} />
        </Link>
        <nav className={`nav ${open ? 'open' : ''}`} aria-label="Main">
          {LINKS.map(([href, label]) => (
            <Link key={href} href={href} aria-current={path.startsWith(href) ? 'page' : undefined} onClick={() => setOpen(false)}>
              {label}
            </Link>
          ))}
        </nav>
        {WHATSAPP && (
          <a className="wa" href={whatsappLink()} target="_blank" rel="noopener noreferrer">
            WhatsApp {whatsappLabel()}
          </a>
        )}
        <a className="btn dark getApp" href={PLAY_URL} target="_blank" rel="noopener noreferrer">Get the app</a>
        <button className="menuBtn" aria-expanded={open} onClick={() => setOpen(!open)}>Menu</button>
      </div>
    </header>
  );
}
