'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { RefreshCw } from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { ErrorBox, Field, Loading, Modal } from '../components/ui';
import { apiAction, apiFetch } from '../lib/admin-api';

type Kpi = { key: string; label: string; value: string; note?: string | null; trend: string };
type CardButton = { kind: string; label: string; args: Record<string, string> };
type Card = { key: string; kind: string; severity: string; title: string; body: string; why: string; since: string; buttons: CardButton[] };
type AreaRow = { territoryId: string; tehsil: string; district: string; requests30: number; driversOnline: number; noOffer: number; offerGap: string; state: string };
type LiveRide = { bookingId: string; reference: string; vehicle: string; route: string; status: string; flag: string; flagTone: string };
type Accounts = { newCustomers: number; newDrivers: number; newOwners: number; newHotelOwners: number; deleted: number; deleteReasons: string[]; activeUsers: number; versions: string[] };
type Hour = { hour: number; today: number; usual: number };
type WeatherDay = { date: string; code: number; max: number; min: number; rain: number; snow: number; wind: number };
type WeatherRow = { placeKey: string; name: string; nowTemp: number | null; nowCode: number | null; days: WeatherDay[]; risk: string; riskTone: string; affects: string | null };
type LogRow = { at: string; card: string; decision: string; actor: string; detail: string };
type FareAdj = { id: string; tehsil: string; vehicleClass: string; percent: number; until: string; reason: string };
type RoadReport = { id: string; tehsil: string; kind: string; note: string; latitude: number; longitude: number; ago: string; driver: string };
type Board = {
  updatedAt: string; kpis: Kpi[]; cards: Card[]; areas: AreaRow[]; liveRides: LiveRide[]; accounts: Accounts; hours: Hour[];
  weather: WeatherRow[]; weatherFetchedAt: string | null; fareAdjustments: FareAdj[]; roadReports: RoadReport[]; log: LogRow[];
};
type District = { id: string; name: string };
type Preview = { audience: string; audienceLabel: string; body: string; count: number; recipients: { name: string; phone: string }[] };

const icon = (code: number | null | undefined) => {
  if (code == null) return '·';
  if (code === 0) return '☀️';
  if (code <= 2) return '⛅';
  if (code === 3) return '☁️';
  if (code === 45 || code === 48) return '🌫️';
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return '❄️';
  if (code >= 95) return '⛈️';
  return '🌧️';
};

const toneClass = (tone: string) =>
  ({ err: 'opsPillRed', warn: 'opsPillAmber', ok: 'opsPillGreen', lime: 'opsPillGreen' } as Record<string, string>)[tone] ?? 'opsPillGray';

const stateTone = (state: string) =>
  ({ Rush: 'err', 'Road band': 'warn', Rate: 'warn', Theek: 'ok', Khamosh: 'gray' } as Record<string, string>)[state] ?? 'gray';

export default function OpsBoardPage() {
  const [board, setBoard] = useState<Board | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  const [district, setDistrict] = useState('');
  const [districts, setDistricts] = useState<District[]>([]);
  const [showAllAreas, setShowAllAreas] = useState(false);
  const [message, setMessage] = useState<{ card: Card | null; args: Record<string, string>; preview: Preview | null; body: string; sending: boolean; error: string } | null>(null);
  const [advisory, setAdvisory] = useState<{ card: Card; title: string; details: string; hours: number } | null>(null);

  const load = useCallback(async () => {
    setBusy(true);
    try {
      setBoard(await apiFetch<Board>(`/api/v1/admin/ops/board${district ? `?district=${district}` : ''}`));
      setError('');
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Ops board load nahi hua.');
    } finally {
      setBusy(false);
    }
  }, [district]);

  useEffect(() => {
    void load();
    const timer = window.setInterval(() => void load(), 60_000);
    return () => window.clearInterval(timer);
  }, [load]);

  useEffect(() => {
    apiFetch<District[]>('/api/v1/admin/areas')
      .then((list) => setDistricts(list.map((d) => ({ id: d.id, name: d.name }))))
      .catch(() => setDistricts([]));
  }, []);

  async function act(run: () => Promise<{ message: string }>) {
    setNotice('');
    try {
      const result = await run();
      setNotice(result.message || 'Ho gaya.');
      await load();
    } catch (value) {
      setNotice(value instanceof Error ? value.message : 'Yeh kaam nahi hua.');
    }
  }

  const post = (path: string, body?: unknown) =>
    apiAction(path, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) });

  async function press(card: Card, button: CardButton) {
    const a = button.args;
    switch (button.kind) {
      case 'fare':
        if (!window.confirm(`${card.title}\n\n${button.label}\nAaj raat 12 baje tak. Theek hai?`)) return;
        await act(() => post('/api/v1/admin/ops/fare-adjustments', {
          territoryId: a.territoryId, vehicleClass: a.vehicleClass, percent: Number(a.percent), cardKey: card.key, reason: card.title,
        }));
        return;
      case 'message':
        await openMessage(card, a);
        return;
      case 'advisory':
        setAdvisory({ card, title: a.title ?? card.title, details: a.details ?? '', hours: 12 });
        return;
      case 'falseReport':
        await act(() => post(`/api/v1/admin/ops/road-reports/review?ids=${encodeURIComponent(a.reportIds ?? '')}&valid=false`));
        return;
      case 'dismiss':
        await act(() => post('/api/v1/admin/ops/decisions', { cardKey: card.key, cardKind: card.kind, title: card.title, decision: 'Dismissed' }));
        return;
      default:
        return;
    }
  }

  async function openMessage(card: Card | null, args: Record<string, string>) {
    setMessage({ card, args, preview: null, body: '', sending: false, error: '' });
    try {
      const preview = await apiFetch<Preview>('/api/v1/admin/ops/messages/preview', {
        method: 'POST',
        body: JSON.stringify({ audience: args.audience, territoryId: args.territoryId, vehicleClass: args.vehicleClass ?? null, cardKey: card?.key ?? null, body: args.detail ?? null }),
      });
      setMessage({ card, args, preview, body: preview.body, sending: false, error: '' });
    } catch (value) {
      setMessage({ card, args, preview: null, body: '', sending: false, error: value instanceof Error ? value.message : 'List nahi bani.' });
    }
  }

  async function sendMessage() {
    if (!message?.preview) return;
    setMessage({ ...message, sending: true, error: '' });
    try {
      const result = await post('/api/v1/admin/ops/messages/send', {
        audience: message.args.audience, territoryId: message.args.territoryId, vehicleClass: message.args.vehicleClass ?? null,
        cardKey: message.card?.key ?? null, body: message.body,
      });
      setMessage(null);
      setNotice(result.message);
      await load();
    } catch (value) {
      setMessage({ ...message, sending: false, error: value instanceof Error ? value.message : 'Message nahi gaya.' });
    }
  }

  const areas = useMemo(() => {
    const list = board?.areas ?? [];
    if (showAllAreas) return list;
    const active = list.filter((a) => a.requests30 > 0 || a.driversOnline > 0 || a.state !== 'Khamosh');
    return active.slice(0, 12);
  }, [board, showAllAreas]);

  const maxHour = Math.max(1, ...(board?.hours ?? []).map((h) => Math.max(h.today, h.usual)));
  const nowHour = new Date(Date.now() + (new Date().getTimezoneOffset() + 300) * 60_000).getHours();

  return (
    <AdminFrame
      title="Ops board"
      subtitle="Aaj ka haal aur aaj ke kaam. Mashwara system deta hai — faisla aur button aap ka."
      actions={
        <div className="opsHeadActions">
          <span className="opsLive"><i />LIVE{board ? ` · ${board.updatedAt}` : ''}</span>
          <select value={district} onChange={(e) => setDistrict(e.target.value)}>
            <option value="">Sab districts</option>
            {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
          </select>
          <button className="secondaryButton" onClick={() => void load()} disabled={busy}>
            <RefreshCw className={busy ? 'spin' : ''} /> Refresh
          </button>
        </div>
      }
    >
      <style>{css}</style>
      {error && <ErrorBox message={error} />}
      {notice && <div className="successBox">{notice}</div>}
      {!board && !error && <Loading />}

      {board && (
        <>
          <h3 className="opsSec">1 · Aaj ka haal <small>aaj ab tak, kal isi waqt tak se muqabla</small></h3>
          <section className="opsKpis">
            {board.kpis.map((k) => (
              <article key={k.key} className={`opsKpi ${k.trend === 'hl' ? 'opsKpiHl' : ''}`}>
                <span>{k.label}</span>
                <b>{k.value}</b>
                {k.note && <em className={k.trend === 'up' ? 'opsUp' : k.trend === 'down' ? 'opsDown' : ''}>{k.note}</em>}
              </article>
            ))}
          </section>

          <div className="opsGrid2">
            <div>
              <h3 className="opsSec">2 · Aaj ke kaam <small>sab se zaroori upar · har card: kya ho raha hai → kya karein</small></h3>
              {board.cards.length === 0 && <div className="opsCard opsMuted">Abhi koi kaam nahi — sab theek chal raha hai.</div>}
              {board.cards.map((card) => (
                <article key={card.key} className={`opsAct opsAct-${card.severity}`}>
                  <header><h4>{card.title}</h4><span className="opsTag">{card.since}</span></header>
                  <p>{card.body}</p>
                  <div className="opsWhy">Kyun? {card.why}</div>
                  <div className="opsBtns">
                    {card.buttons.map((b, i) =>
                      b.kind === 'link' ? (
                        <Link key={i} className="opsBtn" href={b.args.href ?? '/'}>{b.label}</Link>
                      ) : (
                        <button key={i} className={`opsBtn ${i === 0 && b.kind !== 'dismiss' ? 'opsBtnPrimary' : ''} ${b.kind === 'dismiss' || b.kind === 'falseReport' ? 'opsBtnGhost' : ''}`}
                          onClick={() => void press(card, b)}>{b.label}</button>
                      ),
                    )}
                  </div>
                </article>
              ))}

              {board.fareAdjustments.length > 0 && (
                <div className="opsCard">
                  <h3 className="opsSec opsSecTight">Aaj ki fare tabdeeliyan</h3>
                  {board.fareAdjustments.map((f) => (
                    <div key={f.id} className="opsMini">
                      <span>{f.vehicleClass} · {f.tehsil} · <b>{f.percent > 0 ? '+' : ''}{f.percent}%</b> · {f.until} tak</span>
                      <button className="opsBtn opsBtnGhost" onClick={() => void act(() => post(`/api/v1/admin/ops/fare-adjustments/${f.id}/end`))}>Khatam karein</button>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div>
              <h3 className="opsSec">3 · Area ka haal <small>abhi · tehsil-wise</small></h3>
              <div className="opsCard">
                <div className="tableWrap">
                  <table className="opsTable">
                    <thead><tr><th>Tehsil</th><th>Requests 30m</th><th>Drivers online</th><th>Bina offer</th><th>Offer vs fare</th><th>Haal</th></tr></thead>
                    <tbody>
                      {areas.map((a) => (
                        <tr key={a.territoryId}>
                          <td><b>{a.tehsil}</b><small> {a.district}</small></td>
                          <td>{a.requests30}</td><td>{a.driversOnline}</td><td>{a.noOffer}</td><td>{a.offerGap}</td>
                          <td><span className={`opsPill ${toneClass(stateTone(a.state))}`}>{a.state}</span></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <button className="opsBtn opsBtnGhost" onClick={() => setShowAllAreas(!showAllAreas)}>
                  {showAllAreas ? 'Sirf active dikhayein' : `Sab tehsils (${board.areas.length})`}
                </button>
              </div>

              <h3 className="opsSec">Road reports <small>drivers se · pichle 3 ghante</small></h3>
              <div className="opsCard">
                {board.roadReports.length === 0 && <div className="opsMuted">Koi report nahi.</div>}
                {board.roadReports.map((r) => (
                  <div key={r.id} className="opsMini">
                    <span><b>{r.tehsil}</b> · {r.kind}{r.note ? ` — ${r.note}` : ''} · {r.driver} · {r.ago} ·{' '}
                      <a href={`https://www.google.com/maps?q=${r.latitude},${r.longitude}`} target="_blank" rel="noreferrer">map</a></span>
                    <span className="opsBtns">
                      <button className="opsBtn" onClick={() => void act(() => post(`/api/v1/admin/ops/road-reports/review?ids=${r.id}&valid=true`))}>Theek</button>
                      <button className="opsBtn opsBtnGhost" onClick={() => void act(() => post(`/api/v1/admin/ops/road-reports/review?ids=${r.id}&valid=false`))}>Ghalat</button>
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </div>

          <h3 className="opsSec">🌦️ Mausam — aaj aur agle 3 din <small>har ghante · Open-Meteo{board.weatherFetchedAt ? ` · aakhri update ${board.weatherFetchedAt}` : ' · pehli reading ka intezar'}</small></h3>
          <div className="opsCard opsLime">
            {board.weather.length === 0 ? (
              <div className="opsMuted">Mausam ki reading abhi nahi aayi. Server start hone ke 1–2 minute baad aa jati hai, phir har ghante.</div>
            ) : (
              <div className="tableWrap">
                <table className="opsTable">
                  <thead><tr><th>Jagah</th><th>Abhi</th>{['Aaj', 'Kal', 'Parson', 'Agle din'].map((d) => <th key={d}>{d}</th>)}<th>Road / safar ka khatra</th></tr></thead>
                  <tbody>
                    {board.weather.map((w) => (
                      <tr key={w.placeKey}>
                        <td><b>{w.name}</b></td>
                        <td>{icon(w.nowCode)} {w.nowTemp == null ? '—' : `${Math.round(w.nowTemp)}°`}</td>
                        {[0, 1, 2, 3].map((i) => {
                          const d = w.days[i];
                          if (!d) return <td key={i}>—</td>;
                          return (
                            <td key={i}>
                              {icon(d.code)} {Math.round(d.max)}° / {Math.round(d.min)}°
                              {d.snow > 0 ? <small> · barf {d.snow.toFixed(1)} cm</small> : d.rain >= 1 ? <small> · {Math.round(d.rain)} mm</small> : null}
                              {d.wind >= 40 ? <small> · hawa {Math.round(d.wind)}</small> : null}
                            </td>
                          );
                        })}
                        <td><span className={`opsPill ${toneClass(w.riskTone)}`}>{w.risk}</span>{w.affects ? <small> · {w.affects}</small> : null}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          <div className="opsRow3">
            <div className="opsCard">
              <h3 className="opsSec opsSecTight">4 · Chalti rides ({board.liveRides.length})</h3>
              {board.liveRides.length === 0 && <div className="opsMuted">Abhi koi ride nahi chal rahi.</div>}
              {board.liveRides.map((r) => (
                <div key={r.bookingId} className="opsMini">
                  <Link href="/live-tracking">{r.reference} · {r.vehicle} · {r.route}</Link>
                  <span className={`opsPill ${toneClass(r.flagTone)}`}>{r.flag}</span>
                </div>
              ))}
            </div>
            <div className="opsCard">
              <h3 className="opsSec opsSecTight">5 · Log aur accounts <small>aaj</small></h3>
              <div className="opsMini"><span>Naye customers</span><b>{board.accounts.newCustomers}</b></div>
              <div className="opsMini"><span>Naye drivers / vehicle owners</span><b>{board.accounts.newDrivers} / {board.accounts.newOwners}</b></div>
              <div className="opsMini"><span>Naye hotel owners</span><b>{board.accounts.newHotelOwners}</b></div>
              <div className="opsMini"><span>Account delete</span><b>{board.accounts.deleted}{board.accounts.deleteReasons.length ? ` — ${board.accounts.deleteReasons.map((r) => `"${r}"`).join(', ')}` : ''}</b></div>
              <div className="opsMini"><span>App kholne wale (active)</span><b>{board.accounts.activeUsers}</b></div>
              <div className="opsMini"><span>App versions (7 din)</span><b>{board.accounts.versions.join(' · ') || '—'}</b></div>
            </div>
            <div className="opsCard">
              <h3 className="opsSec opsSecTight">6 · Aaj ghante-war requests</h3>
              <div className="opsSpark">
                {board.hours.map((h) => (
                  <i key={h.hour} title={`${h.hour}:00 — aaj ${h.today}, aam taur par ${h.usual}`}
                    className={h.hour === nowHour ? 'opsNow' : ''} style={{ height: `${(h.today / maxHour) * 100}%` }}>
                    <u style={{ bottom: `${(h.usual / maxHour) * 100}%` }} />
                  </i>
                ))}
              </div>
              <div className="opsAxis"><span>12am</span><span>6am</span><span>12pm</span><span>6pm</span><span>11pm</span></div>
              <div className="opsNote">Bar = aaj · lakeer = pichle 7 din ka aam (isi ghante). Lakeer se bahut upar ho to rush.</div>
            </div>
          </div>

          <h3 className="opsSec">7 · Kiye gaye kaam (aaj) <small>kis ne kya kiya</small></h3>
          <div className="opsCard">
            {board.log.length === 0 ? <div className="opsMuted">Aaj abhi koi kaam nahi kiya gaya.</div> : (
              <div className="tableWrap">
                <table className="opsTable">
                  <thead><tr><th>Waqt</th><th>Card</th><th>Faisla</th><th>Kis ne</th><th>Tafseel</th></tr></thead>
                  <tbody>{board.log.map((l, i) => <tr key={i}><td>{l.at}</td><td>{l.card}</td><td>{l.decision}</td><td>{l.actor}</td><td>{l.detail}</td></tr>)}</tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {message && (
        <Modal title="WhatsApp — pehle parhein, phir bhejein" onClose={() => setMessage(null)}>
          {message.error && <div className="errorBox"><span>{message.error}</span></div>}
          {!message.preview && !message.error && <Loading />}
          {message.preview && (
            <div className="detailStack">
              <p><b>Kis ko:</b> {message.preview.audienceLabel} — <b>{message.preview.count}</b> log</p>
              {message.preview.count > 0 && (
                <details><summary>List dekhein</summary>
                  <ul className="opsList">{message.preview.recipients.map((r, i) => <li key={i}>{r.name || '—'} · {r.phone}</li>)}</ul>
                </details>
              )}
              <Field label="Message ({naam} har shakhs ka naam ban jata hai)">
                <textarea rows={7} value={message.body} onChange={(e) => setMessage({ ...message, body: e.target.value })} />
              </Field>
              <p className="opsMuted">"Bhejein" dabane tak kuch nahi jata. Har bheja hua message neeche log hota hai.</p>
              <div className="buttonRow">
                <button className="secondaryButton" onClick={() => setMessage(null)}>Cancel</button>
                <button className="primaryButton" disabled={message.sending || message.preview.count === 0 || message.body.trim().length < 10}
                  onClick={() => void sendMessage()}>Bhejein ({message.preview.count})</button>
              </div>
            </div>
          )}
        </Modal>
      )}

      {advisory && (
        <Modal title="Advisory lagayein" onClose={() => setAdvisory(null)}>
          <Field label="Unwan"><input value={advisory.title} onChange={(e) => setAdvisory({ ...advisory, title: e.target.value })} /></Field>
          <Field label="Tafseel"><textarea rows={4} value={advisory.details} onChange={(e) => setAdvisory({ ...advisory, details: e.target.value })} /></Field>
          <Field label="Kitne ghante">
            <select value={advisory.hours} onChange={(e) => setAdvisory({ ...advisory, hours: Number(e.target.value) })}>
              {[3, 6, 12, 24, 48].map((h) => <option key={h} value={h}>{h} ghante</option>)}
            </select>
          </Field>
          <div className="buttonRow">
            <button className="secondaryButton" onClick={() => setAdvisory(null)}>Cancel</button>
            <button className="primaryButton" disabled={advisory.title.trim().length < 3} onClick={() => {
              const a = advisory;
              setAdvisory(null);
              void act(() => post('/api/v1/admin/ops/advisories', { title: a.title, details: a.details, hours: a.hours, cardKey: a.card.key }));
            }}>Lagayein</button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}

const css = `
.opsHeadActions{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.opsHeadActions select{height:38px;border:1px solid #d5e3dd;border-radius:10px;background:#fff;padding:0 10px;font-weight:700}
.opsLive{display:inline-flex;align-items:center;gap:6px;background:#e3f7ee;color:#087650;border-radius:20px;padding:5px 12px;font-weight:800;font-size:12px}
.opsLive i{width:8px;height:8px;border-radius:50%;background:#0b8b62}
.opsSec{font-size:15px;font-weight:900;margin:20px 0 10px}.opsSec small{font-weight:600;color:#6d7e77;font-size:12px;margin-left:6px}.opsSecTight{margin:0 0 8px}
.opsKpis{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:10px}
.opsKpi{background:#fff;border-radius:14px;padding:12px 14px;border:1px solid #e1ebe7}
.opsKpi span{font-size:10.5px;color:#6d7e77;font-weight:800;text-transform:uppercase;letter-spacing:.05em}
.opsKpi b{display:block;font-size:24px;margin:4px 0 2px;color:#17372d}.opsKpi em{font-style:normal;font-size:11.5px;font-weight:800;color:#6d7e77}
.opsKpiHl{background:#0B1B33;border:none}.opsKpiHl span{color:#b9c3d1}.opsKpiHl b{color:#C6F432}.opsKpiHl em{color:#C6F432}
.opsUp{color:#087650!important}.opsDown{color:#b42335!important}
.opsGrid2{display:grid;grid-template-columns:1.25fr 1fr;gap:16px}
.opsCard{background:#fff;border:1px solid #e1ebe7;border-radius:16px;padding:14px;margin-bottom:12px}
.opsLime{border:2px solid #C6F432}.opsMuted{color:#6d7e77;font-size:12.5px}
.opsAct{background:#fff;border:1px solid #e1ebe7;border-left:5px solid #e5484d;border-radius:12px;padding:12px 14px;margin-bottom:10px}
.opsAct-warn{border-left-color:#f0a020}.opsAct-info{border-left-color:#2b7de9}.opsAct-ok{border-left-color:#0b8b62}
.opsAct header{display:flex;justify-content:space-between;gap:8px;align-items:center}.opsAct h4{margin:0;font-size:14.5px}
.opsAct p{margin:5px 0 8px;font-size:12.5px;color:#4d6159;line-height:1.45}
.opsTag{font-size:10.5px;font-weight:800;border-radius:7px;padding:2px 7px;background:#f1f5f3;color:#4d6159;white-space:nowrap}
.opsWhy{background:#f4f8f6;border-radius:9px;padding:7px 10px;font-size:11.5px;color:#4d6159;margin-bottom:8px}
.opsBtns{display:inline-flex;gap:6px;flex-wrap:wrap}
.opsBtn{border-radius:9px;padding:7px 11px;font-size:12px;font-weight:800;border:1px solid #cfdcd6;background:#fff;color:#17372d;cursor:pointer;text-decoration:none}
.opsBtnPrimary{background:#0b8b62;color:#fff;border-color:#0b8b62}.opsBtnGhost{border-color:transparent;color:#6d7e77;background:transparent}
.opsTable{width:100%;border-collapse:collapse;font-size:12.5px}.opsTable th{text-align:left;font-size:10.5px;color:#6d7e77;text-transform:uppercase;letter-spacing:.05em;padding:7px 6px;border-bottom:1px solid #e1ebe7}
.opsTable td{padding:8px 6px;border-bottom:1px solid #f0f4f2;vertical-align:top}.opsTable small{color:#6d7e77}
.opsPill{border-radius:20px;padding:2px 8px;font-size:11px;font-weight:800;white-space:nowrap}
.opsPillRed{background:#fde8ea;color:#b42335}.opsPillAmber{background:#fff4dc;color:#8a5600}.opsPillGreen{background:#e3f7ee;color:#087650}.opsPillGray{background:#eef2f0;color:#4d6159}
.opsRow3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px;margin-top:4px}
.opsMini{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:7px 0;border-bottom:1px solid #f0f4f2;font-size:12.5px}
.opsSpark{display:flex;align-items:flex-end;gap:3px;height:70px}.opsSpark i{flex:1;background:#cfe9de;border-radius:3px 3px 0 0;position:relative;min-height:2px}
.opsSpark i.opsNow{background:#0b8b62}.opsSpark u{position:absolute;left:0;right:0;height:2px;background:#0B1B33;opacity:.5}
.opsAxis{display:flex;justify-content:space-between;font-size:10.5px;color:#6d7e77;margin-top:4px}
.opsNote{font-size:11.5px;color:#3F5A00;background:#F3FBD9;border-radius:8px;padding:6px 9px;margin-top:8px}
.opsList{max-height:180px;overflow:auto;font-size:12px}
@media(max-width:1200px){.opsKpis{grid-template-columns:repeat(3,minmax(0,1fr))}.opsGrid2,.opsRow3{grid-template-columns:1fr}}
@media(max-width:600px){.opsKpis{grid-template-columns:repeat(2,minmax(0,1fr))}}
`;
