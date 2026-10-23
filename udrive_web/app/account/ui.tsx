'use client';

import { useState } from 'react';

import { authApi } from '@/lib/auth';

/** busy / error / ok message around an API call. */
export function useAction() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [ok, setOk] = useState('');
  async function run(fn: () => Promise<unknown>, done?: string) {
    setBusy(true);
    setError('');
    setOk('');
    try {
      await fn();
      if (done) setOk(done);
      return true;
    } catch (e) {
      setError((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }
  return { busy, error, ok, run, setError };
}

export const call = authApi;
export const json = (method: string, body: unknown): RequestInit => ({ method, body: JSON.stringify(body) });

export async function upload<T>(path: string, file: File): Promise<T> {
  if (file.size > 10 * 1024 * 1024) throw new Error('Photo is too big. Max 10 MB.');
  if (!/^image\/(jpeg|png|webp)$/.test(file.type)) throw new Error('Use a JPG, PNG or WebP photo.');
  const form = new FormData();
  form.append('file', file);
  return authApi<T>(path, { method: 'POST', body: form });
}

export function Msg({ error, ok }: { error?: string; ok?: string }) {
  if (error) return <div className="msg err" role="alert">{error}</div>;
  if (ok) return <div className="msg ok" role="status">{ok}</div>;
  return null;
}

const PILL: Record<string, [string, string]> = {
  Approved: ['p-ok', 'Live'],
  Pending: ['p-wait', 'In review'],
  Info: ['p-wait', 'UDrive asked for info'],
  Rejected: ['p-bad', 'Not approved'],
  Draft: ['p-no', 'Draft'],
  None: ['p-no', 'Not sent'],
};
export function Pill({ status, label }: { status: string; label?: string }) {
  const [cls, text] = PILL[status] ?? ['p-no', status];
  return <span className={`pill ${cls}`}>{label ? `${label}: ${text}` : text}</span>;
}

/** Text input with a live counter and a hard maxLength. `< >` are stripped as you type. */
export function Text({
  label, value, onChange, max, area, placeholder, optional, type = 'text', inputMode,
}: {
  label: string; value: string; onChange: (v: string) => void; max: number; area?: boolean; placeholder?: string;
  optional?: boolean; type?: string; inputMode?: 'numeric' | 'tel' | 'text' | 'email';
}) {
  const clean = (v: string) => v.replace(/[<>]/g, '').slice(0, max);
  return (
    <label className="fld">
      <span>{label} <span className="ctr">{optional ? 'optional · ' : ''}{value.length}/{max}</span></span>
      {area ? (
        <textarea value={value} maxLength={max} placeholder={placeholder} onChange={(e) => onChange(clean(e.target.value))} />
      ) : (
        <input type={type} value={value} maxLength={max} placeholder={placeholder} inputMode={inputMode} onChange={(e) => onChange(clean(e.target.value))} />
      )}
    </label>
  );
}

export function Num({ label, value, onChange, min, max, step }: { label: string; value: number | ''; onChange: (v: number | '') => void; min: number; max: number; step?: number }) {
  return (
    <label className="fld">
      <span>{label}</span>
      <input type="number" inputMode="numeric" min={min} max={max} step={step ?? 1} value={value}
        onChange={(e) => { const v = e.target.value; onChange(v === '' ? '' : Math.min(max, Math.max(0, Number(v)))); }} />
    </label>
  );
}

export function FilePick({ label, done, onFile, disabled }: { label: string; done?: boolean; onFile: (f: File) => void; disabled?: boolean }) {
  return (
    <label className={`fpick ${done ? 'ok' : ''}`}>
      <b>{done ? '✓ ' : ''}{label}</b>
      <span>{done ? 'Uploaded — tap to replace' : 'JPG / PNG, up to 10 MB'}</span>
      <input type="file" accept="image/jpeg,image/png,image/webp" disabled={disabled}
        onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) onFile(f); }} />
    </label>
  );
}

export const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
export const pkToday = () => {
  const p = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  return p; // yyyy-MM-dd
};
export const addDays = (iso: string, n: number) => { const d = new Date(`${iso}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
export const dayLabel = (iso: string) => { const d = new Date(`${iso}T00:00:00Z`); return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }); };
