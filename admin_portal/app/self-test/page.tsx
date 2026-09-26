'use client';

import { useCallback, useEffect, useState } from 'react';
import { CheckCircle2, ChevronLeft, Clock, Play, RefreshCw, XCircle } from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Loading, Stat } from '../components/ui';
import { apiFetch, isSuperAdmin, when } from '../lib/admin-api';

type Step = {
  number: number;
  name: string;
  role: string;
  method: string;
  path: string;
  httpStatus: number | null;
  durationMs: number;
  outcome: 'Passed' | 'Failed' | 'Skipped';
  detail: string | null;
};

type Cleanup = {
  clean: boolean;
  removed: string[];
  leftBehind: string[];
  error: string | null;
};

type Report = {
  id: string;
  triggerSource: string;
  status: string;
  totalSteps: number;
  passedSteps: number;
  failedSteps: number;
  skippedSteps: number;
  durationMs: number;
  failureSummary: string | null;
  steps: Step[];
  cleanup: Cleanup;
  startedAt: string;
  finishedAt: string | null;
};

type Summary = Omit<Report, 'steps' | 'cleanup'>;

type Schedule = {
  enabled: boolean;
  time: string;
  lastRunAt: string | null;
  lastRunStatus: string | null;
  nextRunAt: string | null;
};

type Status = {
  enabled: boolean;
  schedule: Schedule | null;
  message: string | null;
};

function message(value: unknown, fallback: string) {
  return value instanceof Error ? value.message : fallback;
}

/**
 * How long a run took, in the unit a person reads without counting zeros.
 */
function duration(ms: number) {
  return ms < 1000 ? `${ms} ms` : `${(ms / 1000).toFixed(1)} s`;
}

export default function SelfTestPage() {
  const [status, setStatus] = useState<Status | null>(null);
  const [runs, setRuns] = useState<Summary[]>([]);
  const [report, setReport] = useState<Report | null>(null);
  const [busy, setBusy] = useState(true);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [time, setTime] = useState('03:00');
  const [allowed, setAllowed] = useState(true);

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      const current = await apiFetch<Status>('/api/v1/admin/self-test/status');
      setStatus(current);
      if (current.schedule) {
        setTime(current.schedule.time);
      }

      if (current.enabled) {
        setRuns(await apiFetch<Summary[]>('/api/v1/admin/self-test/runs?limit=20'));
      }
    } catch (value) {
      setError(message(value, 'The self-test status could not be read.'));
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    // Only a SuperAdmin can run this, and a page that lets everyone press a
    // button and then shows them a 403 is worse than one that says so up front.
    setAllowed(isSuperAdmin());
    void load();
  }, [load]);

  async function run() {
    setRunning(true);
    setError('');
    setReport(null);
    try {
      setReport(await apiFetch<Report>('/api/v1/admin/self-test/run', { method: 'POST' }));
      setRuns(await apiFetch<Summary[]>('/api/v1/admin/self-test/runs?limit=20'));
    } catch (value) {
      setError(message(value, 'The self-test could not be started.'));
    } finally {
      setRunning(false);
    }
  }

  async function open(id: string) {
    setError('');
    try {
      setReport(await apiFetch<Report>(`/api/v1/admin/self-test/runs/${id}`));
    } catch (value) {
      setError(message(value, 'That run could not be opened.'));
    }
  }

  async function saveSchedule(enabled: boolean) {
    setSaving(true);
    setError('');
    try {
      const saved = await apiFetch<Schedule>('/api/v1/admin/self-test/schedule', {
        method: 'PUT',
        body: JSON.stringify({ enabled, time }),
      });
      setStatus((current) => (current ? { ...current, schedule: saved } : current));
      setTime(saved.time);
    } catch (value) {
      setError(message(value, 'The schedule could not be saved.'));
    } finally {
      setSaving(false);
    }
  }

  const schedule = status?.schedule;

  return (
    <AdminFrame
      title="Self-test"
      subtitle="Signs in as a Customer, a Driver and a Hotel Owner in turn and drives one complete journey through the live API."
      actions={
        <>
          <button className="secondaryButton" onClick={() => void load()} disabled={busy || running}>
            <RefreshCw className={busy ? 'spin' : ''} /> Refresh
          </button>
          <button
            className="primaryButton"
            onClick={() => void run()}
            disabled={running || !status?.enabled || !allowed}
          >
            <Play /> {running ? 'Running…' : 'Run the test now'}
          </button>
        </>
      }
    >
      {error && <ErrorBox message={error} />}

      {!allowed && (
        <ErrorBox message="Only a SuperAdmin can run the self-test. You can still read the history below if it loads." />
      )}

      {status && !status.enabled && (
        <ErrorBox message={status.message ?? 'The self-test is switched off on this API.'} />
      )}

      {/*
        Said plainly, and on the page rather than in a document nobody opens.
        A harness that is believed to cover more than it does is worse than no
        harness at all: a green tick here has been read as "the app works".
      */}
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>What a green run does and does not prove</h2>
            <p>
              This test calls the live API the same way the app does, so it catches a broken query, a
              migration that never ran, an endpoint returning an error, a permission that stopped working
              and a status that no longer advances. It writes to the live database and removes what it
              wrote — anything it cannot remove is reported below.
            </p>
            <p>
              It does not open the app. Nothing here builds a screen, so a green run says nothing about
              layout, navigation, crashes on launch or anything else a person would see. Test the app
              itself on a phone.
            </p>
          </div>
        </header>
      </section>

      {busy && !report ? (
        <Loading />
      ) : (
        <>
          {schedule && (
            <section className="panel">
              <header className="panelHeader">
                <div>
                  <h2>Run it every night</h2>
                  <p>
                    Off by default. When it is on, the test runs once a day at this local time
                    (Pakistan, UTC+5) with nobody watching, and the result appears in the history below.
                  </p>
                </div>
              </header>
              <div className="detailGrid">
                <div>
                  <span>Daily run</span>
                  <Badge value={schedule.enabled ? 'On' : 'Off'} />
                </div>
                <div>
                  <span>Time</span>
                  <input
                    type="time"
                    value={time}
                    onChange={(event) => setTime(event.target.value)}
                    disabled={saving || !status?.enabled || !allowed}
                  />
                </div>
                <div>
                  <span>Next run</span>
                  <strong>{schedule.enabled ? when(schedule.nextRunAt) : '—'}</strong>
                </div>
                <div>
                  <span>Last run</span>
                  <strong>{when(schedule.lastRunAt)}</strong>
                </div>
              </div>
              <div className="topActions">
                <button
                  className={schedule.enabled ? 'secondaryButton' : 'primaryButton'}
                  onClick={() => void saveSchedule(true)}
                  disabled={saving || !status?.enabled || !allowed}
                >
                  <Clock /> {schedule.enabled ? 'Save the time' : 'Turn the daily run on'}
                </button>
                {schedule.enabled && (
                  <button
                    className="dangerButton"
                    onClick={() => void saveSchedule(false)}
                    disabled={saving || !allowed}
                  >
                    Turn it off
                  </button>
                )}
              </div>
            </section>
          )}

          {report ? (
            <ReportView report={report} onBack={() => setReport(null)} />
          ) : (
            <section className="panel">
              <header className="panelHeader">
                <div>
                  <h2>Previous runs</h2>
                  <p>Newest first. Open one to see every step it took.</p>
                </div>
              </header>
              {runs.length === 0 ? (
                <Empty
                  title="No runs yet"
                  copy="Press “Run the test now” to take the platform through one complete journey."
                />
              ) : (
                <div className="tableWrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Started</th>
                        <th>Started by</th>
                        <th>Result</th>
                        <th>Passed</th>
                        <th>Failed</th>
                        <th>Skipped</th>
                        <th>Took</th>
                        <th>First problem</th>
                      </tr>
                    </thead>
                    <tbody>
                      {runs.map((row) => (
                        <tr
                          key={row.id}
                          onClick={() => void open(row.id)}
                          style={{ cursor: 'pointer' }}
                        >
                          <td>{when(row.startedAt)}</td>
                          <td>{row.triggerSource === 'Scheduled' ? 'Daily schedule' : 'An Admin'}</td>
                          <td>
                            <Badge value={row.status} />
                          </td>
                          <td>{row.passedSteps}</td>
                          <td>{row.failedSteps}</td>
                          <td>{row.skippedSteps}</td>
                          <td>{duration(row.durationMs)}</td>
                          <td>{row.failureSummary ?? '—'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
          )}
        </>
      )}
    </AdminFrame>
  );
}

function ReportView({ report, onBack }: { report: Report; onBack: () => void }) {
  return (
    <>
      <section className="statGrid">
        <Stat label="Result" value={report.status} tone={report.status === 'Passed' ? 'emerald' : 'rose'} />
        <Stat label="Passed" value={report.passedSteps} tone="emerald" />
        <Stat
          label="Failed"
          value={report.failedSteps}
          tone={report.failedSteps ? 'rose' : 'slate'}
        />
        <Stat
          label="Skipped"
          value={report.skippedSteps}
          sub="Not counted as passed"
          tone="slate"
        />
        <Stat label="Took" value={duration(report.durationMs)} tone="blue" />
      </section>

      {report.failureSummary && <ErrorBox message={report.failureSummary} />}

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>What the run left in the database</h2>
            <p>
              The test writes real records and then deletes them. Anything it could not delete is still
              there and will show up in bookings, hotel searches and revenue figures until it is removed.
            </p>
          </div>
          <button className="secondaryButton" onClick={onBack}>
            <ChevronLeft /> Back to history
          </button>
        </header>
        <div className="detailGrid">
          <div>
            <span>Cleaned up</span>
            <Badge value={report.cleanup.clean ? 'Yes' : 'No'} />
          </div>
          <div>
            <span>Removed</span>
            <strong>{report.cleanup.removed.length > 0 ? report.cleanup.removed.join(', ') : 'nothing to remove'}</strong>
          </div>
          <div>
            <span>Left behind</span>
            <strong>{report.cleanup.leftBehind.length > 0 ? report.cleanup.leftBehind.join(', ') : 'none'}</strong>
          </div>
        </div>
        {report.cleanup.error && <ErrorBox message={report.cleanup.error} />}
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Every step</h2>
            <p>In the order a real trip happens. The role column is who the test was signed in as.</p>
          </div>
        </header>
        <div className="tableWrap">
          <table>
            <thead>
              <tr>
                <th>#</th>
                <th />
                <th>Step</th>
                <th>As</th>
                <th>Call</th>
                <th>HTTP</th>
                <th>Took</th>
                <th>Detail</th>
              </tr>
            </thead>
            <tbody>
              {report.steps.map((step) => (
                <tr key={step.number}>
                  <td>{step.number}</td>
                  <td>
                    {step.outcome === 'Passed' && <CheckCircle2 size={16} />}
                    {step.outcome === 'Failed' && <XCircle size={16} />}
                    {step.outcome === 'Skipped' && <Clock size={16} />}
                  </td>
                  <td>{step.name}</td>
                  <td>{step.role}</td>
                  <td>
                    {step.method === '-' ? '—' : `${step.method} ${step.path}`}
                  </td>
                  <td>{step.httpStatus ?? '—'}</td>
                  <td>{step.durationMs > 0 ? duration(step.durationMs) : '—'}</td>
                  <td>{step.detail ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </>
  );
}
