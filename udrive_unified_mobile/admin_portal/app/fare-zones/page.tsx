'use client';

import { useCallback, useEffect, useState } from 'react';
import { MapPinned, Plus, RefreshCw, Trash2 } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

const ENDPOINT = '/api/v1/admin/fare/zones';

const MONTHS = [
  { value: 1, label: 'Jan' }, { value: 2, label: 'Feb' }, { value: 3, label: 'Mar' },
  { value: 4, label: 'Apr' }, { value: 5, label: 'May' }, { value: 6, label: 'Jun' },
  { value: 7, label: 'Jul' }, { value: 8, label: 'Aug' }, { value: 9, label: 'Sep' },
  { value: 10, label: 'Oct' }, { value: 11, label: 'Nov' }, { value: 12, label: 'Dec' },
];

/**
 * Centres worth having one keystroke away.
 *
 * The same list the pricing rules page carries, because the same places get
 * drawn around. Picking one fills the fields in and they stay editable.
 */
const PRESETS: { label: string; lat: number; lng: number; radius: number }[] = [
  { label: 'Muzaffarabad', lat: 34.3700, lng: 73.4711, radius: 15 },
  { label: 'Neelum Valley', lat: 34.5890, lng: 73.9070, radius: 40 },
  { label: 'Rawalakot', lat: 33.8580, lng: 73.7600, radius: 12 },
  { label: 'Kotli', lat: 33.5180, lng: 73.9020, radius: 12 },
  { label: 'Mirpur', lat: 33.1478, lng: 73.7519, radius: 15 },
  { label: 'Bhimber', lat: 32.9742, lng: 74.0781, radius: 12 },
];

type Area = {
  id?: string | null;
  label: string | null;
  latitude: number;
  longitude: number;
  radiusKm: number;
};

type Zone = {
  id: string;
  name: string;
  difficultyFactor: number;
  returnShare: number;
  surgeEnabled: boolean;
  activeMonths: number[] | null;
  priority: number;
  isActive: boolean;
  notes: string | null;
  areas: Area[];
};

type Draft = Omit<Zone, 'id'> & { id?: string };

const BLANK: Draft = {
  name: '',
  difficultyFactor: 1,
  returnShare: 0,
  surgeEnabled: true,
  activeMonths: null,
  priority: 0,
  isActive: false,
  notes: '',
  areas: [{ label: '', latitude: 34.37, longitude: 73.4711, radiusKm: 15 }],
};

/**
 * What the two numbers actually cost, on a long trip.
 *
 * They compound, and by more than they look. Difficulty multiplies the whole
 * meter; the return share is a slice of the distance cost and is charged
 * through the same terrain, so it carries the difficulty too. On a long trip
 * almost all of the fare is distance, so the effect is close to
 * difficulty × (1 + return share) — 1.3 with a 0.55 return share is roughly
 * double the flat fare, not thirty per cent more.
 *
 * Nobody should have to work that out from two input boxes, so it is printed
 * next to them. The sample is a Coster valley run: 100 km, four hours, at the
 * seeded rates.
 */
function effectiveMultiplier(difficulty: number, returnShare: number) {
  const perKm = 160;
  const perMinute = 2;
  const km = 100;
  const minutes = 240;

  const distanceCost = perKm * km;
  const meter = distanceCost + perMinute * minutes;
  const withZone = meter * difficulty + distanceCost * returnShare * difficulty;
  return withZone / meter;
}

export default function FareZonesPage() {
  const [zones, setZones] = useState<Zone[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setZones(await apiFetch<Zone[]>(ENDPOINT));
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : 'Unable to load zones.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function save() {
    if (!draft) return;
    setSaving(true);
    try {
      await apiFetch(ENDPOINT, {
        method: 'POST',
        body: JSON.stringify({
          ...draft,
          notes: draft.notes?.trim() || null,
          areas: draft.areas.map((area) => ({
            label: area.label?.trim() || null,
            latitude: Number(area.latitude),
            longitude: Number(area.longitude),
            radiusKm: Number(area.radiusKm),
          })),
        }),
      });
      setDraft(null);
      await load();
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : 'Unable to save this zone.');
    } finally {
      setSaving(false);
    }
  }

  async function remove(zone: Zone) {
    if (!window.confirm(`Delete "${zone.name}"? Trips in this area go back to the default rate.`)) return;
    try {
      await apiFetch(`${ENDPOINT}/${zone.id}`, { method: 'DELETE' });
      await load();
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : 'Unable to delete this zone.');
    }
  }

  function patchArea(index: number, patch: Partial<Area>) {
    setDraft((current) =>
      current
        ? {
            ...current,
            areas: current.areas.map((area, position) =>
              position === index ? { ...area, ...patch } : area,
            ),
          }
        : current,
    );
  }

  return (
    <AdminFrame
      title="Fare zones"
      subtitle="Terrain, empty returns and season — what makes a kilometre in Neelum cost more than a kilometre in town."
    >
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Zones</h2>
            <p>
              A zone is a named set of circles. Highest priority wins where they overlap, then
              the tightest circle. A trip outside every zone is priced flat, exactly as it was
              before zones existed.
            </p>
          </div>
          <div className="tableTools">
            <button className="secondaryButton" onClick={() => void load()}>
              <RefreshCw size={15} /> Refresh
            </button>
            <button className="primaryButton" onClick={() => setDraft({ ...BLANK })}>
              <Plus size={15} /> New zone
            </button>
          </div>
        </header>

        {error && <ErrorBox message={error} />}
        {loading ? (
          <Loading />
        ) : zones.length === 0 ? (
          <Empty title="No zones yet" copy="Every trip is priced at the flat rate until a zone covers it." />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Zone</th>
                  <th>Difficulty</th>
                  <th>Return share</th>
                  <th>On a long trip</th>
                  <th>Season</th>
                  <th>Circles</th>
                  <th>Surge</th>
                  <th>Live</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {zones.map((zone) => (
                  <tr key={zone.id} className="clickable" onClick={() => setDraft({ ...zone })}>
                    <td>
                      <strong>{zone.name}</strong>
                      {zone.notes && <div style={{ fontSize: 11, opacity: 0.7 }}>{zone.notes}</div>}
                    </td>
                    <td>{zone.difficultyFactor.toFixed(2)}×</td>
                    <td>{Math.round(zone.returnShare * 100)}%</td>
                    <td>
                      <strong>
                        {effectiveMultiplier(zone.difficultyFactor, zone.returnShare).toFixed(2)}×
                      </strong>
                    </td>
                    <td>
                      {zone.activeMonths && zone.activeMonths.length > 0
                        ? zone.activeMonths
                            .map((month) => MONTHS.find((entry) => entry.value === month)?.label)
                            .join(' ')
                        : 'All year'}
                    </td>
                    <td>{zone.areas.length}</td>
                    <td>{zone.surgeEnabled ? 'Yes' : 'No'}</td>
                    <td><Badge value={zone.isActive ? 'Active' : 'Off'} /></td>
                    <td>
                      <button
                        className="iconButton"
                        onClick={(event) => {
                          event.stopPropagation();
                          void remove(zone);
                        }}
                      >
                        <Trash2 size={15} />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {draft && (
        <Modal title={draft.id ? 'Edit zone' : 'New zone'} onClose={() => setDraft(null)}>
          <div className="formGrid">
            <Field label="Name">
              <input
                value={draft.name}
                onChange={(event) => setDraft({ ...draft, name: event.target.value })}
                placeholder="Neelum upper (Sharda, Kel)"
              />
            </Field>

            <Field label="Difficulty — multiplies the whole fare">
              <input
                type="number"
                step="0.05"
                min="0.5"
                max="4"
                value={draft.difficultyFactor}
                onChange={(event) =>
                  setDraft({ ...draft, difficultyFactor: Number(event.target.value) })
                }
              />
            </Field>

            <Field label="Return share — how much of the drive back the customer pays">
              <input
                type="number"
                step="0.05"
                min="0"
                max="1"
                value={draft.returnShare}
                onChange={(event) => setDraft({ ...draft, returnShare: Number(event.target.value) })}
              />
            </Field>

            <Field label="Priority — highest wins where zones overlap">
              <input
                type="number"
                value={draft.priority}
                onChange={(event) => setDraft({ ...draft, priority: Number(event.target.value) })}
              />
            </Field>
          </div>

          <div
            style={{
              margin: '10px 0 14px',
              padding: '10px 12px',
              borderRadius: 12,
              background: 'rgba(198,244,50,.14)',
              fontSize: 12.5,
              lineHeight: 1.5,
            }}
          >
            On a long trip this zone charges{' '}
            <strong>
              {effectiveMultiplier(draft.difficultyFactor, draft.returnShare).toFixed(2)}×
            </strong>{' '}
            the flat fare. The two numbers compound — the drive back is through the same terrain,
            so it carries the difficulty too. Read this figure, not the boxes above it.
          </div>

          <Field label="Months this zone prices — none selected means all year">
            <div className="tableTools" style={{ flexWrap: 'wrap', gap: 6 }}>
              {MONTHS.map((month) => {
                const selected = draft.activeMonths?.includes(month.value) ?? false;
                return (
                  <button
                    key={month.value}
                    type="button"
                    className={selected ? 'primaryButton' : 'secondaryButton'}
                    onClick={() => {
                      const current = draft.activeMonths ?? [];
                      const next = selected
                        ? current.filter((value) => value !== month.value)
                        : [...current, month.value].sort((a, b) => a - b);
                      setDraft({ ...draft, activeMonths: next.length === 0 ? null : next });
                    }}
                  >
                    {month.label}
                  </button>
                );
              })}
            </div>
          </Field>

          <div className="formGrid" style={{ marginTop: 12 }}>
            <Field label="Allow surge in this zone">
              <select
                value={draft.surgeEnabled ? 'yes' : 'no'}
                onChange={(event) => setDraft({ ...draft, surgeEnabled: event.target.value === 'yes' })}
              >
                <option value="yes">Yes</option>
                <option value="no">No</option>
              </select>
            </Field>
            <Field label="Live">
              <select
                value={draft.isActive ? 'yes' : 'no'}
                onChange={(event) => setDraft({ ...draft, isActive: event.target.value === 'yes' })}
              >
                <option value="no">Off — not pricing anything</option>
                <option value="yes">Active — pricing real trips</option>
              </select>
            </Field>
          </div>

          <Field label="Notes">
            <input
              value={draft.notes ?? ''}
              onChange={(event) => setDraft({ ...draft, notes: event.target.value })}
            />
          </Field>

          <h3 style={{ margin: '16px 0 6px', fontSize: 14 }}>Circles</h3>
          <p style={{ fontSize: 12, opacity: 0.75, marginBottom: 10 }}>
            A long valley wants four or five overlapping circles along the road rather than one
            large one — a circle big enough to reach Kel also covers places that are nothing like
            it.
          </p>

          {draft.areas.map((area, index) => (
            <div key={index} className="formGrid" style={{ alignItems: 'end' }}>
              <Field label="Label">
                <input
                  value={area.label ?? ''}
                  onChange={(event) => patchArea(index, { label: event.target.value })}
                  placeholder="Sharda"
                />
              </Field>
              <Field label="Latitude">
                <input
                  type="number"
                  step="0.0001"
                  value={area.latitude}
                  onChange={(event) => patchArea(index, { latitude: Number(event.target.value) })}
                />
              </Field>
              <Field label="Longitude">
                <input
                  type="number"
                  step="0.0001"
                  value={area.longitude}
                  onChange={(event) => patchArea(index, { longitude: Number(event.target.value) })}
                />
              </Field>
              <Field label="Radius (km)">
                <input
                  type="number"
                  step="0.5"
                  min="0.1"
                  value={area.radiusKm}
                  onChange={(event) => patchArea(index, { radiusKm: Number(event.target.value) })}
                />
              </Field>
              <button
                className="iconButton"
                type="button"
                onClick={() =>
                  setDraft({
                    ...draft,
                    areas: draft.areas.filter((_, position) => position !== index),
                  })
                }
              >
                <Trash2 size={15} />
              </button>
            </div>
          ))}

          <div className="tableTools" style={{ flexWrap: 'wrap', marginTop: 8 }}>
            <button
              className="secondaryButton"
              type="button"
              onClick={() =>
                setDraft({
                  ...draft,
                  areas: [
                    ...draft.areas,
                    { label: '', latitude: 34.37, longitude: 73.4711, radiusKm: 15 },
                  ],
                })
              }
            >
              <Plus size={14} /> Add circle
            </button>
            {PRESETS.map((preset) => (
              <button
                key={preset.label}
                className="secondaryButton"
                type="button"
                onClick={() =>
                  setDraft({
                    ...draft,
                    areas: [
                      ...draft.areas,
                      {
                        label: preset.label,
                        latitude: preset.lat,
                        longitude: preset.lng,
                        radiusKm: preset.radius,
                      },
                    ],
                  })
                }
              >
                <MapPinned size={14} /> {preset.label}
              </button>
            ))}
          </div>

          <div className="tableTools" style={{ marginTop: 18 }}>
            <button className="secondaryButton" onClick={() => setDraft(null)}>
              Cancel
            </button>
            <button className="primaryButton" disabled={saving} onClick={() => void save()}>
              {saving ? 'Saving…' : 'Save zone'}
            </button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
