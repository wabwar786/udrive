'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus, Save, Trash2 } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { apiFetch, money, when } from '../lib/admin-api';

type City = { id: string; name: string; isActive?: boolean };

type Milestone = {
  id?: string | null;
  sortOrder: number;
  title: string;
  description?: string | null;
  rewardAmount: number;
  conditionType: string;
  conditionValue: number;
};

type Campaign = {
  id: string;
  campaignType: string;
  code: string;
  title: string;
  description?: string | null;
  cityId?: string | null;
  cityName?: string | null;
  zoneId?: string | null;
  zoneName?: string | null;
  rewardAmount: number;
  startsAt?: string | null;
  endsAt?: string | null;
  dailyStartTime?: string | null;
  dailyEndTime?: string | null;
  daysOfWeek: number[];
  driverSegment: string;
  minOnlineSeconds?: number | null;
  minCompletedRides?: number | null;
  minAcceptedRides?: number | null;
  maxCancellations?: number | null;
  minRating?: number | null;
  minAcceptanceRate?: number | null;
  inactiveDays?: number | null;
  maxAwardsPerDriver: number;
  totalBudget?: number | null;
  spentAmount: number;
  isActive: boolean;
  milestones: Milestone[];
};

type Award = {
  id: string;
  driverProfileId: string;
  driverName: string;
  milestoneTitle?: string | null;
  periodKey: string;
  progressValue: number;
  targetValue: number;
  status: string;
  rewardAmount: number;
  qualifiedAt?: string | null;
  creditedAt?: string | null;
};

/**
 * The seven types the engine measures.
 *
 * Anything else saves and then sits there measuring nothing, because
 * `LoadCampaignsAsync` filters on exactly this list before a campaign is ever
 * evaluated. A free-text box here would be a way to create a funded campaign
 * that can never pay anybody and never reports an error.
 */
const CAMPAIGN_TYPES = [
  'WelcomeBonus',
  'DailyMission',
  'PeakHourReward',
  'WeeklyReward',
  'Referral',
  'Reactivation',
  'FoundingBenefit',
] as const;

/**
 * The eleven conditions `MeasureAsync` knows.
 *
 * Its switch ends in `_ => 0`, deliberately: an unknown condition is left at
 * zero so an admin decides rather than the engine guessing and paying. The
 * cost of that safety is that a typo here is silent — the milestone measures
 * zero for ever, no error anywhere. Hence a dropdown, and hence this list is
 * the one place it is written down outside the service.
 */
const CONDITION_TYPES = [
  'AccountVerified',
  'ProfileCompleted',
  'VehicleApproved',
  'FirstRide',
  'CompletedRides',
  'OnlineSeconds',
  'OnlineSessions',
  'AcceptanceRate',
  'ReferralVerified',
  'ReferralFirstRide',
  'ReferralActive',
] as const;

/** What each condition counts, so an admin is not guessing at the units. */
const CONDITION_HINT: Record<string, string> = {
  AccountVerified: 'Documents approved — use 1',
  ProfileCompleted: 'Profile filled in — use 1',
  VehicleApproved: 'At least one vehicle approved — use 1',
  FirstRide: 'Any completed ride — use 1',
  CompletedRides: 'Number of completed rides in the period',
  OnlineSeconds: 'Seconds online in the period (1 hour = 3600)',
  OnlineSessions: 'Separate days online in the period',
  AcceptanceRate: 'Percentage, 0–100',
  ReferralVerified: 'Invited drivers whose documents were approved',
  ReferralFirstRide: 'Invited drivers who completed a ride',
  ReferralActive: 'Invited drivers who became active',
};

const SEGMENTS = ['All', 'New', 'Founding', 'Inactive'] as const;

const EMPTY: Campaign = {
  id: '',
  campaignType: 'DailyMission',
  code: '',
  title: '',
  description: '',
  cityId: null,
  rewardAmount: 0,
  daysOfWeek: [],
  driverSegment: 'All',
  maxAwardsPerDriver: 1,
  totalBudget: null,
  spentAmount: 0,
  isActive: false,
  milestones: [],
};

/**
 * Growth campaigns — where every driver incentive is created.
 *
 * The API for this shipped with the growth system and no page ever called it,
 * which means that until now no campaign could be created at all. Everything
 * running in production is a row a migration seeded. That is the gap this page
 * closes, and it is why the two dropdowns above matter more than the layout:
 * the engine fails silently on an unknown campaign type or condition, so the
 * only safe way to offer those fields is a closed list.
 */
export default function Page() {
  const [cities, setCities] = useState<City[]>([]);
  const [rows, setRows] = useState<Campaign[]>([]);
  const [cityFilter, setCityFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [search, setSearch] = useState('');

  const [editing, setEditing] = useState<Campaign | null>(null);
  const [awardsFor, setAwardsFor] = useState<Campaign | null>(null);
  const [awards, setAwards] = useState<Award[]>([]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');

  const load = useCallback(async () => {
    try {
      const [c, r] = await Promise.all([
        apiFetch<City[]>('/api/v1/admin/growth/cities'),
        apiFetch<Campaign[]>('/api/v1/admin/growth/campaigns'),
      ]);
      setCities(c);
      setRows(r);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'This section is unavailable.');
    }
  }, []);

  useEffect(() => {
    setLoading(true);
    void load().finally(() => setLoading(false));
  }, [load]);

  const visible = useMemo(() => {
    const term = search.trim().toLowerCase();
    return rows.filter(
      (r) =>
        (!cityFilter || r.cityId === cityFilter) &&
        (!typeFilter || r.campaignType === typeFilter) &&
        (!term ||
          r.title.toLowerCase().includes(term) ||
          r.code.toLowerCase().includes(term)),
    );
  }, [rows, cityFilter, typeFilter, search]);

  const stats = useMemo(() => {
    const active = rows.filter((r) => r.isActive);
    const committed = rows.reduce((sum, r) => sum + (r.totalBudget ?? 0), 0);
    const spent = rows.reduce((sum, r) => sum + r.spentAmount, 0);
    return {
      active: active.length,
      cities: new Set(active.map((r) => r.cityId ?? 'all')).size,
      committed,
      spent,
    };
  }, [rows]);

  const save = async () => {
    if (!editing) return;
    setBusy(true);
    setError('');
    setNote('');
    try {
      const body = JSON.stringify({
        campaignType: editing.campaignType,
        code: editing.code.trim(),
        title: editing.title.trim(),
        description: editing.description || null,
        cityId: editing.cityId || null,
        zoneId: editing.zoneId || null,
        rewardAmount: Number(editing.rewardAmount) || 0,
        startsAt: editing.startsAt || null,
        endsAt: editing.endsAt || null,
        dailyStartTime: editing.dailyStartTime || null,
        dailyEndTime: editing.dailyEndTime || null,
        daysOfWeek: editing.daysOfWeek,
        driverSegment: editing.driverSegment,
        minOnlineSeconds: editing.minOnlineSeconds ?? null,
        minCompletedRides: editing.minCompletedRides ?? null,
        minAcceptedRides: editing.minAcceptedRides ?? null,
        maxCancellations: editing.maxCancellations ?? null,
        minRating: editing.minRating ?? null,
        minAcceptanceRate: editing.minAcceptanceRate ?? null,
        inactiveDays: editing.inactiveDays ?? null,
        maxAwardsPerDriver: Number(editing.maxAwardsPerDriver) || 1,
        totalBudget: editing.totalBudget ?? null,
        isActive: editing.isActive,
        // The id travels with every milestone. Position used to be identity
        // here, so reordering the list overwrote rows rather than moving them —
        // one milestone permanently unpayable, another paid twice under a new
        // id. The API guards against that only if the page sends the id back.
        milestones: editing.milestones.map((m) => ({
          id: m.id ?? null,
          sortOrder: m.sortOrder,
          title: m.title.trim(),
          description: m.description || null,
          rewardAmount: Number(m.rewardAmount) || 0,
          conditionType: m.conditionType,
          conditionValue: Number(m.conditionValue) || 0,
        })),
      });

      await apiFetch<string>(
        editing.id
          ? `/api/v1/admin/growth/campaigns/${editing.id}`
          : '/api/v1/admin/growth/campaigns',
        { method: editing.id ? 'PUT' : 'POST', body },
      );

      setEditing(null);
      setNote('Saved. Drivers are measured against it from the next evaluation.');
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be saved.');
    } finally {
      setBusy(false);
    }
  };

  const toggle = async (row: Campaign) => {
    setBusy(true);
    setError('');
    try {
      await apiFetch<boolean>(
        `/api/v1/admin/growth/campaigns/${row.id}/active`,
        { method: 'POST', body: JSON.stringify({ isActive: !row.isActive }) },
      );
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be changed.');
    } finally {
      setBusy(false);
    }
  };

  const openAwards = async (row: Campaign) => {
    setAwardsFor(row);
    setAwards([]);
    try {
      setAwards(
        await apiFetch<Award[]>(
          `/api/v1/admin/growth/campaigns/${row.id}/awards`,
        ),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Awards are unavailable.');
    }
  };

  const setField = <K extends keyof Campaign>(key: K, value: Campaign[K]) =>
    setEditing((c) => (c ? { ...c, [key]: value } : c));

  const setMilestone = (index: number, patch: Partial<Milestone>) =>
    setEditing((c) =>
      c
        ? {
            ...c,
            milestones: c.milestones.map((m, i) =>
              i === index ? { ...m, ...patch } : m,
            ),
          }
        : c,
    );

  return (
    <AdminFrame
      title="Campaigns"
      subtitle="Every driver reward — welcome bonus, missions, peak hours, weekly targets, referrals."
      actions={
        <button
          className="primaryButton"
          onClick={() => setEditing({ ...EMPTY })}
          disabled={busy}
        >
          <Plus /> New campaign
        </button>
      }
    >
      {error && <ErrorBox message={error} />}
      {note && (
        <section className="panel">
          <p>{note}</p>
        </section>
      )}

      {loading ? (
        <Loading />
      ) : (
        <>
          <div className="statGrid">
            <Stat
              label="Active campaigns"
              value={stats.active}
              sub={`${stats.cities} city/cities`}
              tone="emerald"
            />
            <Stat
              label="Budget committed"
              value={money(stats.committed)}
              sub="Across every campaign"
              tone="blue"
            />
            <Stat
              label="Paid so far"
              value={money(stats.spent)}
              sub="Credited to driver wallets"
              tone="violet"
            />
            <Stat
              label="Campaigns off"
              value={rows.length - stats.active}
              sub="Created but not running"
              tone="slate"
            />
          </div>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Campaigns</h2>
                <p>{visible.length} of {rows.length}</p>
              </div>
            </header>

            <div className="toolbar">
              <select
                value={cityFilter}
                onChange={(e) => setCityFilter(e.target.value)}
              >
                <option value="">Every city</option>
                {cities.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
              <select
                value={typeFilter}
                onChange={(e) => setTypeFilter(e.target.value)}
              >
                <option value="">Every type</option>
                {CAMPAIGN_TYPES.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Title or code"
              />
            </div>

            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Campaign</th>
                    <th>Type</th>
                    <th>City</th>
                    <th>Segment</th>
                    <th>Reward</th>
                    <th>Budget</th>
                    <th>Steps</th>
                    <th>Running</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {visible.map((row) => (
                    <tr
                      key={row.id}
                      className="clickable"
                      onClick={() => setEditing({ ...row })}
                    >
                      <td>
                        <strong>{row.title}</strong>
                        <small>{row.code}</small>
                      </td>
                      <td>
                        <Badge value={row.campaignType} />
                      </td>
                      <td>{row.cityName ?? 'All cities'}</td>
                      <td>
                        {row.driverSegment}
                        {row.driverSegment === 'Inactive' && row.inactiveDays
                          ? ` · ${row.inactiveDays}d`
                          : ''}
                      </td>
                      <td>{money(row.rewardAmount)}</td>
                      <td>
                        {money(row.spentAmount)}
                        <small>
                          {row.totalBudget
                            ? `of ${money(row.totalBudget)}`
                            : 'no budget set'}
                        </small>
                      </td>
                      <td>{row.milestones.length || '—'}</td>
                      <td>
                        <Badge value={row.isActive ? 'Running' : 'Off'} />
                      </td>
                      <td>
                        <button
                          className="secondaryButton"
                          disabled={busy}
                          onClick={(e) => {
                            e.stopPropagation();
                            void toggle(row);
                          }}
                        >
                          {row.isActive ? 'Stop' : 'Start'}
                        </button>
                        <button
                          className="secondaryButton"
                          onClick={(e) => {
                            e.stopPropagation();
                            void openAwards(row);
                          }}
                        >
                          Paid
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}

      {editing && (
        <Modal
          title={editing.id ? 'Edit campaign' : 'New campaign'}
          onClose={() => setEditing(null)}
        >
          <div className="formGrid">
            <Field label="Type">
              <select
                value={editing.campaignType}
                onChange={(e) => setField('campaignType', e.target.value)}
              >
                {CAMPAIGN_TYPES.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Code">
              <input
                value={editing.code}
                onChange={(e) => setField('code', e.target.value)}
                placeholder="WELCOME-MZD"
                maxLength={48}
              />
            </Field>
          </div>

          <Field label="Title — the driver sees this">
            <input
              value={editing.title}
              onChange={(e) => setField('title', e.target.value)}
              placeholder="Your first week"
              maxLength={160}
            />
          </Field>
          <Field label="Description">
            <textarea
              rows={2}
              value={editing.description ?? ''}
              onChange={(e) => setField('description', e.target.value)}
            />
          </Field>

          <div className="formGrid">
            <Field label="City">
              <select
                value={editing.cityId ?? ''}
                onChange={(e) => setField('cityId', e.target.value || null)}
              >
                <option value="">All cities</option>
                {cities.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Who it applies to">
              <select
                value={editing.driverSegment}
                onChange={(e) => setField('driverSegment', e.target.value)}
              >
                {SEGMENTS.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
            </Field>
          </div>

          {editing.driverSegment === 'Inactive' && (
            <Field label="Days without a ride before a driver counts as inactive">
              <input
                type="number"
                min={1}
                value={editing.inactiveDays ?? 14}
                onChange={(e) =>
                  setField('inactiveDays', Number(e.target.value))
                }
              />
            </Field>
          )}

          <div className="formGrid">
            <Field label="Reward (PKR) — used when there are no steps">
              <input
                type="number"
                min={0}
                value={editing.rewardAmount}
                onChange={(e) =>
                  setField('rewardAmount', Number(e.target.value))
                }
              />
            </Field>
            <Field label="Total budget (PKR) — blank means no ceiling">
              <input
                type="number"
                min={0}
                value={editing.totalBudget ?? ''}
                onChange={(e) =>
                  setField(
                    'totalBudget',
                    e.target.value === '' ? null : Number(e.target.value),
                  )
                }
              />
            </Field>
          </div>

          {editing.campaignType === 'PeakHourReward' && (
            <div className="formGrid">
              <Field label="Starts (HH:MM)">
                <input
                  value={editing.dailyStartTime ?? ''}
                  onChange={(e) => setField('dailyStartTime', e.target.value)}
                  placeholder="17:00"
                />
              </Field>
              <Field label="Ends (HH:MM)">
                <input
                  value={editing.dailyEndTime ?? ''}
                  onChange={(e) => setField('dailyEndTime', e.target.value)}
                  placeholder="21:00"
                />
              </Field>
            </div>
          )}

          <Field label="Most awards one driver can receive">
            <input
              type="number"
              min={1}
              value={editing.maxAwardsPerDriver}
              onChange={(e) =>
                setField('maxAwardsPerDriver', Number(e.target.value))
              }
            />
          </Field>

          {/* Steps are the whole campaign when there are any: a campaign with
              steps pays each one separately and ignores the single reward
              above. A campaign with none pays the reward once, measured
              against the minimums. */}
          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Steps</h2>
                <p>
                  Each step pays on its own. Leave empty for a single-reward
                  campaign.
                </p>
              </div>
              <button
                className="secondaryButton"
                onClick={() =>
                  setField('milestones', [
                    ...editing.milestones,
                    {
                      id: null,
                      sortOrder: editing.milestones.length + 1,
                      title: '',
                      rewardAmount: 0,
                      conditionType: 'CompletedRides',
                      conditionValue: 1,
                    },
                  ])
                }
              >
                <Plus /> Add step
              </button>
            </header>

            {editing.milestones.map((m, index) => (
              <div className="formGrid" key={m.id ?? `new-${index}`}>
                <Field label="Title">
                  <input
                    value={m.title}
                    onChange={(e) =>
                      setMilestone(index, { title: e.target.value })
                    }
                    placeholder="Finish 20 rides"
                  />
                </Field>
                <Field label="Condition">
                  <select
                    value={m.conditionType}
                    onChange={(e) =>
                      setMilestone(index, { conditionType: e.target.value })
                    }
                  >
                    {CONDITION_TYPES.map((t) => (
                      <option key={t} value={t}>
                        {t}
                      </option>
                    ))}
                  </select>
                </Field>
                <Field label={CONDITION_HINT[m.conditionType] ?? 'Target'}>
                  <input
                    type="number"
                    min={0}
                    value={m.conditionValue}
                    onChange={(e) =>
                      setMilestone(index, {
                        conditionValue: Number(e.target.value),
                      })
                    }
                  />
                </Field>
                <Field label="Pays (PKR)">
                  <input
                    type="number"
                    min={0}
                    value={m.rewardAmount}
                    onChange={(e) =>
                      setMilestone(index, {
                        rewardAmount: Number(e.target.value),
                      })
                    }
                  />
                </Field>
                <Field label="Order">
                  <input
                    type="number"
                    min={1}
                    value={m.sortOrder}
                    onChange={(e) =>
                      setMilestone(index, { sortOrder: Number(e.target.value) })
                    }
                  />
                </Field>
                <Field label=" ">
                  <button
                    className="dangerButton"
                    onClick={() =>
                      setField(
                        'milestones',
                        editing.milestones.filter((_, i) => i !== index),
                      )
                    }
                  >
                    <Trash2 /> Remove
                  </button>
                </Field>
              </div>
            ))}
          </section>

          <Field label="Running">
            <select
              value={editing.isActive ? 'yes' : 'no'}
              onChange={(e) => setField('isActive', e.target.value === 'yes')}
            >
              <option value="no">Off — created but not measuring</option>
              <option value="yes">On — drivers are measured against it</option>
            </select>
          </Field>

          <div className="buttonRow">
            <button
              className="secondaryButton"
              onClick={() => setEditing(null)}
              disabled={busy}
            >
              Cancel
            </button>
            <button
              className="primaryButton"
              onClick={() => void save()}
              disabled={
                busy ||
                editing.code.trim().length === 0 ||
                editing.title.trim().length === 0
              }
            >
              <Save /> Save
            </button>
          </div>
        </Modal>
      )}

      {awardsFor && (
        <Modal
          title={`Paid — ${awardsFor.title}`}
          onClose={() => setAwardsFor(null)}
        >
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Driver</th>
                  <th>Step</th>
                  <th>Period</th>
                  <th>Progress</th>
                  <th>Status</th>
                  <th>Amount</th>
                  <th>Credited</th>
                </tr>
              </thead>
              <tbody>
                {awards.map((a) => (
                  <tr key={a.id}>
                    <td>{a.driverName}</td>
                    <td>{a.milestoneTitle ?? '—'}</td>
                    <td>{a.periodKey}</td>
                    <td>
                      {a.progressValue} / {a.targetValue}
                    </td>
                    <td>
                      <Badge value={a.status} />
                    </td>
                    <td>{money(a.rewardAmount)}</td>
                    <td>{a.creditedAt ? when(a.creditedAt) : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {awards.length === 0 && <p>Nothing has been awarded yet.</p>}
        </Modal>
      )}
    </AdminFrame>
  );
}
