'use client';

import { RefreshCw, RotateCcw, Save } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';

import { AdminFrame } from '../components/admin-frame';
import { ErrorBox, Loading } from '../components/ui';
import { apiAction, apiFetch, when } from '../lib/admin-api';
import { usePermissions } from '../lib/permissions';

type Template = {
  key: string;
  title: string;
  audience: 'Customer' | 'Driver';
  description: string;
  placeholders: string[];
  body: string;
  defaultBody: string;
  isActive: boolean;
  updatedAt: string;
  sentLast7Days: number;
  failedLast7Days: number;
};

const audienceChip = (audience: Template['audience']) =>
  ({
    padding: '3px 9px',
    borderRadius: 999,
    fontSize: 11,
    fontWeight: 800,
    background: audience === 'Customer' ? '#eef4ff' : '#f3fbd9',
    color: audience === 'Customer' ? '#1b5fa8' : '#3f5a00',
  }) as const;

/** Setup → WhatsApp messages: the text of each message and whether it is sent at all. */
export default function MessageTemplatesPage() {
  const { can } = usePermissions();
  const canEdit = can('settings', 'edit');
  const [rows, setRows] = useState<Template[]>([]);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setRows(await apiFetch<Template[]>('/api/v1/admin/message-templates'));
    } catch (value) {
      setError(value instanceof Error ? value.message : 'The messages could not be loaded.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <AdminFrame
      title="WhatsApp messages"
      subtitle="Booking, accept aur wallet ke WhatsApp messages ka text — kisi bhi waqt badlein ya band karein."
      actions={
        <button className="secondaryButton" onClick={() => void load()}>
          <RefreshCw size={17} />
          Refresh
        </button>
      }
    >
      {error && <ErrorBox message={error} />}
      {busy ? (
        <Loading />
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 520px), 1fr))', gap: 16 }}>
          {rows.map((row) => (
            <TemplateCard
              key={row.key}
              template={row}
              canEdit={canEdit}
              onSaved={(saved) => setRows((current) => current.map((item) => (item.key === saved.key ? saved : item)))}
            />
          ))}
        </div>
      )}
    </AdminFrame>
  );
}

function TemplateCard({
  template,
  canEdit,
  onSaved,
}: {
  template: Template;
  canEdit: boolean;
  onSaved: (saved: Template) => void;
}) {
  const [body, setBody] = useState(template.body);
  const [active, setActive] = useState(template.isActive);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [failed, setFailed] = useState(false);
  const box = useRef<HTMLTextAreaElement>(null);

  const dirty = body !== template.body || active !== template.isActive;

  function insert(name: string) {
    const token = `{${name}}`;
    const element = box.current;
    if (!element) {
      setBody((value) => value + token);
      return;
    }
    const start = element.selectionStart ?? body.length;
    const end = element.selectionEnd ?? body.length;
    const next = body.slice(0, start) + token + body.slice(end);
    setBody(next);
    requestAnimationFrame(() => {
      element.focus();
      element.setSelectionRange(start + token.length, start + token.length);
    });
  }

  async function save() {
    setSaving(true);
    setMessage('');
    setFailed(false);
    try {
      const result = await apiAction<Template>(`/api/v1/admin/message-templates/${template.key}`, {
        method: 'PUT',
        body: JSON.stringify({ body, isActive: active }),
      });
      onSaved(result.data);
      setBody(result.data.body);
      setActive(result.data.isActive);
      setMessage(result.message || 'Save ho gaya.');
    } catch (value) {
      setFailed(true);
      setMessage(value instanceof Error ? value.message : 'Save nahi ho saka.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="panel" style={{ marginBottom: 0, opacity: active ? 1 : 0.85 }}>
      <header className="panelHeader" style={{ alignItems: 'flex-start', flexWrap: 'wrap', gap: 10 }}>
        <div style={{ minWidth: 0, flex: '1 1 260px' }}>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            <h2 style={{ margin: 0 }}>{template.title}</h2>
            <span style={audienceChip(template.audience)}>{template.audience}</span>
          </div>
          <p style={{ marginTop: 4 }}>{template.description}</p>
        </div>
        <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 800, fontSize: 13, cursor: canEdit ? 'pointer' : 'default' }}>
          <input
            type="checkbox"
            checked={active}
            disabled={!canEdit}
            onChange={(event) => setActive(event.target.checked)}
            style={{ width: 18, height: 18 }}
          />
          {active ? 'Active' : 'Band'}
        </label>
      </header>

      <div style={{ padding: 16, display: 'flex', flexDirection: 'column', gap: 10 }}>
        <label style={{ display: 'grid', gap: 6 }}>
          <span style={{ fontSize: 12, fontWeight: 750, color: '#465b53' }}>Message ka text</span>
          <textarea
            ref={box}
            rows={8}
            value={body}
            maxLength={1000}
            readOnly={!canEdit}
            onChange={(event) => setBody(event.target.value)}
            style={{
              border: '1px solid #d9e5e0',
              background: '#fbfdfc',
              borderRadius: 12,
              padding: 12,
              resize: 'vertical',
              fontFamily: 'inherit',
              fontSize: 14,
              lineHeight: 1.5,
            }}
          />
          <small style={{ color: '#66796f' }}>{body.length} / 1000</small>
        </label>

        <div>
          <span style={{ fontSize: 12, fontWeight: 750, color: '#465b53' }}>
            In ki jagah asal value aayegi {canEdit ? '(click karein to text mein lag jayega)' : ''}
          </span>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 6 }}>
            {template.placeholders.map((name) => (
              <button
                key={name}
                type="button"
                disabled={!canEdit}
                onClick={() => insert(name)}
                style={{
                  border: '1px solid #cfe7dc',
                  background: '#f4faf7',
                  color: '#22594a',
                  borderRadius: 8,
                  padding: '4px 8px',
                  fontFamily: 'Consolas, monospace',
                  fontSize: 12,
                  fontWeight: 700,
                  cursor: canEdit ? 'pointer' : 'default',
                }}
              >
                {`{${name}}`}
              </button>
            ))}
          </div>
        </div>

        {message && <div className={failed ? 'errorBox' : 'successBox'} style={{ margin: 0 }}>{message}</div>}

        <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
          {canEdit && (
            <>
              <button type="button" className="primaryButton" disabled={saving || !dirty || !body.trim()} onClick={() => void save()}>
                {saving ? <RefreshCw size={16} className="spin" /> : <Save size={16} />} Save
              </button>
              <button
                type="button"
                className="secondaryButton"
                disabled={saving || body === template.defaultBody}
                onClick={() => setBody(template.defaultBody)}
              >
                <RotateCcw size={16} /> Default text
              </button>
            </>
          )}
          <small style={{ color: '#66796f', marginLeft: 'auto' }}>
            7 din: {template.sentLast7Days} gaye · {template.failedLast7Days} fail · Updated {when(template.updatedAt)}
          </small>
        </div>
      </div>
    </section>
  );
}
