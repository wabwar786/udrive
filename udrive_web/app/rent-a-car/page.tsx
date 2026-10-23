import type { Metadata } from 'next';

import { JsonLd } from '@/components/JsonLd';
import { atBuild } from '@/lib/api';
import { SITE_URL } from '@/lib/config';
import type { RentCar } from '@/lib/types';
import { RentView } from './rent-view';

export const metadata: Metadata = {
  title: 'Rent a car in Azad Kashmir — with or without driver',
  description:
    'Rent a car, jeep, Hiace or Coaster by the day in Muzaffarabad, Neelum, Bagh and across Azad Kashmir. With driver or self drive, from verified local owners.',
  alternates: { canonical: '/rent-a-car/' },
  openGraph: { title: 'Rent a car in Azad Kashmir | UDrive', url: '/rent-a-car/' },
};

const FAQ = [
  ['How do I book a car?', 'Choose a car here, then book it in the UDrive app: pick your dates, pay the advance, and the owner confirms on WhatsApp.'],
  ['Can I drive it myself?', 'Yes, where the owner offers self drive. You need your CNIC and a valid driving licence; some cars ask for a security deposit at handover.'],
  ['Do you have 4×4 jeeps for Neelum and Leepa?', 'Yes — filter by Jeep / 4×4. For high roads like Arang Kel or Ratti Gali, a jeep with an experienced local driver is best.'],
];

export default async function Page() {
  const cars = await atBuild<RentCar[]>('/api/v1/web/rent-cars', []);
  return (
    <div className="wrap">
      <JsonLd data={{
        '@context': 'https://schema.org',
        '@graph': [
          { '@type': 'BreadcrumbList', itemListElement: [
            { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE_URL}/` },
            { '@type': 'ListItem', position: 2, name: 'Rent a car', item: `${SITE_URL}/rent-a-car/` },
          ] },
          { '@type': 'FAQPage', mainEntity: FAQ.map(([q, a]) => ({ '@type': 'Question', name: q, acceptedAnswer: { '@type': 'Answer', text: a } })) },
        ],
      }} />
      <div className="pagehead">
        <h1>Rent a car in Azad Kashmir</h1>
        <p className="muted" style={{ maxWidth: 680 }}>By the day, with a driver or self drive — cars, 4×4 jeeps, Hiace and Coaster from owners checked by UDrive.</p>
      </div>
      <RentView initial={cars} />
      <section className="sec">
        <h2 style={{ fontSize: 22, marginBottom: 8 }}>Questions</h2>
        {FAQ.map(([q, a]) => <details key={q} className="faq"><summary>{q}</summary><p>{a}</p></details>)}
      </section>
    </div>
  );
}
