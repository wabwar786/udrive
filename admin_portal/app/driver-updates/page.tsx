'use client';

import { useCallback, useEffect, useState } from 'react';
import { Send, Trash2 } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, ErrorBox, Field, Loading } from '../components/ui';
import { apiFetch, when } from '../lib/admin-api';

type City = { id: string; name: string; isActive?: boolean };

type Update = {
  id: string;
  cityId?: string;
  cityName: string;
  category: string;
  title: string;
  body: string;
  actionPath?: string;
  publishAt: string;
  expiresAt?: string;
  isPublished: boolean;
  createdBy: string;
};

const CATEGORIES = ['Demand', 'Rewards', 'Policy', 'Service', 'System'];

/**
 * What drivers are told, by city.
 *
 * The endpoint that saves these has existed since the growth system shipped and
 * no page ever called it, so in practice no update has ever been written. The
 * driver app reads fifty of them and has only ever shown the first one on the
 * home screen; both halves of that are fixed in this release.
 *
 * There was also no way to read them back — an Admin could write one and then
 * never see it again, which is most of why none were written. The list below is
 * the other half of the fix.
 */
export default function Page() {
  const [cities, setCities] = useState<City[]>([]);
  const [rows, setRows] = useState<Update[]>([]);

  const [cityId, setCityId] = useState('');
  const [category, setCategory] = useState('Demand');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [editing, setEditing] = useState<string | null>(null);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');

  const load = useCallback(async () => {
    try {
      const [c, u] = await Promise.all([
        apiFetch<City[]>('/api/v1/admin/growth/cities'),
        apiFetch<Update[]>('/api/v1/admin/growth/updates'),
      ]);
      setCities(c);
      setRows(u);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'This section is unavailable.');
    }
  }, []);

  useEffect(() => {
    setLoading(true);
    void load().finally(() => setLoading(false));
  }, [load]);

  const reset = () => {
    setEditing(null);
    setTitle('');
    setBody('');
    setCategory('Demand');
    setCityId('');
  };

  const publish = async () => {
    setBusy(true);
    setError('');
    setNote('');
    try {
      await apiFetch<string>(
        editing
          ? `/api/v1/admin/growth/updates/${editing}`
          : '/api/v1/admin/growth/updates',
        {
          method: editing ? 'PUT' : 'POST',
          body: JSON.stringify({
            cityId: cityId || null,
            category,
            title,
            body,
            actionPath: null,
            publishAt: null,
            expiresAt: null,
            isPublished: true,
          }),
        },
      );
      reset();
      setNote('Published. Drivers in that city see it the next time they open the app.');
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be published.');
    } finally {
      setBusy(false);
    }
  };

  const remove = async (row: Update) => {
    setBusy(true);
    setError('');
    try {
      await apiFetch<boolean>(`/api/v1/admin/growth/updates/${row.id}`, {
        method: 'DELETE',
      });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That could not be removed.');
    } finally {
      setBusy(false);
    }
  };

  const edit = (row: Update) => {
    setEditing(row.id);
    setCityId(row.cityId ?? '');
    setCategory(row.category);
    setTitle(row.title);
    setBody(row.body);
  };

  return (
    <AdminFrame
      title="Driver updates"
      subtitle="Road conditions, demand, policy — what drivers see on their home screen."
    >
      {error && <ErrorBox message={error} />}
      {note && <section className="panel"><p>{note}</p></section>}

      {loading ? (
        <Loading />
      ) : (
        <>
          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>{editing ? 'Edit update' : 'Write an update'}</h2>
                <p>Keep it to what a driver can act on today.</p>
              </div>
              <div>
                {editing && (
                  <button className="secondaryButton" onClick={reset} disabled={busy}>
                    Cancel
                  </button>
                )}
                <button
                  className="primaryButton"
                  onClick={() => void publish()}
                  disabled={busy || title.trim().length === 0 || body.trim().length === 0}
                >
                  <Send /> {editing ? 'Save' : 'Publish'}
                </button>
              </div>
            </header>

            <div className="formGrid">
              {/* No city means every city. The driver API filters by the
                  driver's own launch city and treats a null as "everyone",
                  which is how a commission change reaches the whole country
                  without writing it once per town. */}
              <Field label="City">
                <select value={cityId} onChange={(e) => setCityId(e.target.value)}>
                  <option value="">All cities</option>
                  {cities.map((c) => (
                    <option key={c.id} value={c.id}>{c.name}</option>
                  ))}
                </select>
              </Field>
              <Field label="Category">
                <select value={category} onChange={(e) => setCategory(e.target.value)}>
                  {CATEGORIES.map((c) => (
                    <option key={c} value={c}>{c}</option>
                  ))}
                </select>
              </Field>
            </div>

            <Field label="Title">
              <input
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Neelum road is open"
                maxLength={160}
              />
            </Field>
            <Field label="Body">
              <textarea
                rows={4}
                value={body}
                onChange={(e) => setBody(e.target.value)}
                placeholder="Cars can reach Kel. Single lane after Athmuqam — take care at night."
              />
            </Field>
          </section>

          <section className="panel">
            <header className="panelHeader">
              <div>
                <h2>Published</h2>
                <p>{rows.length} update(s)</p>
              </div>
            </header>
            <div className="tableWrap">
              <table>
                <thead>
                  <tr>
                    <th>Title</th>
                    <th>City</th>
                    <th>Category</th>
                    <th>Published</th>
                    <th>By</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <tr key={row.id} className="clickable" onClick={() => edit(row)}>
                      <td>
                        <strong>{row.title}</strong>
                        <small>{row.body.slice(0, 90)}</small>
                      </td>
                      <td>{row.cityName}</td>
                      <td><Badge value={row.category} /></td>
                      <td>
                        {when(row.publishAt)}
                        {!row.isPublished && <small>draft</small>}
                      </td>
                      <td>{row.createdBy}</td>
                      <td>
                        <button
                          className="iconButton"
                          disabled={busy}
                          onClick={(e) => {
                            e.stopPropagation();
                            void remove(row);
                          }}
                        >
                          <Trash2 />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </AdminFrame>
  );
}
