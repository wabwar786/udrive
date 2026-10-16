'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus, RefreshCw, Trash2 } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal } from '../components/ui';
import { apiFetch } from '../lib/admin-api';
import { SimplePricing } from './simple-pricing';

const ENDPOINT = '/api/v1/admin/pricing-rules';
const SEAT_ENDPOINT = '/api/v1/admin/seat-fares';

/** Vehicles that can be sold by the seat. A bike has no seats to share. */
const SEAT_CATEGORIES = ['Coster', 'Hiace'] as const;

const SERVICE_TYPES = ['City', 'PrivateVehicle'] as const;
const CATEGORIES = ['Car', 'Bike', 'Rickshaw', 'Coster', 'Hiace'] as const;

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
  baseFare: number;
  daysOfWeek: number[];
  areaLabel: string | null;
  areaLatitude: number | null;
  areaLongitude: number | null;
  areaRadiusKm: number | null;
  priority: number;
  isActive: boolean;
  updatedAt?: string;
};

type SeatFare = {
  id?: string;
  vehicleCategory: string;
  originLabel: string;
  originLatitude: number;
  originLongitude: number;
  originRadiusKm: number;
  destinationLabel: string;
  destinationLatitude: number;
  destinationLongitude: number;
  destinationRadiusKm: number;
  perSeatFare: number;
  appliesBothWays: boolean;
  notes: string | null;
  isActive: boolean;
  updatedAt?: string;
};

const BLANK_SEAT_FARE: SeatFare = {
  vehicleCategory: 'Coster',
  originLabel: '',
  originLatitude: 0,
  originLongitude: 0,
  originRadiusKm: 10,
  destinationLabel: '',
  destinationLatitude: 0,
  destinationLongitude: 0,
  destinationRadiusKm: 10,
  perSeatFare: 0,
  appliesBothWays: true,
  notes: null,
  isActive: true,
};

const BLANK: Rule = {
  name: '',
  serviceType: 'City',
  vehicleCategory: 'Car',
  perKmRate: 65,
  minimumFare: 1600,
  perMinuteRate: 2,
  baseFare: 0,
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

  // Everyday rules are edited in the table up top, so the Advanced list
  // shows only the narrower ones.
  const [standardIds, setStandardIds] = useState<string[]>([]);
  const onSetupLoaded = useCallback((setup: { standardRuleIds: string[] }) => setStandardIds(setup.standardRuleIds), []);

  const [seatFares, setSeatFares] = useState<SeatFare[]>([]);
  const [seatForm, setSeatForm] = useState<SeatFare | null>(null);
  const [seatSaving, setSeatSaving] = useState(false);

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      const [loadedRules, loadedSeatFares] = await Promise.all([
        apiFetch<Rule[]>(ENDPOINT),
        apiFetch<SeatFare[]>(SEAT_ENDPOINT),
      ]);
      setRules(loadedRules);
      setSeatFares(loadedSeatFares);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load pricing.');
    } finally {
      setBusy(false);
    }
  }, []);

  async function saveSeatFare() {
    if (!seatForm) return;
    setSeatSaving(true);
    setError('');
    try {
      const { id, updatedAt: _updatedAt, ...payload } = seatForm;
      await apiFetch(`${SEAT_ENDPOINT}${id ? `/${id}` : ''}`, {
        method: id ? 'PUT' : 'POST',
        body: JSON.stringify(payload),
      });
      setSeatForm(null);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save this route.');
    } finally {
      setSeatSaving(false);
    }
  }

  async function removeSeatFare(fare: SeatFare) {
    if (!fare.id) return;
    if (
      !window.confirm(
        `Delete "${fare.originLabel} → ${fare.destinationLabel}"? Per-seat trips on this route go back to per-kilometre pricing.`,
      )
    ) {
      return;
    }
    try {
      await apiFetch(`${SEAT_ENDPOINT}/${fare.id}`, { method: 'DELETE' });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not delete this route.');
    }
  }

  /** Fills both ends of a route from the shortcut list. */
  function applyEndpoint(which: 'origin' | 'destination', label: string) {
    if (!seatForm) return;
    const preset = PRESET_AREAS.find((a) => a.label === label);
    if (!preset) return;
    setSeatForm(
      which === 'origin'
        ? {
            ...seatForm,
            originLabel: preset.label,
            originLatitude: preset.lat,
            originLongitude: preset.lng,
          }
        : {
            ...seatForm,
            destinationLabel: preset.label,
            destinationLatitude: preset.lat,
            destinationLongitude: preset.lng,
          },
    );
  }

  useEffect(() => {
    void load();
  }, [load]);

  const grouped = useMemo(() => {
    const map = new Map<string, Rule[]>();
    for (const rule of rules) {
      if (rule.id && standardIds.includes(rule.id)) continue;
      const key = rule.serviceType;
      map.set(key, [...(map.get(key) ?? []), rule]);
    }
    return [...map.entries()];
  }, [rules, standardIds]);

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

  return (
    <AdminFrame
      title="Pricing"
      subtitle="Har number aap khud likhte hain. System sirf Suggest karta hai — Use dabane aur Save karne tak kuch nahi badalta."
    >
      <SimplePricing areas={PRESET_AREAS} onSaved={() => void load()} onLoaded={onSetupLoaded} />

      <details className="panel spAdv">
        <summary>▸ Advanced: Khaas rate — kisi din ya area ke liye</summary>
        <header className="panelHeader">
          <div>
            <h2>Pricing rules</h2>
            <p>
              Har din, har jagah wala rate upar table mein hai. Yahan sirf khaas rules: sab se
              makhsoos active rule jeetta hai — ilaqa har jagah se upar, chhota ilaqa bare se upar,
              aur likhe hue din har din se upar.
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
        ) : grouped.length === 0 ? (
          <Empty
            title="Koi khaas rule nahi"
            copy="Har din, har jagah ka rate upar table mein hai. Kisi din ya ilaqe ka alag rate chahiye to Add rule."
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
                    <th>Shuru fees</th>
                    <th>Per km</th>
                    <th>Per minute</th>
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
                      <td>PKR {rule.baseFare}</td>
                      <td>
                        <strong>PKR {rule.perKmRate}</strong>
                      </td>
                      <td>PKR {rule.perMinuteRate}</td>
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
      </details>

      <details className="panel spAdv">
        <summary>▸ Advanced: Fixed per-seat routes</summary>
        <header className="panelHeader">
          <div>
            <h2>Fixed per-seat routes</h2>
            <p>
              A Coster running per seat charges a set fare for a known route, not
              a figure worked out from the distance. List the route here and
              per-seat trips on it are quoted that fare, with no bidding. Hiring
              the whole vehicle is unaffected.
            </p>
          </div>
          <div className="tableTools">
            <button
              className="primaryButton"
              onClick={() => setSeatForm({ ...BLANK_SEAT_FARE })}
            >
              <Plus />
              Add route
            </button>
          </div>
        </header>

        {busy ? (
          <Loading />
        ) : seatFares.length === 0 ? (
          <Empty
            title="No fixed routes yet"
            copy="Until a route is listed, per-seat trips are priced per kilometre like any other."
          />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Route</th>
                  <th>Vehicle</th>
                  <th>Per seat</th>
                  <th>Both ways</th>
                  <th>Catchment</th>
                  <th>Active</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {seatFares.map((fare) => (
                  <tr
                    key={fare.id}
                    className="clickable"
                    onClick={() => setSeatForm({ ...fare })}
                  >
                    <td>
                      <strong>
                        {fare.originLabel} → {fare.destinationLabel}
                      </strong>
                    </td>
                    <td>{fare.vehicleCategory}</td>
                    <td>
                      <strong>PKR {fare.perSeatFare.toLocaleString()}</strong>
                    </td>
                    <td>{fare.appliesBothWays ? 'Yes' : 'One way'}</td>
                    <td>
                      {fare.originRadiusKm} km / {fare.destinationRadiusKm} km
                    </td>
                    <td>
                      <Badge value={fare.isActive ? 'Active' : 'Off'} />
                    </td>
                    <td>
                      <button
                        className="iconButton"
                        title="Delete"
                        onClick={(e) => {
                          e.stopPropagation();
                          void removeSeatFare(fare);
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
        )}
      </details>

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
            <Field label="Base fare (PKR) — charged once per trip">
              <input
                type="number"
                min={0}
                value={form.baseFare}
                onChange={(e) => setForm({ ...form, baseFare: Number(e.target.value) })}
              />
            </Field>
          </div>

          <p style={{ fontSize: 12, opacity: 0.78, lineHeight: 1.55, margin: '2px 0 10px' }}>
            A base fare is what lets the minimum come down. With no base and a high minimum, the
            per-kilometre rate does nothing until a trip is long enough to clear it — at 65/km
            with a 1,600 minimum that is about 23&nbsp;km, so every car ride inside Muzaffarabad
            costs exactly 1,600 and the distance rate is decorative. Setting a base and lowering
            the minimum together makes short rides cost what they should without making them
            free.
          </p>

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

      {seatForm && (
        <Modal
          title={seatForm.id ? 'Edit route fare' : 'Add route fare'}
          onClose={() => setSeatForm(null)}
        >
          <div className="formGrid">
            <Field label="Vehicle">
              <select
                value={seatForm.vehicleCategory}
                onChange={(e) =>
                  setSeatForm({ ...seatForm, vehicleCategory: e.target.value })
                }
              >
                {SEAT_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Fare per seat (PKR)">
              <input
                type="number"
                min={1}
                value={seatForm.perSeatFare}
                onChange={(e) =>
                  setSeatForm({ ...seatForm, perSeatFare: Number(e.target.value) })
                }
              />
            </Field>
            <Field label="Also applies in reverse">
              <input
                type="checkbox"
                checked={seatForm.appliesBothWays}
                onChange={(e) =>
                  setSeatForm({ ...seatForm, appliesBothWays: e.target.checked })
                }
              />
            </Field>

            <Field label="From — pick a town">
              <select value="" onChange={(e) => applyEndpoint('origin', e.target.value)}>
                <option value="">Choose…</option>
                {PRESET_AREAS.map((a) => (
                  <option key={a.label} value={a.label}>
                    {a.label}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="From — name shown to customers">
              <input
                value={seatForm.originLabel}
                onChange={(e) =>
                  setSeatForm({ ...seatForm, originLabel: e.target.value })
                }
              />
            </Field>
            <Field label="From — how far out counts (km)">
              <input
                type="number"
                min={1}
                value={seatForm.originRadiusKm}
                onChange={(e) =>
                  setSeatForm({ ...seatForm, originRadiusKm: Number(e.target.value) })
                }
              />
            </Field>

            <Field label="To — pick a town">
              <select
                value=""
                onChange={(e) => applyEndpoint('destination', e.target.value)}
              >
                <option value="">Choose…</option>
                {PRESET_AREAS.map((a) => (
                  <option key={a.label} value={a.label}>
                    {a.label}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="To — name shown to customers">
              <input
                value={seatForm.destinationLabel}
                onChange={(e) =>
                  setSeatForm({ ...seatForm, destinationLabel: e.target.value })
                }
              />
            </Field>
            <Field label="To — how far out counts (km)">
              <input
                type="number"
                min={1}
                value={seatForm.destinationRadiusKm}
                onChange={(e) =>
                  setSeatForm({
                    ...seatForm,
                    destinationRadiusKm: Number(e.target.value),
                  })
                }
              />
            </Field>

            <Field label="Active">
              <input
                type="checkbox"
                checked={seatForm.isActive}
                onChange={(e) => setSeatForm({ ...seatForm, isActive: e.target.checked })}
              />
            </Field>
          </div>

          <Field label="Note (optional)">
            <textarea
              rows={2}
              value={seatForm.notes ?? ''}
              placeholder="e.g. luggage above 20 kg charged separately"
              onChange={(e) =>
                setSeatForm({ ...seatForm, notes: e.target.value || null })
              }
            />
          </Field>

          <p style={{ margin: '4px 4px 12px', opacity: 0.7, fontSize: 12.5, lineHeight: 1.6 }}>
            The radius is what makes a town name mean the whole town. Passengers
            board somewhere in Muzaffarabad, not at one coordinate, so a pickup
            anywhere inside the circle counts as this route.
          </p>

          <button
            className="primaryButton"
            onClick={() => void saveSeatFare()}
            disabled={seatSaving}
          >
            {seatSaving ? 'Saving…' : 'Save route'}
          </button>
        </Modal>
      )}
    </AdminFrame>
  );
}
