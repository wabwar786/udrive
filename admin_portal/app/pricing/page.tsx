'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Calculator, Plus, RefreshCw, Trash2 } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

const ENDPOINT = '/api/v1/admin/pricing-rules';

const SERVICE_TYPES = ['City', 'PrivateVehicle'] as const;
const CATEGORIES = ['Car', 'Bike', 'Coster', 'Hiace'] as const;

/** ISO days: 1 = Monday … 7 = Sunday, matching what the API stores. */
const DAYS: { value: number; label: string }[] = [
  { value: 1, label: 'Mon' },
  { value: 2, label: 'Tue' },
  { value: 3, label: 'Wed' },
  { value: 4, label: 'Thu' },
  { value: 5, label: 'Fri' },
  { value: 6, label: 'Sat' },
  { value: 7, label: 'Sun' },
];

/**
 * Centres for the places rules are most likely to be drawn around.
 *
 * A shortcut, not a limit — picking one fills the coordinates in and they stay
 * editable, so an area nobody listed here is still a few keystrokes away.
 */
const PRESET_AREAS: { label: string; lat: number; lng: number; radius: number }[] = [
  { label: 'Muzaffarabad', lat: 34.3700, lng: 73.4711, radius: 15 },
  { label: 'Rawalakot', lat: 33.8580, lng: 73.7600, radius: 12 },
  { label: 'Mirpur', lat: 33.1478, lng: 73.7519, radius: 15 },
  { label: 'Bhimber', lat: 32.9742, lng: 74.0781, radius: 12 },
  { label: 'Kotli', lat: 33.5180, lng: 73.9020, radius: 12 },
  { label: 'Neelum Valley', lat: 34.5890, lng: 73.9070, radius: 40 },
  { label: 'Islamabad', lat: 33.6844, lng: 73.0479, radius: 25 },
  { label: 'Rawalpindi', lat: 33.5651, lng: 73.0169, radius: 20 },
];

type Rule = {
  id?: string;
  name: string;
  serviceType: string;
  vehicleCategory: string;
  perKmRate: number;
  minimumFare: number;
  perMinuteRate: number;
  daysOfWeek: number[];
  areaLabel: string | null;
  areaLatitude: number | null;
  areaLongitude: number | null;
  areaRadiusKm: number | null;
  priority: number;
  isActive: boolean;
  updatedAt?: string;
};

type Preview = {
  vehicleCategory: string;
  matchedRuleName: string | null;
  perKmRate: number;
  minimumFare: number;
  perMinuteRate: number;
  fare: number;
};

const BLANK: Rule = {
  name: '',
  serviceType: 'City',
  vehicleCategory: 'Car',
  perKmRate: 65,
  minimumFare: 1600,
  perMinuteRate: 2,
  daysOfWeek: [],
  areaLabel: null,
  areaLatitude: null,
  areaLongitude: null,
  areaRadiusKm: null,
  priority: 0,
  isActive: true,
};

function describeDays(days: number[]) {
  if (!days || days.length === 0) return 'Every day';
  if (days.length === 7) return 'Every day';
  return DAYS.filter((d) => days.includes(d.value))
    .map((d) => d.label)
    .join(', ');
}

function describeArea(rule: Rule) {
  if (rule.areaRadiusKm == null) return 'Everywhere';
  const name = rule.areaLabel?.trim() || 'Custom area';
  return `${name} · ${rule.areaRadiusKm} km`;
}

export default function Page() {
  const [rules, setRules] = useState<Rule[]>([]);
  const [form, setForm] = useState<Rule | null>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  // Preview inputs. Defaults are an ordinary town trip rather than a round
  // number, so the figure shown is one someone might actually be charged.
  const [distanceKm, setDistanceKm] = useState(12);
  const [minutes, setMinutes] = useState(25);
  const [previewArea, setPreviewArea] = useState('');
  const [preview, setPreview] = useState<Preview[] | null>(null);
  const [previewBusy, setPreviewBusy] = useState(false);

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setRules(await apiFetch<Rule[]>(ENDPOINT));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load pricing rules.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const grouped = useMemo(() => {
    const map = new Map<string, Rule[]>();
    for (const rule of rules) {
      const key = rule.serviceType;
      map.set(key, [...(map.get(key) ?? []), rule]);
    }
    return [...map.entries()];
  }, [rules]);

  async function save() {
    if (!form) return;
    setSaving(true);
    setError('');
    try {
      const { id, updatedAt: _updatedAt, ...payload } = form;
      await apiFetch(`${ENDPOINT}${id ? `/${id}` : ''}`, {
        method: id ? 'PUT' : 'POST',
        body: JSON.stringify(payload),
      });
      setForm(null);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save this rule.');
    } finally {
      setSaving(false);
    }
  }

  async function remove(rule: Rule) {
    if (!rule.id) return;
    if (!window.confirm(`Delete "${rule.name}"? Pricing falls back to the next matching rule.`)) {
      return;
    }
    try {
      await apiFetch(`${ENDPOINT}/${rule.id}`, { method: 'DELETE' });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not delete this rule.');
    }
  }

  async function runPreview() {
    setPreviewBusy(true);
    setError('');
    try {
      const area = PRESET_AREAS.find((a) => a.label === previewArea);
      const query = new URLSearchParams({
        serviceType: 'City',
        distanceKm: String(distanceKm),
        minutes: String(minutes),
      });
      if (area) {
        query.set('lat', String(area.lat));
        query.set('lng', String(area.lng));
      }
      setPreview(await apiFetch<Preview[]>(`${ENDPOINT}/preview?${query}`));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not run the preview.');
    } finally {
      setPreviewBusy(false);
    }
  }

  function toggleDay(day: number) {
    if (!form) return;
    const days = form.daysOfWeek ?? [];
    setForm({
      ...form,
      daysOfWeek: days.includes(day)
        ? days.filter((d) => d !== day)
        : [...days, day].sort((a, b) => a - b),
    });
  }

  function applyPreset(label: string) {
    if (!form) return;
    if (!label) {
      setForm({
        ...form,
        areaLabel: null,
        areaLatitude: null,
        areaLongitude: null,
        areaRadiusKm: null,
      });
      return;
    }
    const preset = PRESET_AREAS.find((a) => a.label === label);
    if (!preset) return;
    setForm({
      ...form,
      areaLabel: preset.label,
      areaLatitude: preset.lat,
      areaLongitude: preset.lng,
      areaRadiusKm: preset.radius,
    });
  }

  /**
   * The plain per-km rate for each vehicle, with no day or area attached.
   *
   * This is the thing most visits to this page are about — a bike costs less
   * per kilometre than a car, a car less than a Hiace, a Hiace less than a
   * Coster — and making that a four-row grid means it can be set and compared
   * in one place instead of opening four rules to read four numbers.
   */
  const baseRules = useMemo(
    () =>
      rules
        .filter(
          (r) =>
            r.serviceType === 'City' &&
            r.areaRadiusKm == null &&
            (r.daysOfWeek ?? []).length === 0,
        )
        .sort(
          (a, b) =>
            CATEGORIES.indexOf(a.vehicleCategory as (typeof CATEGORIES)[number]) -
            CATEGORIES.indexOf(b.vehicleCategory as (typeof CATEGORIES)[number]),
        ),
    [rules],
  );

  const [baseDraft, setBaseDraft] = useState<Record<string, { perKmRate: number; minimumFare: number }>>({});
  const [baseSaving, setBaseSaving] = useState(false);

  useEffect(() => {
    setBaseDraft(
      Object.fromEntries(
        baseRules.map((r) => [
          r.id!,
          { perKmRate: r.perKmRate, minimumFare: r.minimumFare },
        ]),
      ),
    );
  }, [baseRules]);

  const baseDirty = baseRules.some((r) => {
    const draft = baseDraft[r.id!];
    return (
      draft &&
      (draft.perKmRate !== r.perKmRate || draft.minimumFare !== r.minimumFare)
    );
  });

  async function saveBaseRates() {
    setBaseSaving(true);
    setError('');
    try {
      // Only the rows that actually changed. Rewriting all four would bump
      // `updated_at` on rules nobody touched, and that timestamp is what breaks
      // ties between equally specific rules.
      for (const rule of baseRules) {
        const draft = baseDraft[rule.id!];
        if (!draft) continue;
        if (
          draft.perKmRate === rule.perKmRate &&
          draft.minimumFare === rule.minimumFare
        ) {
          continue;
        }
        const { id, updatedAt: _updatedAt, ...rest } = rule;
        await apiFetch(`${ENDPOINT}/${id}`, {
          method: 'PUT',
          body: JSON.stringify({ ...rest, ...draft }),
        });
      }
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save the rates.');
    } finally {
      setBaseSaving(false);
    }
  }

  return (
    <AdminFrame
      title="Pricing"
      subtitle="Set the per-kilometre rate, and narrow it to particular days or areas."
    >
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Standard rate per kilometre</h2>
            <p>
              The everyday City rate for each vehicle. Anything more specific — a
              weekend rate, a rate for one town — goes in the rules below.
            </p>
          </div>
          <div className="tableTools">
            <button
              className="primaryButton"
              onClick={() => void saveBaseRates()}
              disabled={!baseDirty || baseSaving}
            >
              {baseSaving ? 'Saving…' : 'Save rates'}
            </button>
          </div>
        </header>

        {busy ? (
          <Loading />
        ) : baseRules.length === 0 ? (
          <Empty
            title="No standard rates yet"
            copy="Add a rule below with no days and no area to create one."
          />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Vehicle</th>
                  <th>Rate per km (PKR)</th>
                  <th>Minimum fare (PKR)</th>
                </tr>
              </thead>
              <tbody>
                {baseRules.map((rule) => (
                  <tr key={rule.id}>
                    <td>
                      <strong>{rule.vehicleCategory}</strong>
                    </td>
                    <td>
                      <input
                        type="number"
                        min={1}
                        value={baseDraft[rule.id!]?.perKmRate ?? rule.perKmRate}
                        onChange={(e) =>
                          setBaseDraft({
                            ...baseDraft,
                            [rule.id!]: {
                              perKmRate: Number(e.target.value),
                              minimumFare:
                                baseDraft[rule.id!]?.minimumFare ?? rule.minimumFare,
                            },
                          })
                        }
                      />
                    </td>
                    <td>
                      <input
                        type="number"
                        min={0}
                        value={baseDraft[rule.id!]?.minimumFare ?? rule.minimumFare}
                        onChange={(e) =>
                          setBaseDraft({
                            ...baseDraft,
                            [rule.id!]: {
                              perKmRate:
                                baseDraft[rule.id!]?.perKmRate ?? rule.perKmRate,
                              minimumFare: Number(e.target.value),
                            },
                          })
                        }
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <p style={{ margin: '14px 4px 0', opacity: 0.72, fontSize: 13, lineHeight: 1.6 }}>
          <strong>Tourism is not priced here.</strong> A multi-day trip is not a
          metered ride, so each driver publishes their own asking price for their
          own vehicle, in the Driver app under Tour rate. Nothing on this page
          changes what a tour costs.
        </p>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Fare preview</h2>
            <p>What a trip would cost right now, before you change anything.</p>
          </div>
          <div className="tableTools">
            <button className="secondaryButton" onClick={() => void runPreview()} disabled={previewBusy}>
              <Calculator />
              {previewBusy ? 'Working…' : 'Preview'}
            </button>
          </div>
        </header>

        <div className="formGrid">
          <Field label="Distance (km)">
            <input
              type="number"
              min={1}
              value={distanceKm}
              onChange={(e) => setDistanceKm(Number(e.target.value))}
            />
          </Field>
          <Field label="Travel time (minutes)">
            <input
              type="number"
              min={1}
              value={minutes}
              onChange={(e) => setMinutes(Number(e.target.value))}
            />
          </Field>
          <Field label="Pickup area">
            <select value={previewArea} onChange={(e) => setPreviewArea(e.target.value)}>
              <option value="">Anywhere (no area rules)</option>
              {PRESET_AREAS.map((a) => (
                <option key={a.label} value={a.label}>
                  {a.label}
                </option>
              ))}
            </select>
          </Field>
        </div>

        {preview && (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Vehicle</th>
                  <th>Rule applied</th>
                  <th>Per km</th>
                  <th>Minimum</th>
                  <th>Customer sees</th>
                </tr>
              </thead>
              <tbody>
                {preview.map((row) => (
                  <tr key={row.vehicleCategory}>
                    <td>{row.vehicleCategory}</td>
                    <td>{row.matchedRuleName ?? '—'}</td>
                    <td>PKR {row.perKmRate}</td>
                    <td>PKR {row.minimumFare}</td>
                    <td>
                      <strong>PKR {row.fare.toLocaleString()}</strong>
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
            <h2>Pricing rules</h2>
            <p>
              The most specific active rule wins: an area beats everywhere, a smaller area beats a
              larger one, and named days beat every day.
            </p>
          </div>
          <div className="tableTools">
            <button className="secondaryButton" onClick={() => void load()}>
              <RefreshCw />
              Refresh
            </button>
            <button className="primaryButton" onClick={() => setForm({ ...BLANK })}>
              <Plus />
              Add rule
            </button>
          </div>
        </header>

        {error && <ErrorBox message={error} />}

        {busy ? (
          <Loading />
        ) : rules.length === 0 ? (
          <Empty
            title="No pricing rules yet"
            copy="Add one to set the per-kilometre rate customers are quoted."
          />
        ) : (
          grouped.map(([serviceType, items]) => (
            <div key={serviceType} className="tableWrap">
              <h3 style={{ margin: '14px 4px 6px' }}>{serviceType}</h3>
              <table>
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Vehicle</th>
                    <th>Per km</th>
                    <th>Minimum</th>
                    <th>Days</th>
                    <th>Area</th>
                    <th>Priority</th>
                    <th>Active</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {items.map((rule) => (
                    <tr key={rule.id} className="clickable" onClick={() => setForm({ ...rule })}>
                      <td>{rule.name}</td>
                      <td>{rule.vehicleCategory}</td>
                      <td>
                        <strong>PKR {rule.perKmRate}</strong>
                      </td>
                      <td>PKR {rule.minimumFare}</td>
                      <td>{describeDays(rule.daysOfWeek)}</td>
                      <td>{describeArea(rule)}</td>
                      <td>{rule.priority}</td>
                      <td>
                        <Badge value={rule.isActive ? 'Active' : 'Off'} />
                      </td>
                      <td>
                        <button
                          className="iconButton"
                          title="Delete"
                          onClick={(e) => {
                            e.stopPropagation();
                            void remove(rule);
                          }}
                        >
                          <Trash2 />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ))
        )}
      </section>

      {form && (
        <Modal title={form.id ? 'Edit pricing rule' : 'Add pricing rule'} onClose={() => setForm(null)}>
          <div className="formGrid">
            <Field label="Name (for your reference)">
              <input
                value={form.name}
                placeholder="Car — Muzaffarabad weekends"
                onChange={(e) => setForm({ ...form, name: e.target.value })}
              />
            </Field>
            <Field label="Service">
              <select
                value={form.serviceType}
                onChange={(e) => setForm({ ...form, serviceType: e.target.value })}
              >
                {SERVICE_TYPES.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Vehicle">
              <select
                value={form.vehicleCategory}
                onChange={(e) => setForm({ ...form, vehicleCategory: e.target.value })}
              >
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </Field>

            <Field label="Rate per kilometre (PKR)">
              <input
                type="number"
                min={1}
                value={form.perKmRate}
                onChange={(e) => setForm({ ...form, perKmRate: Number(e.target.value) })}
              />
            </Field>
            <Field label="Minimum fare (PKR)">
              <input
                type="number"
                min={0}
                value={form.minimumFare}
                onChange={(e) => setForm({ ...form, minimumFare: Number(e.target.value) })}
              />
            </Field>
            <Field label="Per minute (PKR)">
              <input
                type="number"
                min={0}
                value={form.perMinuteRate}
                onChange={(e) => setForm({ ...form, perMinuteRate: Number(e.target.value) })}
              />
            </Field>
          </div>

          <Field label="Days this rate applies (none selected = every day)">
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {DAYS.map((day) => {
                const on = (form.daysOfWeek ?? []).includes(day.value);
                return (
                  <button
                    key={day.value}
                    type="button"
                    className={on ? 'primaryButton' : 'secondaryButton'}
                    onClick={() => toggleDay(day.value)}
                  >
                    {day.label}
                  </button>
                );
              })}
            </div>
          </Field>

          <div className="formGrid">
            <Field label="Area (leave as Everywhere to apply to all pickups)">
              <select value={form.areaLabel ?? ''} onChange={(e) => applyPreset(e.target.value)}>
                <option value="">Everywhere</option>
                {PRESET_AREAS.map((a) => (
                  <option key={a.label} value={a.label}>
                    {a.label}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Radius (km)">
              <input
                type="number"
                min={0}
                value={form.areaRadiusKm ?? ''}
                onChange={(e) =>
                  setForm({
                    ...form,
                    areaRadiusKm: e.target.value === '' ? null : Number(e.target.value),
                  })
                }
              />
            </Field>
            <Field label="Centre latitude">
              <input
                type="number"
                value={form.areaLatitude ?? ''}
                onChange={(e) =>
                  setForm({
                    ...form,
                    areaLatitude: e.target.value === '' ? null : Number(e.target.value),
                  })
                }
              />
            </Field>
            <Field label="Centre longitude">
              <input
                type="number"
                value={form.areaLongitude ?? ''}
                onChange={(e) =>
                  setForm({
                    ...form,
                    areaLongitude: e.target.value === '' ? null : Number(e.target.value),
                  })
                }
              />
            </Field>
            <Field label="Priority (higher wins a tie)">
              <input
                type="number"
                value={form.priority}
                onChange={(e) => setForm({ ...form, priority: Number(e.target.value) })}
              />
            </Field>
            <Field label="Active">
              <input
                type="checkbox"
                checked={form.isActive}
                onChange={(e) => setForm({ ...form, isActive: e.target.checked })}
              />
            </Field>
          </div>

          <button className="primaryButton" onClick={() => void save()} disabled={saving}>
            {saving ? 'Saving…' : 'Save rule'}
          </button>
        </Modal>
      )}
    </AdminFrame>
  );
}
