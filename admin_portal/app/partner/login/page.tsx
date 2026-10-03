'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { ArrowRight, Handshake, Loader2 } from 'lucide-react';

import {
  requestPartnerOtp,
  verifyPartnerOtp,
} from '../../lib/partner-api';

/**
 * Partner sign-in: phone number, then the WhatsApp code.
 *
 * The same sign-in the app uses, against the same account. A partner is a
 * customer who signed a contract, so a second password would be a second thing to
 * lose — and this way the phone number on the signature is one the OTP has
 * already proven.
 *
 * (The admin portal uses a username and password instead, for the opposite
 * reason: the WhatsApp settings that send these codes are configured inside that
 * portal, so an OTP-only sign-in there locks itself out whenever WA Engine is
 * misconfigured.)
 */
export default function Page() {
  const router = useRouter();
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const send = async () => {
    setBusy(true);
    setError('');
    try {
      await requestPartnerOtp(phone.trim());
      setSent(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'We could not send the code.');
    } finally {
      setBusy(false);
    }
  };

  const verify = async () => {
    setBusy(true);
    setError('');
    try {
      await verifyPartnerOtp(phone.trim(), code.trim());
      router.replace('/partner');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That code did not work.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="loginPage">
      <section className="loginShowcase">
        <div className="loginLogo">
          <span>UD</span> UDrive Partner
        </div>
        <div>
          <div className="eyebrow">TERRITORY PARTNERS</div>
          <h1>
            Your area.
            <br />
            Your record.
          </h1>
          <p>
            Your contract, what you committed to each month, and what your area
            earned — all in one place, the same figures the UDrive office sees.
          </p>
        </div>
        <div className="trustStrip">
          <Handshake />
          <span>One partner per area · Signed, dated and recorded</span>
        </div>
      </section>

      <section className="loginPanel">
        <div className="loginCard">
          <div className="loginIcon">
            <Handshake />
          </div>
          <h2>Partner sign in</h2>
          <p>
            Use the phone number UDrive has for you. We send a code on WhatsApp — the
            same way you sign in to the app.
          </p>

          {error && <div className="errorBox">{error}</div>}

          {!sent ? (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                void send();
              }}
            >
              <label className="field">
                <span>Phone number</span>
                <input
                  value={phone}
                  inputMode="tel"
                  autoComplete="tel"
                  placeholder="03xxxxxxxxx"
                  onChange={(e) => setPhone(e.target.value)}
                />
              </label>
              <button
                className="primaryButton wide"
                type="submit"
                disabled={busy || phone.trim().length < 10}
              >
                {busy ? <Loader2 className="spin" /> : 'Send the code'}
                <ArrowRight />
              </button>
            </form>
          ) : (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                void verify();
              }}
            >
              <label className="field">
                <span>Code from WhatsApp</span>
                <input
                  value={code}
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  placeholder="______"
                  onChange={(e) => setCode(e.target.value)}
                />
              </label>
              <button
                className="primaryButton wide"
                type="submit"
                disabled={busy || code.trim().length < 4}
              >
                {busy ? <Loader2 className="spin" /> : 'Sign in'}
                <ArrowRight />
              </button>
              <button
                className="secondaryButton wide"
                type="button"
                style={{ marginTop: 10 }}
                disabled={busy}
                onClick={() => {
                  setSent(false);
                  setCode('');
                }}
              >
                Change the number
              </button>
            </form>
          )}
        </div>
      </section>
    </main>
  );
}
