import type { Metadata } from 'next';

import { AccountView } from './account-view';

export const metadata: Metadata = {
  title: 'My account',
  alternates: { canonical: '/account/' },
  robots: { index: false, follow: false },
};

export default function Page() {
  return <AccountView />;
}
