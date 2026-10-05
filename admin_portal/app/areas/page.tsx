'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { MapPin, Pencil, Plus, RefreshCw, Save } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { apiAction, apiFetch } from '../lib/admin-api';
import { usePermissions } from '../lib/permissions';

type AdminTehsil = {
  id: string;
  name: string;
  latitude: number | null;
  longitude: number | null;
  isActive: boolean;
  vehicles: number;
  drivers: number;
};

type AdminDistrict = {
  id: string;
  name: string;
  isActive: boolean;
  vehicles: number;
  drivers: number;
  tehsils: AdminTehsil[];
};

type Editor =
  | { kind: 'district' }
  | { kind: 'tehsil' }
  | { kind: 'edit'; id: string; isTehsil: boolean };

type AreaForm = {
  districtId: string;
  name: string;
  latitude: string;
  longitude: string;
  isActive: boolean;
};

const EMPTY_FORM: AreaForm = {
  districtId: '',
  name: '',
  latitude: '',
  longitude: '',
  isActive: true,
};

/** A named place outside the districts, offered for a departure's From / To. */
type AdminPlace = {
  id: string;
  name: string;
  region: string;
  latitude: number | null;
  longitude: number | null;
  isActive: boolean;
};

type PlaceForm = {
  name: string;
  region: string;
  latitude: string;
  longitude: string;
  isActive: boolean;
};

const EMPTY_PLACE: PlaceForm = {
  name: '',
  region: '',
  latitude: '',
  longitude: '',
  isActive: true,
};

const subtext = { display: 'block', color: '#6d7e77', marginTop: 3 } as const;

function pinText(latitude: number | null, longitude: number | null) {
  if (latitude === null || longitude === null) return 'No pin';
  return `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`;
}

/** Same rule as the tehsil form: both numbers, or both empty. */
function readPinValues(
  latText: string,
  lngText: string,
): { latitude: number | null; longitude: number | null } | string {
  const lat = latText.trim();
  const lng = lngText.trim();
  if (!lat && !lng) return { latitude: null, longitude: null };
  if (!lat || !lng) return 'Enter both latitude and longitude, or leave both empty.';
  const latitude = Number(lat);
  const longitude = Number(lng);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) return 'Latitude must be between -90 and 90.';
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) return 'Longitude must be between -180 and 180.';
  return { latitude, longitude };
}

export default function AreasPage() {
  const [districts, setDistricts] = useState<AdminDistrict[]>([]);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const [editor, setEditor] = useState<Editor | null>(null);
  const [form, setForm] = useState<AreaForm>(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState('');

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setDistricts(await apiFetch<AdminDistrict[]>('/api/v1/admin/areas'));
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Areas could not be loaded.');
    } finally {
      setBusy(false);
    }
  }, []);

  const { can } = usePermissions();
  const canEditPlaces = can('settings', 'edit');

  const [places, setPlaces] = useState<AdminPlace[]>([]);
  const [placesBusy, setPlacesBusy] = useState(true);
  const [placesError, setPlacesError] = useState('');
  const [placesSuccess, setPlacesSuccess] = useState('');
  /** null = closed, '' = adding, otherwise the id being edited. */
  const [placeEditing, setPlaceEditing] = useState<string | null>(null);
  const [placeForm, setPlaceForm] = useState<PlaceForm>(EMPTY_PLACE);
  const [placeSaving, setPlaceSaving] = useState(false);
  const [placeFormError, setPlaceFormError] = useState('');

  const loadPlaces = useCallback(async () => {
    setPlacesBusy(true);
    setPlacesError('');
    try {
      setPlaces(await apiFetch<AdminPlace[]>('/api/v1/admin/areas/places'));
    } catch (value) {
      setPlacesError(value instanceof Error ? value.message : 'Places could not be loaded.');
    } finally {
      setPlacesBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    void loadPlaces();
  }, [loadPlaces]);

  function setPlaceField<K extends keyof PlaceForm>(key: K, value: PlaceForm[K]) {
    setPlaceForm((current) => ({ ...current, [key]: value }));
  }

  function openAddPlace() {
    setPlaceForm(EMPTY_PLACE);
    setPlaceFormError('');
    setPlaceEditing('');
  }

  function openEditPlace(place: AdminPlace) {
    setPlaceForm({
      name: place.name,
      region: place.region,
      latitude: place.latitude === null ? '' : String(place.latitude),
      longitude: place.longitude === null ? '' : String(place.longitude),
      isActive: place.isActive,
    });
    setPlaceFormError('');
    setPlaceEditing(place.id);
  }

  async function savePlace() {
    if (placeEditing === null) return;
    setPlaceFormError('');
    const name = placeForm.name.trim();
    if (!name) {
      setPlaceFormError('Enter a name.');
      return;
    }
    const pin = readPinValues(placeForm.latitude, placeForm.longitude);
    if (typeof pin === 'string') {
      setPlaceFormError(pin);
      return;
    }

    const adding = placeEditing === '';
    const path = adding
      ? '/api/v1/admin/areas/places'
      : `/api/v1/admin/areas/places/${encodeURIComponent(placeEditing)}`;
    const body = { name, region: placeForm.region.trim(), ...pin, isActive: placeForm.isActive };

    setPlaceSaving(true);
    try {
      const result = await apiAction<AdminPlace>(path, {
        method: adding ? 'POST' : 'PUT',
        body: JSON.stringify(body),
      });
      setPlaceEditing(null);
      setPlacesSuccess(result.message || (adding ? `Place ${name} added.` : `${name} saved.`));
      await loadPlaces();
    } catch (value) {
      setPlaceFormError(value instanceof Error ? value.message : 'The place could not be saved.');
    } finally {
      setPlaceSaving(false);
    }
  }

  const totals = useMemo(
    () => ({
      districts: districts.length,
      tehsils: districts.reduce((sum, item) => sum + item.tehsils.length, 0),
      noPin: districts.reduce(
        (sum, item) =>
          sum + item.tehsils.filter((tehsil) => tehsil.latitude === null || tehsil.longitude === null).length,
        0,
      ),
      vehicles: districts.reduce((sum, item) => sum + item.vehicles, 0),
    }),
    [districts],
  );

  function setField<K extends keyof AreaForm>(key: K, value: AreaForm[K]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function openDistrict() {
    setForm(EMPTY_FORM);
    setFormError('');
    setEditor({ kind: 'district' });
  }

  function openTehsil(districtId = '') {
    setForm({ ...EMPTY_FORM, districtId: districtId || districts[0]?.id || '' });
    setFormError('');
    setEditor({ kind: 'tehsil' });
  }

  function openEditDistrict(district: AdminDistrict) {
    setForm({ ...EMPTY_FORM, name: district.name, isActive: district.isActive });
    setFormError('');
    setEditor({ kind: 'edit', id: district.id, isTehsil: false });
  }

  function openEditTehsil(tehsil: AdminTehsil) {
    setForm({
      ...EMPTY_FORM,
      name: tehsil.name,
      latitude: tehsil.latitude === null ? '' : String(tehsil.latitude),
      longitude: tehsil.longitude === null ? '' : String(tehsil.longitude),
      isActive: tehsil.isActive,
    });
    setFormError('');
    setEditor({ kind: 'edit', id: tehsil.id, isTehsil: true });
  }

  /** Both numbers, or both empty. Returns null pin values when empty. */
  function readPin(): { latitude: number | null; longitude: number | null } | string {
    const lat = form.latitude.trim();
    const lng = form.longitude.trim();
    if (!lat && !lng) return { latitude: null, longitude: null };
    if (!lat || !lng) return 'Enter both latitude and longitude, or leave both empty.';
    const latitude = Number(lat);
    const longitude = Number(lng);
    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) return 'Latitude must be between -90 and 90.';
    if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) return 'Longitude must be between -180 and 180.';
    return { latitude, longitude };
  }

  async function save() {
    if (!editor) return;
    setFormError('');
    const name = form.name.trim();
    if (!name) {
      setFormError('Enter a name.');
      return;
    }

    const withPin = editor.kind === 'tehsil' || (editor.kind === 'edit' && editor.isTehsil);
    const pin = withPin ? readPin() : { latitude: null, longitude: null };
    if (typeof pin === 'string') {
      setFormError(pin);
      return;
    }

    let path = '';
    let method = 'POST';
    let body: Record<string, unknown> = {};
    if (editor.kind === 'district') {
      path = '/api/v1/admin/areas/districts';
      body = { name, isActive: form.isActive };
    } else if (editor.kind === 'tehsil') {
      if (!form.districtId) {
        setFormError('Choose a district.');
        return;
      }
      path = '/api/v1/admin/areas/tehsils';
      body = { districtId: form.districtId, name, ...pin, isActive: form.isActive };
    } else {
      path = `/api/v1/admin/areas/${editor.id}`;
      method = 'PUT';
      body = { name, ...pin, isActive: form.isActive };
    }

    setSaving(true);
    try {
      await apiFetch(path, { method, body: JSON.stringify(body) });
      setEditor(null);
      setSuccess(
        editor.kind === 'district'
          ? `District ${name} added.`
          : editor.kind === 'tehsil'
            ? `Tehsil ${name} added.`
            : `${name} saved.`,
      );
      await load();
    } catch (value) {
      setFormError(value instanceof Error ? value.message : 'The area could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  const editorTitle = !editor
    ? ''
    : editor.kind === 'district'
      ? 'Add district'
      : editor.kind === 'tehsil'
        ? 'Add tehsil'
        : editor.isTehsil
          ? 'Edit tehsil'
          : 'Edit district';

  const showPin = editor?.kind === 'tehsil' || (editor?.kind === 'edit' && editor.isTehsil);

  return (
    <AdminFrame
      title="Areas"
      subtitle="Districts and tehsils used everywhere: vehicle base, hotels, businesses and team access. Each tehsil has a centre pin so a GPS location can be matched to it."
      actions={
        <>
          <button
            className="secondaryButton"
            onClick={() => {
              void load();
              void loadPlaces();
            }}
            disabled={busy}
          >
            <RefreshCw className={busy ? 'spin' : ''} /> Refresh
          </button>
          <button className="secondaryButton" onClick={openDistrict}>
            <Plus /> Add district
          </button>
          <button className="primaryButton" onClick={() => openTehsil()} disabled={districts.length === 0}>
            <Plus /> Add tehsil
          </button>
        </>
      }
    >
      {error && <ErrorBox message={error} />}
      {success && <div className="successBox" style={{ margin: '0 0 14px' }}>{success}</div>}

      <section className="statGrid">
        <Stat label="Districts" value={totals.districts} tone="emerald" />
        <Stat label="Tehsils" value={totals.tehsils} tone="blue" />
        <Stat label="Tehsils without a pin" value={totals.noPin} tone="amber" />
        <Stat label="Vehicles placed" value={totals.vehicles} tone="violet" />
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Districts and tehsils</h2>
            <p>A GPS location is matched to the nearest tehsil centre pin within 80 km.</p>
          </div>
        </header>

        {busy ? (
          <Loading />
        ) : districts.length === 0 ? (
          <Empty title="No districts yet" copy="Add a district, then add its tehsils with a centre pin." />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Centre pin</th>
                  <th>Vehicles</th>
                  <th>Drivers</th>
                  <th>Status</th>
                  <th aria-label="Actions" />
                </tr>
              </thead>
              <tbody>
                {districts.map((district) => (
                  <DistrictRows
                    key={district.id}
                    district={district}
                    onEditDistrict={() => openEditDistrict(district)}
                    onAddTehsil={() => openTehsil(district.id)}
                    onEditTehsil={openEditTehsil}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Other places (outside AJK)</h2>
            <p>Names drivers can pick for a departure&apos;s From / To, e.g. Rawalpindi, Islamabad.</p>
          </div>
          {canEditPlaces && (
            <button type="button" className="primaryButton" onClick={openAddPlace}>
              <Plus /> Add place
            </button>
          )}
        </header>

        {placesError && <ErrorBox message={placesError} />}
        {placesSuccess && <div className="successBox" style={{ margin: '0 0 14px' }}>{placesSuccess}</div>}

        {placesBusy ? (
          <Loading />
        ) : places.length === 0 ? (
          <Empty title="No other places yet" copy="Add a city outside the districts, such as Rawalpindi or Islamabad." />
        ) : (
          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Region</th>
                  <th>Centre pin</th>
                  <th>Status</th>
                  {canEditPlaces && <th aria-label="Actions" />}
                </tr>
              </thead>
              <tbody>
                {places.map((place) => (
                  <tr key={place.id}>
                    <td>
                      <strong>{place.name}</strong>
                    </td>
                    <td>{place.region || '—'}</td>
                    <td>
                      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
                        <MapPin size={14} color={place.latitude === null ? '#a35a00' : '#087650'} />
                        {pinText(place.latitude, place.longitude)}
                      </span>
                    </td>
                    <td>
                      <Badge value={place.isActive ? 'Active' : 'Inactive'} />
                    </td>
                    {canEditPlaces && (
                      <td>
                        <button type="button" className="secondaryButton" onClick={() => openEditPlace(place)}>
                          <Pencil size={14} /> Edit
                        </button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {placeEditing !== null && (
        <Modal
          title={placeEditing === '' ? 'Add place' : 'Edit place'}
          onClose={() => !placeSaving && setPlaceEditing(null)}
        >
          {placeFormError && <ErrorBox message={placeFormError} />}
          <div className="formGrid">
            <Field label="Name *">
              <input
                value={placeForm.name}
                onChange={(event) => setPlaceField('name', event.target.value)}
                placeholder="Rawalpindi"
                autoFocus
              />
            </Field>
            <Field label="Region">
              <input
                value={placeForm.region}
                onChange={(event) => setPlaceField('region', event.target.value)}
                placeholder="Punjab"
              />
            </Field>
            <Field label="Centre latitude">
              <input
                inputMode="decimal"
                value={placeForm.latitude}
                onChange={(event) => setPlaceField('latitude', event.target.value)}
                placeholder="33.6"
              />
            </Field>
            <Field label="Centre longitude">
              <input
                inputMode="decimal"
                value={placeForm.longitude}
                onChange={(event) => setPlaceField('longitude', event.target.value)}
                placeholder="73.05"
              />
            </Field>
            <div>
              <label className="check">
                <input
                  type="checkbox"
                  checked={placeForm.isActive}
                  onChange={(event) => setPlaceField('isActive', event.target.checked)}
                />{' '}
                Active
              </label>
            </div>
          </div>
          <div className="buttonRow">
            <button
              type="button"
              className="secondaryButton"
              onClick={() => setPlaceEditing(null)}
              disabled={placeSaving}
            >
              Cancel
            </button>
            <button type="button" className="primaryButton" disabled={placeSaving} onClick={() => void savePlace()}>
              {placeSaving ? <RefreshCw className="spin" /> : <Save />} Save
            </button>
          </div>
        </Modal>
      )}

      {editor && (
        <Modal title={editorTitle} onClose={() => !saving && setEditor(null)}>
          {formError && <ErrorBox message={formError} />}
          <div className="formGrid">
            {editor.kind === 'tehsil' && (
              <Field label="District *">
                <select value={form.districtId} onChange={(event) => setField('districtId', event.target.value)}>
                  <option value="">Choose a district</option>
                  {districts.map((district) => (
                    <option key={district.id} value={district.id}>
                      {district.name}
                    </option>
                  ))}
                </select>
              </Field>
            )}
            <Field label="Name *">
              <input value={form.name} onChange={(event) => setField('name', event.target.value)} autoFocus />
            </Field>
            {showPin && (
              <>
                <Field label="Centre latitude">
                  <input
                    inputMode="decimal"
                    value={form.latitude}
                    onChange={(event) => setField('latitude', event.target.value)}
                    placeholder="34.37"
                  />
                </Field>
                <Field label="Centre longitude">
                  <input
                    inputMode="decimal"
                    value={form.longitude}
                    onChange={(event) => setField('longitude', event.target.value)}
                    placeholder="73.47"
                  />
                </Field>
              </>
            )}
            <div>
              <label className="check">
                <input
                  type="checkbox"
                  checked={form.isActive}
                  onChange={(event) => setField('isActive', event.target.checked)}
                />{' '}
                Active
              </label>
            </div>
          </div>
          <div className="buttonRow">
            <button type="button" className="secondaryButton" onClick={() => setEditor(null)} disabled={saving}>
              Cancel
            </button>
            <button type="button" className="primaryButton" disabled={saving} onClick={() => void save()}>
              {saving ? <RefreshCw className="spin" /> : <Save />} Save
            </button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}

function DistrictRows({
  district,
  onEditDistrict,
  onAddTehsil,
  onEditTehsil,
}: {
  district: AdminDistrict;
  onEditDistrict: () => void;
  onAddTehsil: () => void;
  onEditTehsil: (tehsil: AdminTehsil) => void;
}) {
  return (
    <>
      <tr style={{ background: '#f8fbfa' }}>
        <td>
          <strong>{district.name}</strong>
          <small style={subtext}>
            District · {district.tehsils.length} {district.tehsils.length === 1 ? 'tehsil' : 'tehsils'}
          </small>
        </td>
        <td>—</td>
        <td>{district.vehicles}</td>
        <td>{district.drivers}</td>
        <td>
          <Badge value={district.isActive ? 'Active' : 'Inactive'} />
        </td>
        <td>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            <button type="button" className="secondaryButton" onClick={onEditDistrict}>
              <Pencil size={14} /> Edit
            </button>
            <button type="button" className="secondaryButton" onClick={onAddTehsil}>
              <Plus size={14} /> Tehsil
            </button>
          </div>
        </td>
      </tr>
      {district.tehsils.map((tehsil) => (
        <tr key={tehsil.id}>
          <td style={{ paddingLeft: 36 }}>
            {tehsil.name}
            <small style={subtext}>Tehsil</small>
          </td>
          <td>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
              <MapPin size={14} color={tehsil.latitude === null ? '#a35a00' : '#087650'} />
              {pinText(tehsil.latitude, tehsil.longitude)}
            </span>
          </td>
          <td>{tehsil.vehicles}</td>
          <td>{tehsil.drivers}</td>
          <td>
            <Badge value={tehsil.isActive ? 'Active' : 'Inactive'} />
          </td>
          <td>
            <button type="button" className="secondaryButton" onClick={() => onEditTehsil(tehsil)}>
              <Pencil size={14} /> Edit
            </button>
          </td>
        </tr>
      ))}
    </>
  );
}
