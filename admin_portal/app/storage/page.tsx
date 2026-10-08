'use client';

import { useCallback, useEffect, useState } from 'react';
import { HardDrive, ImageDown, RefreshCw, Search, Trash2 } from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { ErrorBox, Loading, Stat } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

type Folder = { name: string; files: number; bytes: number };
type Summary = {
  uploadRoot: string;
  ephemeral: boolean;
  usedBytes: number;
  files: number;
  volumeTotalBytes?: number | null;
  volumeFreeBytes?: number | null;
  trashBytes: number;
  trashFiles: number;
  folders: Folder[];
};
type Shrink = { shrunk: number; savedBytes: number; remaining: number };
type Orphans = { files: number; bytes: number; sample: string[]; moved: number };

function size(bytes: number | null | undefined) {
  if (bytes == null) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

/** Folder names on disk → words. */
const LABELS: Record<string, string> = {
  driverdocuments: 'Driver documents',
  vehicledocuments: 'Vehicle documents',
  vehiclephotos: 'Vehicle photos',
  hotelphotos: 'Hotel photos',
  wallettopups: 'Wallet top-up screenshots',
  holdclaims: 'Hold claims',
  testshots: 'Test screenshots',
  'partner-signature': 'Partner signatures (kept as evidence)',
};

function message(value: unknown, fallback: string) {
  return value instanceof Error ? value.message : fallback;
}

export default function StoragePage() {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [shrink, setShrink] = useState<{ shrunk: number; saved: number; remaining: number } | null>(null);
  const [orphans, setOrphans] = useState<Orphans | null>(null);
  const [note, setNote] = useState('');

  const load = useCallback(async () => {
    setError('');
    try {
      setSummary(await apiFetch<Summary>('/api/v1/admin/storage'));
    } catch (value) {
      setError(message(value, 'Storage ki maloomat nahi mil saki.'));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function shrinkAll() {
    setBusy(true);
    setError('');
    setNote('');
    let shrunk = 0;
    let saved = 0;
    try {
      // Small batches, so one request never runs for minutes.
      for (let round = 0; round < 200; round++) {
        const result = await apiFetch<Shrink>('/api/v1/admin/storage/shrink?limit=40', { method: 'POST' });
        shrunk += result.shrunk;
        saved += result.savedBytes;
        setShrink({ shrunk, saved, remaining: result.remaining });
        if (result.remaining === 0 || result.shrunk === 0) break;
      }
      setNote(`${shrunk} photos chhoti ho gayin — ${size(saved)} bachi.`);
      await load();
    } catch (value) {
      setError(message(value, 'Photos chhoti nahi ho sakin.'));
    } finally {
      setBusy(false);
    }
  }

  async function scan() {
    setBusy(true);
    setError('');
    setNote('');
    try {
      setOrphans(await apiFetch<Orphans>('/api/v1/admin/storage/orphans'));
    } catch (value) {
      setError(message(value, 'Scan nahi ho saka.'));
    } finally {
      setBusy(false);
    }
  }

  async function moveToTrash() {
    if (!orphans || orphans.files === 0) return;
    if (!window.confirm(`${orphans.files} files (${size(orphans.bytes)}) trash mein daalein? 30 din baad khud delete ho jayengi.`)) return;
    setBusy(true);
    setError('');
    try {
      const result = await apiFetch<Orphans>('/api/v1/admin/storage/orphans/move', { method: 'POST' });
      setNote(`${result.moved} files trash mein chali gayin.`);
      setOrphans(null);
      await load();
    } catch (value) {
      setError(message(value, 'Files trash mein nahi ja sakin.'));
    } finally {
      setBusy(false);
    }
  }

  const total = summary?.volumeTotalBytes ?? null;
  const used = summary?.usedBytes ?? 0;
  const maxFolder = Math.max(1, ...(summary?.folders.map((f) => f.bytes) ?? [1]));

  return (
    <AdminFrame
      title="Storage"
      subtitle="Uploads volume kitna bhara hai, aur jagah kaise bachayein. Nayi photos khud chhoti WebP ban kar save hoti hain."
      actions={
        <button className="secondaryButton" onClick={() => void load()} disabled={busy}>
          <RefreshCw /> Refresh
        </button>
      }
    >
      {error && <ErrorBox message={error} />}
      {note && <div className="successBox">{note}</div>}
      {!summary ? (
        <Loading />
      ) : (
        <>
          {summary.ephemeral && (
            <ErrorBox message="Uploads volume par nahi hain — har deploy par files mit jayengi. Railway par volume lagayein aur UPLOAD_ROOT=/data/uploads rakhein." />
          )}
          <section className="statGrid">
            <Stat label="Uploads" value={size(used)} sub={`${summary.files.toLocaleString()} files`} />
            <Stat label="Volume" value={total ? size(total) : '—'} sub={total ? `${Math.round((1 - (summary.volumeFreeBytes ?? 0) / total) * 100)}% bhara` : 'pata nahi'} tone="blue" />
            <Stat label="Khaali" value={size(summary.volumeFreeBytes)} tone={total && (summary.volumeFreeBytes ?? 0) < total * 0.15 ? 'rose' : 'emerald'} />
            <Stat label="Trash" value={size(summary.trashBytes)} sub={`${summary.trashFiles} files · 30 din baad delete`} tone="amber" />
          </section>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Folder ke hisaab se</h2>
                <p>Sab se bari cheez upar.</p>
              </div>
            </header>
            <div style={{ display: 'grid', gap: 8, padding: '4px 0' }}>
              {summary.folders.map((folder) => (
                <div key={folder.name} style={{ display: 'grid', gridTemplateColumns: 'minmax(160px, 1fr) 2fr 90px 80px', gap: 12, alignItems: 'center', fontSize: 13 }}>
                  <span>{LABELS[folder.name] ?? folder.name}</span>
                  <span style={{ height: 10, borderRadius: 5, background: '#E6F5EE', overflow: 'hidden' }}>
                    <span style={{ display: 'block', height: 10, width: `${Math.max(2, (folder.bytes / maxFolder) * 100)}%`, background: '#0b8b62' }} />
                  </span>
                  <strong style={{ textAlign: 'right' }}>{size(folder.bytes)}</strong>
                  <span style={{ textAlign: 'right', color: '#5D7068' }}>{folder.files} files</span>
                </div>
              ))}
              {summary.folders.length === 0 && <p>Abhi koi file nahi.</p>}
            </div>
          </section>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Purani photos chhoti karein</h2>
                <p>
                  220 KB se bari har purani photo WebP ban jati hai (lambi taraf 1280px, documents 1600px). File ka naam
                  aur link wohi rehta hai, sirf size kam hota hai. CNIC aur number plate saaf parhi jati hai.
                </p>
              </div>
            </header>
            <div className="topActions">
              <button className="primaryButton" onClick={() => void shrinkAll()} disabled={busy}>
                <ImageDown /> {busy && shrink ? `Chal raha hai… ${shrink.shrunk} ho gayin` : 'Purani photos chhoti karein'}
              </button>
              {shrink && (
                <span style={{ fontSize: 13 }}>
                  {shrink.shrunk} photos · {size(shrink.saved)} bachi · {shrink.remaining} baqi
                </span>
              )}
            </div>
          </section>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Faltu files</h2>
                <p>
                  Woh files jin ki taraf database ka koi record ishara nahi karta (2 din se purani). Trash mein jati hain,
                  delete nahi — 30 din tak wapas laayi ja sakti hain. Partner signatures kabhi nahi chhuyi jatin.
                </p>
              </div>
            </header>
            <div className="topActions">
              <button className="secondaryButton" onClick={() => void scan()} disabled={busy}>
                <Search /> Faltu files dhoondein
              </button>
              {orphans && orphans.files > 0 && (
                <button className="dangerButton" onClick={() => void moveToTrash()} disabled={busy}>
                  <Trash2 /> {orphans.files} files ({size(orphans.bytes)}) trash mein daalein
                </button>
              )}
              {orphans && orphans.files === 0 && <span style={{ fontSize: 13 }}>Koi faltu file nahi mili.</span>}
            </div>
            {orphans && orphans.sample.length > 0 && (
              <ul style={{ fontSize: 12, color: '#5D7068', margin: '8px 0 0', paddingLeft: 18 }}>
                {orphans.sample.map((s) => (
                  <li key={s}>{s}</li>
                ))}
              </ul>
            )}
          </section>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>
                  <HardDrive style={{ width: 16, height: 16, verticalAlign: -2 }} /> Rozana khud safai
                </h2>
                <p>
                  Har roz: 30 din purana trash delete · approve/reject ho chuke top-up screenshots 90 din baad · test
                  screenshots 7 din baad (jin par improvement likhi ho woh rehte hain) · app usage sessions 90 din,
                  devices 180 din.
                </p>
              </div>
            </header>
          </section>
        </>
      )}
    </AdminFrame>
  );
}
