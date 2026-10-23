import Link from 'next/link';

import { API_URL, PLAY_URL, whatsappLink } from '@/lib/config';

export function Footer() {
  const legal = (p: string) => (API_URL ? `${API_URL}/${p}` : '#');
  return (
    <footer className="foot">
      <div className="wrap">
        <div>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="UDrive" width={85} height={32} loading="lazy" />
          <div>Rides, tours and hotels across Azad Kashmir. Muzaffarabad first — more cities soon.</div>
        </div>
        <div>
          <b>Travel</b>
          <Link href="/tours/">Tour packages</Link>
          <Link href="/rent-a-car/">Rent a car</Link>
          <Link href="/hotels/">Hotels</Link>
          <Link href="/destinations/">Destinations</Link>
          <Link href="/weather/">Weather</Link>
          <Link href="/rides/">City rides</Link>
        </div>
        <div>
          <b>Partners</b>
          <Link href="/partner/">Become a partner</Link>
          <Link href="/account/">List your vehicle</Link>
          <Link href="/list-your-hotel/">List your hotel</Link>
          <Link href="/drive/">Drive with UDrive</Link>
          <a href={whatsappLink('Assalam o Alaikum, I want to advertise on UDrive.')} target="_blank" rel="noopener noreferrer">Advertise with us</a>
        </div>
        <div>
          <b>UDrive</b>
          <Link href="/about/">About</Link>
          <a href={whatsappLink()} target="_blank" rel="noopener noreferrer">Contact on WhatsApp</a>
          <a href={legal('privacy')} rel="noopener">Privacy policy</a>
          <a href={legal('terms')} rel="noopener">Terms</a>
          <a href={PLAY_URL} target="_blank" rel="noopener noreferrer">UDrive on Google Play</a>
        </div>
        <div className="copy">© {new Date().getFullYear()} UDrive. All rights reserved.</div>
      </div>
    </footer>
  );
}
