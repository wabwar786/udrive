'use client';

import { useEffect, useState } from 'react';
import { Badge, ErrorBox, Loading, Modal } from '../components/ui';
import { API_BASE, apiFetch, apiProtectedFile, money } from '../lib/admin-api';

type Detail = {
  hotel: {
    id: string;
    name: string;
    propertyType: string;
    description: string;
    address: string;
    city: string;
    district: string;
    latitude: number | null;
    longitude: number | null;
    contactPhone: string;
    amenities: string[];
    transportAvailable: boolean;
    checkInTime: string | null;
    checkOutTime: string | null;
    status: string;
    photos: { id: string; url: string; isMain: boolean }[];
    rooms: { id: string; roomType: string; capacity: number; totalRooms: number; baseRate: number; imageUrl: string }[];
    missing: string[];
  };
  owner: {
    ownerName: string;
    businessName: string;
    phone: string;
    email: string;
    verificationStatus: string;
    cnicFrontUrl: string | null;
    cnicBackUrl: string | null;
  };
};

function publicUrl(value: string) {
  if (!value) return '';
  return /^https?:\/\//i.test(value) ? value : new URL(value, API_BASE).toString();
}

/** A CNIC side: protected, so fetched with the admin token and shown as a blob. */
function Cnic({ label, path }: { label: string; path: string | null }) {
  const [url, setUrl] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    let alive = true;
    let objectUrl = '';
    if (!path) return;
    apiProtectedFile(path)
      .then((file) => {
        objectUrl = file.objectUrl;
        if (alive) setUrl(file.objectUrl);
      })
      .catch((value) => alive && setError(value instanceof Error ? value.message : 'Could not load.'));
    return () => {
      alive = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [path]);

  return (
    <figure style={{ margin: 0, flex: 1 }}>
      <figcaption style={{ fontSize: 11, fontWeight: 800, marginBottom: 6 }}>CNIC {label}</figcaption>
      <div style={{ height: 150, borderRadius: 12, background: '#f2f5f4', display: 'grid', placeItems: 'center', overflow: 'hidden' }}>
        {!path ? (
          <span style={{ color: '#9d2332', fontSize: 12 }}>Not uploaded</span>
        ) : url ? (
          <a href={url} target="_blank" rel="noreferrer" style={{ width: '100%', height: '100%' }}>
            <img src={url} alt={`CNIC ${label}`} style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
          </a>
        ) : error ? (
          <span style={{ color: '#9d2332', fontSize: 12 }}>{error}</span>
        ) : (
          <span style={{ color: '#6d7e77', fontSize: 12 }}>Loading…</span>
        )}
      </div>
    </figure>
  );
}

export function HotelDetails({ id, name, onClose }: { id: string; name: string; onClose: () => void }) {
  const [data, setData] = useState<Detail | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    apiFetch<Detail>(`/api/v1/hotels/admin/${id}/details`)
      .then(setData)
      .catch((value) => setError(value instanceof Error ? value.message : 'Details could not be loaded.'));
  }, [id]);

  const fact = (label: string, value: string) => (
    <div style={{ background: '#f4f8f6', borderRadius: 10, padding: 9 }}>
      <div style={{ fontSize: 9, textTransform: 'uppercase', letterSpacing: '.08em', color: '#7a8a84' }}>{label}</div>
      <div style={{ marginTop: 4, fontSize: 12, fontWeight: 750, overflowWrap: 'anywhere' }}>{value || '—'}</div>
    </div>
  );

  return (
    <Modal title={name} onClose={onClose}>
      {error && <ErrorBox message={error} />}
      {!data && !error && <Loading />}
      {data && (
        <div style={{ display: 'grid', gap: 16, maxHeight: '70vh', overflowY: 'auto' }}>
          <section>
            <h3 style={{ margin: '0 0 8px', fontSize: 14 }}>Owner</h3>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2,minmax(0,1fr))', gap: 8 }}>
              {fact('Owner name', data.owner.ownerName)}
              {fact('Business', data.owner.businessName)}
              {fact('Contact / WhatsApp', data.owner.phone)}
              {fact('Email', data.owner.email)}
            </div>
            <div style={{ margin: '8px 0' }}>
              <Badge value={data.owner.verificationStatus} />
            </div>
            <div style={{ display: 'flex', gap: 10 }}>
              <Cnic label="front" path={data.owner.cnicFrontUrl} />
              <Cnic label="back" path={data.owner.cnicBackUrl} />
            </div>
          </section>

          <section>
            <h3 style={{ margin: '0 0 8px', fontSize: 14 }}>Hotel</h3>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2,minmax(0,1fr))', gap: 8 }}>
              {fact('Type', data.hotel.propertyType)}
              {fact('Booking WhatsApp', data.hotel.contactPhone)}
              {fact('Area', [data.hotel.city, data.hotel.district].filter(Boolean).join(', '))}
              {fact('Check-in / out', `${data.hotel.checkInTime ?? '—'} / ${data.hotel.checkOutTime ?? '—'}`)}
              {fact('Address', data.hotel.address)}
              {fact(
                'Map pin',
                data.hotel.latitude == null ? '' : `${data.hotel.latitude.toFixed(5)}, ${data.hotel.longitude?.toFixed(5)}`,
              )}
            </div>
            {data.hotel.latitude != null && (
              <a
                href={`https://www.google.com/maps?q=${data.hotel.latitude},${data.hotel.longitude}`}
                target="_blank"
                rel="noreferrer"
                style={{ display: 'inline-block', marginTop: 8, fontSize: 12 }}
              >
                Open pin on Google Maps
              </a>
            )}
            <p style={{ color: '#62746d', lineHeight: 1.5 }}>{data.hotel.description || 'No description.'}</p>
            <p style={{ fontSize: 12 }}>
              <strong>Amenities:</strong>{' '}
              {[...data.hotel.amenities, ...(data.hotel.transportAvailable ? ['Pickup (UDrive)'] : [])].join(', ') || '—'}
            </p>
            {data.hotel.missing.length > 0 && (
              <div className="hotelRejectionReason">
                <strong>Still missing</strong>
                {data.hotel.missing.join(', ')}
              </div>
            )}
          </section>

          <section>
            <h3 style={{ margin: '0 0 8px', fontSize: 14 }}>Photos ({data.hotel.photos.length})</h3>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 8 }}>
              {data.hotel.photos.map((photo) => (
                <a key={photo.id} href={publicUrl(photo.url)} target="_blank" rel="noreferrer" style={{ position: 'relative' }}>
                  <img
                    src={publicUrl(photo.url)}
                    alt=""
                    style={{ width: '100%', height: 100, objectFit: 'cover', borderRadius: 10 }}
                  />
                  {photo.isMain && (
                    <span style={{ position: 'absolute', left: 6, top: 6, background: '#c6f432', borderRadius: 6, fontSize: 10, fontWeight: 800, padding: '2px 6px' }}>
                      MAIN
                    </span>
                  )}
                </a>
              ))}
            </div>
          </section>

          <section>
            <h3 style={{ margin: '0 0 8px', fontSize: 14 }}>Rooms ({data.hotel.rooms.length})</h3>
            <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Type</th>
                  <th>Guests</th>
                  <th>Rooms</th>
                  <th>Per night</th>
                </tr>
              </thead>
              <tbody>
                {data.hotel.rooms.map((room) => (
                  <tr key={room.id}>
                    <td>{room.roomType}</td>
                    <td>{room.capacity}</td>
                    <td>{room.totalRooms}</td>
                    <td>{money(room.baseRate)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            </div>
          </section>
        </div>
      )}
    </Modal>
  );
}
