'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { BarChart3, RefreshCw, Save, ShieldCheck } from 'lucide-react';
import { ErrorBox, Loading } from '../components/ui';
import { apiAction, apiFetch } from '../lib/admin-api';
import { useCatalogAreas } from '../verification/area-select';

/**
 * Team page → Reports access.
 *
 * Which reports in the Reports Centre this person may open. SuperAdmin needs
 * nothing here — they see every report in every area. For a team user the
 * areas are the ones set above on the same page; for an Admin, Manager or
 * Operations user (whose other access is not set on this page) the areas are
 * chosen here. The server repeats every check.
 */

type ReportItem = { key: string; category: string; title: string; description: string };
type Access = {
  userId: string;
  superAdmin: boolean;
  teamUser: boolean;
  allAreas: boolean;
  areaIds: string[];
  reportKeys: string[];
  categories: string[];
  reports: ReportItem[];
};

const box = { width: 18, height: 18, accentColor: '#0b8b62' } as const;

export function ReportsAccess({ userId, readOnly, number }: { userId: string; readOnly: boolean; number?: number }) {
  const { districts } = useCatalogAreas();
  const [access, setAccess] = useState<Access | null>(null);
  const [keys, setKeys] = useState<Set<string>>(new Set());
  const [allAreas, setAllAreas] = useState(false);
  const [areaIds, setAreaIds] = useState<string[]>([]);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setError('');
    try {
      const data = await apiFetch<Access>(`/api/v1/admin/team/${encodeURIComponent(userId)}/reports`);
      setAccess(data);
      setKeys(new Set(data.reportKeys));
      setAllAreas(data.allAreas);
      setAreaIds(data.areaIds);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Reports access could not be loaded.');
    }
  }, [userId]);

  useEffect(() => {
    void load();
  }, [load]);

  const byCategory = useMemo(
    () => (access?.categories ?? []).map((c) => ({ category: c, reports: (access?.reports ?? []).filter((r) => r.category === c) }))
      .filter((g) => g.reports.length),
    [access],
  );

  function toggle(key: string, on: boolean) {
    setKeys((current) => {
      const next = new Set(current);
      if (on) next.add(key);
      else next.delete(key);
      return next;
    });
  }

  function toggleCategory(reports: ReportItem[], on: boolean) {
    setKeys((current) => {
      const next = new Set(current);
      for (const r of reports) {
        if (on) next.add(r.key);
        else next.delete(r.key);
      }
      return next;
    });
  }

  function toggleArea(id: string, on: boolean, tehsilIds: string[] = []) {
    setAreaIds((current) => {
      const rest = current.filter((x) => x !== id && !tehsilIds.includes(x));
      return on ? [...rest, id] : rest;
    });
  }

  async function save() {
    if (!access) return;
    setSaving(true);
    setError('');
    setMessage('');
    try {
      const body = access.teamUser
        ? { reportKeys: [...keys] }
        : { reportKeys: [...keys], allAreas, areaIds: allAreas ? [] : areaIds };
      const result = await apiAction<Access>(`/api/v1/admin/team/${encodeURIComponent(userId)}/reports`, {
        method: 'PUT',
        body: JSON.stringify(body),
      });
      if (result.data) {
        setAccess(result.data);
        setKeys(new Set(result.data.reportKeys));
      }
      setMessage(`Reports access saved — ${keys.size} report${keys.size === 1 ? '' : 's'}.`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Reports access could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  const title = `${number ? `${number}. ` : ''}Reports access`;

  if (error && !access) return <ErrorBox message={error} />;
  if (!access) {
    return (
      <section className="panel">
        <Loading />
      </section>
    );
  }

  if (access.superAdmin) {
    return (
      <div className="permissionNote" style={{ margin: '0 0 20px' }}>
        <BarChart3 size={18} />
        <div>
          <strong>Reports: everything</strong>
          <span>SuperAdmin sees every report in the Reports Centre, for every area.</span>
        </div>
      </div>
    );
  }

  return (
    <section className="panel">
      <header className="panelHeader" style={{ flexWrap: 'wrap' }}>
        <div>
          <h2>{title}</h2>
          <p>
            Only the ticked reports appear in their Reports Centre, and only with data from their areas. Nothing ticked = no
            Reports Centre.
          </p>
        </div>
        {!readOnly && (
          <div style={{ display: 'flex', gap: 8 }}>
            <button type="button" className="secondaryButton" onClick={() => setKeys(new Set(access.reports.map((r) => r.key)))}>
              Tick all
            </button>
            <button type="button" className="secondaryButton" onClick={() => setKeys(new Set())}>
              Clear
            </button>
          </div>
        )}
      </header>

      <div style={{ padding: 16, display: 'grid', gap: 14 }}>
        {access.teamUser ? (
          <div className="permissionNote" style={{ margin: 0 }}>
            <ShieldCheck size={18} />
            <div>
              <strong>Areas</strong>
              <span>The same areas as in “Areas” above. Save the user first if you changed them.</span>
            </div>
          </div>
        ) : (
          <div style={{ border: '1px solid #e3ece8', borderRadius: 14, padding: 12, display: 'grid', gap: 10 }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 800 }}>
              <input type="checkbox" style={box} checked={allAreas} disabled={readOnly} onChange={(e) => setAllAreas(e.target.checked)} />
              All areas (head office)
            </label>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(230px, 1fr))', gap: 8, opacity: allAreas ? 0.5 : 1 }}>
              {districts.map((d) => {
                const tehsilIds = d.tehsils.map((t) => t.id);
                const whole = areaIds.includes(d.id);
                return (
                  <div key={d.id} style={{ border: '1px solid #edf2f0', borderRadius: 12, padding: 10 }}>
                    <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 800 }}>
                      <input type="checkbox" style={box} checked={whole} disabled={readOnly || allAreas}
                        onChange={(e) => toggleArea(d.id, e.target.checked, tehsilIds)} />
                      {d.name}
                    </label>
                    {!whole && d.tehsils.map((t) => (
                      <label key={t.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '3px 0 3px 24px', fontSize: 12 }}>
                        <input type="checkbox" style={box} checked={areaIds.includes(t.id)} disabled={readOnly || allAreas}
                          onChange={(e) => toggleArea(t.id, e.target.checked)} />
                        {t.name}
                      </label>
                    ))}
                  </div>
                );
              })}
            </div>
            <small style={{ color: '#6d7e77' }}>District ticked = all its tehsils. These areas apply to reports only.</small>
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: 12 }}>
          {byCategory.map((g) => {
            const on = g.reports.filter((r) => keys.has(r.key)).length;
            return (
              <div key={g.category} style={{ border: '1px solid #e3ece8', borderRadius: 14, padding: 12 }}>
                <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 800, marginBottom: 6 }}>
                  <input
                    type="checkbox"
                    style={box}
                    checked={on === g.reports.length}
                    ref={(el) => {
                      if (el) el.indeterminate = on > 0 && on < g.reports.length;
                    }}
                    disabled={readOnly}
                    onChange={(e) => toggleCategory(g.reports, e.target.checked)}
                  />
                  {g.category} <small style={{ color: '#71827b', fontWeight: 600 }}>({on}/{g.reports.length})</small>
                </label>
                {g.reports.map((r) => (
                  <label key={r.key} title={r.description}
                    style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0 4px 24px', color: '#435d54', fontSize: 12.5 }}>
                    <input type="checkbox" style={box} checked={keys.has(r.key)} disabled={readOnly}
                      onChange={(e) => toggle(r.key, e.target.checked)} />
                    {r.title}
                  </label>
                ))}
              </div>
            );
          })}
          <div style={{ border: '1px dashed #d9e5e0', borderRadius: 14, padding: 12, color: '#71827b', fontSize: 12.5 }}>
            <strong style={{ color: '#435d54' }}>Team — staff actions</strong>
            <div style={{ marginTop: 6 }}>SuperAdmin only; cannot be given.</div>
          </div>
        </div>

        {error && <div className="errorBox" style={{ margin: 0 }}>{error}</div>}
        {message && <div className="successBox" style={{ margin: 0 }}>{message}</div>}
        {!readOnly && (
          <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
            <button type="button" className="primaryButton" style={{ minHeight: 44, padding: '0 18px' }} disabled={saving}
              onClick={() => void save()}>
              {saving ? <RefreshCw className="spin" /> : <Save />} Save reports access
            </button>
          </div>
        )}
      </div>
    </section>
  );
}
