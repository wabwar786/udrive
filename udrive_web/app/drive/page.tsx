import type { Metadata } from 'next';

import { PlayButton } from '@/components/PlayButton';

export const metadata: Metadata = {
  title: 'Drive with UDrive — rides, tours and rentals',
  description: 'Car, bike, rickshaw, Hiace or Coaster? Join UDrive in the app, set your own tour packages and get bookings straight to your phone. Rs 1,000 welcome bonus in your wallet.',
  alternates: { canonical: '/drive/' },
};

export default function Page() {
  return (
    <div className="wrap">
      <div className="pagehead">
        <h1>Drive with UDrive</h1>
        <p className="muted" style={{ maxWidth: 640 }}>City rides, city-to-city trips, tours and rent-a-car — all from one app. Registration happens in the UDrive app (Driver mode), not on the website.</p>
      </div>
      <section className="sec">
        <div className="steps">
          <div className="step"><em>01</em><b>Install the app</b><p>Download UDrive from Google Play and sign in with your WhatsApp number.</p></div>
          <div className="step"><em>02</em><b>Switch to Driver mode</b><p>Add your vehicle, CNIC and driving licence. Our team checks them before you go live.</p></div>
          <div className="step"><em>03</em><b>Choose your work</b><p>City rides, tours with your own packages and dates, or rent a car — bookings come straight to your phone.</p></div>
        </div>
      </section>
      <section className="sec owner">
        <div className="ob">
          <h3>What you get</h3>
          <ul className="ticks">
            <li>Rs 1,000 welcome bonus in your UDrive wallet (wallet credit, not cash)</li>
            <li>You name your own fare on rides — customers choose the offer they like</li>
            <li>Tour packages with your own dates, per seat and whole vehicle prices</li>
            <li>Tour and rent bookings on WhatsApp too, even when the app is closed</li>
          </ul>
          <PlayButton />
        </div>
        <div className="ob">
          <h3>Vehicles we take</h3>
          <ul className="ticks"><li>Car</li><li>Bike</li><li>Rickshaw</li><li>Hiace</li><li>Coaster</li></ul>
          <p>Anyone who drives customers must have a valid driving licence — including owners who drive themselves.</p>
        </div>
      </section>
    </div>
  );
}
