import type { Metadata } from 'next';

import { JsonLd } from '@/components/JsonLd';
import { SITE_URL } from '@/lib/config';
import { PartnerForm } from './partner-form';

export const metadata: Metadata = {
  title: 'Become a UDrive partner in your city',
  description:
    'Bring UDrive rides, tours, rent-a-car and hotels to your city in Azad Kashmir. Tell us about yourself and your investment budget — our team will contact you on WhatsApp.',
  alternates: { canonical: '/partner/' },
  openGraph: { title: 'Become a UDrive partner', description: 'Run UDrive in your city in Azad Kashmir — send a partnership request.', url: '/partner/' },
};

const FAQ = [
  ['Who can become a partner?', 'Anyone in Azad Kashmir or Pakistan with local knowledge, a team or a transport business, who wants to run UDrive’s driver, hotel and tour network in one city or district.'],
  ['Do I pay anything online?', 'No. Sending the form is free and is not an agreement. UDrive never asks for money on WhatsApp before a written agreement is signed in person.'],
  ['What happens after I send the form?', 'Our team reads every request, contacts you on WhatsApp, and plans a meeting. You can follow the status and reply under “My partnership request” after logging in.'],
  ['Which budget should I choose?', 'Choose what you could invest in office, marketing and a local team. It helps us plan — the final amount is agreed in the meeting.'],
];

export default function Page() {
  return (
    <div className="wrap">
      <JsonLd data={{
        '@context': 'https://schema.org',
        '@graph': [
          { '@type': 'BreadcrumbList', itemListElement: [
            { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE_URL}/` },
            { '@type': 'ListItem', position: 2, name: 'Become a partner', item: `${SITE_URL}/partner/` },
          ] },
          { '@type': 'FAQPage', mainEntity: FAQ.map(([q, a]) => ({ '@type': 'Question', name: q, acceptedAnswer: { '@type': 'Answer', text: a } })) },
        ],
      }} />
      <div className="pg">
        <div>
          <span className="eyebrow">Partnership</span>
          <h1 style={{ fontSize: 'clamp(32px,4.4vw,46px)' }}>Bring UDrive to your city.</h1>
          <p className="lead">We are opening Azad Kashmir city by city with local partners who know the roads, the drivers and the people. Tell us about yourself — our team will contact you.</p>
          <div className="why">
            <div><b>Your city, your team</b><span>Run UDrive&apos;s driver, hotel and tour network in your area.</span></div>
            <div><b>Share in every booking</b><span>A share of UDrive&apos;s commission from your territory.</span></div>
            <div><b>Full support</b><span>App, brand, training and marketing material from UDrive.</span></div>
            <div><b>Clear agreement</b><span>Written terms before anything is paid.</span></div>
          </div>
          <p className="small muted">Sending this form is not an agreement and no money is taken online. UDrive never asks for payment on WhatsApp before a signed agreement.</p>
          <h2 style={{ fontSize: 22, margin: '30px 0 8px' }}>Questions</h2>
          {FAQ.map(([q, a]) => <details key={q} className="faq"><summary>{q}</summary><p>{a}</p></details>)}
        </div>
        <PartnerForm />
      </div>
    </div>
  );
}
