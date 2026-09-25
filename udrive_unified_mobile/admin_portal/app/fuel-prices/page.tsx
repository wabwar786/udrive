'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Fuel, RefreshCw } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Empty, ErrorBox, Field, Loading, Stat } from '../components/ui';
import { apiFetch, when } from '../lib/admin-api';

const ENDPOINT = '/api/v1/admin/fare/fuel-prices';
const BASELINE_ENDPOINT = '/api/v1/admin/fare/fuel-baselines';

type FuelPrice = {
  id: string;
  fuelType: 'Petrol' | 'Diesel';
  pricePerLitre: number;
  effectiveFrom: string;
  source: string | null;
  createdAt: string;
};

/**
 * Where the rate card was set.
 *
 * Read from settings rather than typed here: the index is current ÷ baseline,
 * and a baseline of zero switches fuel indexing off entirely. That is how the
 * platform ships, so recording prices changes nothing until a baseline exists.
 */
type Baselines = {
  petrol: number;
  diesel: number;
  factorMin: number;
  factorMax: number;
};

export default function FuelPricesPage() {
  const [prices, setPrices] = useState<FuelPrice[]>([]);
  const [baselines, setBaselines] = useState<Baselines>({
    petrol: 0,
    diesel: 0,
    factorMin: 0.85,
    factorMax: 1.25,
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const [fuelType, setFuelType] = useState<'Petrol' | 'Diesel'>('Petrol');
  const [price, setPrice] = useState('');
  const [effectiveFrom, setEffectiveFrom] = useState(() =>
    new Date().toISOString().slice(0, 10),
  );
  const [source, setSource] = useState('OGRA notification');

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // Settled rather than all: the baselines and the history are two
      // independent facts, and failing to read one is no reason to tell the
      // operator the other does not exist.
      const [rowsResult, savedResult] = await Promise.allSettled([
        apiFetch<FuelPrice[]>(`${ENDPOINT}?limit=60`),
        apiFetch<Baselines>(BASELINE_ENDPOINT),
      ]);

      if (rowsResult.status === 'fulfilled') setPrices(rowsResult.value);
      if (savedResult.status === 'fulfilled') setBaselines(savedResult.value);

      const failed = [rowsResult, savedResult].find((entry) => entry.status === 'rejected');
      if (failed && failed.status === 'rejected') {
        setError(
          failed.reason instanceof Error
            ? failed.reason.message
            : 'Part of this page could not be loaded.',
        );
      }
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : 'Unable to load fuel prices.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const current = useMemo(() => {
    const today = new Date().toISOString().slice(0, 10);
    const latest = (type: 'Petrol' | 'Diesel') =>
      prices
        .filter((row) => row.fuelType === type && row.effectiveFrom.slice(0, 10) <= today)
        .sort((a, b) => b.effectiveFrom.localeCompare(a.effectiveFrom))[0];
    return { petrol: latest('Petrol'), diesel: latest('Diesel') };
  }, [prices]);

  function indexFor(now: FuelPrice | undefined, baseline: number) {
    if (!now || baseline <= 0) return null;
    const raw = now.pricePerLitre / baseline;
    // The engine's own caps, read from settings with the baselines — hard-coding
    // them here would state a multiplier that is not the one being charged the
    // moment either setting moves.
    return Math.min(baselines.factorMax, Math.max(baselines.factorMin, raw));
  }

  const petrolIndex = indexFor(current.petrol, baselines.petrol);
  const dieselIndex = indexFor(current.diesel, baselines.diesel);

  async function saveBaselines(next: Baselines) {
    setSaving(true);
    setError(null);
    try {
      setBaselines(await apiFetch<Baselines>(BASELINE_ENDPOINT, {
        method: 'PUT',
        body: JSON.stringify(next),
      }));
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : 'Unable to save the baselines.');
    } finally {
      setSaving(false);
    }
  }

  async function record() {
    const value = Number(price);
    if (!Number.isFinite(value) || value <= 0) {
      setError('Enter the price per litre.');
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await apiFetch(ENDPOINT, {
        method: 'POST',
        body: JSON.stringify({
          fuelType,
          pricePerLitre: value,
          effectiveFrom,
          source: source.trim() || null,
        }),
      });
      setPrice('');
      await load();
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : 'Unable to record this price.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <AdminFrame
      title="Fuel prices"
      subtitle="Every fare moves with the pump. Record a price when it changes; the rate card stays as you set it."
    >
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Where fares are now</h2>
            <p>
              The index is today&apos;s price divided by the price the rate card was set against,
              capped between 0.85× and 1.25×. A baseline of zero means fuel indexing is off and
              every fare is exactly what the rate card says.
            </p>
          </div>
          <div className="tableTools">
            <button className="secondaryButton" onClick={() => void load()}>
              <RefreshCw size={15} /> Refresh
            </button>
          </div>
        </header>

        <div className="formGrid">
          <Stat
            label="Petrol"
            value={current.petrol ? `PKR ${current.petrol.pricePerLitre}` : '—'}
            sub={
              baselines.petrol > 0
                ? `baseline ${baselines.petrol} · fares ×${petrolIndex?.toFixed(3) ?? '1.000'}`
                : 'no baseline set — indexing off'
            }
          />
          <Stat
            label="Diesel"
            value={current.diesel ? `PKR ${current.diesel.pricePerLitre}` : '—'}
            sub={
              baselines.diesel > 0
                ? `baseline ${baselines.diesel} · fares ×${dieselIndex?.toFixed(3) ?? '1.000'}`
                : 'no baseline set — indexing off'
            }
          />
        </div>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Baselines</h2>
            <p>
              The pump prices your rate card is correct at. Setting them switches fuel indexing
              on; raising a baseline afterwards lowers every fare and lowering it raises them,
              so this is the most consequential number on these screens.
            </p>
          </div>
        </header>

        <div className="formGrid">
          <Field label="Petrol baseline (PKR / litre) — 0 turns indexing off">
            <input
              type="number"
              step="0.01"
              min="0"
              value={baselines.petrol}
              onChange={(event) =>
                setBaselines({ ...baselines, petrol: Number(event.target.value) })
              }
            />
          </Field>
          <Field label="Diesel baseline (PKR / litre) — 0 turns indexing off">
            <input
              type="number"
              step="0.01"
              min="0"
              value={baselines.diesel}
              onChange={(event) =>
                setBaselines({ ...baselines, diesel: Number(event.target.value) })
              }
            />
          </Field>
        </div>

        <div className="tableTools" style={{ marginTop: 12, flexWrap: 'wrap' }}>
          <button
            className="primaryButton"
            disabled={saving}
            onClick={() => void saveBaselines(baselines)}
          >
            {saving ? 'Saving…' : 'Save baselines'}
          </button>
          {current.petrol && (
            <button
              className="secondaryButton"
              disabled={saving}
              onClick={() =>
                void saveBaselines({
                  ...baselines,
                  petrol: current.petrol!.pricePerLitre,
                  diesel: current.diesel?.pricePerLitre ?? baselines.diesel,
                })
              }
            >
              Set to today&apos;s prices — fares unchanged from now
            </button>
          )}
        </div>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Record a price</h2>
            <p>
              Pakistan revises pump prices about every fortnight. Entering the same day twice
              corrects it rather than adding a second row, and a date in the future takes effect
              on that day.
            </p>
          </div>
        </header>

        {error && <ErrorBox message={error} />}

        <div className="formGrid">
          <Field label="Fuel">
            <select
              value={fuelType}
              onChange={(event) => setFuelType(event.target.value as 'Petrol' | 'Diesel')}
            >
              <option value="Petrol">Petrol — bike, car, rickshaw</option>
              <option value="Diesel">Diesel — Hiace, Coster</option>
            </select>
          </Field>
          <Field label="Price per litre (PKR)">
            <input
              type="number"
              step="0.01"
              min="1"
              value={price}
              onChange={(event) => setPrice(event.target.value)}
              placeholder="275.50"
            />
          </Field>
          <Field label="Effective from">
            <input
              type="date"
              value={effectiveFrom}
              onChange={(event) => setEffectiveFrom(event.target.value)}
            />
          </Field>
          <Field label="Source">
            <input value={source} onChange={(event) => setSource(event.target.value)} />
          </Field>
        </div>

        <div className="tableTools" style={{ marginTop: 12 }}>
          <button className="primaryButton" disabled={saving} onClick={() => void record()}>
            <Fuel size={15} /> {saving ? 'Saving…' : 'Record price'}
          </button>
        </div>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>History</h2>
            <p>Newest first.</p>
          </div>
        </header>

        {loading ? (
          <Loading />
        ) : prices.length === 0 ? (
          <Empty
            title="No prices recorded"
            copy="Fares stay exactly as the rate card sets them until a baseline and a price both exist."
          />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Effective from</th>
                  <th>Fuel</th>
                  <th>Price / litre</th>
                  <th>Source</th>
                  <th>Recorded</th>
                </tr>
              </thead>
              <tbody>
                {prices.map((row) => (
                  <tr key={row.id}>
                    <td>{row.effectiveFrom.slice(0, 10)}</td>
                    <td>{row.fuelType}</td>
                    <td>PKR {row.pricePerLitre}</td>
                    <td>{row.source ?? '—'}</td>
                    <td>{when(row.createdAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </AdminFrame>
  );
}
