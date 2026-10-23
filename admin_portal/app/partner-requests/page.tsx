'use client';

import { useCallback, useEffect, useState } from 'react';
import { RefreshCw } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading } from '../components/ui';
import { apiAction, apiFetch } from '../lib/admin-api';

/** Website → "Become a partner" requests: status, replies (WhatsApp optional) and internal notes. */

type Row = { id: string; reference: string; fullName: string; phone: string; targetCity: string; budget: string; status: string; unread: number; createdAt: string; updatedAt: string };
type Message = { id: string; author: 'Applicant' | 'Team' | 'Note' | string; body: string; whatsAppSent: boolean; createdAt: string };
type Detail = { id: string; reference: string; fullName: string; phone: string; email: string | null; currentCity: string; targetCity: string; work: string | null; budget: string; status: string; createdAt: string; messages: Message[] };
type List = { items: Row[]; counts: Record<string, number> };

const STATUSES = ['New', 'Contacted', 'Meeting', 'Approved', 'Declined', 'Closed'];
const dt = (s: string) => new Date(s).toLocaleString('en-GB', { timeZone: 'Asia/Karachi', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
const phone = (p: string) => (p.startsWith('+92') ? `0${p.slice(3, 6)} ${p.slice(6)}` : p);

export default function Page() {
  const [filter, setFilter] = useState('');
  const [list, setList] = useState<List | null>(null);
  const [sel, setSel] = useState<Detail | null>(null);
  const [body, setBody] = useState('');
  const [wa, setWa] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const load = useCallback(async () => {
    setError('');
    try {
      setList(await apiFetch<List>(`/api/v1/admin/partner-requests${filter ? `?status=${filter}` : ''}`));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load partner requests.');
    }
  }, [filter]);
  useEffect(() => { void load(); }, [load]);

  async function open(id: string) {
    setNotice('');
    try { setSel(await apiFetch<Detail>(`/api/v1/admin/partner-requests/${id}`)); } catch (e) { setError(e instanceof Error ? e.message : 'Could not open.'); }
  }

  async function act(path: string, payload: unknown, done: string) {
    if (!sel) return;
    setBusy(true); setError('');
    try {
      const { data, message } = await apiAction<Detail>(`/api/v1/admin/partner-requests/${sel.id}/${path}`, { method: 'POST', body: JSON.stringify(payload) });
      setSel(data); setNotice(message || done);
      await load();
      return true;
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save.');
      return false;
    } finally { setBusy(false); }
  }

  async function reply(note: boolean) {
    const text = body.replace(/[<>]/g, '').trim();
    if (!text) return setError('Write the message first.');
    if (await act('reply', { body: text, sendWhatsApp: !note && wa, internalNote: note }, note ? 'Note saved.' : 'Reply sent.')) setBody('');
  }

  const total = list ? Object.values(list.counts).reduce((a, b) => a + b, 0) : 0;
  return (
    <AdminFrame
      title="Partner requests"
      subtitle='From the website "Become a partner" form.'
      actions={
        <div className="tableTools">
          <button className={filter === '' ? 'primaryButton' : 'secondaryButton'} onClick={() => setFilter('')}>All {total}</button>
          {STATUSES.map((s) => <button key={s} className={filter === s ? 'primaryButton' : 'secondaryButton'} onClick={() => setFilter(s)}>{s} {list?.counts[s] ?? 0}</button>)}
          <button className="secondaryButton" onClick={() => void load()}><RefreshCw /> Refresh</button>
        </div>
      }
    >
      {error && <ErrorBox message={error} />}
      {notice && <div className="successBox">{notice}</div>}
      {!list ? <Loading /> : (
        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1.3fr) minmax(0,1fr)', gap: 18, alignItems: 'start' }}>
          <section className="panel">
            <header className="panelHeader"><div><h2>Requests</h2><p>Newest first. Click one to open it.</p></div></header>
            {list.items.length === 0 ? <Empty title="No requests" copy="New requests from the website appear here." /> : (
              <div className="tableWrap"><table>
                <thead><tr><th>Received</th><th>Name</th><th>City</th><th>Budget</th><th>Status</th></tr></thead>
                <tbody>{list.items.map((r) => (
                  <tr key={r.id} onClick={() => void open(r.id)} style={{ cursor: 'pointer', background: sel?.id === r.id ? '#F2FBD5' : undefined }}>
                    <td>{dt(r.createdAt)}<br /><small>{r.reference}</small></td>
                    <td><strong>{r.fullName}</strong><br /><small>{phone(r.phone)}</small></td>
                    <td>{r.targetCity}</td><td>Rs {r.budget}</td>
                    <td><Badge value={r.status} />{r.unread > 0 && <><br /><small style={{ color: '#B26B00', fontWeight: 700 }}>{r.unread} new {r.unread === 1 ? 'reply' : 'replies'}</small></>}</td>
                  </tr>
                ))}</tbody>
              </table></div>
            )}
          </section>
          <section className="panel">
            {!sel ? <Empty title="Choose a request" copy="Its details and messages show here." /> : (
              <>
                <header className="panelHeader">
                  <div>
                    <h2>{sel.fullName} — {sel.targetCity}</h2>
                    <p>Rs {sel.budget} · lives in {sel.currentCity}{sel.work ? ` · ${sel.work}` : ''}{sel.email ? ` · ${sel.email}` : ''} · {phone(sel.phone)} · {sel.reference}</p>
                  </div>
                </header>
                <div style={{ padding: '14px 17px' }}>
                  <Field label="Status">
                    <select value={sel.status} disabled={busy} onChange={(e) => void act('status', { status: e.target.value }, 'Status changed.')}>
                      {STATUSES.map((s) => <option key={s}>{s}</option>)}
                    </select>
                  </Field>
                  {sel.messages.length === 0 && <p style={{ color: '#6D7E77', fontSize: 13 }}>No messages yet.</p>}
                  {sel.messages.map((m) => (
                    <div key={m.id} style={{
                      borderRadius: 12, padding: '10px 12px', margin: '10px 0', fontSize: 14, lineHeight: 1.5, whiteSpace: 'pre-line', overflowWrap: 'anywhere',
                      background: m.author === 'Team' ? '#F2FBD5' : m.author === 'Note' ? '#FFF6E5' : '#F2F4F7',
                      border: m.author === 'Team' ? '1px solid #DCEFA3' : m.author === 'Note' ? '1px dashed #E9C46A' : 'none',
                    }}>
                      <small style={{ display: 'block', color: '#7A8492', fontSize: 11.5, marginBottom: 3 }}>
                        {m.author === 'Team' ? 'UDrive team' : m.author === 'Note' ? 'Internal note (team only)' : 'Applicant'} · {dt(m.createdAt)}{m.whatsAppSent ? ' · sent on WhatsApp ✓' : ''}
                      </small>
                      {m.body}
                    </div>
                  ))}
                  <Field label={`Reply to applicant (${body.length}/1000)`}>
                    <textarea rows={4} maxLength={1000} value={body} onChange={(e) => setBody(e.target.value.replace(/[<>]/g, ''))} />
                  </Field>
                  <label style={{ fontSize: 13, display: 'block', margin: '6px 0 12px' }}><input type="checkbox" checked={wa} onChange={(e) => setWa(e.target.checked)} /> Also send on WhatsApp</label>
                  <div className="tableTools">
                    <button className="primaryButton" disabled={busy || sel.status === 'Closed'} onClick={() => void reply(false)}>Send reply</button>
                    <button className="secondaryButton" disabled={busy} onClick={() => void reply(true)}>Save as internal note</button>
                  </div>
                </div>
              </>
            )}
          </section>
        </div>
      )}
    </AdminFrame>
  );
}
