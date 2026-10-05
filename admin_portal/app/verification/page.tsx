'use client';

import { RefreshCw } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';

import { AdminFrame } from '../components/admin-frame';
import { ErrorBox } from '../components/ui';
import { apiFetch } from '../lib/admin-api';
import { useCatalogAreas } from './area-select';
import { CityRidesWorkspace } from './city-rides-workspace';
import { HubQueue, type HubTab } from './hub-queue';
import styles from './verification.module.css';

type TabKey = 'city' | HubTab;

type Summary = {
  city: number;
  tour: number;
  rent: number;
  hotels: number;
  businesses: number;
};

const TABS: { key: TabKey; label: string }[] = [
  { key: 'city', label: 'City rides' },
  { key: 'tour', label: 'Tour vehicles' },
  { key: 'rent', label: 'Rent-a-car' },
  { key: 'hotels', label: 'Hotels' },
  { key: 'businesses', label: 'Businesses' },
];

const selectStyle = {
  height: 40,
  border: '1px solid #dde9e4',
  borderRadius: 12,
  background: '#fff',
  padding: '0 12px',
  color: '#31564a',
} as const;

export default function VerificationHubPage() {
  const { districts, error: areasError } = useCatalogAreas();
  const [districtId, setDistrictId] = useState('');
  const [tehsilId, setTehsilId] = useState('');
  const [tab, setTab] = useState<TabKey>('city');
  const [summary, setSummary] = useState<Summary | null>(null);
  const [summaryError, setSummaryError] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);

  // A tehsil is the narrowest filter; a district (or "none") is next; empty is everything.
  const area = tehsilId || districtId;
  const district = districts.find((item) => item.id === districtId) ?? null;

  const loadSummary = useCallback(async () => {
    setSummaryError('');
    try {
      setSummary(
        await apiFetch<Summary>(
          `/api/v1/admin/verify/summary${area ? `?area=${encodeURIComponent(area)}` : ''}`,
        ),
      );
    } catch (value) {
      setSummaryError(value instanceof Error ? value.message : 'Waiting counts could not be loaded.');
    }
  }, [area]);

  useEffect(() => {
    void loadSummary();
  }, [loadSummary]);

  const refresh = useCallback(() => {
    setRefreshKey((value) => value + 1);
    void loadSummary();
  }, [loadSummary]);

  const reloadSummary = useCallback(() => {
    void loadSummary();
  }, [loadSummary]);

  return (
    <AdminFrame
      title="Verification"
      subtitle="Everything that needs approval, in one place."
      actions={
        <button className="secondaryButton" onClick={refresh}>
          <RefreshCw size={17} />
          Refresh
        </button>
      }
    >
      {(areasError || summaryError) && <ErrorBox message={areasError || summaryError} />}

      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: 12,
          alignItems: 'center',
          justifyContent: 'space-between',
          marginBottom: 16,
        }}
      >
        <div role="tablist" className={styles.tabs} style={{ flexWrap: 'wrap' }}>
          {TABS.map((item) => (
            <button
              key={item.key}
              role="tab"
              aria-selected={tab === item.key}
              className={tab === item.key ? styles.activeTab : ''}
              onClick={() => setTab(item.key)}
            >
              {item.label}
              <span>{summary ? summary[item.key] : '·'}</span>
            </button>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
          <select
            aria-label="District"
            style={selectStyle}
            value={districtId}
            onChange={(event) => {
              setDistrictId(event.target.value);
              setTehsilId('');
            }}
          >
            <option value="">All areas</option>
            {districts.map((item) => (
              <option key={item.id} value={item.id}>
                {item.name}
              </option>
            ))}
            <option value="none">Unassigned</option>
          </select>
          <select
            aria-label="Tehsil"
            style={selectStyle}
            value={tehsilId}
            disabled={!district}
            onChange={(event) => setTehsilId(event.target.value)}
          >
            <option value="">All tehsils</option>
            {(district?.tehsils ?? []).map((item) => (
              <option key={item.id} value={item.id}>
                {item.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      {tab === 'city' ? (
        <CityRidesWorkspace key={`city-${refreshKey}`} area={area} />
      ) : (
        <HubQueue
          key={`${tab}-${refreshKey}`}
          tab={tab}
          area={area}
          districts={districts}
          onChanged={reloadSummary}
        />
      )}
    </AdminFrame>
  );
}
