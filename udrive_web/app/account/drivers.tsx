'use client';

import { useState } from 'react';

import { normalisePhone } from '@/lib/format';
import type { ListingHome } from '@/lib/types';
import { call, json, Msg, Text, useAction } from './ui';

const STATUS: Record<string, [string, string]> = {
  Approved: ['p-ok', 'Approved'], Submitted: ['p-wait', 'In review'], Invited: ['p-no', 'Invite sent'], Rejected: ['p-bad', 'Not approved'], Declined: ['p-no', 'Declined'],
};

export function Drivers({ home, reload }: { home: ListingHome | null; reload: () => Promise<void> }) {
  const a = useAction();
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  if (!home) return <div className="skel" style={{ minHeight: 300 }} />;

  async function invite() {
    await a.run(async () => {
      const p = normalisePhone(phone);
      if (name.trim().length < 2) throw new Error("Write the driver's name.");
      if (!p) throw new Error('Write a Pakistani mobile number, like 0300 1234567.');
      await call('/api/v1/listings/drivers', json('POST', { name: name.trim(), phone: p }));
      setName(''); setPhone('');
      await reload();
    }, 'Invite sent on WhatsApp. The driver sends CNIC, licence and selfie from the UDrive app.');
  }
  async function remove(id: string, n: string) {
    if (!window.confirm(`Remove ${n} from your drivers?`)) return;
    await a.run(async () => { await call(`/api/v1/listings/drivers/${id}/remove`, { method: 'POST' }); await reload(); }, 'Removed.');
  }

  return (
    <>
      <div className="acctHead"><div><h1>Drivers</h1><p className="muted">People who drive your vehicles. Each one is checked by UDrive before they can take a trip.</p></div></div>
      <Msg error={a.error} ok={a.ok} />
      {home.drivers.length === 0 ? <div className="empty" style={{ marginBottom: 16 }}>No drivers added. If you drive yourself, you don&apos;t need to add anyone.</div> : (
        <table className="tbl" style={{ marginBottom: 20 }}>
          <thead><tr><th>Name</th><th>Phone</th><th>Status</th><th>Licence</th><th /></tr></thead>
          <tbody>{home.drivers.map((d) => {
            const [cls, label] = STATUS[d.status] ?? ['p-no', d.status];
            return (
              <tr key={d.id}>
                <td><b>{d.name}</b>{d.isOwner ? ' (you)' : ''}</td><td>{d.phone}</td>
                <td><span className={`pill ${cls}`}>{label}</span>{d.reviewNote ? <div className="note2">{d.reviewNote}</div> : null}</td>
                <td>{d.licenceExpiry ? (d.licenceValid ? `valid${d.expiresInDays != null && d.expiresInDays < 60 ? ` · ${d.expiresInDays} days left` : ''}` : 'expired') : '—'}</td>
                <td>{!d.isOwner && <button className="btn ghost" disabled={a.busy} onClick={() => remove(d.id, d.name)}>Remove</button>}</td>
              </tr>
            );
          })}</tbody>
        </table>
      )}
      <div className="sec2">
        <h3 style={{ marginBottom: 10 }}>Add a driver</h3>
        <div className="form2">
          <Text label="Driver name" value={name} onChange={setName} max={80} />
          <Text label="Driver WhatsApp" value={phone} onChange={(x) => setPhone(x.replace(/[^\d +]/g, ''))} max={16} inputMode="tel" placeholder="0300 1234567" />
        </div>
        <button className="btn dark" onClick={invite} disabled={a.busy}>{a.busy ? 'Sending…' : 'Send invite'}</button>
      </div>
    </>
  );
}
