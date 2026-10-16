'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { ErrorBox, Loading } from '../components/ui';
import { apiAction, apiFetch } from '../lib/admin-api';

/**
 * Pricing — aasan.
 *
 * 1 · how a fare is built, with the switches on top of the meter
 * 2 · one row per vehicle: shuru fees, per km, per minute, minimum
 * 3 · fare check: the real server quote, line by line
 *
 * Every number is the admin's. A suggestion sits under each box and is only
 * copied in when "Use" is pressed; nothing is written until Save.
 */

const ENDPOINT = '/api/v1/admin/pricing-setup';

type Suggestion = {
  baseFare: number;
  perKmRate: number;
  perMinuteRate: number;
  minimumFare: number;
  basis: string;
  fuelCostPerKm: number | null;
  marketPerKm: number | null;
  marketTrips: number;
};

type VehicleRow = {
  category: string;
  ruleId: string | null;
  baseFare: number;
  perKmRate: number;
  perMinuteRate: number;
  minimumFare: number;
  suggestion: Suggestion;
};

type Switches = {
  roundingStep: number;
  zonesEnabled: boolean;
  fuelEnabled: boolean;
  surgeEnabled: boolean;
  offerCeiling: number;
};

type SwitchSuggestion = { key: string; value: string; reason: string };

type Status = {
  activeZones: number;
  petrolBaseline: number;
  dieselBaseline: number;
  petrolPrice: number | null;
  dieselPrice: number | null;
  surgeSteps: number;
  specialRules: number;
  opsAdjustments: string[];
};

export type PricingSetup = {
  vehicles: VehicleRow[];
  switches: Switches;
  switchSuggestions: SwitchSuggestion[];
  status: Status;
  standardRuleIds: string[];
};

type CheckLine = { label: string; value: string; dim: boolean };
type CheckResult = {
  ruleName: string;
  lines: CheckLine[];
  recommended: number;
  minimum: number;
  maximum: number;
  negotiable: boolean;
  appListEstimate: number;
};

type Draft = { baseFare: number; perKmRate: number; perMinuteRate: number; minimumFare: number };
type Field = keyof Draft;

const FIELDS: { key: Field; label: string; min: number }[] = [
  { key: 'baseFare', label: 'Shuru fees (PKR)', min: 0 },
  { key: 'perKmRate', label: 'Per km (PKR)', min: 1 },
  { key: 'perMinuteRate', label: 'Per minute (PKR)', min: 0 },
  { key: 'minimumFare', label: 'Minimum (PKR)', min: 1 },
];

const ICONS: Record<string, string> = { Car: '🚗', Bike: '🏍', Rickshaw: '🛺', Hiace: '🚐', Coster: '🚌' };
const ROUNDING = [1, 5, 10, 50, 100];
const CEILINGS = [1.5, 2, 2.5, 3, 4, 5];

const fmt = (n: number) => Math.round(n).toLocaleString('en-US');
const roundUp = (v: number, step: number) => (step > 0 ? Math.ceil(v / step - 1e-9) * step : v);

/** The meter alone (no hill area, petrol index or rush), as the table's example columns. */
function example(d: Draft, km: number, minutes: number, step: number) {
  const distance = d.perKmRate * km;
  const time = d.perMinuteRate * minutes;
  const metered = d.baseFare + distance + time;
  const charged = roundUp(Math.max(metered, d.minimumFare), step);
  return { distance, time, metered, charged, minimumWins: d.minimumFare > metered };
}

export function SimplePricing({
  areas,
  onSaved,
  onLoaded,
}: {
  areas: { label: string; lat: number; lng: number }[];
  onSaved: () => void;
  onLoaded?: (setup: PricingSetup) => void;
}) {
  const [setup, setSetup] = useState<PricingSetup | null>(null);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [sw, setSw] = useState<Switches | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [saving, setSaving] = useState('');

  const [checkCat, setCheckCat] = useState('Car');
  const [checkFrom, setCheckFrom] = useState(areas[0]?.label ?? '');
  const [checkTo, setCheckTo] = useState('');
  const [checkKm, setCheckKm] = useState(125);
  const [checkMin, setCheckMin] = useState(179);
  const [check, setCheck] = useState<CheckResult | null>(null);
  const [checking, setChecking] = useState(false);

  const apply = useCallback(
    (data: PricingSetup) => {
      setSetup(data);
      setDrafts(
        Object.fromEntries(
          data.vehicles.map((v) => [
            v.category,
            { baseFare: v.baseFare, perKmRate: v.perKmRate, perMinuteRate: v.perMinuteRate, minimumFare: v.minimumFare },
          ]),
        ),
      );
      setSw(data.switches);
      onLoaded?.(data);
    },
    [onLoaded],
  );

  const load = useCallback(async () => {
    setError('');
    try {
      apply(await apiFetch<PricingSetup>(ENDPOINT));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Pricing load nahi hui.');
    }
  }, [apply]);

  useEffect(() => {
    void load();
  }, [load]);

  const changedRows = useMemo(() => {
    if (!setup) return [];
    return setup.vehicles.filter((v) => {
      const d = drafts[v.category];
      return (
        d &&
        (d.baseFare !== v.baseFare ||
          d.perKmRate !== v.perKmRate ||
          d.perMinuteRate !== v.perMinuteRate ||
          d.minimumFare !== v.minimumFare)
      );
    });
  }, [setup, drafts]);

  const switchesDirty =
    !!setup &&
    !!sw &&
    (sw.roundingStep !== setup.switches.roundingStep ||
      sw.zonesEnabled !== setup.switches.zonesEnabled ||
      sw.fuelEnabled !== setup.switches.fuelEnabled ||
      sw.surgeEnabled !== setup.switches.surgeEnabled ||
      sw.offerCeiling !== setup.switches.offerCeiling);

  function setValue(cat: string, key: Field, value: number) {
    setDrafts((all) => ({ ...all, [cat]: { ...all[cat], [key]: value } }));
  }

  function applyAllSuggestions() {
    if (!setup) return;
    setDrafts(
      Object.fromEntries(
        setup.vehicles.map((v) => [
          v.category,
          {
            baseFare: v.suggestion.baseFare,
            perKmRate: v.suggestion.perKmRate,
            perMinuteRate: v.suggestion.perMinuteRate,
            minimumFare: v.suggestion.minimumFare,
          },
        ]),
      ),
    );
    setNotice('Sab suggestion boxes mein aa gayi. Dekh kar "Rates save karein" dabayein — abhi kuch save nahi hua.');
  }

  async function saveRates() {
    if (!setup || changedRows.length === 0) return;
    for (const v of changedRows) {
      const d = drafts[v.category];
      for (const f of FIELDS) {
        if (!Number.isFinite(d[f.key]) || d[f.key] < f.min) {
          setError(`${v.category}: ${f.label} kam az kam ${f.min} hona chahiye.`);
          return;
        }
      }
    }
    setSaving('rates');
    setError('');
    setNotice('');
    try {
      const { data, message } = await apiAction<PricingSetup>(`${ENDPOINT}/rates`, {
        method: 'PUT',
        body: JSON.stringify({ rates: changedRows.map((v) => ({ category: v.category, ...drafts[v.category] })) }),
      });
      apply(data);
      setNotice(message || 'Rates save ho gaye.');
      setCheck(null);
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Rates save nahi hue.');
    } finally {
      setSaving('');
    }
  }

  async function saveSwitches() {
    if (!sw) return;
    setSaving('switches');
    setError('');
    setNotice('');
    try {
      const { data, message } = await apiAction<PricingSetup>(`${ENDPOINT}/switches`, {
        method: 'PUT',
        body: JSON.stringify(sw),
      });
      apply(data);
      setNotice(message || 'Settings save ho gayi.');
      setCheck(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Settings save nahi huin.');
    } finally {
      setSaving('');
    }
  }

  async function runCheck() {
    const from = areas.find((a) => a.label === checkFrom);
    if (!from) {
      setError('Fare check ke liye "Kahan se" chunein.');
      return;
    }
    const to = areas.find((a) => a.label === checkTo);
    setChecking(true);
    setError('');
    try {
      setCheck(
        await apiFetch<CheckResult>(`${ENDPOINT}/check`, {
          method: 'POST',
          body: JSON.stringify({
            category: checkCat,
            pickupLatitude: from.lat,
            pickupLongitude: from.lng,
            destinationLatitude: to?.lat ?? null,
            destinationLongitude: to?.lng ?? null,
            distanceKm: checkKm,
            minutes: checkMin,
          }),
        }),
      );
    } catch (e) {
      setCheck(null);
      setError(e instanceof Error ? e.message : 'Fare check nahi hua.');
    } finally {
      setChecking(false);
    }
  }

  function applySwitchSuggestion(s: SwitchSuggestion) {
    if (!sw) return;
    if (s.key === 'rounding') setSw({ ...sw, roundingStep: Number(s.value) });
    if (s.key === 'zones') setSw({ ...sw, zonesEnabled: s.value === 'on' });
    if (s.key === 'fuel') setSw({ ...sw, fuelEnabled: s.value === 'on' });
    if (s.key === 'surge') setSw({ ...sw, surgeEnabled: s.value === 'on' });
    if (s.key === 'ceiling') setSw({ ...sw, offerCeiling: Number(s.value) });
  }

  if (!setup || !sw) {
    return (
      <section className="panel">
        <style>{css}</style>
        {error ? <ErrorBox message={error} /> : <Loading />}
      </section>
    );
  }

  const st = setup.status;
  const sug = (key: string) => setup.switchSuggestions.find((s) => s.key === key);
  const step = sw.roundingStep;

  const switchSuggestionLine = (key: string, current: string) => {
    const s = sug(key);
    if (!s) return null;
    const same = s.value === current;
    const shown = s.value === 'on' ? 'On' : s.value === 'off' ? 'Off' : key === 'ceiling' ? `${s.value}×` : `${s.value} rupay`;
    return (
      <div className="spSug">
        Suggest: {shown} {same ? '· theek hai' : <button type="button" onClick={() => applySwitchSuggestion(s)}>Use</button>}
        <small>{s.reason}</small>
      </div>
    );
  };

  const toggle = (on: boolean, set: (v: boolean) => void) => (
    <div className="spToggle">
      <button type="button" className={!on ? 'spOn' : ''} onClick={() => set(false)}>Off</button>
      <button type="button" className={on ? 'spOn' : ''} onClick={() => set(true)}>On</button>
    </div>
  );

  return (
    <>
      <style>{css}</style>
      {error && <ErrorBox message={error} />}
      {notice && <div className="successBox">{notice}</div>}

      {/* 1 · how a fare is built */}
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2><span className="spNum">1</span>Kiraya aise banta hai</h2>
            <p>Har safar par yahi hisaab — app aur server dono same. Har number aap khud rakhte hain; system sirf suggest karta hai.</p>
          </div>
          <div className="tableTools">
            <button className="primaryButton" onClick={() => void saveSwitches()} disabled={!switchesDirty || saving !== ''}>
              {saving === 'switches' ? 'Saving…' : 'Settings save karein'}
            </button>
          </div>
        </header>

        <div className="spFormula">
          <div className="spChip">Shuru fees<small>har safar par ek baar</small></div>
          <span>+</span>
          <div className="spChip">Km × Per km<small>raste ki lambai</small></div>
          <span>+</span>
          <div className="spChip">Minute × Per minute<small>raste ka waqt</small></div>
          <span>=</span>
          <div className="spChip spChipDark">Kiraya<small>{step} rupay tak upar round</small></div>
          <em>agar yeh <b>Minimum</b> se kam ho → Minimum lagega</em>
        </div>

        <div className="spSubhead">Upar se lagne wali settings — aap khud On/Off karein:</div>
        <div className="spSwitches">
          <div className="spSwitch">
            <b>Round kitna</b>
            <select value={sw.roundingStep} onChange={(e) => setSw({ ...sw, roundingStep: Number(e.target.value) })}>
              {ROUNDING.map((r) => <option key={r} value={r}>{r} rupay</option>)}
            </select>
            {switchSuggestionLine('rounding', String(sw.roundingStep))}
          </div>
          <div className="spSwitch">
            <b>Pahari area (Fare zones)</b>
            {toggle(sw.zonesEnabled, (v) => setSw({ ...sw, zonesEnabled: v }))}
            <div className="spState">{st.activeZones} zone active · <Link href="/fare-zones">Fare zones →</Link></div>
            {switchSuggestionLine('zones', sw.zonesEnabled ? 'on' : 'off')}
          </div>
          <div className="spSwitch">
            <b>Petrol / diesel index</b>
            {toggle(sw.fuelEnabled, (v) => setSw({ ...sw, fuelEnabled: v }))}
            <div className="spState">
              Petrol {st.petrolPrice ?? '—'} · Diesel {st.dieselPrice ?? '—'}
              {st.petrolBaseline > 0 || st.dieselBaseline > 0
                ? ` · base ${st.petrolBaseline || '—'}/${st.dieselBaseline || '—'}`
                : ' · base set nahi'} · <Link href="/fuel-prices">Fuel prices →</Link>
            </div>
            {switchSuggestionLine('fuel', sw.fuelEnabled ? 'on' : 'off')}
          </div>
          <div className="spSwitch">
            <b>Rush (surge)</b>
            {toggle(sw.surgeEnabled, (v) => setSw({ ...sw, surgeEnabled: v }))}
            <div className="spState">{st.surgeSteps} steps set{!sw.zonesEnabled ? ' · Pahari area Off ho to Rush nahi lagta' : ''}</div>
            {switchSuggestionLine('surge', sw.surgeEnabled ? 'on' : 'off')}
          </div>
          <div className="spSwitch">
            <b>Customer max offer</b>
            <select value={sw.offerCeiling} onChange={(e) => setSw({ ...sw, offerCeiling: Number(e.target.value) })}>
              {CEILINGS.map((c) => <option key={c} value={c}>{c}× suggested fare</option>)}
            </select>
            {switchSuggestionLine('ceiling', String(sw.offerCeiling))}
          </div>
        </div>
        <p className="spFoot">
          Ops board aaj: {st.opsAdjustments.length === 0 ? 'koi % nahi chal raha' : st.opsAdjustments.join(' · ')} ·{' '}
          <Link href="/ops">Ops board →</Link> &nbsp;|&nbsp; Khaas rate (din/area): {st.specialRules} rules — neeche Advanced mein.
        </p>
      </section>

      {/* 2 · each vehicle */}
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2><span className="spNum">2</span>Har gaari ka rate</h2>
            <p>Har din, har jagah ka normal rate (City). Ek table, sab gaariyan, ek Save.</p>
          </div>
          <div className="tableTools">
            <button className="secondaryButton" onClick={applyAllSuggestions} disabled={saving !== ''}>
              Sab suggestion Use karein
            </button>
            <button className="primaryButton" onClick={() => void saveRates()} disabled={changedRows.length === 0 || saving !== ''}>
              {saving === 'rates' ? 'Saving…' : changedRows.length > 0 ? `Rates save karein (${changedRows.length})` : 'Rates save karein'}
            </button>
          </div>
        </header>

        <div className="tableWrap">
          <table className="spTable">
            <thead>
              <tr>
                <th>Gaari</th>
                {FIELDS.map((f) => <th key={f.key}>{f.label}</th>)}
                <th>Chhota safar<br />6 km · 15 min</th>
                <th>Lamba safar<br />125 km · 3 ghante</th>
              </tr>
            </thead>
            <tbody>
              {setup.vehicles.map((v) => {
                const d = drafts[v.category];
                if (!d) return null;
                const short = example(d, 6, 15, step);
                const long = example(d, 125, 180, step);
                const ratio = long.distance > 0 ? long.time / long.distance : 0;
                const timeHeavy = ratio >= 3;
                return (
                  <tr key={v.category}>
                    <td>
                      <strong>{ICONS[v.category] ?? ''} {v.category}</strong>
                      {!v.ruleId && <div className="spMuted">abhi rule nahi — save se banega</div>}
                    </td>
                    {FIELDS.map((f) => {
                      const sv = v.suggestion[f.key];
                      const bad = f.key === 'perMinuteRate' && timeHeavy;
                      return (
                        <td key={f.key}>
                          <input
                            type="number"
                            min={f.min}
                            className={bad ? 'spBad' : ''}
                            value={Number.isFinite(d[f.key]) ? d[f.key] : ''}
                            onChange={(e) => setValue(v.category, f.key, e.target.value === '' ? NaN : Number(e.target.value))}
                          />
                          <div className="spSug">
                            Suggest: {fmt(sv)}{' '}
                            {sv === d[f.key] ? '' : <button type="button" onClick={() => setValue(v.category, f.key, sv)}>Use</button>}
                          </div>
                        </td>
                      );
                    })}
                    <td className="spEx">
                      <b>{fmt(short.charged)}</b>
                      <small>
                        {short.minimumWins
                          ? `Minimum lagu (meter ${fmt(short.metered)})`
                          : `${fmt(d.baseFare)} + ${fmt(short.distance)} + ${fmt(short.time)}`}
                      </small>
                    </td>
                    <td className="spEx">
                      <b>{fmt(long.charged)}</b>
                      <small>
                        {long.minimumWins
                          ? `Minimum lagu (meter ${fmt(long.metered)})`
                          : `${fmt(d.baseFare)} + ${fmt(long.distance)} + ${fmt(long.time)}`}
                      </small>
                      {timeHeavy && <div className="spWarn">⚠ Time ka kiraya km se {Math.round(ratio)} guna</div>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <p className="spFoot">
          💡 <b>Suggestion kahan se:</b>{' '}
          {setup.vehicles.map((v) => `${v.category}: ${v.suggestion.basis}`).join(' · ')}. Example columns likhte hi badalti hain
          (Pahari area, petrol index aur rush ke baghair — asal fare neeche Fare check mein). App ki list gaari tap karne se pehle
          chhota andaza dikhati hai (Shuru fees ke baghair); gaari tap karte hi yahi fare aata hai.
        </p>
      </section>

      {/* 3 · fare check */}
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2><span className="spNum">3</span>Fare check karein</h2>
            <p>Asli server se — bilkul wahi hisaab jo customer ko gaari chunne par milta hai, har line ke saath. Kuch save nahi hota.</p>
          </div>
          <div className="tableTools">
            <button className="secondaryButton" onClick={() => void runCheck()} disabled={checking}>
              {checking ? 'Checking…' : 'Check'}
            </button>
          </div>
        </header>
        <div className="spCheck">
          <div className="spCheckForm">
            <label>Gaari
              <select value={checkCat} onChange={(e) => setCheckCat(e.target.value)}>
                {setup.vehicles.map((v) => <option key={v.category} value={v.category}>{v.category}</option>)}
              </select>
            </label>
            <label>Kahan se
              <select value={checkFrom} onChange={(e) => setCheckFrom(e.target.value)}>
                {areas.map((a) => <option key={a.label} value={a.label}>{a.label}</option>)}
              </select>
            </label>
            <label>Kahan tak
              <select value={checkTo} onChange={(e) => setCheckTo(e.target.value)}>
                <option value="">Usi ilaqe mein</option>
                {areas.map((a) => <option key={a.label} value={a.label}>{a.label}</option>)}
              </select>
            </label>
            <div className="spRow">
              <label>Km<input type="number" min={0.1} value={checkKm} onChange={(e) => setCheckKm(Number(e.target.value))} /></label>
              <label>Minute<input type="number" min={0} value={checkMin} onChange={(e) => setCheckMin(Number(e.target.value))} /></label>
            </div>
            {changedRows.length > 0 && <div className="spWarn">Table mein unsaved tabdeeli hai — check purane (saved) rate se hoga.</div>}
          </div>
          <div className="spCheckResult">
            {!check ? (
              <div className="spMuted">Gaari, jagah, km aur minute likh kar Check dabayein.</div>
            ) : (
              <>
                <div className="spLine spDim"><span>Rate kahan se</span><b>{check.ruleName}</b></div>
                {check.lines.map((l, i) => (
                  <div key={i} className={`spLine ${l.dim ? 'spDim' : ''}`}><span>{l.label}</span><b>{l.value}</b></div>
                ))}
                <div className="spLine spDim"><span>App ki list mein (gaari tap karne se pehle)</span><b>{fmt(check.appListEstimate)}</b></div>
                <div className="spTotal"><span>Customer app par dikhega</span><b>PKR {fmt(check.recommended)}</b></div>
              </>
            )}
          </div>
        </div>
      </section>
    </>
  );
}

const css = `
.spNum{display:inline-flex;width:26px;height:26px;border-radius:50%;background:#0B1B33;color:#C6F432;font-weight:900;align-items:center;justify-content:center;font-size:13px;margin-right:8px;vertical-align:middle}
.spFormula{display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:16px 17px 14px;font-weight:800;font-size:15px}
.spFormula>span{font-size:22px;color:#8aa39a}
.spFormula em{font-style:normal;font-weight:600;color:#62746d;font-size:13px}
.spChip{background:#eef6f2;border:1px solid #cfe5da;border-radius:12px;padding:10px 14px}
.spChip small{display:block;font-weight:600;color:#6d7e77;font-size:11px}
.spChipDark{background:#0B1B33;color:#C6F432;border:none}.spChipDark small{color:#b9c3d1}
.spSubhead{font-size:12.5px;font-weight:800;color:#62746d;margin:0 17px 8px}
.spSwitches{padding:0 17px;display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px}
.spSwitch{border:1px solid #e1ebe7;border-radius:12px;padding:10px 12px;font-size:12.5px;background:#fff}
.spSwitch b{display:block;font-size:13.5px;margin-bottom:6px}
.spSwitch select{height:32px;border:1px solid #cfdcd6;border-radius:8px;padding:0 8px;font-weight:700;background:#fff}
.spToggle{display:inline-flex;gap:4px}
.spToggle button{border:1px solid #cfdcd6;background:#fff;border-radius:8px;padding:4px 12px;font-weight:800;font-size:12px;cursor:pointer}
.spToggle button.spOn{background:#0B1B33;color:#fff;border-color:#0B1B33}
.spState{margin-top:6px;color:#62746d}.spState a{color:#0b7a55;font-weight:700}
.spSug{font-size:11px;color:#6d7e77;margin-top:5px;font-weight:600}
.spSug button{border:none;background:none;color:#0b7a55;font-weight:800;text-decoration:underline;cursor:pointer;padding:0;font-size:11px}
.spSug small{display:block;font-weight:500;color:#8a9a93;margin-top:2px}
.spFoot{margin:0;padding:12px 17px 16px;font-size:12.5px;color:#62746d;line-height:1.6}.spFoot a{color:#0b7a55;font-weight:700}
.spTable input{width:96px;border:1px solid #cfdcd6;border-radius:8px;padding:7px 10px;font-weight:700}
.spTable input.spBad{border:2px solid #e0a100;background:#fff8e6}
.spEx b{display:block;font-size:15px}.spEx small{display:block;color:#6d7e77;font-size:11px}
.spWarn{color:#b26b00;font-size:11.5px;font-weight:700;margin-top:4px}
.spMuted{color:#8a9a93;font-size:12px}
.spCheck{display:grid;grid-template-columns:minmax(240px,320px) minmax(0,1fr);gap:22px;padding:16px 17px 18px}
@media (max-width:820px){.spCheck{grid-template-columns:1fr}}
.spCheckForm{display:flex;flex-direction:column;gap:10px}
.spCheckForm label{display:flex;flex-direction:column;gap:5px;font-size:12px;font-weight:800}
.spCheckForm select,.spCheckForm input{width:100%;min-width:0;box-sizing:border-box;height:38px;border:1px solid #cfdcd6;border-radius:10px;padding:0 10px;font-weight:600;background:#fff}
.spRow{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:10px}
.spLine{display:flex;justify-content:space-between;gap:12px;padding:8px 0;border-bottom:1px dashed #e1ebe7;font-size:14px}
.spLine span{color:#62746d}.spDim{color:#9aaaa3}.spDim span{color:#9aaaa3}
.spTotal{display:flex;justify-content:space-between;align-items:center;margin-top:12px;background:#0B1B33;color:#fff;border-radius:12px;padding:14px 18px}
.spTotal b{font-size:26px;color:#C6F432}
.spAdv>summary{cursor:pointer;font-weight:800;font-size:14px;padding:15px 17px;list-style:none}
.spAdv[open]>summary{border-bottom:1px solid #edf2f0}
`;
