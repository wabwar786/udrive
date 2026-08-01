'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Eye,
  EyeOff,
  ImagePlus,
  MapPin,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  ShieldCheck,
  Trash2,
  Upload,
} from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Field, Loading, Modal, Stat } from '../components/ui';
import { API_BASE, apiFetch } from '../lib/admin-api';

type Destination = {
  id: string;
  slug: string;
  nameEn: string;
  nameUr: string;
  summaryEn: string;
  summaryUr: string;
  district: string;
  bestSeason: string;
  recommendedVehicle: string;
  networkStatus: string;
  familySuitabilityScore: number;
  routeSafetyScore: number;
  latitude: number;
  longitude: number;
  isActive: boolean;
  coverImageUrl?: string | null;
};

type FormState = Omit<Destination, 'id'> & { id?: string };

const emptyForm: FormState = {
  slug: '',
  nameEn: '',
  nameUr: '',
  summaryEn: '',
  summaryUr: '',
  latitude: 34.37,
  longitude: 73.47,
  district: 'Muzaffarabad',
  bestSeason: 'April to October',
  recommendedVehicle: 'SUV / 4 Wheel',
  networkStatus: 'Good',
  familySuitabilityScore: 90,
  routeSafetyScore: 85,
  coverImageUrl: '',
  isActive: true,
};

function imageUrl(value?: string | null) {
  if (!value) return '';
  if (/^https?:\/\//i.test(value)) return value;
  return new URL(value, API_BASE).toString();
}

export default function DestinationsPage() {
  const [rows, setRows] = useState<Destination[]>([]);
  const [form, setForm] = useState<FormState | null>(null);
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setRows(await apiFetch<Destination[]>('/api/v1/admin/operations/destinations'));
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Destinations could not be loaded.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return rows;
    return rows.filter((item) =>
      `${item.nameEn} ${item.nameUr} ${item.district} ${item.bestSeason} ${item.recommendedVehicle}`
        .toLowerCase()
        .includes(query),
    );
  }, [rows, search]);

  async function save() {
    if (!form) return;
    if (!form.nameEn.trim() || !form.nameUr.trim() || !form.slug.trim()) {
      setError('English name, Urdu name and URL slug are required.');
      return;
    }

    setSaving(true);
    setError('');
    try {
      const payload = { ...form };
      delete payload.id;
      const id = form.id
        ? (await apiFetch<string>(`/api/v1/admin/operations/destinations/${form.id}`, {
            method: 'PUT',
            body: JSON.stringify(payload),
          })) || form.id
        : await apiFetch<string>('/api/v1/admin/operations/destinations', {
            method: 'POST',
            body: JSON.stringify(payload),
          });

      if (selectedFile) {
        const upload = new FormData();
        upload.append('file', selectedFile);
        await apiFetch<string>(`/api/v1/admin/operations/destinations/${id}/image`, {
          method: 'POST',
          body: upload,
        });
      }

      setForm(null);
      setSelectedFile(null);
      await load();
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Destination could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  async function toggle(item: Destination) {
    setError('');
    try {
      const { id, ...payload } = item;
      await apiFetch(`/api/v1/admin/operations/destinations/${id}`, {
        method: 'PUT',
        body: JSON.stringify({ ...payload, isActive: !item.isActive }),
      });
      await load();
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Status could not be changed.');
    }
  }

  async function remove(item: Destination) {
    const confirmed = window.confirm(
      `Delete “${item.nameEn}”? If it is used by a package or route, the system will ask you to deactivate it instead.`,
    );
    if (!confirmed) return;
    setError('');
    try {
      await apiFetch(`/api/v1/admin/operations/destinations/${item.id}`, { method: 'DELETE' });
      await load();
    } catch (value) {
      setError(value instanceof Error ? value.message : 'Destination could not be deleted.');
    }
  }

  const activeCount = rows.filter((item) => item.isActive).length;
  const preview = selectedFile ? URL.createObjectURL(selectedFile) : imageUrl(form?.coverImageUrl);

  return (
    <AdminFrame
      title="Explore Kashmir management"
      subtitle="Add and manage the destination images used in the mobile Home hero slider and Explore Kashmir."
      actions={
        <button className="primaryButton" onClick={() => { setForm({ ...emptyForm }); setSelectedFile(null); }}>
          <Plus /> Add destination
        </button>
      }
    >
      {error && <ErrorBox message={error} />}

      <section className="statGrid destinationStats">
        <Stat label="Total destinations" value={rows.length} tone="blue" />
        <Stat label="Visible to customers" value={activeCount} tone="emerald" />
        <Stat label="Hidden / inactive" value={rows.length - activeCount} tone="amber" />
      </section>

      <section className="panel destinationManager">
        <header className="panelHeader">
          <div>
            <h2>Explore Kashmir catalogue</h2>
            <p>Every active destination cover image rotates automatically in Customer Mode → Home hero slider and also appears in Explore Kashmir.</p>
          </div>
          <div className="tableTools">
            <label className="searchBox">
              <Search />
              <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search destination…" />
            </label>
            <button className="secondaryButton" onClick={() => void load()}>
              <RefreshCw /> Refresh
            </button>
          </div>
        </header>

        {busy ? (
          <Loading />
        ) : filtered.length === 0 ? (
          <Empty title="No destinations found" copy="Add a destination to publish it in Explore Kashmir." />
        ) : (
          <div className="destinationGrid">
            {filtered.map((item) => (
              <article className="destinationAdminCard" key={item.id}>
                <div className="destinationCover">
                  {item.coverImageUrl ? (
                    <img src={imageUrl(item.coverImageUrl)} alt={item.nameEn} />
                  ) : (
                    <div className="destinationCoverFallback"><ImagePlus /></div>
                  )}
                  <span className="destinationVisibility"><Badge value={item.isActive ? 'Active' : 'Hidden'} /></span>
                </div>
                <div className="destinationCardBody">
                  <div className="destinationTitleRow">
                    <div>
                      <h3>{item.nameEn}</h3>
                      <p dir="rtl">{item.nameUr}</p>
                    </div>
                    <span className="destinationScore"><ShieldCheck /> {item.routeSafetyScore}</span>
                  </div>
                  <p className="destinationSummary">{item.summaryEn || 'No description added.'}</p>
                  <div className="destinationFacts">
                    <span><MapPin /> {item.district}</span>
                    <span>{item.bestSeason}</span>
                    <span>{item.recommendedVehicle}</span>
                  </div>
                  <div className="destinationActions">
                    <button className="secondaryButton" onClick={() => { setForm({ ...item }); setSelectedFile(null); }}><Pencil /> Edit</button>
                    <button className="secondaryButton" onClick={() => void toggle(item)}>{item.isActive ? <EyeOff /> : <Eye />} {item.isActive ? 'Hide' : 'Publish'}</button>
                    <button className="dangerButton" onClick={() => void remove(item)}><Trash2 /> Delete</button>
                  </div>
                </div>
              </article>
            ))}
          </div>
        )}
      </section>

      {form && (
        <Modal title={form.id ? 'Edit destination' : 'Add destination'} onClose={() => { setForm(null); setSelectedFile(null); }}>
          <div className="destinationEditor">
            <section className="destinationImageEditor">
              <div className="destinationImagePreview">
                {preview ? <img src={preview} alt="Destination preview" /> : <ImagePlus />}
              </div>
              <input
                ref={fileInput}
                hidden
                type="file"
                accept="image/jpeg,image/png,image/webp"
                onChange={(event) => setSelectedFile(event.target.files?.[0] ?? null)}
              />
              <button className="secondaryButton wide" type="button" onClick={() => fileInput.current?.click()}>
                <Upload /> {selectedFile ? 'Change selected image' : 'Upload home hero image'}
              </button>
              <small>JPG, PNG or WebP. Maximum 10 MB. Recommended 1440 × 1920 or higher portrait image for the full-screen mobile hero.</small>
            </section>

            <div className="formGrid destinationFormGrid">
              <Field label="English name"><input value={form.nameEn} onChange={(e) => setForm({ ...form, nameEn: e.target.value })} /></Field>
              <Field label="Urdu name"><input dir="rtl" value={form.nameUr} onChange={(e) => setForm({ ...form, nameUr: e.target.value })} /></Field>
              <Field label="URL slug"><input value={form.slug} onChange={(e) => setForm({ ...form, slug: e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, '-') })} /></Field>
              <Field label="District"><input value={form.district} onChange={(e) => setForm({ ...form, district: e.target.value })} /></Field>
              <Field label="English description"><textarea rows={4} value={form.summaryEn} onChange={(e) => setForm({ ...form, summaryEn: e.target.value })} /></Field>
              <Field label="Urdu description"><textarea dir="rtl" rows={4} value={form.summaryUr} onChange={(e) => setForm({ ...form, summaryUr: e.target.value })} /></Field>
              <Field label="Best season"><input value={form.bestSeason} onChange={(e) => setForm({ ...form, bestSeason: e.target.value })} /></Field>
              <Field label="Recommended vehicle"><input value={form.recommendedVehicle} onChange={(e) => setForm({ ...form, recommendedVehicle: e.target.value })} /></Field>
              <Field label="Network status"><input value={form.networkStatus} onChange={(e) => setForm({ ...form, networkStatus: e.target.value })} /></Field>
              <Field label="Family suitability (0–100)"><input type="number" min="0" max="100" value={form.familySuitabilityScore} onChange={(e) => setForm({ ...form, familySuitabilityScore: Number(e.target.value) })} /></Field>
              <Field label="Route safety (0–100)"><input type="number" min="0" max="100" value={form.routeSafetyScore} onChange={(e) => setForm({ ...form, routeSafetyScore: Number(e.target.value) })} /></Field>
              <Field label="Latitude"><input type="number" step="any" value={form.latitude} onChange={(e) => setForm({ ...form, latitude: Number(e.target.value) })} /></Field>
              <Field label="Longitude"><input type="number" step="any" value={form.longitude} onChange={(e) => setForm({ ...form, longitude: Number(e.target.value) })} /></Field>
              <Field label="Visible to customers"><input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} /></Field>
            </div>
          </div>
          <div className="buttonRow">
            <button className="primaryButton" disabled={saving} onClick={() => void save()}>{saving ? 'Saving…' : 'Save destination'}</button>
            <button className="secondaryButton" disabled={saving} onClick={() => { setForm(null); setSelectedFile(null); }}>Cancel</button>
          </div>
        </Modal>
      )}
    </AdminFrame>
  );
}
