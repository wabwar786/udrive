'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { signOut } from '@/lib/auth';
import { useSession } from '@/lib/useSession';

const LINKS = [
  ['/tours/', 'Tours'],
  ['/rent-a-car/', 'Rent a car'],
  ['/hotels/', 'Hotels'],
  ['/destinations/', 'Destinations'],
  ['/weather/', 'Weather'],
  ['/partner/', 'Become a partner'],
] as const;

export function Header() {
  const path = usePathname() ?? '/';
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [menu, setMenu] = useState(false);
  const { user } = useSession();
  const first = (user?.name || '').split(' ')[0] || 'Account';
  // Home: the header floats over the hero picture until the page scrolls.
  const home = path === '/';
  const [solid, setSolid] = useState(false);
  useEffect(() => {
    if (!home) return;
    const on = () => setSolid(window.scrollY > 40);
    on();
    window.addEventListener('scroll', on, { passive: true });
    return () => window.removeEventListener('scroll', on);
  }, [home]);

  return (
    <header className={`top ${home ? `home ${solid || open ? 'solid' : ''}` : ''}`}>
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
          <Link className="navOnly" href={user ? '/account/' : '/login/?next=/account/'} onClick={() => setOpen(false)}>List your vehicle or hotel</Link>
        </nav>
        <Link className="btn ghost listBtn" href={user ? '/account/' : '/login/?next=/account/'}>List your vehicle or hotel</Link>
        {user ? (
          <div className="who">
            <button className="btn dark" aria-expanded={menu} onClick={() => setMenu(!menu)}>{first} ▾</button>
            {menu && (
              <div className="whoMenu" onMouseLeave={() => setMenu(false)}>
                <Link href="/account/?tab=myrentals" onClick={() => setMenu(false)}>My rentals</Link>
                <Link href="/account/?tab=vehicles" onClick={() => setMenu(false)}>My vehicles &amp; hotels</Link>
                <Link href="/account/?tab=partner" onClick={() => setMenu(false)}>My partnership request</Link>
                <button onClick={async () => { setMenu(false); await signOut(); router.push('/'); }}>Log out</button>
              </div>
            )}
          </div>
        ) : (
          <Link className="btn dark" href={`/login/?next=${encodeURIComponent(path.startsWith('/login') ? '/account/' : path)}`}>Log in</Link>
        )}
        <button className="menuBtn" aria-expanded={open} onClick={() => setOpen(!open)}>Menu</button>
      </div>
    </header>
  );
}
