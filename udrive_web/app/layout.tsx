import type { Metadata, Viewport } from 'next';

import { Footer } from '@/components/Footer';
import { Header } from '@/components/Header';
import { JsonLd } from '@/components/JsonLd';
import { API_URL, PLAY_URL, SITE_DESCRIPTION, SITE_NAME, SITE_URL, WHATSAPP } from '@/lib/config';
import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: { default: `${SITE_NAME} — Tours, rent a car and hotels in Azad Kashmir`, template: `%s | ${SITE_NAME}` },
  description: SITE_DESCRIPTION,
  applicationName: 'UDrive',
  alternates: { canonical: '/' },
  openGraph: {
    type: 'website',
    siteName: SITE_NAME,
    locale: 'en_PK',
    url: '/',
    title: `${SITE_NAME} — Tours, rent a car and hotels in Azad Kashmir`,
    description: SITE_DESCRIPTION,
    images: [{ url: '/og.png', width: 1200, height: 630, alt: 'UDrive — Travel & Tour in Azad Kashmir' }],
  },
  twitter: { card: 'summary_large_image', title: SITE_NAME, description: SITE_DESCRIPTION, images: ['/og.png'] },
  robots: { index: true, follow: true },
  formatDetection: { telephone: false },
};

export const viewport: Viewport = { themeColor: '#0B1B33', width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>{API_URL && <link rel="preconnect" href={API_URL} crossOrigin="anonymous" />}</head>
      <body>
        <JsonLd
          data={{
            '@context': 'https://schema.org',
            '@graph': [
              {
                '@type': 'TravelAgency',
                '@id': `${SITE_URL}/#org`,
                name: SITE_NAME,
                alternateName: 'UDrive',
                url: `${SITE_URL}/`,
                logo: `${SITE_URL}/logo.png`,
                image: `${SITE_URL}/og.png`,
                description: SITE_DESCRIPTION,
                areaServed: { '@type': 'AdministrativeArea', name: 'Azad Jammu and Kashmir' },
                address: { '@type': 'PostalAddress', addressLocality: 'Muzaffarabad', addressCountry: 'PK' },
                ...(WHATSAPP ? { telephone: `+${WHATSAPP}` } : {}),
                sameAs: [PLAY_URL],
              },
              { '@type': 'WebSite', '@id': `${SITE_URL}/#site`, url: `${SITE_URL}/`, name: SITE_NAME, alternateName: 'UDrive', publisher: { '@id': `${SITE_URL}/#org` }, inLanguage: 'en' },
              {
                '@type': 'SiteNavigationElement',
                name: ['Tours', 'Rent a car', 'Hotels', 'Destinations', 'Become a partner'],
                url: ['/tours/', '/rent-a-car/', '/hotels/', '/destinations/', '/partner/'].map((p) => `${SITE_URL}${p}`),
              },
            ],
          }}
        />
        <a className="sr" href="#main">Skip to content</a>
        <Header />
        <main id="main">{children}</main>
        <Footer />
      </body>
    </html>
  );
}
