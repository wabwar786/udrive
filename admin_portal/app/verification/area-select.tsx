'use client';

import { CheckCircle2 } from 'lucide-react';
import { useEffect, useState } from 'react';

import { ErrorBox, Field, Modal } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

export type CatalogTehsil = {
  id: string;
  name: string;
  latitude: number | null;
  longitude: number | null;
  isActive: boolean;
};

export type CatalogDistrict = {
  id: string;
  name: string;
  isActive: boolean;
  tehsils: CatalogTehsil[];
};

/** The public district → tehsil list, loaded once per component. */
export function useCatalogAreas() {
  const [districts, setDistricts] = useState<CatalogDistrict[]>([]);
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    apiFetch<CatalogDistrict[]>('/api/v1/catalog/areas')
      .then((rows) => {
        if (active) setDistricts(rows ?? []);
      })
      .catch((loadError: unknown) => {
        if (active) {
          setError(
            loadError instanceof Error
              ? loadError.message
              : 'Areas could not be loaded.',
          );
        }
      });
    return () => {
      active = false;
    };
  }, []);

  return { districts, error };
}

/** "District · Tehsil", or "Unassigned" when the record has no area yet. */
export function areaLabel(
  districtName?: string | null,
  tehsilName?: string | null,
) {
  if (!districtName && !tehsilName) return 'Unassigned';
  return [districtName, tehsilName].filter(Boolean).join(' · ');
}

/** A tehsil select grouped by district. */
export function TehsilSelect({
  districts,
  value,
  onChange,
  emptyLabel = 'Choose a tehsil',
  disabled,
}: {
  districts: CatalogDistrict[];
  value: string;
  onChange: (tehsilId: string) => void;
  emptyLabel?: string;
  disabled?: boolean;
}) {
  return (
    <select
      value={value}
      disabled={disabled}
      onChange={(event) => onChange(event.target.value)}
    >
      <option value="">{emptyLabel}</option>
      {districts.map((district) => (
        <optgroup key={district.id} label={district.name}>
          {district.tehsils.map((tehsil) => (
            <option key={tehsil.id} value={tehsil.id}>
              {tehsil.name}
            </option>
          ))}
        </optgroup>
      ))}
    </select>
  );
}

/**
 * Small modal that moves one record to another tehsil.
 *
 * `path` is the full PUT endpoint; the body is always `{ tehsilId }`.
 */
export function LocationModal({
  title,
  path,
  currentTehsilId,
  onClose,
  onSaved,
}: {
  title: string;
  path: string;
  currentTehsilId?: string | null;
  onClose: () => void;
  onSaved: () => Promise<void> | void;
}) {
  const { districts, error: areasError } = useCatalogAreas();
  const [tehsilId, setTehsilId] = useState(currentTehsilId ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  async function save() {
    if (!tehsilId) {
      setError('Choose a tehsil.');
      return;
    }
    setSaving(true);
    setError('');
    try {
      await apiFetch(path, {
        method: 'PUT',
        body: JSON.stringify({ tehsilId }),
      });
      await onSaved();
      onClose();
    } catch (saveError) {
      setError(
        saveError instanceof Error
          ? saveError.message
          : 'The area could not be saved.',
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal title={title} onClose={() => !saving && onClose()}>
      {(error || areasError) && <ErrorBox message={error || areasError} />}
      <div className="formGrid" style={{ gridTemplateColumns: '1fr' }}>
        <Field label="Tehsil">
          <TehsilSelect
            districts={districts}
            value={tehsilId}
            onChange={setTehsilId}
          />
        </Field>
      </div>
      <div className="buttonRow">
        <button
          type="button"
          className="secondaryButton"
          onClick={onClose}
          disabled={saving}
        >
          Cancel
        </button>
        <button
          type="button"
          className="primaryButton"
          disabled={saving || !tehsilId}
          onClick={() => void save()}
        >
          <CheckCircle2 size={16} /> Save
        </button>
      </div>
    </Modal>
  );
}
