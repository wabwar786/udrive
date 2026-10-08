'use client';

import { RefreshCw } from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { AdminFrame } from '../components/admin-frame';
import { ErrorBox } from '../components/ui';
import { apiFetch } from '../lib/admin-api';
import { usePermissions, type ModuleKey } from '../lib/permissions';
import { limitDistricts, useCatalogAreas } from '../verification/area-select';
import type { HubTab } from '../verification/hub-queue';
import styles from '../verification/verification.module.css';
import { ApprovedQueue } from './approved-queue';

type Summary = {
  city: number;
  tour: number;
  rent: number;
  hotels: number;
  businesses: number;
  suspended: number;
  claimsWaiting: number;
};

const TABS: { key: HubTab; label: string; module: ModuleKey }[] = [
  { key: 'city', label: 'City rides', module: 'verification.city' },
  { key: 'tour', label: 'Tour vehicles', module: 'verification.tour' },
  { key: 'rent', label: 'Rent-a-car', module: 'verification.rent' },
  { key: 'hotels', label: 'Hotels', module: 'verification.hotels' },
  { key: 'businesses', label: 'Businesses', module: 'verification.businesses' },
];

const selectStyle = {
  height: 40,
  border: '1px solid #dde9e4',
  borderRadius: 12,
  background: '#fff',
  padding: '0 12px',
  color: '#31564a',
} as const;

const chip = {
  borderRadius: 999,
  padding: '6px 11px',
  fontWeight: 800,
  fontSize: 12,
} as const;

export default function ApprovedPage() {
  const { districts: allDistricts, error: areasError } = useCatalogAreas();
  const { can, allAreas, areas } = usePermissions();
  const [districtId, setDistrictId] = useState('');
  const [tehsilId, setTehsilId] = useState('');
  const [tab, setTab] = useState<HubTab>('city');
  const [summary, setSummary] = useState<Summary | null>(null);
  const [summaryError, setSummaryError] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);

  const tabs = useMemo(() => TABS.filter((item) => can(item.module, 'view')), [can]);
  const activeTab: HubTab | null = tabs.some((item) => item.key === tab) ? tab : (tabs[0]?.key ?? null);
  const districts = useMemo(() => limitDistricts(allDistricts, areas, allAreas), [allDistricts, areas, allAreas]);
  const area = tehsilId || districtId;
  const district = districts.find((item) => item.id === districtId) ?? null;

  const loadSummary = useCallback(async () => {
    setSummaryError('');
    try {
      setSummary(
        await apiFetch<Summary>(
          `/api/v1/admin/verify/approved-summary${area ? `?area=${encodeURIComponent(area)}` : ''}`,
        ),
      );
    } catch (value) {
      setSummaryError(value instanceof Error ? value.message : 'Counts could not be loaded.');
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
      title="Approved"
      subtitle="Jo live hai ya suspend hai. Naye aur dobara review wale Verification mein."
      actions={
        <button className="secondaryButton" onClick={refresh}>
          <RefreshCw size={17} />
          Refresh
        </button>
      }
    >
      {(areasError || summaryError) && <ErrorBox message={areasError || summaryError} />}

      {summary && (summary.suspended > 0 || summary.claimsWaiting > 0) && (
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 12 }}>
          {summary.suspended > 0 && (
            <span style={{ ...chip, background: '#ffe1e5', color: '#a62032' }}>{summary.suspended} suspended</span>
          )}
          {summary.claimsWaiting > 0 && (
            <span style={{ ...chip, background: '#fff2cf', color: '#7a5300' }}>
              {summary.claimsWaiting} re-claim jawab ke intezar mein
            </span>
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

      {activeTab && (
        <ApprovedQueue key={`${activeTab}-${refreshKey}`} tab={activeTab} area={area} onChanged={reloadSummary} />
      )}
    </AdminFrame>
  );
}
