/**
 * Leaflet, loaded once from the CDN at runtime (no npm package).
 *
 * Map tiles: OpenStreetMap streets (no key) and Esri World Imagery for
 * satellite. Both are free for this level of use; a busy public deployment
 * may later need a paid tile provider.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */
export type LeafletApi = any;

const VERSION = '1.9.4';
const CSS = `https://unpkg.com/leaflet@${VERSION}/dist/leaflet.css`;
const JS = `https://unpkg.com/leaflet@${VERSION}/dist/leaflet.js`;

let loading: Promise<LeafletApi> | null = null;

export function loadLeaflet(): Promise<LeafletApi> {
  if (typeof window === 'undefined') return Promise.reject(new Error('No browser.'));
  const existing = (window as unknown as { L?: LeafletApi }).L;
  if (existing) return Promise.resolve(existing);
  if (loading) return loading;

  loading = new Promise<LeafletApi>((resolve, reject) => {
    if (!document.querySelector(`link[href="${CSS}"]`)) {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = CSS;
      link.crossOrigin = '';
      document.head.appendChild(link);
    }

    const script = document.createElement('script');
    script.src = JS;
    script.async = true;
    script.crossOrigin = '';
    script.onload = () => {
      const L = (window as unknown as { L?: LeafletApi }).L;
      if (L) resolve(L);
      else reject(new Error('The map could not start.'));
    };
    script.onerror = () => {
      loading = null;
      reject(new Error('The map could not be loaded. Check the internet connection.'));
    };
    document.head.appendChild(script);
  });

  return loading;
}

export const STREET_TILES = {
  url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: '&copy; OpenStreetMap contributors',
  maxZoom: 19,
};

export const SATELLITE_TILES = {
  url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  attribution: 'Imagery &copy; Esri',
  maxZoom: 19,
};

/** A Google Maps link for a point. */
export function googleMapsLink(latitude: number, longitude: number) {
  return `https://www.google.com/maps?q=${latitude.toFixed(6)},${longitude.toFixed(6)}`;
}
