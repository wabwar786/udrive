'use client';

import Link from 'next/link';
import { useState } from 'react';

import { OtpForm } from '@/components/OtpForm';
import { ApiError } from '@/lib/api';
import { authApi } from '@/lib/auth';
import type { PartnerRequest } from '@/lib/types';
import { useSession } from '@/lib/useSession';

export const CITIES = [
  'Muzaffarabad', 'Neelum (Athmuqam)', 'Hattian Bala', 'Bagh', 'Dhirkot', 'Haveli (Forward Kahuta)', 'Rawalakot', 'Hajira',
  'Abbaspur', 'Pallandri (Sudhnoti)', 'Kotli', 'Mirpur', 'Bhimber', 'Other',
];
const BUDGETS = ['1M', '2M', '3M', '4M+'] as const;
const EMAIL = /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]{2,}$/;
const strip = (v: string, max: number) => v.replace(/[<>]/g, '').slice(0, max);

export function PartnerForm() {
  const { user } = useSession();
  const [f, setF] = useState({ fullName: '', email: '', currentCity: '', targetCity: '', work: '', budget: '' as string, message: '' });
  const [stage, setStage] = useState<'form' | 'otp' | 'done'>('form');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState<PartnerRequest | null>(null);
  const [open, setOpen] = useState(false);
  const set = (k: keyof typeof f, v: string, max: number) => setF((x) => ({ ...x, [k]: strip(v, max) }));

  function check(): string {
    if (f.fullName.trim().length < 3) return 'Write your full name.';
    if (f.email && !EMAIL.test(f.email.trim())) return 'Email looks wrong — or leave it empty.';
    if (f.currentCity.trim().length < 2) return 'Write the city you live in now.';
    if (!f.targetCity) return 'Choose the city you want to partner in.';
    if (!f.budget) return 'Choose your investment budget.';
    return '';
  }

  async function submit() {
    setBusy(true); setError(''); setOpen(false);
    try {
      const r = await authApi<PartnerRequest>('/api/v1/web/partner', {
        method: 'POST',
        body: JSON.stringify({
          fullName: f.fullName.trim(), email: f.email.trim() || null, currentCity: f.currentCity.trim(), targetCity: f.targetCity,
          work: f.work.trim() || null, budget: f.budget, message: f.message.trim() || null,
        }),
      });
      setSent(r); setStage('done');
    } catch (e) {
      if (e instanceof ApiError && e.code === 'request_open') setOpen(true);
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  function next() {
    const problem = check();
    if (problem) return setError(problem);
    setError('');
    if (user) void submit(); else setStage('otp');
  }

  if (stage === 'done' && sent) {
    return (
      <div className="sec2 formCard done" role="status">
        <div className="big">✓</div>
        <h3>Request sent</h3>
        <p className="muted">Reference <b style={{ color: 'var(--ink)' }}>{sent.reference}</b>. Our team will contact you on WhatsApp. You can follow it and reply any time.</p>
        <Link className="btn dark" href="/account/?tab=partner">My partnership request</Link>
      </div>
    );
  }

  return (
    <div className="sec2 formCard">
      <h3 style={{ fontSize: 20, marginBottom: 4 }}>Partnership form</h3>
      <p className="muted small" style={{ marginTop: 0 }}>All fields are needed unless marked optional.</p>
      <fieldset disabled={stage === 'otp'} style={{ border: 'none', padding: 0, margin: 0 }}>
        <div className="form2">
          <label className="fld"><span>Full name <span className="ctr">{f.fullName.length}/80</span></span><input value={f.fullName} maxLength={80} autoComplete="name" onChange={(e) => set('fullName', e.target.value, 80)} /></label>
          <label className="fld"><span>Email <span className="ctr">optional</span></span><input type="email" value={f.email} maxLength={160} autoComplete="email" onChange={(e) => set('email', e.target.value.replace(/\s/g, ''), 160)} /></label>
          <label className="fld"><span>Your city now <span className="ctr">{f.currentCity.length}/60</span></span><input value={f.currentCity} maxLength={60} onChange={(e) => set('currentCity', e.target.value, 60)} /></label>
          <label className="fld"><span>City you want to partner in</span>
            <select value={f.targetCity} onChange={(e) => set('targetCity', e.target.value, 60)}><option value="">Choose…</option>{CITIES.map((c) => <option key={c}>{c}</option>)}</select>
          </label>
        </div>
        <label className="fld"><span>Your work today <span className="ctr">optional · {f.work.length}/120</span></span><input value={f.work} maxLength={120} placeholder="Transport business, 6 vehicles" onChange={(e) => set('work', e.target.value, 120)} /></label>
        <div className="small muted" style={{ margin: '8px 0 6px' }}>Investment budget</div>
        <div className="bud" role="radiogroup" aria-label="Investment budget">
          {BUDGETS.map((b) => <button key={b} type="button" role="radio" aria-checked={f.budget === b} className={f.budget === b ? 'on' : ''} onClick={() => setF({ ...f, budget: b })}>Rs {b}</button>)}
        </div>
        <label className="fld"><span>Anything else <span className="ctr">optional · {f.message.length}/1000</span></span><textarea value={f.message} maxLength={1000} onChange={(e) => set('message', e.target.value, 1000)} /></label>
      </fieldset>
      {error && <div className="msg err" role="alert">{error}{open && <> <Link className="link" href="/account/?tab=partner">Open my request</Link></>}</div>}
      {stage === 'form' ? (
        <button className="btn dark block" onClick={next} disabled={busy}>{busy ? 'Sending…' : user ? 'Send partnership request' : 'Next — confirm your WhatsApp'}</button>
      ) : (
        <>
          <div className="msg info">We send a code to your WhatsApp to confirm the number. <button className="link" style={{ background: 'none', border: 'none', cursor: 'pointer' }} onClick={() => setStage('form')}>Edit form</button></div>
          <OtpForm action="Send partnership request" askName={false} presetName={f.fullName} busy={busy} onVerified={() => void submit()} />
        </>
      )}
      <div className="note">You&apos;ll get a reply on WhatsApp and under <b>My partnership request</b> after you log in.</div>
    </div>
  );
}
