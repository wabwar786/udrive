'use client';

import { RefreshCw } from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { AdminFrame } from '../components/admin-frame';
import { ErrorBox } from '../components/ui';
import { apiFetch } from '../lib/admin-api';
import { usePermissions, type ModuleKey } from '../lib/permissions';
import { limitDistricts, teamAreaLabel, useCatalogAreas } from './area-select';
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

const TABS: { key: TabKey; label: string; module: ModuleKey }[] = [
  { key: 'city', label: 'City rides', module: 'verification.city' },
  { key: 'tour', label: 'Tour vehicles', module: 'verification.tour' },
  { key: 'rent', label: 'Rent-a-car', module: 'verification.rent' },
  { key: 'hotels', label: 'Hotels', module: 'verification.hotels' },
  { key: 'businesses', label: 'Businesses', module: 'verification.businesses' },
];

const chipStyle = {
  background: '#dff6ec',
  color: '#087650',
  borderRadius: 999,
  padding: '6px 11px',
  fontWeight: 800,
  fontSize: 12,
} as const;

const selectStyle = {
  height: 40,
  border: '1px solid #dde9e4',
  borderRadius: 12,
  background: '#fff',
  padding: '0 12px',
  color: '#31564a',
} as const;

export default function VerificationHubPage() {
  const { districts: allDistricts, error: areasError } = useCatalogAreas();
  const { can, allAreas, areas } = usePermissions();
  const [districtId, setDistrictId] = useState('');
  const [tehsilId, setTehsilId] = useState('');
  const [tab, setTab] = useState<TabKey>('city');

  // A team user sees only the tabs and the areas they were given.
  const tabs = useMemo(() => TABS.filter((item) => can(item.module, 'view')), [can]);
  const activeTab: TabKey | null = tabs.some((item) => item.key === tab)
    ? tab
    : (tabs[0]?.key ?? null);
  const districts = useMemo(
    () => limitDistricts(allDistricts, areas, allAreas),
    [allDistricts, areas, allAreas],
  );
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

      {!allAreas && (
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            flexWrap: 'wrap',
            marginBottom: 12,
          }}
        >
          <span style={{ fontSize: 12, color: '#5d716a', fontWeight: 700 }}>Your areas</span>
          {areas.length === 0 ? (
            <span style={{ ...chipStyle, background: '#edf0ef', color: '#5d6b66' }}>
              No areas given yet
            </span>
          ) : (
            areas.map((item) => (
              <span key={item.id} style={chipStyle}>
                {teamAreaLabel(item)}
              </span>
            ))
          )}
        </div>
      )}

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
          {tabs.map((item) => (
            <button
              key={item.key}
              role="tab"
              aria-selected={activeTab === item.key}
              className={activeTab === item.key ? styles.activeTab : ''}
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
            <option value="">{allAreas ? 'All areas' : 'All my areas'}</option>
            {districts.map((item) => (
              <option key={item.id} value={item.id}>
                {item.name}
              </option>
            ))}
            {allAreas && <option value="none">Unassigned</option>}
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

      {activeTab === null ? null : activeTab === 'city' ? (
        <CityRidesWorkspace key={`city-${refreshKey}`} area={area} />
      ) : (
        <HubQueue
          key={`${activeTab}-${refreshKey}`}
          tab={activeTab}
          area={area}
          districts={districts}
          onChanged={reloadSummary}
        />
      )}
    </AdminFrame>
  );
}
