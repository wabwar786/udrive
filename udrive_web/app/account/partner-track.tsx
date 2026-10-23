'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import type { PartnerRequest } from '@/lib/types';
import { call, json, Msg, Text, useAction } from './ui';

const STEPS = ['New', 'Contacted', 'Meeting', 'Decision'];
const LABEL: Record<string, [string, string]> = {
  New: ['p-no', 'Received'], Contacted: ['p-wait', 'Contacted'], Meeting: ['p-wait', 'Meeting planned'],
  Approved: ['p-ok', 'Approved'], Declined: ['p-bad', 'Not this time'], Closed: ['p-no', 'Closed'],
};
const at = (iso: string) => new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Karachi', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(iso));

export function PartnerTrack() {
  const [list, setList] = useState<PartnerRequest[] | null>(null);
  const a = useAction();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { void a.run(async () => setList(await call<PartnerRequest[]>('/api/v1/web/partner/mine'))); }, []);

  return (
    <>
      <div className="acctHead"><div><h1>My partnership request</h1><p className="muted">Status and messages from the UDrive team.</p></div></div>
      <Msg error={a.error} />
      {list === null ? <div className="skel" style={{ minHeight: 200 }} /> : list.length === 0 ? (
        <div className="empty">No request yet. <Link className="link" href="/partner/">Become a partner</Link></div>
      ) : list.map((r) => <One key={r.id} r={r} onChange={(x) => setList(list.map((y) => (y.id === x.id ? x : y)))} />)}
    </>
  );
}

function One({ r, onChange }: { r: PartnerRequest; onChange: (r: PartnerRequest) => void }) {
  const a = useAction();
  const [body, setBody] = useState('');
  const [cls, label] = LABEL[r.status] ?? ['p-no', r.status];
  const stepIndex = ['Approved', 'Declined', 'Closed'].includes(r.status) ? 3 : STEPS.indexOf(r.status);
  const open = !['Declined', 'Closed'].includes(r.status);

  async function send() {
    await a.run(async () => {
      if (body.trim().length < 1) throw new Error('Write a message.');
      onChange(await call<PartnerRequest>(`/api/v1/web/partner/${r.id}/reply`, json('POST', { body: body.trim() })));
      setBody('');
    }, 'Sent.');
  }

  return (
    <>
      <div className="sec2">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
          <div><b style={{ fontSize: 17 }}>{r.targetCity} · Rs {r.budget}</b><div className="small muted">Sent {at(r.createdAt)} · Ref {r.reference}</div></div>
          <span className={`pill ${cls}`} style={{ fontSize: 13 }}>{label}</span>
        </div>
        <div className="wsteps" style={{ margin: '16px 0 0' }}>
          {STEPS.map((s, i) => <span key={s} className={i === stepIndex ? 'on' : i < stepIndex ? 'done' : ''}>{s === 'New' ? 'Received' : s}</span>)}
        </div>
      </div>
      <div className="thread">
        <b>Messages</b>
        {r.messages.length === 0 && <p className="muted small">No messages yet. The UDrive team will contact you on WhatsApp.</p>}
        {r.messages.map((m) => (
          <div key={m.id} className={`msgx ${m.author === 'Team' ? 'ud' : 'me'}`}>
            <small>{m.author === 'Team' ? 'UDrive team' : 'You'} · {at(m.createdAt)}</small>{m.body}
          </div>
        ))}
        {open && (
          <>
            <Msg error={a.error} ok={a.ok} />
            <Text label="Reply" value={body} onChange={setBody} max={1000} area />
            <button className="btn dark" onClick={send} disabled={a.busy}>{a.busy ? 'Sending…' : 'Send reply'}</button>
          </>
        )}
      </div>
    </>
  );
}
