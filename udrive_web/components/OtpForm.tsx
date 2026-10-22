'use client';

import { useEffect, useState } from 'react';

import { currentToken, requestCode, signedInPhone, verifyCode } from '@/lib/auth';
import { normalisePhone } from '@/lib/format';

/**
 * Name + WhatsApp number → 4-digit code on WhatsApp → signed in.
 * The token stays in memory only. `onVerified` gets the token.
 */
export function OtpForm({
  action,
  onVerified,
  busy,
}: {
  action: string;
  onVerified: (token: string, name: string) => void;
  busy?: boolean;
}) {
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false);
  const [wait, setWait] = useState(0);
  const [error, setError] = useState('');
  const [working, setWorking] = useState(false);

  useEffect(() => {
    if (wait <= 0) return;
    const t = setTimeout(() => setWait(wait - 1), 1000);
    return () => clearTimeout(t);
  }, [wait]);

  const token = currentToken();
  if (token && signedInPhone()) {
    return (
      <>
        <label className="fld"><span>Your name</span><input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} autoComplete="name" /></label>
        <div className="msg info">Signed in with {signedInPhone()}.</div>
        <button className="btn dark block" disabled={busy || name.trim().length < 2} onClick={() => onVerified(token, name.trim())}>{action}</button>
      </>
    );
  }

  async function send() {
    setError('');
    const p = normalisePhone(phone);
    if (name.trim().length < 2) return setError('Please write your name.');
    if (!p) return setError('Write a Pakistani mobile number, like 0300 1234567.');
    setWorking(true);
    try {
      setWait(await requestCode(p));
      setSent(true);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setWorking(false);
    }
  }

  async function verify() {
    setError('');
    const p = normalisePhone(phone)!;
    if (!/^\d{4,8}$/.test(code.trim())) return setError('Write the code from WhatsApp.');
    setWorking(true);
    try {
      const t = await verifyCode(p, code, name);
      onVerified(t, name.trim());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setWorking(false);
    }
  }

  return (
    <>
      <label className="fld"><span>Your name</span><input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} autoComplete="name" disabled={sent} /></label>
      <label className="fld"><span>WhatsApp number</span><input value={phone} onChange={(e) => setPhone(e.target.value)} inputMode="tel" autoComplete="tel" placeholder="0300 1234567" disabled={sent} /></label>
      {sent && (
        <label className="fld"><span>Code sent to your WhatsApp</span><input value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))} inputMode="numeric" autoComplete="one-time-code" maxLength={8} autoFocus /></label>
      )}
      {error && <div className="msg err" role="alert">{error}</div>}
      {!sent ? (
        <button className="btn dark block" onClick={send} disabled={working}>{working ? 'Sending…' : 'Send code on WhatsApp'}</button>
      ) : (
        <>
          <button className="btn dark block" onClick={verify} disabled={working || busy}>{working || busy ? 'Please wait…' : action}</button>
          <div className="note">
            {wait > 0 ? `Didn't get it? You can resend in ${wait}s.` : <button className="link" style={{ background: 'none', border: 'none', cursor: 'pointer' }} onClick={send}>Resend code</button>}
            {' · '}<button className="link" style={{ background: 'none', border: 'none', cursor: 'pointer' }} onClick={() => { setSent(false); setCode(''); }}>Change number</button>
          </div>
        </>
      )}
    </>
  );
}
