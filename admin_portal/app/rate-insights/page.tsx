'use client';

import { useCallback, useEffect, useState } from 'react';
import { RefreshCw } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Empty, ErrorBox, Field, Loading } from '../components/ui';
import { apiFetch, money } from '../lib/admin-api';

const ENDPOINT = '/api/v1/admin/fare/route-insights';

type Insight = {
  originZone: string;
  destinationZone: string;
  vehicleCategory: string;
  completedRides: number;
  requestsWithNoOffer: number;
  noOfferRate: number;
  medianAgreedFare: number | null;
  medianSuggestedFare: number | null;
  medianFirstOfferSeconds: number | null;
  suggestedChangePercent: number | null;
};

export default function RateInsightsPage() {
  const [rows, setRows] = useState<Insight[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [days, setDays] = useState(60);
  const [minimumSample, setMinimumSample] = useState(20);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setRows(
        await apiFetch<Insight[]>(
          `${ENDPOINT}?days=${days}&minimumSample=${minimumSample}`,
        ),
      );
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : 'Unable to load insights.');
    } finally {
      setLoading(false);
    }
  }, [days, minimumSample]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <AdminFrame
      title="Route insights"
      subtitle="What drivers actually accept, against what UDrive suggests."
    >
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>By route and vehicle</h2>
            <p>
              A median and two counts — no model, nothing to explain to a driver beyond the
              numbers on this screen. Nothing here changes a price: read the row, decide, then
              change the rate or the zone yourself.
            </p>
          </div>
          <div className="tableTools">
            <button className="secondaryButton" onClick={() => void load()}>
              <RefreshCw size={15} /> Refresh
            </button>
          </div>
        </header>

        <div className="formGrid">
          <Field label="Look back (days)">
            <input
              type="number"
              min="7"
              max="365"
              value={days}
              onChange={(event) => setDays(Number(event.target.value))}
            />
          </Field>
          <Field label="Fewest requests before a route is listed">
            <input
              type="number"
              min="1"
              max="500"
              value={minimumSample}
              onChange={(event) => setMinimumSample(Number(event.target.value))}
            />
          </Field>
        </div>

        {error && <ErrorBox message={error} />}

        {loading ? (
          <Loading />
        ) : rows.length === 0 ? (
          <Empty
            title="Not enough rides yet"
            copy="A route appears once it has enough requests to say something. Lower the threshold to see thinner routes."
          />
        ) : (
          <>
            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Route</th>
                    <th>Vehicle</th>
                    <th>Completed</th>
                    <th>No offer</th>
                    <th>UDrive suggests</th>
                    <th>Drivers accept</th>
                    <th>First offer</th>
                    <th>Suggested change</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => {
                    const key = `${row.originZone}|${row.destinationZone}|${row.vehicleCategory}`;
                    const change = row.suggestedChangePercent;
                    return (
                      <tr key={key}>
                        <td>
                          <strong>{row.originZone}</strong>
                          <div style={{ fontSize: 11, opacity: 0.7 }}>→ {row.destinationZone}</div>
                        </td>
                        <td>{row.vehicleCategory}</td>
                        <td>{row.completedRides}</td>
                        <td>
                          {row.requestsWithNoOffer}
                          <div style={{ fontSize: 11, opacity: 0.7 }}>{row.noOfferRate}%</div>
                        </td>
                        <td>{row.medianSuggestedFare == null ? '—' : money(row.medianSuggestedFare)}</td>
                        <td>{row.medianAgreedFare == null ? '—' : money(row.medianAgreedFare)}</td>
                        <td>
                          {row.medianFirstOfferSeconds == null
                            ? '—'
                            : `${Math.round(row.medianFirstOfferSeconds)}s`}
                        </td>
                        <td>
                          {change == null ? (
                            <span style={{ opacity: 0.6 }}>not enough rides</span>
                          ) : (
                            <strong>
                              {change > 0 ? '+' : ''}
                              {change}%
                            </strong>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <p style={{ fontSize: 12, opacity: 0.75, marginTop: 12, lineHeight: 1.6 }}>
              <strong>Read the &ldquo;no offer&rdquo; column first.</strong> A route where the
              suggestion is close to the agreed fare but a third of requests attract no offer at
              all is priced below what a driver will get out of bed for — and the median cannot
              show that, because the rides nobody accepted are not in it.
              <br />
              The suggested change is the gap between the two fare columns, capped at 25% and
              held back until a route has ten completed rides. To act on one, raise the
              per-kilometre rate or the minimum on <em>Pricing &amp; fares</em>, or the zone&apos;s
              difficulty and return share on <em>Fare zones</em>.
            </p>
          </>
        )}
      </section>
    </AdminFrame>
  );
}
