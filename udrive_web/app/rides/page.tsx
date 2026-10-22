import type { Metadata } from 'next';

import { PlayButton } from '@/components/PlayButton';

export const metadata: Metadata = {
  title: 'City rides and rent a car in Muzaffarabad',
  description: 'Name your own fare and pick the driver you like — car, bike, rickshaw, Hiace or Coaster. City rides, city-to-city trips and rent a car in the UDrive app.',
  alternates: { canonical: '/rides/' },
};

export default function Page() {
  return (
    <div className="wrap">
      <div className="pagehead">
        <h1>City rides, in the app</h1>
        <p className="muted" style={{ maxWidth: 640 }}>Rides are booked in the UDrive app, where you can see drivers near you live, track your trip and use SOS.</p>
      </div>
      <section className="sec">
        <div className="steps">
          <div className="step"><em>01</em><b>Say where and how much</b><p>Choose the vehicle — car, bike, rickshaw, Hiace or Coaster — and the fare you want to pay.</p></div>
          <div className="step"><em>02</em><b>Drivers send offers</b><p>Nearby drivers accept or send their own fare. You see each driver&apos;s rating and vehicle.</p></div>
          <div className="step"><em>03</em><b>Pick one and go</b><p>Confirm the offer you like and track the driver live until pickup.</p></div>
        </div>
      </section>
      <section className="sec owner" id="rent">
        <div className="ob">
          <h3>Rent a car</h3>
          <p>Rent a car by the day, with or without a driver, from owners on UDrive. Choose dates, see the daily rent and the terms, and book in the app.</p>
          <PlayButton />
        </div>
        <div className="ob">
          <h3>City to city</h3>
          <p>Muzaffarabad to Islamabad, Rawalakot, Kotli and back — book a seat or the whole vehicle on trips leaving today.</p>
          <PlayButton />
        </div>
      </section>
    </div>
  );
}
