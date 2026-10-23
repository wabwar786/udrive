import type { Metadata } from 'next';

import { LoginView } from './login-view';

export const metadata: Metadata = {
  title: 'Log in',
  description: 'Log in to UDrive with your WhatsApp number — the same account as the UDrive app.',
  alternates: { canonical: '/login/' },
  robots: { index: false, follow: false },
};

export default function Page() {
  return <LoginView />;
}
