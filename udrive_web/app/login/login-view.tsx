'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { OtpForm } from '@/components/OtpForm';
import { useSession } from '@/lib/useSession';

/** Only our own pages: "/account/", never "//evil.com" or "https://…". */
const safeNext = (raw: string | null) => (raw && /^\/(?!\/)[\w\-/?=&.%]*$/.test(raw) ? raw : '/account/');

export function LoginView() {
  const router = useRouter();
  const { ready, user } = useSession();
  const [next, setNext] = useState('/account/');

  useEffect(() => {
    setNext(safeNext(new URLSearchParams(window.location.search).get('next')));
  }, []);

  useEffect(() => {
    if (ready && user) router.replace(next);
  }, [ready, user, next, router]);

  return (
    <div className="wrap">
      <div className="login">
        <h1>Log in</h1>
        <p className="muted" style={{ marginTop: 0 }}>Use your WhatsApp number — the same account as the UDrive app. We send a code to WhatsApp, no password.</p>
        <OtpForm action="Log in" askName={false} onVerified={() => router.replace(next)} />
        <ul className="ticks small" style={{ marginTop: 18, marginBottom: 0 }}>
          <li>List cars for rent and tours — as many as you own</li>
          <li>Manage your hotel rooms, rates and special dates</li>
          <li>Track your partnership request</li>
        </ul>
        <p className="note">For your safety you are logged out after 30 minutes without use, and when you close the browser.</p>
      </div>
    </div>
  );
}
