'use client';

import { useEffect, useState } from 'react';

import { currentToken, requestCode, verifyCode } from '@/lib/auth';
import { useSession } from '@/lib/useSession';
import { normalisePhone } from '@/lib/format';

/**
 * Name + WhatsApp number → 4-digit code on WhatsApp → signed in.
 * The session is kept for this tab only (see lib/auth). `onVerified` gets the token.
 * `askName={false}` hides the name (log-in page: the name is optional there).
 */
export function OtpForm({
  action,
  onVerified,
  busy,
  askName = true,
  presetName = '',
}: {
  action: string;
  onVerified: (token: string, name: string) => void;
  busy?: boolean;
  askName?: boolean;
  /** Name typed elsewhere on the page (sent with the code when askName is off). */
  presetName?: string;
}) {
  const { ready, user } = useSession();
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

  useEffect(() => {
    if (user?.name && !name) setName(user.name);
  }, [user, name]);

  const token = ready && user ? currentToken() : null;
  if (token && user) {
    return (
      <>
        {askName && <label className="fld"><span>Your name</span><input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} autoComplete="name" /></label>}
        <div className="msg info">Logged in with {user.phone}.</div>
        <button className="btn dark block" disabled={busy || (askName && name.trim().length < 2)} onClick={() => onVerified(token, askName ? name.trim() : presetName.trim())}>{action}</button>
      </>
    );
  }

  async function send() {
    setError('');
    const p = normalisePhone(phone);
    if (askName && name.trim().length < 2) return setError('Please write your name.');
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
      const t = await verifyCode(p, code, askName ? name : presetName);
      onVerified(t, name.trim());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setWorking(false);
    }
  }

  return (
    <>
      {askName && <label className="fld"><span>Your name</span><input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} autoComplete="name" disabled={sent} /></label>}
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
