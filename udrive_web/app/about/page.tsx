import type { Metadata } from 'next';
import Link from 'next/link';

import { whatsappLink } from '@/lib/config';

export const metadata: Metadata = {
  title: 'About UDrive',
  description: 'UDrive is a ride, tour and hotel app built for Azad Kashmir, starting in Muzaffarabad.',
  alternates: { canonical: '/about/' },
};

export default function Page() {
  return (
    <div className="wrap" style={{ maxWidth: 760 }}>
      <div className="pagehead"><h1>About UDrive</h1></div>
      <div className="prose sec">
        <p>UDrive is a ride, tour and hotel app made for Azad Kashmir. We started in Muzaffarabad and are adding more cities step by step.</p>
        <p>On UDrive you name the fare and choose the driver you like. Tour drivers publish their own packages with dates, seats and prices, and hotels list their own rooms and rates. Every driver and hotel owner is checked by our team before they go live.</p>
        <p>Questions, complaints or a business enquiry? <a className="link" href={whatsappLink()} target="_blank" rel="noopener noreferrer">Message us on WhatsApp</a>.</p>
        <p><Link className="link" href="/tours/">See open tours</Link></p>
      </div>
    </div>
  );
}
