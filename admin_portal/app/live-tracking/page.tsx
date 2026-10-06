'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle,
  Copy,
  Crosshair,
  ExternalLink,
  Layers,
  LocateFixed,
  Maximize2,
  Radio,
  RefreshCw,
  Search,
  Share2,
  Signal,
  SignalZero,
} from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Field, Modal } from '../components/ui';
import { API_BASE, apiFetch, when } from '../lib/admin-api';
import { googleMapsLink, loadLeaflet, SATELLITE_TILES, STREET_TILES, type LeafletApi } from '../lib/leaflet';
import { usePermissions } from '../lib/permissions';

type Active = { bookingId: string; bookingReference: string; driverName: string; vehicle: string; registrationNumber: string; tripStatus: string; city: string; lastUpdate?: string; stale: boolean; emergency: boolean; speedKph?: number; heading?: number; accuracy?: number };
type Point = { latitude: number; longitude: number; accuracy?: number; heading?: number; speedKph?: number; batteryLevel?: number; deviceTimestamp: string; serverTimestamp: string; stale: boolean; online: boolean; emergency: boolean };
type Tracking = { bookingId: string; bookingReference: string; tripStatus: string; pickupLabel: string; destinationLabel: string; pickupLatitude?: number; pickupLongitude?: number; destinationLatitude?: number; destinationLongitude?: number; driverName?: string; vehicle?: string; registrationNumber?: string; driverLocation?: Point; recentPath: Point[] };
type ShareLink = { url: string; expiresAt: string };

/** The selected trip refreshes every 5 seconds; the list every 15. */
const TRIP_REFRESH_MS = 5000;
const LIST_REFRESH_MS = 15000;

export default function LiveTrackingPage() {
  const [list, setList] = useState<Active[]>([]);
  const [selected, setSelected] = useState<string>('');
  const [tracking, setTracking] = useState<Tracking | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');
  const [city, setCity] = useState('');
  const [emergency, setEmergency] = useState(false);
  const [stale, setStale] = useState(false);
  const [notice, setNotice] = useState('');
  const [sharing, setSharing] = useState(false);
  const { can } = usePermissions();
  const canShare = can('operations', 'edit');

  const loadList = useCallback(async () => {
    try {
      const q = new URLSearchParams();
      if (search) q.set('search', search);
      if (status) q.set('status', status);
      if (city) q.set('city', city);
      if (emergency) q.set('emergencyOnly', 'true');
      if (stale) q.set('staleOnly', 'true');
      const result = await apiFetch<Active[]>(`/api/v1/tracking/admin/active?${q}`);
      setList(result);
      setSelected((current) => current || result[0]?.bookingId || '');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Tracking list failed.');
    } finally {
      setLoading(false);
    }
  }, [search, status, city, emergency, stale]);

  const loadTracking = useCallback(async () => {
    if (!selected) {
      setTracking(null);
      return;
    }
    try {
      setTracking(await apiFetch<Tracking>(`/api/v1/tracking/admin/${selected}`));
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Trip tracking failed.');
    }
  }, [selected]);

  useEffect(() => {
    const t = setTimeout(() => void loadList(), 200);
    const timer = setInterval(() => void loadList(), LIST_REFRESH_MS);
    return () => {
      clearTimeout(t);
      clearInterval(timer);
    };
  }, [loadList]);

  useEffect(() => {
    void loadTracking();
    const timer = setInterval(() => void loadTracking(), TRIP_REFRESH_MS);
    return () => clearInterval(timer);
  }, [loadTracking]);

  const flash = (text: string) => {
    setNotice(text);
    window.setTimeout(() => setNotice(''), 2500);
  };

  async function copy(text: string, label: string) {
    try {
      await navigator.clipboard.writeText(text);
      flash(`${label} copied.`);
    } catch {
      window.prompt('Copy this:', text);
    }
  }

  const location = tracking?.driverLocation;
  const hasDestinationPin = tracking?.destinationLatitude != null && tracking?.destinationLongitude != null;

  return (
    <AdminFrame
      title="Live Tracking"
      subtitle="Active drivers, stale-location warnings and emergency visibility."
      actions={
        <button className="secondaryButton" onClick={() => { void loadList(); void loadTracking(); }}>
          <RefreshCw />Refresh
        </button>
      }
    >
      <div className="trackingLayout">
        <section className="panel trackingList">
          <div className="trackingFilters">
            <label className="searchBox"><Search /><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Driver, booking or registration" /></label>
            <input value={city} onChange={(e) => setCity(e.target.value)} placeholder="City" />
            <select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">All active statuses</option>
              {['DriverAccepted', 'DriverEnRoute', 'DriverArrived', 'TripStarted', 'Emergency'].map((x) => <option key={x}>{x}</option>)}
            </select>
            <label><input type="checkbox" checked={emergency} onChange={(e) => setEmergency(e.target.checked)} /> Emergency only</label>
            <label><input type="checkbox" checked={stale} onChange={(e) => setStale(e.target.checked)} /> Stale only</label>
          </div>
          {loading ? (
            <div className="loading"><span /><span /><span /></div>
          ) : list.length === 0 ? (
            <div className="empty"><LocateFixed size={40} /><h3>No active tracked trips</h3></div>
          ) : (
            <div className="trackingRows">
              {list.map((x) => (
                <button key={x.bookingId} className={`${selected === x.bookingId ? 'selected' : ''} ${x.emergency ? 'emergency' : ''}`} onClick={() => setSelected(x.bookingId)}>
                  <div className="trackingStatusIcon">{x.stale ? <SignalZero /> : <Signal />}</div>
                  <div><strong>{x.bookingReference} · {x.driverName}</strong><span>{x.vehicle} · {x.registrationNumber}</span><small>{x.city} · {x.tripStatus}</small></div>
                  <div><span className={`badge ${x.emergency ? 'badge-critical' : x.stale ? 'badge-pending' : 'badge-active'}`}>{x.emergency ? 'Emergency' : x.stale ? 'Stale' : 'Live'}</span><small>{x.lastUpdate ? when(x.lastUpdate) : 'No location'}</small></div>
                </button>
              ))}
            </div>
          )}
        </section>

        <section className="panel trackingMapPanel">
          {error && <div className="errorBox">{error}</div>}
          {notice && <div className="successBox">{notice}</div>}
          {tracking ? (
            <>
              <div className="panelHeader">
                <div>
                  <h2>{tracking.bookingReference}</h2>
                  <p>{tracking.driverName || 'Driver'} · {tracking.vehicle || 'Vehicle'} · {tracking.registrationNumber || '—'}</p>
                </div>
                <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                  {canShare && (
                    <button className="primaryButton" onClick={() => setSharing(true)}><Share2 size={16} />Share live</button>
                  )}
                  <span className={`badge badge-${tracking.tripStatus.toLowerCase()}`}>{tracking.tripStatus}</span>
                </div>
              </div>

              <LiveMap tracking={tracking} />

              <div className="trackingMetrics">
                <div><span>Last update</span><strong>{location ? `${when(location.serverTimestamp)} (${ago(location.serverTimestamp)})` : 'No location'}</strong></div>
                <div><span>Speed</span><strong>{location?.speedKph?.toFixed(0) ?? '—'} km/h</strong></div>
                <div><span>Heading</span><strong>{location?.heading?.toFixed(0) ?? '—'}°</strong></div>
                <div><span>Accuracy</span><strong>{location?.accuracy?.toFixed(0) ?? '—'} m</strong></div>
                <div><span>Connection</span><strong>{location?.online ? 'Online' : 'Offline / stale'}</strong></div>
                <div><span>Battery</span><strong>{location?.batteryLevel ?? '—'}%</strong></div>
              </div>

              <div className="routeSummary">
                {location && (
                  <div className="routeLine">
                    <i className="driverDot" />
                    <span><strong>Car now</strong>{location.latitude.toFixed(5)}, {location.longitude.toFixed(5)}</span>
                    <div className="routeActions">
                      <button className="secondaryButton" onClick={() => void copy(googleMapsLink(location.latitude, location.longitude), 'Live location link')}><Copy size={14} />Copy live location</button>
                      <a className="secondaryButton" href={googleMapsLink(location.latitude, location.longitude)} target="_blank" rel="noreferrer"><ExternalLink size={14} />Open</a>
                    </div>
                  </div>
                )}
                <div className="routeLine">
                  <i className="pickupDot" />
                  <span><strong>Pickup</strong>{tracking.pickupLabel || '—'}</span>
                </div>
                <div className="routeLine">
                  <i className="destinationDot" />
                  <span><strong>Destination</strong>{tracking.destinationLabel || '—'}</span>
                  <div className="routeActions">
                    <button className="secondaryButton" disabled={!tracking.destinationLabel} onClick={() => void copy(tracking.destinationLabel, 'Destination address')}><Copy size={14} />Copy address</button>
                    {hasDestinationPin && (
                      <>
                        <button className="secondaryButton" onClick={() => void copy(googleMapsLink(tracking.destinationLatitude!, tracking.destinationLongitude!), 'Destination map link')}><Copy size={14} />Copy map link</button>
                        <a className="secondaryButton" href={googleMapsLink(tracking.destinationLatitude!, tracking.destinationLongitude!)} target="_blank" rel="noreferrer"><ExternalLink size={14} />Open in Google Maps</a>
                      </>
                    )}
                  </div>
                </div>
              </div>
            </>
          ) : (
            <div className="empty"><Radio size={45} /><h3>Select an active trip</h3><p>Live location and route details will appear here.</p></div>
          )}
        </section>
      </div>

      {sharing && tracking && (
        <ShareModal
          bookingId={tracking.bookingId}
          reference={tracking.bookingReference}
          onClose={() => setSharing(false)}
          onCopy={(text) => void copy(text, 'Tracking link')}
        />
      )}
    </AdminFrame>
  );
}

function ago(value: string) {
  const seconds = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  return `${Math.round(minutes / 60)} h ago`;
}

/** A real map: zoom, drag, follow the car, fit the whole trip, streets or satellite. */
function LiveMap({ tracking }: { tracking: Tracking }) {
  const holder = useRef<HTMLDivElement | null>(null);
  const map = useRef<LeafletApi>(null);
  const layers = useRef<{ L: LeafletApi; streets: LeafletApi; satellite: LeafletApi; driver: LeafletApi; accuracy: LeafletApi; path: LeafletApi; pickup: LeafletApi; destination: LeafletApi } | null>(null);
  const [follow, setFollow] = useState(true);
  const [satellite, setSatellite] = useState(false);
  const [mapError, setMapError] = useState('');
  const fitted = useRef<string>('');
  const [tick, setTick] = useState(0);

  const points = useMemo(() => {
    const pts: Array<[number, number]> = tracking.recentPath.map((p) => [p.latitude, p.longitude]);
    if (tracking.driverLocation) pts.push([tracking.driverLocation.latitude, tracking.driverLocation.longitude]);
    if (tracking.pickupLatitude != null && tracking.pickupLongitude != null) pts.push([tracking.pickupLatitude, tracking.pickupLongitude]);
    if (tracking.destinationLatitude != null && tracking.destinationLongitude != null) pts.push([tracking.destinationLatitude, tracking.destinationLongitude]);
    return pts;
  }, [tracking]);

  // Create the map once.
  useEffect(() => {
    let cancelled = false;
    loadLeaflet()
      .then((L) => {
        if (cancelled || !holder.current || map.current) return;
        const m = L.map(holder.current, { zoomControl: true, attributionControl: true }).setView([34.37, 73.47], 12);
        const streets = L.tileLayer(STREET_TILES.url, { attribution: STREET_TILES.attribution, maxZoom: STREET_TILES.maxZoom }).addTo(m);
        const satelliteLayer = L.tileLayer(SATELLITE_TILES.url, { attribution: SATELLITE_TILES.attribution, maxZoom: SATELLITE_TILES.maxZoom });
        const path = L.polyline([], { color: '#148f69', weight: 5, opacity: 0.9 }).addTo(m);
        const accuracy = L.circle([0, 0], { radius: 0, color: '#14ad7a', weight: 1, fillOpacity: 0.12 }).addTo(m);
        const pickup = L.circleMarker([0, 0], { radius: 9, color: '#fff', weight: 3, fillColor: '#2676d8', fillOpacity: 1 }).bindTooltip('Pickup');
        const destination = L.circleMarker([0, 0], { radius: 9, color: '#fff', weight: 3, fillColor: '#ee7b24', fillOpacity: 1 }).bindTooltip('Destination');
        const driver = L.marker([0, 0], { icon: carIcon(L, 0, false), zIndexOffset: 1000 }).bindTooltip('Driver');
        m.on('dragstart', () => setFollow(false));
        map.current = m;
        layers.current = { L, streets, satellite: satelliteLayer, driver, accuracy, path, pickup, destination };
        setMapError('');
        setTick((t) => t + 1);
      })
      .catch((e: unknown) => setMapError(e instanceof Error ? e.message : 'The map could not be loaded.'));
    return () => {
      cancelled = true;
      if (map.current) {
        map.current.remove();
        map.current = null;
        layers.current = null;
      }
    };
  }, []);


  // Draw the trip on every refresh.
  useEffect(() => {
    const m = map.current;
    const ly = layers.current;
    if (!m || !ly) return;
    const { L } = ly;
    ly.path.setLatLngs(tracking.recentPath.map((p) => [p.latitude, p.longitude]));

    if (tracking.pickupLatitude != null && tracking.pickupLongitude != null) {
      ly.pickup.setLatLng([tracking.pickupLatitude, tracking.pickupLongitude]).addTo(m);
    } else ly.pickup.remove();

    if (tracking.destinationLatitude != null && tracking.destinationLongitude != null) {
      ly.destination.setLatLng([tracking.destinationLatitude, tracking.destinationLongitude]).addTo(m);
    } else ly.destination.remove();

    const loc = tracking.driverLocation;
    if (loc) {
      ly.driver.setLatLng([loc.latitude, loc.longitude]).setIcon(carIcon(L, loc.heading ?? 0, loc.emergency)).addTo(m);
      ly.accuracy.setLatLng([loc.latitude, loc.longitude]).setRadius(Math.min(loc.accuracy ?? 0, 500));
    } else {
      ly.driver.remove();
      ly.accuracy.setRadius(0);
    }

    // First time a trip is shown: zoom close on the car (or fit everything).
    if (fitted.current !== tracking.bookingId) {
      fitted.current = tracking.bookingId;
      setFollow(true);
      if (loc) m.setView([loc.latitude, loc.longitude], 16);
      else if (points.length) m.fitBounds(points, { padding: [40, 40], maxZoom: 16 });
    } else if (follow && loc) {
      m.panTo([loc.latitude, loc.longitude], { animate: true });
    }
  }, [tracking, follow, points, tick]);

  useEffect(() => {
    const m = map.current;
    const ly = layers.current;
    if (!m || !ly) return;
    if (satellite) {
      ly.streets.remove();
      ly.satellite.addTo(m);
    } else {
      ly.satellite.remove();
      ly.streets.addTo(m);
    }
  }, [satellite, tick]);

  const fitTrip = () => {
    if (!map.current || !points.length) return;
    setFollow(false);
    map.current.fitBounds(points, { padding: [40, 40], maxZoom: 16 });
  };

  const followCar = () => {
    setFollow(true);
    const loc = tracking.driverLocation;
    if (map.current && loc) map.current.setView([loc.latitude, loc.longitude], Math.max(map.current.getZoom(), 16));
  };

  return (
    <div className="liveMap">
      <div ref={holder} className="leafletHolder" aria-label="Live trip map" />
      <div className="mapTools">
        <button className={follow ? 'primaryButton' : 'secondaryButton'} onClick={followCar}><Crosshair size={15} />{follow ? 'Following car' : 'Follow car'}</button>
        <button className="secondaryButton" onClick={fitTrip}><Maximize2 size={15} />Fit trip</button>
        <button className="secondaryButton" onClick={() => setSatellite((s) => !s)}><Layers size={15} />{satellite ? 'Streets' : 'Satellite'}</button>
      </div>
      {mapError && <div className="staleOverlay"><AlertTriangle />{mapError}</div>}
      {!mapError && tracking.driverLocation?.stale && (
        <div className="staleOverlay"><AlertTriangle />Location is stale · {ago(tracking.driverLocation.serverTimestamp)}</div>
      )}
      {!mapError && !tracking.driverLocation && <div className="staleOverlay"><AlertTriangle />No location from the driver yet</div>}
    </div>
  );
}

/** The car: a dark dot with an arrow pointing where it is heading. */
function carIcon(L: LeafletApi, heading: number, emergency: boolean) {
  const fill = emergency ? '#e83b4e' : '#092f24';
  const html = `<div style="width:40px;height:40px;display:grid;place-items:center;transform:rotate(${Math.round(heading)}deg)">
    <svg width="40" height="40" viewBox="0 0 40 40" aria-hidden="true">
      <circle cx="20" cy="20" r="17" fill="${emergency ? '#e83b4e' : '#14ad7a'}" opacity="0.28"/>
      <circle cx="20" cy="20" r="10" fill="${fill}" stroke="#fff" stroke-width="3"/>
      <path d="M20 4 L25 13 L20 11 L15 13 Z" fill="${fill}" stroke="#fff" stroke-width="1.5"/>
    </svg></div>`;
  return L.divIcon({ html, className: 'carIcon', iconSize: [40, 40], iconAnchor: [20, 20] });
}

/** Creates a link anyone can open to follow this trip; stops when the trip ends. */
function ShareModal({ bookingId, reference, onClose, onCopy }: { bookingId: string; reference: string; onClose: () => void; onCopy: (text: string) => void }) {
  const [minutes, setMinutes] = useState(120);
  const [link, setLink] = useState<ShareLink | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  async function create() {
    setBusy(true);
    setError('');
    try {
      const data = await apiFetch<{ token: string; expiresAt: string }>(`/api/v1/tracking/${bookingId}/link`, {
        method: 'POST',
        body: JSON.stringify({ expiresInMinutes: minutes }),
      });
      setLink({ url: `${API_BASE.replace(/\/$/, '')}/track/${data.token}`, expiresAt: data.expiresAt });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The link could not be created.');
    } finally {
      setBusy(false);
    }
  }

  async function stop() {
    setBusy(true);
    setError('');
    try {
      await apiFetch<boolean>(`/api/v1/tracking/${bookingId}/link`, { method: 'DELETE' });
      setLink(null);
      setMessage('Every shared link for this trip has stopped working.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Sharing could not be stopped.');
    } finally {
      setBusy(false);
    }
  }

  const whatsapp = link
    ? `https://wa.me/?text=${encodeURIComponent(`Live location of UDrive trip ${reference}: ${link.url}`)}`
    : '';

  return (
    <Modal title={`Share live tracking · ${reference}`} onClose={onClose}>
      <div className="detailStack">
        <p style={{ margin: 0, color: '#5d716a' }}>
          Anyone with the link can watch the car on a map — no sign-in. They see the driver&apos;s first name, the vehicle and plate, the
          trip status and the last update; never a phone number or the trip code. The link stops when the trip ends.
        </p>
        {error && <div className="errorBox">{error}</div>}
        {message && <div className="successBox">{message}</div>}
        {!link ? (
          <>
            <Field label="Link works for">
              <select value={minutes} onChange={(e) => setMinutes(Number(e.target.value))}>
                <option value={60}>1 hour</option>
                <option value={120}>2 hours</option>
                <option value={1440}>Until the trip ends (up to 24 hours)</option>
              </select>
            </Field>
            <div className="buttonRow" style={{ padding: 0 }}>
              <button className="primaryButton" disabled={busy} onClick={() => void create()}><Share2 size={16} />Create link</button>
              <button className="dangerButton" disabled={busy} onClick={() => void stop()}>Stop sharing</button>
            </div>
          </>
        ) : (
          <>
            <Field label="Tracking link">
              <input readOnly value={link.url} onFocus={(e) => e.currentTarget.select()} />
            </Field>
            <small style={{ color: '#5d716a' }}>Works until {when(link.expiresAt)} or the end of the trip, whichever comes first.</small>
            <div className="buttonRow" style={{ padding: 0 }}>
              <button className="primaryButton" onClick={() => onCopy(link.url)}><Copy size={16} />Copy link</button>
              <a className="secondaryButton" href={whatsapp} target="_blank" rel="noreferrer">WhatsApp</a>
              <a className="secondaryButton" href={link.url} target="_blank" rel="noreferrer"><ExternalLink size={14} />Open</a>
              <button className="dangerButton" disabled={busy} onClick={() => void stop()}>Stop sharing</button>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}
