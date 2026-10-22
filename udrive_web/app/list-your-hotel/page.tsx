import type { Metadata } from 'next';

import { HotelWizard } from './wizard';

export const metadata: Metadata = {
  title: 'List your hotel or guest house',
  description: 'Hotel, guest house or hut in Azad Kashmir? List it on UDrive for free and get bookings from tour travellers on WhatsApp.',
  alternates: { canonical: '/list-your-hotel/' },
};

export default function Page() {
  return (
    <div className="wrap">
      <div className="pagehead">
        <h1>List your hotel on UDrive</h1>
        <p className="muted" style={{ maxWidth: 640 }}>
          Hotels, guest houses, resorts and huts across Azad Kashmir. Your listing goes live after a quick check by our
          team, and every booking comes to your WhatsApp. You can manage it any time from Hotel mode in the UDrive app.
        </p>
      </div>
      <section className="sec"><HotelWizard /></section>
    </div>
  );
}
