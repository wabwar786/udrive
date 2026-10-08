'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { CheckCircle2, RefreshCw, Save, Trash2 } from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Empty, ErrorBox, Loading } from '../components/ui';
import { apiFetch, apiProtectedFile, when } from '../lib/admin-api';

type Run = {
  id: string;
  suite: string;
  title?: string | null;
  status: 'Running' | 'Passed' | 'Failed' | 'Stopped';
  source?: string | null;
  commitSha?: string | null;
  stepsTotal: number;
  stepsPassed: number;
  stepsFailed: number;
  startedAt: string;
  finishedAt?: string | null;
};
type Step = {
  id: string;
  seq: number;
  name: string;
  status: 'Running' | 'Passed' | 'Failed' | 'Skipped' | 'Info';
  detail?: string | null;
  device: string;
  screenshotUrl?: string | null;
  createdAt: string;
};
type Overview = { keyConfigured: boolean; runs: Run[]; improvementsOpen: number; improvementsDone: number };
type Detail = { run: Run; steps: Step[] };
type Improvement = {
  id: string;
  runId?: string | null;
  stepId?: string | null;
  suite?: string | null;
  stepName?: string | null;
  screenshotUrl?: string | null;
  note: string;
  status: 'Open' | 'Done';
  createdBy?: string | null;
  createdAt: string;
  doneAt?: string | null;
};

const PHONES = [
  { device: 'customer', label: 'CUSTOMER' },
  { device: 'driver', label: 'DRIVER' },
] as const;

function message(value: unknown, fallback: string) {
  return value instanceof Error ? value.message : fallback;
}

function elapsed(from: string, to: string) {
  const s = Math.max(0, Math.round((new Date(to).getTime() - new Date(from).getTime()) / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

const tone = {
  ok: { background: '#E6F5EE', color: '#0a7a58' },
  run: { background: '#FFF2CF', color: '#7a5300' },
  bad: { background: '#FFE1E5', color: '#a62032' },
  idle: { background: '#F1F4F3', color: '#8A9A93' },
};

function runTone(run: Run) {
  return run.status === 'Running' ? tone.run : run.status === 'Passed' ? tone.ok : tone.bad;
}

function stepTone(step: Step) {
  return step.status === 'Passed' ? tone.ok : step.status === 'Failed' ? tone.bad : step.status === 'Running' ? tone.run : tone.idle;
}

/** An authorised screenshot, loaded once per URL. */
function useShot(url: string | null | undefined) {
  const cache = useRef(new Map<string, string>());
  const [src, setSrc] = useState<string | null>(null);
  useEffect(() => {
    if (!url) {
      setSrc(null);
      return;
    }
    const hit = cache.current.get(url);
    if (hit) {
      setSrc(hit);
      return;
    }
    let alive = true;
    apiProtectedFile(url)
      .then(({ objectUrl }) => {
        cache.current.set(url, objectUrl);
        if (alive) setSrc(objectUrl);
      })
      .catch(() => alive && setSrc(null));
    return () => {
      alive = false;
    };
  }, [url]);
  return src;
}

function Phone({ label, step, live }: { label: string; step: Step | null; live: boolean }) {
  const src = useShot(step?.screenshotUrl);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'center' }}>
      <span style={{ fontSize: 12, fontWeight: 800, color: '#5D7068', letterSpacing: '.08em' }}>{label}</span>
      <div
        style={{
          width: 260,
          height: 540,
          borderRadius: 30,
          border: '8px solid #0B1B33',
          overflow: 'hidden',
          background: '#FFFFFF',
          boxShadow: live ? '0 0 0 3px #C6F432' : 'none',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={src} alt={step?.name ?? label} style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'top' }} />
        ) : (
          <span style={{ fontSize: 12, color: '#8A9A93', padding: 20, textAlign: 'center' }}>
            {step ? 'Is qadam ki screenshot nahi' : 'Abhi is phone par koi qadam nahi'}
          </span>
        )}
      </div>
      <span style={{ fontSize: 11, color: '#5D7068', maxWidth: 260, textAlign: 'center' }}>
        {step ? `#${step.seq} ${step.name}` : '—'}
        {live ? ' · abhi yahan' : ''}
      </span>
    </div>
  );
}

export default function TestingPage() {
  const [overview, setOverview] = useState<Overview | null>(null);
  const [runId, setRunId] = useState<string | null>(null);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [improvements, setImprovements] = useState<Improvement[]>([]);
  const [note, setNote] = useState('');
  const [error, setError] = useState('');
  const [saved, setSaved] = useState('');
  const [busy, setBusy] = useState(false);
  const followLatest = useRef(true);

  const loadOverview = useCallback(async () => {
    try {
      const data = await apiFetch<Overview>('/api/v1/admin/testing?limit=40');
      setOverview(data);
      setRunId((current) => {
        if (current && !followLatest.current) return current;
        const running = data.runs.find((r) => r.status === 'Running');
        return running?.id ?? data.runs[0]?.id ?? null;
      });
    } catch (value) {
      setError(message(value, 'Testing ki maloomat nahi mil saki.'));
    }
  }, []);

  const loadImprovements = useCallback(async () => {
    try {
      setImprovements(await apiFetch<Improvement[]>('/api/v1/admin/testing/improvements'));
    } catch {
      // Shown again on the next load.
    }
  }, []);

  useEffect(() => {
    void loadOverview();
    void loadImprovements();
    const timer = window.setInterval(() => void loadOverview(), 5000);
    return () => window.clearInterval(timer);
  }, [loadOverview, loadImprovements]);

  // The open run: everything once, then only new steps every 1.5 s while it runs.
  useEffect(() => {
    if (!runId) return;
    let alive = true;
    let last = 0;
    let timer = 0;
    setDetail(null);
    setSelected(null);
    async function tick() {
      try {
        const data = await apiFetch<Detail>(`/api/v1/admin/testing/runs/${runId}?afterSeq=${last}`);
        if (!alive) return;
        if (data.steps.length) last = data.steps[data.steps.length - 1].seq;
        setDetail((prev) => ({ run: data.run, steps: [...(prev?.run.id === data.run.id ? prev.steps : []), ...data.steps] }));
        if (data.run.status === 'Running') timer = window.setTimeout(() => void tick(), 1500);
      } catch (value) {
        if (alive) setError(message(value, 'Run nahi khul saka.'));
      }
    }
    void tick();
    return () => {
      alive = false;
      window.clearTimeout(timer);
    };
  }, [runId]);

  const suites = useMemo(() => {
    const latest = new Map<string, Run>();
    for (const run of overview?.runs ?? []) if (!latest.has(run.suite)) latest.set(run.suite, run);
    return [...latest.values()];
  }, [overview]);

  const steps = detail?.steps ?? [];
  const latestStep = steps.length ? steps[steps.length - 1] : null;
  const selectedStep = steps.find((s) => s.id === selected) ?? null;
  const focus = selectedStep ?? latestStep;

  function shotFor(device: string) {
    // The chosen step on its own phone; otherwise the newest screen of each phone.
    if (selectedStep && selectedStep.device === device) return selectedStep;
    const upTo = selectedStep ? steps.filter((s) => s.seq <= selectedStep.seq) : steps;
    for (let i = upTo.length - 1; i >= 0; i--) if (upTo[i].device === device) return upTo[i];
    return null;
  }

  async function saveImprovement() {
    if (!note.trim()) return;
    setBusy(true);
    setError('');
    try {
      await apiFetch<Improvement>('/api/v1/admin/testing/improvements', {
        method: 'POST',
        body: JSON.stringify({ stepId: focus?.id ?? null, runId: detail?.run.id ?? null, note }),
      });
      setNote('');
      setSaved('Improvement save ho gayi.');
      window.setTimeout(() => setSaved(''), 2500);
      await Promise.all([loadImprovements(), loadOverview()]);
    } catch (value) {
      setError(message(value, 'Improvement save nahi hui.'));
    } finally {
      setBusy(false);
    }
  }

  async function setStatus(item: Improvement, status: 'Open' | 'Done') {
    try {
      await apiFetch<boolean>(`/api/v1/admin/testing/improvements/${item.id}/status`, {
        method: 'POST',
        body: JSON.stringify({ status }),
      });
      await Promise.all([loadImprovements(), loadOverview()]);
    } catch (value) {
      setError(message(value, 'Status nahi badla.'));
    }
  }

  async function remove(item: Improvement) {
    if (!window.confirm('Yeh improvement delete karein?')) return;
    try {
      await apiFetch<boolean>(`/api/v1/admin/testing/improvements/${item.id}`, { method: 'DELETE' });
      await Promise.all([loadImprovements(), loadOverview()]);
    } catch (value) {
      setError(message(value, 'Delete nahi hui.'));
    }
  }

  const run = detail?.run;
  const open = improvements.filter((i) => i.status === 'Open');
  const done = improvements.filter((i) => i.status === 'Done');

  return (
    <AdminFrame
      title="Live testing"
      subtitle="Staging par jo test chal raha hai, wohi screen yahan. Kisi bhi qadam par improvement likhein."
      actions={
        <>
          {run && (
            <span
              style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 12px', borderRadius: 10, background: '#FFFFFF', border: '1px solid #DDE9E4', fontSize: 13, fontWeight: 700 }}
            >
              <span style={{ width: 9, height: 9, borderRadius: 5, background: run.status === 'Running' ? '#16a878' : run.status === 'Passed' ? '#0a7a58' : '#a62032' }} />
              {run.suite} · {run.status === 'Running' ? 'chal raha hai' : run.status === 'Passed' ? 'pass' : run.status === 'Failed' ? 'fail' : 'ruk gaya'}
            </span>
          )}
          <button className="secondaryButton" onClick={() => { followLatest.current = true; void loadOverview(); }}>
            <RefreshCw /> Latest
          </button>
        </>
      }
    >
      {error && <ErrorBox message={error} />}
      {saved && <div className="successBox">{saved}</div>}

      {!overview ? (
        <Loading />
      ) : (
        <>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 14 }}>
            {suites.map((s) => {
              const activeSuite = run?.suite === s.suite;
              const t = runTone(s);
              return (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => { followLatest.current = false; setRunId(s.id); }}
                  style={{
                    height: 36, padding: '0 12px', borderRadius: 10, fontWeight: 800, fontSize: 12.5, cursor: 'pointer',
                    display: 'flex', alignItems: 'center', gap: 8,
                    background: activeSuite ? '#12251E' : '#FFFFFF', color: activeSuite ? '#FFFFFF' : '#12251E',
                    border: activeSuite ? 'none' : '1px solid #DDE9E4',
                  }}
                >
                  {s.suite}
                  <span style={{ fontSize: 11, padding: '2px 7px', borderRadius: 7, ...t }}>
                    {s.stepsPassed}/{s.stepsTotal}
                  </span>
                </button>
              );
            })}
            <Link href="/self-test" className="secondaryButton" style={{ height: 36 }}>
              API self-test →
            </Link>
          </div>

          {overview.runs.length === 0 ? (
            <section className="panel">
              <Empty title="Abhi koi test nahi chala" copy="Neeche 'Setup' dekhein: GitHub par test chalne se yahan screens aana shuru ho jayengi." />
            </section>
          ) : !detail ? (
            <Loading />
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, max-content)) minmax(320px, 1fr)', gap: 16, alignItems: 'start' }}>
              {PHONES.map((p) => {
                const step = shotFor(p.device);
                return <Phone key={p.device} label={p.label} step={step} live={!selectedStep && run?.status === 'Running' && latestStep?.device === p.device} />;
              })}

              <div style={{ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 }}>
                <section className="panel" style={{ margin: 0, padding: 0, overflow: 'hidden' }}>
                  <div style={{ padding: '12px 16px', borderBottom: '1px solid #EDF2F0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <b style={{ fontSize: 15 }}>Qadam (steps)</b>
                    <span style={{ fontSize: 12, color: '#5D7068' }}>
                      {run?.stepsPassed}/{run?.stepsTotal} pass · {run?.stepsFailed} fail · {when(run?.startedAt)}
                    </span>
                  </div>
                  <div style={{ maxHeight: 420, overflowY: 'auto' }}>
                    {steps.map((st) => {
                      const t = stepTone(st);
                      const on = (selectedStep?.id ?? latestStep?.id) === st.id;
                      return (
                        <button
                          key={st.id}
                          type="button"
                          onClick={() => setSelected(selectedStep?.id === st.id ? null : st.id)}
                          style={{ display: 'flex', width: '100%', alignItems: 'center', gap: 10, padding: '8px 16px', border: 'none', borderTop: '1px solid #EDF2F0', color: '#12251E', cursor: 'pointer', background: on ? '#EEF8F3' : '#FFFFFF', textAlign: 'left' }}
                        >
                          <span style={{ width: 22, height: 22, flexShrink: 0, borderRadius: 11, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 800, ...t }}>
                            {st.status === 'Passed' ? '✓' : st.status === 'Failed' ? '✕' : st.status === 'Running' ? '…' : '·'}
                          </span>
                          <span style={{ display: 'flex', flexDirection: 'column', gap: 2, flexGrow: 1, minWidth: 0 }}>
                            <span style={{ fontWeight: 700, fontSize: 13 }}>{st.name}</span>
                            <span style={{ fontSize: 11, color: '#5D7068', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {st.device} · {st.detail ?? st.status}
                            </span>
                          </span>
                          <span style={{ fontSize: 11, color: '#5D7068' }}>{run ? elapsed(run.startedAt, st.createdAt) : ''}</span>
                        </button>
                      );
                    })}
                    {steps.length === 0 && <p style={{ padding: 16, fontSize: 13 }}>Pehle qadam ka intezar…</p>}
                  </div>
                </section>

                <section className="panel" style={{ margin: 0 }}>
                  <b style={{ fontSize: 13.5 }}>Is screen par improvement</b>
                  <p style={{ fontSize: 11.5, color: '#5D7068', margin: '4px 0 8px' }}>
                    Qadam: {focus ? `#${focus.seq} ${focus.name}` : '—'} — screenshot ke saath save hoga
                  </p>
                  <textarea
                    aria-label="Improvement"
                    value={note}
                    onChange={(e) => setNote(e.target.value)}
                    placeholder="Masalan: kiraya ka font bara karein, Find offers button upar laayein"
                    style={{ width: '100%', boxSizing: 'border-box', height: 64, borderRadius: 10, border: '1px solid #D3DFDA', padding: '8px 10px', fontFamily: 'inherit', resize: 'vertical' }}
                  />
                  <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: 8 }}>
                    <button className="primaryButton" onClick={() => void saveImprovement()} disabled={busy || !note.trim()}>
                      <Save /> Save improvement
                    </button>
                    <span style={{ fontSize: 11.5, color: '#5D7068' }}>
                      Improvements: {overview.improvementsOpen} khuli · {overview.improvementsDone} ho gayi
                    </span>
                  </div>
                </section>
              </div>
            </div>
          )}

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Improvements ({open.length} khuli)</h2>
                <p>Jo aap ne likha, screen ke naam ke saath. Kaam ho jaye to "Ho gaya" dabayein.</p>
              </div>
            </header>
            {improvements.length === 0 ? (
              <Empty title="Abhi koi improvement nahi" copy="Kisi qadam ko chun kar upar likhein." />
            ) : (
              <div className="tableWrap">
                <table>
                  <thead>
                    <tr>
                      <th>Screen</th>
                      <th>Improvement</th>
                      <th>Kis ne / kab</th>
                      <th>Status</th>
                      <th />
                    </tr>
                  </thead>
                  <tbody>
                    {[...open, ...done].map((item) => (
                      <tr key={item.id} style={{ opacity: item.status === 'Done' ? 0.6 : 1 }}>
                        <td>
                          <strong>{item.stepName ?? '—'}</strong>
                          <br />
                          <small>{item.suite ?? ''}</small>
                        </td>
                        <td style={{ whiteSpace: 'pre-wrap', maxWidth: 480 }}>{item.note}</td>
                        <td>
                          {item.createdBy ?? '—'}
                          <br />
                          <small>{when(item.createdAt)}</small>
                        </td>
                        <td>
                          {item.status === 'Open' ? (
                            <button className="secondaryButton" onClick={() => void setStatus(item, 'Done')}>
                              <CheckCircle2 /> Ho gaya
                            </button>
                          ) : (
                            <button className="secondaryButton" onClick={() => void setStatus(item, 'Open')}>
                              Dobara kholein
                            </button>
                          )}
                        </td>
                        <td>
                          <button className="iconButton" aria-label="Delete" onClick={() => void remove(item)}>
                            <Trash2 />
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Setup — test kaise chalta hai</h2>
                <p>
                  Test GitHub Actions par Android emulator mein chalta hai aur har qadam ki screenshot yahan bhejta hai.
                  Chalane ke liye: GitHub → Actions → <b>App tests</b> → <b>Run workflow</b>. Chalte hi yeh page khud naya
                  run dikhana shuru kar deta hai.
                </p>
                <p>
                  Koi GitHub secret nahi chahiye: test Google Play reviewer wale number aur code se sign in karta hai (Setup
                  → WhatsApp OTP). Yeh number aur code app mein bhi likha hai — portal mein badlein to app mein bhi badalna hoga.
                  Test sirf search aur kiraya dekhta hai, ride book nahi karta.
                </p>
              </div>
            </header>
          </section>
        </>
      )}
    </AdminFrame>
  );
}
