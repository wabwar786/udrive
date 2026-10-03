'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { MapPin, Plus, Save, Trash2 } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { apiFetch, money, when } from '../lib/admin-api';

type Node = {
  id: string;
  parentId?: string | null;
  kind: string;
  name: string;
  launchCityId?: string | null;
  launchStatus?: string | null;
  isActive: boolean;
  depth: number;
  path: string;
  partnerId?: string | null;
  partnerName?: string | null;
  partnerStatus?: string | null;
  tierKey?: string | null;
  driverCount: number;
  waitingCount: number;
  pendingApplications: number;
};

type Tier = {
  tierKey: string;
  displayName: string;
  territoryKind: string;
  securityDeposit: number;
  commissionSharePct: number;
  termMonths: number;
  description?: string | null;
  isActive: boolean;
  commitments: {
    id: string;
    metricKey: string;
    targetValue: number;
    label: string;
    isActive: boolean;
  }[];
};

type City = { id: string; name: string; isActive: boolean; launchStatus: string };

type Area = {
  id: string;
  launchCityId: string;
  label?: string | null;
  latitude: number;
  longitude: number;
  radiusKm: number;
};

type Waiting = {
  id: string;
  cityId: string;
  cityName: string;
  fullName?: string | null;
  phoneNumber?: string | null;
  createdAt: string;
};

const EMPTY_NODE = {
  parentId: '' as string,
  kind: 'Tehsil',
  name: '',
  launchCityId: '' as string,
  isActive: true,
  notes: '',
};

/**
 * Territories, the circles that put a customer in a city, and the tier terms.
 *
 * Three separate jobs on one screen because they are one job in practice: you
 * cannot sell a City Head position in Rawalakot until Rawalakot exists as a
 * territory, has a circle on the map so the app knows who is standing in it, and
 * has terms to offer.
 *
 * **The circles are what make the coming-soon screen possible.** Before them the
 * app had no idea which city it was in: somebody in Rawalakot saw the same home
 * screen as somebody in Muzaffarabad and could try to book a car where there are
 * none. A city is a set of circles rather than one point because a town plus its
 * outskirts is three circles and one polygon nobody will draw in a form.
 *
 * **The waiting list is the argument.** People who register in a closed city are
 * counted here, and "286 people waiting in Rawalakot" is the strongest thing you
 * can say to somebody deciding whether to be its City Head — and the clearest
 * signal of which city to open next.
 */
export default function Page() {
  const [nodes, setNodes] = useState<Node[]>([]);
  const [tiers, setTiers] = useState<Tier[]>([]);
  const [cities, setCities] = useState<City[]>([]);
  const [areas, setAreas] = useState<Area[]>([]);
  const [waiting, setWaiting] = useState<Waiting[]>([]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');

  const [editingNode, setEditingNode] = useState<Node | null>(null);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({ ...EMPTY_NODE });

  const [addingArea, setAddingArea] = useState(false);
  const [areaForm, setAreaForm] = useState({
    launchCityId: '',
    label: '',
    latitude: '',
    longitude: '',
    radiusKm: '12',
  });

  const [editingTier, setEditingTier] = useState<Tier | null>(null);
  const [tierForm, setTierForm] = useState({
    displayName: '',
    securityDeposit: 0,
    commissionSharePct: 0,
    termMonths: 24,
    description: '',
    isActive: true,
  });

  const load = useCallback(async () => {
    const [tree, tierList, cityList, areaList, waitList] = await Promise.all([
      apiFetch<Node[]>('/api/v1/admin/partners/territories'),
      apiFetch<Tier[]>('/api/v1/admin/partners/tiers'),
      apiFetch<City[]>('/api/v1/admin/growth/cities'),
      apiFetch<Area[]>('/api/v1/admin/partners/city-areas'),
      apiFetch<Waiting[]>('/api/v1/admin/partners/waitlist'),
    ]);
    setNodes(tree);
    setTiers(tierList);
    setCities(cityList);
    setAreas(areaList);
    setWaiting(waitList);
  }, []);

  useEffect(() => {
    setLoading(true);
    setError('');
    void load()
      .catch((e) =>
        setError(e instanceof Error ? e.message : 'This section is unavailable.'),
      )
      .finally(() => setLoading(false));
  }, [load]);

  const act = async (run: () => Promise<unknown>, message: string) => {
    setBusy(true);
    setError('');
    setNote('');
    try {
      await run();
      setNote(message);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be saved.');
    } finally {
      setBusy(false);
    }
  };

  const stats = useMemo(
    () => ({
      areas: nodes.length,
      held: nodes.filter((n) => n.partnerId).length,
      free: nodes.filter((n) => !n.partnerId && n.isActive).length,
      waiting: waiting.length,
    }),
    [nodes, waiting],
  );

  const cityName = (id: string) => cities.find((c) => c.id === id)?.name ?? '—';

  const openNode = (node: Node | null) => {
    setEditingNode(node);
    setCreating(node === null);
    setForm(
      node
        ? {
            parentId: node.parentId ?? '',
            kind: node.kind,
            name: node.name,
            launchCityId: node.launchCityId ?? '',
            isActive: node.isActive,
            notes: '',
          }
        : { ...EMPTY_NODE },
    );
  };

  const saveNode = async () => {
    const body = JSON.stringify({
      parentId: form.parentId || null,
      kind: form.kind,
      name: form.name,
      launchCityId: form.kind === 'City' ? form.launchCityId || null : null,
      isActive: form.isActive,
      notes: form.notes || null,
    });

    await act(async () => {
      if (creating) {
        await apiFetch('/api/v1/admin/partners/territories', {
          method: 'POST',
          body,
        });
      } else if (editingNode) {
        await apiFetch(`/api/v1/admin/partners/territories/${editingNode.id}`, {
          method: 'PUT',
          body,
        });
      }
      setEditingNode(null);
      setCreating(false);
    }, 'Saved.');
  };

  return (
    <AdminFrame
      title="Territories & areas"
      subtitle="The tree a partner is appointed over, the map circles that place a customer in a city, and the tier terms."
      actions={
        <button className="primaryButton" onClick={() => openNode(null)}>
          <Plus /> Add an area
        </button>
      }
    >
      {error && <ErrorBox message={error} />}
      {note && (
        <div className="successBox">
          <strong>{note}</strong>
        </div>
      )}

      {loading ? (
        <Loading />
      ) : (
        <>
          <div className="statGrid">
            <Stat label="Areas" value={stats.areas} tone="blue" />
            <Stat label="Held by a partner" value={stats.held} tone="emerald" />
            <Stat label="Open" value={stats.free} sub="Nobody appointed" tone="amber" />
            <Stat
              label="People waiting"
              value={stats.waiting}
              sub="In cities not yet live"
              tone="violet"
            />
          </div>

          {/* ─────────────────────────────────────────── the tree */}

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>The tree</h2>
                <p>Region → City → Tehsil. One partner per area.</p>
              </div>
            </header>

            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Area</th>
                    <th>City status</th>
                    <th>Partner</th>
                    <th>Drivers</th>
                    <th>Waiting</th>
                    <th>Requests</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {nodes.map((node) => (
                    <tr key={node.id}>
                      <td>
                        <strong style={{ paddingLeft: node.depth * 18 }}>
                          {node.depth > 0 && '└ '}
                          {node.name}
                        </strong>
                        <small style={{ paddingLeft: node.depth * 18 }}>
                          {node.kind}
                          {!node.isActive && ' · switched off'}
                        </small>
                      </td>
                      <td>
                        {node.launchCityId ? (
                          <Badge value={node.launchStatus ?? '—'} />
                        ) : (
                          <span>—</span>
                        )}
                      </td>
                      <td>
                        {node.partnerName ? (
                          <>
                            <strong>{node.partnerName}</strong>
                            <small>
                              {node.tierKey} · {node.partnerStatus}
                            </small>
                          </>
                        ) : (
                          <span style={{ color: '#087650', fontWeight: 700 }}>open</span>
                        )}
                      </td>
                      <td>{node.driverCount}</td>
                      <td>{node.waitingCount || '—'}</td>
                      <td>{node.pendingApplications || '—'}</td>
                      <td>
                        <button
                          className="secondaryButton"
                          disabled={busy}
                          onClick={() => openNode(node)}
                        >
                          Edit
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          {/* ───────────────────────────── the circles on the map */}

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Where each city is</h2>
                <p>
                  A centre and a radius, as many as a city needs. Without at least one
                  circle, the app cannot tell which city a customer is in and shows
                  them the full city list to choose from instead.
                </p>
              </div>
              <button
                className="primaryButton"
                onClick={() => {
                  setAreaForm({
                    launchCityId: cities[0]?.id ?? '',
                    label: '',
                    latitude: '',
                    longitude: '',
                    radiusKm: '12',
                  });
                  setAddingArea(true);
                }}
              >
                <MapPin /> Add a circle
              </button>
            </header>

            {areas.length === 0 ? (
              <Empty
                title="No circles yet"
                copy="Until a city has one, nobody is placed in it automatically."
              />
            ) : (
              <div className="tableWrap">
                <table>
                  <thead>
                    <tr>
                      <th>City</th>
                      <th>Label</th>
                      <th>Centre</th>
                      <th>Radius</th>
                      <th />
                    </tr>
                  </thead>
                  <tbody>
                    {areas.map((area) => (
                      <tr key={area.id}>
                        <td>
                          <strong>{cityName(area.launchCityId)}</strong>
                        </td>
                        <td>{area.label ?? '—'}</td>
                        <td>
                          {area.latitude.toFixed(4)}, {area.longitude.toFixed(4)}
                        </td>
                        <td>{area.radiusKm} km</td>
                        <td>
                          <button
                            className="dangerButton"
                            disabled={busy}
                            onClick={() =>
                              void act(
                                () =>
                                  apiFetch(
                                    `/api/v1/admin/partners/city-areas/${area.id}`,
                                    { method: 'DELETE' },
                                  ),
                                'Circle removed.',
                              )
                            }
                          >
                            <Trash2 /> Remove
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          {/* ─────────────────────────────────── the waiting list */}

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Waiting for us to open</h2>
                <p>
                  {waiting.length} registered in a city that is not live yet. This
                  number is the clearest signal of which city to open next.
                </p>
              </div>
            </header>

            {waiting.length === 0 ? (
              <Empty
                title="Nobody waiting"
                copy="People who register in a coming-soon city appear here."
              />
            ) : (
              <div className="tableWrap">
                <table>
                  <thead>
                    <tr>
                      <th>City</th>
                      <th>Who</th>
                      <th>Phone</th>
                      <th>Since</th>
                    </tr>
                  </thead>
                  <tbody>
                    {waiting.slice(0, 100).map((row) => (
                      <tr key={row.id}>
                        <td>
                          <strong>{row.cityName}</strong>
                        </td>
                        <td>{row.fullName ?? '—'}</td>
                        <td>{row.phoneNumber ?? '—'}</td>
                        <td>{when(row.createdAt)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          {/* ───────────────────────────────────────────── tiers */}

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Tier terms</h2>
                <p>
                  What a new contract starts from. Changing a figure here never
                  rewrites a contract somebody has already signed — those carry their
                  own copy.
                </p>
              </div>
            </header>

            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Tier</th>
                    <th>For</th>
                    <th>Security deposit</th>
                    <th>Share of commission</th>
                    <th>Term</th>
                    <th>Monthly commitments</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {tiers.map((tier) => (
                    <tr key={tier.tierKey}>
                      <td>
                        <strong>{tier.displayName}</strong>
                        <small>{tier.isActive ? 'open' : 'closed'}</small>
                      </td>
                      <td>{tier.territoryKind}</td>
                      <td>{money(tier.securityDeposit)}</td>
                      <td>{tier.commissionSharePct}%</td>
                      <td>{tier.termMonths} months</td>
                      <td>
                        {tier.commitments.length === 0 ? (
                          <span>—</span>
                        ) : (
                          tier.commitments.map((c) => (
                            <small key={c.id}>
                              {c.label}: <strong>{c.targetValue}</strong>
                            </small>
                          ))
                        )}
                      </td>
                      <td>
                        <button
                          className="secondaryButton"
                          disabled={busy}
                          onClick={() => {
                            setEditingTier(tier);
                            setTierForm({
                              displayName: tier.displayName,
                              securityDeposit: tier.securityDeposit,
                              commissionSharePct: tier.commissionSharePct,
                              termMonths: tier.termMonths,
                              description: tier.description ?? '',
                              isActive: tier.isActive,
                            });
                          }}
                        >
                          Edit
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div style={{ padding: '0 22px 20px' }}>
              <p style={{ color: '#71827b' }}>
                The shares <strong>add up</strong> where tiers overlap: a ride in a
                tehsil that has a Tehsil Head, inside a city with a City Head, inside a
                region with a Regional Head pays all three. Read the total before
                changing one of them.
              </p>
            </div>
          </section>
        </>
      )}

      {/* ───────────────────────────────────────────── modals */}

      {(editingNode || creating) && (
        <Modal
          title={creating ? 'Add an area' : `Edit ${editingNode?.name}`}
          onClose={() => {
            setEditingNode(null);
            setCreating(false);
          }}
        >
          <div className="formGrid">
            <Field label="Kind">
              <select
                value={form.kind}
                onChange={(e) => setForm({ ...form, kind: e.target.value })}
              >
                <option value="Region">Region</option>
                <option value="City">City</option>
                <option value="Tehsil">Tehsil</option>
              </select>
            </Field>
            <Field label="Name">
              <input
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                placeholder="Pattika"
              />
            </Field>
            <Field label="Sits inside">
              <select
                value={form.parentId}
                onChange={(e) => setForm({ ...form, parentId: e.target.value })}
              >
                <option value="">— nothing (a Region) —</option>
                {nodes
                  .filter((n) => n.id !== editingNode?.id && n.kind !== 'Tehsil')
                  .map((n) => (
                    <option key={n.id} value={n.id}>
                      {n.path}
                    </option>
                  ))}
              </select>
            </Field>
            {form.kind === 'City' && (
              <Field label="Launch city it stands for">
                <select
                  value={form.launchCityId}
                  onChange={(e) => setForm({ ...form, launchCityId: e.target.value })}
                >
                  <option value="">— none —</option>
                  {cities.map((city) => (
                    <option key={city.id} value={city.id}>
                      {city.name} ({city.launchStatus})
                    </option>
                  ))}
                </select>
              </Field>
            )}
            <Field label="Open for applications">
              <select
                value={form.isActive ? 'yes' : 'no'}
                onChange={(e) =>
                  setForm({ ...form, isActive: e.target.value === 'yes' })
                }
              >
                <option value="yes">Yes</option>
                <option value="no">No</option>
              </select>
            </Field>
          </div>

          <div style={{ margin: '0 22px 14px' }}>
            <p style={{ color: '#71827b' }}>
              A Tehsil has to sit inside a City. Only a City can stand for a launch
              city, and only one area can stand for each — that is what makes &ldquo;the
              City Head of Mirpur&rdquo; a single row.
            </p>
          </div>

          <div className="buttonRow">
            <button
              className="primaryButton"
              disabled={busy || !form.name.trim()}
              onClick={() => void saveNode()}
            >
              <Save /> Save
            </button>
            {!creating && editingNode && (
              <button
                className="dangerButton"
                disabled={busy}
                onClick={() =>
                  void act(async () => {
                    await apiFetch(
                      `/api/v1/admin/partners/territories/${editingNode.id}`,
                      { method: 'DELETE' },
                    );
                    setEditingNode(null);
                  }, 'Deleted.')
                }
              >
                <Trash2 /> Delete
              </button>
            )}
          </div>
        </Modal>
      )}

      {addingArea && (
        <Modal title="Add a circle" onClose={() => setAddingArea(false)}>
          <div className="formGrid">
            <Field label="City">
              <select
                value={areaForm.launchCityId}
                onChange={(e) =>
                  setAreaForm({ ...areaForm, launchCityId: e.target.value })
                }
              >
                {cities.map((city) => (
                  <option key={city.id} value={city.id}>
                    {city.name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Label (optional)">
              <input
                value={areaForm.label}
                onChange={(e) => setAreaForm({ ...areaForm, label: e.target.value })}
                placeholder="Town centre"
              />
            </Field>
            <Field label="Latitude">
              <input
                value={areaForm.latitude}
                onChange={(e) =>
                  setAreaForm({ ...areaForm, latitude: e.target.value })
                }
                placeholder="34.3700"
              />
            </Field>
            <Field label="Longitude">
              <input
                value={areaForm.longitude}
                onChange={(e) =>
                  setAreaForm({ ...areaForm, longitude: e.target.value })
                }
                placeholder="73.4711"
              />
            </Field>
            <Field label="Radius (km)">
              <input
                value={areaForm.radiusKm}
                onChange={(e) =>
                  setAreaForm({ ...areaForm, radiusKm: e.target.value })
                }
              />
            </Field>
          </div>

          <div style={{ margin: '0 22px 14px' }}>
            <p style={{ color: '#71827b' }}>
              The easiest way to get the numbers: open the place in Google Maps, right
              click the centre of town, and the first line of the menu is the latitude
              and longitude. Start generous — 12 km covers a town and its outskirts —
              and add a second circle rather than stretching one.
            </p>
          </div>

          <div className="buttonRow">
            <button
              className="primaryButton"
              disabled={
                busy ||
                !areaForm.launchCityId ||
                !areaForm.latitude ||
                !areaForm.longitude
              }
              onClick={() =>
                void act(async () => {
                  await apiFetch('/api/v1/admin/partners/city-areas', {
                    method: 'POST',
                    body: JSON.stringify({
                      launchCityId: areaForm.launchCityId,
                      label: areaForm.label || null,
                      latitude: Number(areaForm.latitude),
                      longitude: Number(areaForm.longitude),
                      radiusKm: Number(areaForm.radiusKm),
                    }),
                  });
                  setAddingArea(false);
                }, 'Circle added. The app will place customers inside it from now on.')
              }
            >
              <Save /> Add it
            </button>
            <button className="secondaryButton" onClick={() => setAddingArea(false)}>
              Cancel
            </button>
          </div>
        </Modal>
      )}

      {editingTier && (
        <Modal
          title={`${editingTier.displayName} terms`}
          onClose={() => setEditingTier(null)}
        >
          <div className="formGrid">
            <Field label="Name shown to applicants">
              <input
                value={tierForm.displayName}
                onChange={(e) =>
                  setTierForm({ ...tierForm, displayName: e.target.value })
                }
              />
            </Field>
            <Field label="Security deposit (PKR, refundable)">
              <input
                type="number"
                value={tierForm.securityDeposit}
                onChange={(e) =>
                  setTierForm({
                    ...tierForm,
                    securityDeposit: Number(e.target.value),
                  })
                }
              />
            </Field>
            <Field label="Share of UDrive's commission (%)">
              <input
                type="number"
                step="0.5"
                value={tierForm.commissionSharePct}
                onChange={(e) =>
                  setTierForm({
                    ...tierForm,
                    commissionSharePct: Number(e.target.value),
                  })
                }
              />
            </Field>
            <Field label="Term (months)">
              <input
                type="number"
                value={tierForm.termMonths}
                onChange={(e) =>
                  setTierForm({ ...tierForm, termMonths: Number(e.target.value) })
                }
              />
            </Field>
            <Field label="Open for applications">
              <select
                value={tierForm.isActive ? 'yes' : 'no'}
                onChange={(e) =>
                  setTierForm({ ...tierForm, isActive: e.target.value === 'yes' })
                }
              >
                <option value="yes">Yes</option>
                <option value="no">No</option>
              </select>
            </Field>
          </div>

          <Field label="What this tier is, in the applicant's words">
            <textarea
              rows={3}
              value={tierForm.description}
              onChange={(e) =>
                setTierForm({ ...tierForm, description: e.target.value })
              }
            />
          </Field>

          <div style={{ margin: '14px 22px' }}>
            <p style={{ color: '#71827b' }}>
              The share is a percentage of <strong>UDrive&apos;s commission</strong>,
              not of the fare. The fare belongs mostly to the driver; commission is
              what the business keeps. A percentage of the fare looks like a smaller
              number and is several times larger.
            </p>
          </div>

          <div className="buttonRow">
            <button
              className="primaryButton"
              disabled={busy}
              onClick={() =>
                void act(async () => {
                  await apiFetch(
                    `/api/v1/admin/partners/tiers/${editingTier.tierKey}`,
                    {
                      method: 'PUT',
                      body: JSON.stringify({
                        displayName: tierForm.displayName,
                        securityDeposit: tierForm.securityDeposit,
                        commissionSharePct: tierForm.commissionSharePct,
                        termMonths: tierForm.termMonths,
                        description: tierForm.description || null,
                        isActive: tierForm.isActive,
                        commitments: null,
                      }),
                    },
                  );
                  setEditingTier(null);
                }, 'Saved. New contracts start from these terms.')
              }
            >
              <Save /> Save
            </button>
            <button className="secondaryButton" onClick={() => setEditingTier(null)}>
              Cancel
            </button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
