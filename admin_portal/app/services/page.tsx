'use client';

import { useCallback, useEffect, useState } from 'react';
import { Save } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { ErrorBox, Field, Loading } from '../components/ui';
import { apiFetch } from '../lib/admin-api';

type Service = {
  serviceKey: string;
  isOpen: boolean;
  badgeLabel: string;
  closedMessage: string;
};

/**
 * Which services customers may open.
 *
 * Closing one does **not** touch the driver app: vehicles can still be
 * registered and verified for a closed service, so it has a fleet on the day it
 * opens. Without that the platform deadlocks — closed because there are no
 * vehicles, and no vehicles because it is closed.
 */
const NAMES: Record<string, string> = {
  cityRides: 'City rides',
  tour: 'Tour',
  cityToCity: 'City to city',
  hotels: 'Hotels',
  coster: 'Coster',
  explore: 'Explore',
  carRental: 'Car rental',
};

export default function Page() {
  const [rows, setRows] = useState<Service[]>([]);

  /**
   * How often a driver publishes their position.
   *
   * Here rather than in code because the right answer changes without a
   * release: fast makes the map smooth and costs battery and data, slow makes
   * the car jump a block at a time. Which trade is right depends on how many
   * drivers are online and what a megabyte costs them.
   */
  const [ping, setPing] = useState(2);

  /**
   * How far a request reaches, and how far customers see.
   *
   * Two numbers, not one. The request radius is about reach — how far a driver
   * may be and still be offered the job. The nearby radius is about honesty —
   * only showing cars that would realistically come. Tying them together would
   * mean widening the map every time you widened the search.
   */
  const [requestKm, setRequestKm] = useState(5);
  const [nearbyKm, setNearbyKm] = useState(1);

  /**
   * The platform's cut of each fare.
   *
   * Taken from the driver's prepaid balance the moment a trip starts — not
   * when it ends, because a driver who loses signal after dropping someone off
   * never sends the completion, and the platform was carrying rides it was not
   * paid for.
   */
  const [, setCommission] = useState(10);

  /** Commission per kind of work, as text while it is being typed. */
  const [rates, setRates] = useState({ city: '10', intercity: '10', tour: '10', rent: '10', hotel: '0' });
  // Hotel wallet: below the minimum the hotel is hidden; below the alert the owner is told.
  const [hotelMin, setHotelMin] = useState('0');
  const [hotelAlert, setHotelAlert] = useState('500');

  /**
   * The welcome credit, and where drivers send top-ups.
   *
   * The credit is a number that expires in usefulness: early on it buys a
   * fleet, because a driver who must top up before their first fare has been
   * asked to pay to find out whether the platform works. Once there are
   * drivers, that reason is gone and it comes down.
   */
  const [bonus, setBonus] = useState(1000);
  // Welcome credit for the other kinds of work (city is `bonus`).
  const [kindBonus, setKindBonus] = useState({ tour: 500, rent: 500, hotel: 500 });
  const [easypaisa, setEasypaisa] = useState('');
  const [accountName, setAccountName] = useState('');

  /**
   * What the driver offer card shows a customer.
   *
   * Ratings and ride counts start off. A new platform has no ratings, so
   * "0.00" and "0 rides" sit beside every driver — and a zero next to a name
   * reads as a bad driver rather than a new one.
   */
  const [card, setCard] = useState<Record<string, boolean>>({
    vehiclePhoto: true,
    driverPhoto: true,
    rating: false,
    rides: false,
    plate: true,
  });
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState('');

  const load = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      setRows(await apiFetch<Service[]>('/api/v1/admin/services'));
      const ops = await apiFetch<{
        pingSeconds: number;
        requestRadiusKm: number;
        nearbyRadiusKm: number;
        commissionPercentage: number;
        commissionRates?: {
          city: number;
          intercity: number;
          tour: number;
          rent: number;
          hotel?: number;
          hotelMinimumBalance?: number;
          hotelLowBalanceAlert?: number;
        };
        offerCard: Record<string, boolean>;
      }>('/api/v1/settings/operations');
      setPing(ops.pingSeconds);
      setRequestKm(ops.requestRadiusKm);
      setNearbyKm(ops.nearbyRadiusKm);
      setCommission(ops.commissionPercentage);
      const r = ops.commissionRates;
      setRates({
        city: String(r?.city ?? ops.commissionPercentage),
        intercity: String(r?.intercity ?? ops.commissionPercentage),
        tour: String(r?.tour ?? ops.commissionPercentage),
        rent: String(r?.rent ?? ops.commissionPercentage),
        hotel: String(r?.hotel ?? 0),
      });
      setHotelMin(String(r?.hotelMinimumBalance ?? 0));
      setHotelAlert(String(r?.hotelLowBalanceAlert ?? 500));
      if (ops.offerCard) setCard(ops.offerCard);

      const wallet = await apiFetch<{
        welcomeBonus: number;
        tourWelcomeBonus?: number;
        rentWelcomeBonus?: number;
        hotelWelcomeBonus?: number;
        easypaisaNumber: string;
        accountName: string;
      }>('/api/v1/admin/settings/wallet');
      setBonus(wallet.welcomeBonus);
      setKindBonus({
        tour: wallet.tourWelcomeBonus ?? 500,
        rent: wallet.rentWelcomeBonus ?? 500,
        hotel: wallet.hotelWelcomeBonus ?? 500,
      });
      setEasypaisa(wallet.easypaisaNumber ?? '');
      setAccountName(wallet.accountName ?? '');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load services.');
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  function edit(key: string, patch: Partial<Service>) {
    setRows((current) =>
      current.map((row) =>
        row.serviceKey === key ? { ...row, ...patch } : row,
      ),
    );
  }

  async function save(row: Service) {
    setSaving(row.serviceKey);
    setError('');
    setSaved('');
    try {
      await apiFetch(`/api/v1/admin/services/${row.serviceKey}`, {
        method: 'PUT',
        body: JSON.stringify({
          isOpen: row.isOpen,
          badgeLabel: row.badgeLabel,
          closedMessage: row.closedMessage,
        }),
      });
      setSaved(`${NAMES[row.serviceKey] ?? row.serviceKey} updated.`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that change.');
    } finally {
      setSaving(null);
    }
  }

  async function savePing(seconds: number) {
    setPing(seconds);
    setError('');
    setSaved('');
    try {
      await apiFetch('/api/v1/admin/settings/tracking', {
        method: 'PUT',
        body: JSON.stringify({ pingSeconds: seconds }),
      });
      setSaved(`Drivers will now report every ${seconds} second${seconds === 1 ? '' : 's'}.`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that.');
    }
  }

  async function saveRadius(request: number, nearby: number) {
    setRequestKm(request);
    setNearbyKm(nearby);
    setError('');
    setSaved('');
    try {
      await apiFetch('/api/v1/admin/settings/radius', {
        method: 'PUT',
        body: JSON.stringify({
          requestRadiusKm: request,
          nearbyRadiusKm: nearby,
        }),
      });
      setSaved(
        `Requests now reach ${request} km; customers see ${nearby} km around them.`,
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that.');
    }
  }

  async function saveCommission() {
    setError('');
    setSaved('');
    const parsed = {
      city: Number(rates.city),
      intercity: Number(rates.intercity),
      tour: Number(rates.tour),
      rent: Number(rates.rent),
      hotel: Number(rates.hotel),
    };
    if (Object.values(parsed).some((v) => !Number.isFinite(v) || v < 0 || v > 40)) {
      setError('Har commission 0 se 40% ke beech honi chahiye.');
      return;
    }
    const minimum = Number(hotelMin);
    const alert = Number(hotelAlert);
    if (![minimum, alert].every((v) => Number.isFinite(v) && v >= 0 && v <= 1000000)) {
      setError('Hotel wallet ki raqam 0 se 10,00,000 ke beech honi chahiye.');
      return;
    }
    try {
      await apiFetch('/api/v1/admin/settings/commission', {
        method: 'PUT',
        body: JSON.stringify({
          percentage: parsed.city,
          intercityPercentage: parsed.intercity,
          tourPercentage: parsed.tour,
          rentPercentage: parsed.rent,
          hotelPercentage: parsed.hotel,
          hotelMinimumBalance: minimum,
          hotelLowBalanceAlert: alert,
        }),
      });
      setCommission(parsed.city);
      setSaved(
        `Commission saved — city ${parsed.city}%, city to city ${parsed.intercity}%, tours ${parsed.tour}%, rent ${parsed.rent}%, hotel ${parsed.hotel}%.`,
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that.');
    }
  }

  async function saveWallet() {
    setError('');
    setSaved('');
    try {
      await apiFetch('/api/v1/admin/settings/wallet', {
        method: 'PUT',
        body: JSON.stringify({
          welcomeBonus: bonus,
          tourWelcomeBonus: kindBonus.tour,
          rentWelcomeBonus: kindBonus.rent,
          hotelWelcomeBonus: kindBonus.hotel,
          easypaisaNumber: easypaisa,
          accountName,
        }),
      });
      setSaved('Wallet settings updated.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that.');
    }
  }

  async function saveCard(next: Record<string, boolean>) {
    setCard(next);
    setError('');
    setSaved('');
    try {
      await apiFetch('/api/v1/admin/settings/offer-card', {
        method: 'PUT',
        body: JSON.stringify(next),
      });
      setSaved('Offer card updated.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that.');
    }
  }

  return (
    <AdminFrame
      title="Services"
      subtitle="Turn a service off for customers without hiding it from drivers."
    >
      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Driver offer card</h2>
            <p>
              What a customer sees on each offer. Ratings and ride counts are
              off to begin with — on a new platform they are 0.00 and 0 for
              everybody, and a zero beside a name reads as a bad driver rather
              than a new one. Turn them on when the numbers start meaning
              something.
            </p>
          </div>
        </header>

        <div style={{ padding: '4px 18px 18px' }}>
          {[
            ['vehiclePhoto', 'Vehicle photograph', "The driver's own, or the category picture"],
            ['driverPhoto', 'Driver photograph', 'From their approved selfie'],
            ['plate', 'Number plate', 'What the customer looks for at the kerb'],
            ['rating', 'Star rating', 'Hide until drivers have been rated'],
            ['rides', 'Rides completed', 'Hide until the numbers help'],
          ].map(([key, label, hint]) => (
            <div key={key} className="serviceRow" style={{ marginBottom: 8 }}>
              <div className="serviceRowHead">
                <div>
                  <strong>{label}</strong>
                  <small>{hint}</small>
                </div>
                <label className="serviceToggle">
                  <input
                    type="checkbox"
                    checked={card[key] ?? false}
                    onChange={(e) =>
                      void saveCard({ ...card, [key]: e.target.checked })
                    }
                  />
                  <span>{card[key] ? 'Shown' : 'Hidden'}</span>
                </label>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Wallet + welcome credit</h2>
            <p>
              Har kaam ka apna welcome credit, approve hone par wallet mein aik dafa
              (har kaam ka sirf pehli dafa). Neeche woh number jahan drivers aur hotel
              owners top-up bhejte hain.
            </p>
          </div>
        </header>

        <div style={{ padding: '4px 18px 18px', display: 'grid', gap: '12px' }}>
          <div style={{ display: 'grid', gap: 8 }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1.3fr 1fr 2fr', gap: 12, fontSize: 12, fontWeight: 800, color: '#5D7068' }}>
              <span>KAAM</span>
              <span>WELCOME CREDIT (PKR)</span>
              <span>KAB MILTA HAI</span>
            </div>
            {(
              [
                ['city', 'City rides', 'Driver + city gaari approve hone par (city + city to city)'],
                ['tour', 'Tour', 'Gaari tour ke liye approve hone par'],
                ['rent', 'Rent a car', 'Gaari rent ke liye approve hone par'],
                ['hotel', 'Hotel', 'Hotel approve hone par (hotel owner ka wallet)'],
              ] as const
            ).map(([key, label, when]) => (
              <div
                key={key}
                style={{ display: 'grid', gridTemplateColumns: '1.3fr 1fr 2fr', gap: 12, alignItems: 'center', borderTop: '1px solid #EDF2F0', paddingTop: 8 }}
              >
                <strong>{label}</strong>
                <input
                  type="number"
                  min={0}
                  max={20000}
                  aria-label={`${label} welcome credit`}
                  value={key === 'city' ? bonus : kindBonus[key]}
                  onChange={(e) => {
                    const value = Number(e.target.value);
                    if (key === 'city') setBonus(value);
                    else setKindBonus((current) => ({ ...current, [key]: value }));
                  }}
                  style={{ width: 120, height: 38, borderRadius: 10, border: '1px solid #D3DFDA', textAlign: 'center', fontWeight: 700 }}
                />
                <span style={{ color: '#5D7068', fontSize: 13 }}>{when}</span>
              </div>
            ))}
            <p className="pingNote" style={{ margin: 0 }}>
              0 likhein to us kaam ka credit band. Jo pehle mil chuka woh wapas nahi hota.
            </p>
          </div>
          <Field label="EasyPaisa number drivers send to">
            <input
              value={easypaisa}
              maxLength={24}
              placeholder="03xx xxxxxxx"
              onChange={(e) => setEasypaisa(e.target.value)}
            />
          </Field>
          <Field label="Name on that account">
            <input
              value={accountName}
              maxLength={120}
              onChange={(e) => setAccountName(e.target.value)}
            />
          </Field>
          <p className="pingNote" style={{ margin: 0 }}>
            Drivers see this number in Add funds, with a copy button. Changing
            it takes effect immediately — nothing is baked into the app.
          </p>
          <div>
            <button className="primaryButton" onClick={() => void saveWallet()}>
              <Save size={15} />
              Save wallet settings
            </button>
          </div>
        </div>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Commission</h2>
            <p>
              Har kaam ka apna %. Driver ke prepaid wallet se katta hai; hotel ki commission hotel owner ke wallet se. Pehle se kati hui commission
              nahi badalti.
            </p>
          </div>
        </header>
        <div style={{ padding: '4px 20px 18px', display: 'grid', gap: 10, maxWidth: 760 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1.3fr 1fr 2fr', gap: 12, fontSize: 12, fontWeight: 800, color: '#5D7068' }}>
            <span>KAAM</span>
            <span>COMMISSION %</span>
            <span>KAB KATEGA (WALLET SE)</span>
          </div>
          {(
            [
              ['city', 'City rides', 'Ride shuru hone par'],
              ['intercity', 'City to city', 'Ride shuru hone par'],
              ['tour', 'Tours', 'Tour shuru hone par'],
              ['rent', 'Rent a car', 'Driver ke accept karne par (customer cancel kare to wapas)'],
              ['hotel', 'Hotel', 'Booking confirm hone par, hotel owner ke wallet se'],
            ] as const
          ).map(([key, label, when]) => (
            <div
              key={key}
              style={{ display: 'grid', gridTemplateColumns: '1.3fr 1fr 2fr', gap: 12, alignItems: 'center', borderTop: '1px solid #EDF2F0', paddingTop: 10 }}
            >
              <strong>{label}</strong>
              <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <input
                  type="number"
                  min={0}
                  max={40}
                  step={0.5}
                  aria-label={`${label} commission percent`}
                  value={rates[key]}
                  onChange={(e) => setRates((current) => ({ ...current, [key]: e.target.value }))}
                  style={{ width: 80, height: 38, borderRadius: 10, border: '1px solid #D3DFDA', textAlign: 'center', fontWeight: 700 }}
                />
                %
              </label>
              <span style={{ color: '#5D7068', fontSize: 13 }}>{when}</span>
            </div>
          ))}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, borderTop: '1px solid #EDF2F0', paddingTop: 10 }}>
            <Field label="Hotel wallet — kam se kam (PKR)">
              <input type="number" min={0} value={hotelMin} onChange={(e) => setHotelMin(e.target.value)} />
            </Field>
            <Field label="Hotel wallet — kam hone ka alert (PKR)">
              <input type="number" min={0} value={hotelAlert} onChange={(e) => setHotelAlert(e.target.value)} />
            </Field>
            <p className="pingNote" style={{ margin: 0, gridColumn: 'span 2' }}>
              Hotel wallet &quot;kam se kam&quot; se neeche ho to hotel naye customers ko nazar nahi aata (pehle se
              confirm bookings chalti rahengi). Alert se neeche aaye to owner ko WhatsApp jata hai.
            </p>
          </div>
          <div>
            <button className="primaryButton" onClick={() => void saveCommission()}>
              <Save size={15} />
              Save commission
            </button>
          </div>
        </div>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Driver location updates</h2>
            <p>
              How often a driver&apos;s phone reports its position while a trip
              is live. The customer&apos;s map polls at the same rate.
              Faster is smoother and costs the driver battery and data; slower
              makes the car appear to jump between fixes.
            </p>
          </div>
        </header>

        <div className="pingRow">
          {[1, 2, 3, 5, 10, 15, 30].map((seconds) => (
            <button
              key={seconds}
              type="button"
              className={seconds === ping ? 'pingOn' : 'pingOff'}
              onClick={() => void savePing(seconds)}
            >
              {seconds}s
            </button>
          ))}
        </div>
        <p className="pingNote">
          Currently every {ping} second{ping === 1 ? '' : 's'}. Drivers pick this
          up when their next trip starts, so a change does not interrupt a trip
          already under way.
        </p>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>How far a request travels</h2>
            <p>
              A driver further than this from the pickup is never offered the
              job. Wider reaches more drivers and sends more of them a request
              they will not take; narrower is quieter and can leave a customer
              with nobody at all.
            </p>
          </div>
        </header>
        <div className="pingRow">
          {[1, 2, 3, 5, 8, 12, 20].map((km) => (
            <button
              key={km}
              type="button"
              className={km === requestKm ? 'pingOn' : 'pingOff'}
              onClick={() => void saveRadius(km, nearbyKm)}
            >
              {km} km
            </button>
          ))}
        </div>
        <p className="pingNote">Currently {requestKm} km.</p>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>How far customers see vehicles</h2>
            <p>
              What the home map shows around the customer. Keep it tighter than
              the request radius — a car shown eight kilometres away is a car
              nobody is waiting for, and an empty-looking map is more honest
              than a busy one that produces no driver.
            </p>
          </div>
        </header>
        <div className="pingRow">
          {[0.5, 1, 2, 3, 5, 8].map((km) => (
            <button
              key={km}
              type="button"
              className={km === nearbyKm ? 'pingOn' : 'pingOff'}
              onClick={() => void saveRadius(requestKm, km)}
            >
              {km} km
            </button>
          ))}
        </div>
        <p className="pingNote">Currently {nearbyKm} km.</p>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>Customer availability</h2>
            <p>
              A closed service still appears on the home screen, dimmed and
              badged, and cannot be opened. Drivers are unaffected — vehicles
              can be registered and verified while it is closed, so it has a
              fleet on the day you open it.
            </p>
          </div>
        </header>

        {error && <ErrorBox message={error} />}
        {saved && <p className="successNote">{saved}</p>}

        {busy ? (
          <Loading />
        ) : (
          <div style={{ padding: '4px 18px 18px' }}>
            {rows.map((row) => (
              <div key={row.serviceKey} className="serviceRow">
                <div className="serviceRowHead">
                  <div>
                    <strong>{NAMES[row.serviceKey] ?? row.serviceKey}</strong>
                    <small>
                      {row.isOpen
                        ? 'Open to customers'
                        : 'Coming soon — customers see the label'}
                    </small>
                  </div>

                  <label className="serviceToggle">
                    <input
                      type="checkbox"
                      checked={row.isOpen}
                      onChange={(e) =>
                        edit(row.serviceKey, { isOpen: e.target.checked })
                      }
                    />
                    <span>{row.isOpen ? 'Open' : 'Closed'}</span>
                  </label>
                </div>

                {/*
                  Only shown when closed. The label and the message describe a
                  state the service is not in while it is open, and editing them
                  then is editing something invisible.
                */}
                {!row.isOpen && (
                  <div className="serviceRowBody">
                    <Field label="Badge on the tile">
                      <input
                        value={row.badgeLabel}
                        maxLength={24}
                        onChange={(e) =>
                          edit(row.serviceKey, { badgeLabel: e.target.value })
                        }
                      />
                    </Field>
                    <Field label="What a customer is told on tapping">
                      <input
                        value={row.closedMessage}
                        maxLength={200}
                        onChange={(e) =>
                          edit(row.serviceKey, {
                            closedMessage: e.target.value,
                          })
                        }
                      />
                    </Field>
                    <p className="serviceNote">
                      Drivers can still register vehicles for this service.
                    </p>

                    {/*
                      The tile, as the customer will see it.

                      Badge text and a closed message are easy to write and
                      hard to picture, and the only way to check them used to
                      be to open the app on a phone. A tile drawn from the same
                      two fields answers it here: a badge that is too long to
                      fit is visible before it ships.
                    */}
                    <TilePreview
                      name={NAMES[row.serviceKey] ?? row.serviceKey}
                      badge={row.badgeLabel}
                    />
                  </div>
                )}

                <div className="serviceRowFoot">
                  <button
                    className="primaryButton"
                    disabled={saving === row.serviceKey}
                    onClick={() => void save(row)}
                  >
                    <Save size={15} />
                    {saving === row.serviceKey ? 'Saving…' : 'Save'}
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <WhatsAppOtpPanel />
    </AdminFrame>
  );
}

type OtpSettings = {
  provider: string;
  effectiveProvider: string;
  providerOverriddenByEnvironment: boolean;
  baseUrl: string;
  apiKeySet: boolean;
  apiKeyHint: string;
  sendPath: string;
  messageTemplate: string;
  testPhone: string;
  testCodeSet: boolean;
  lastTestOkAt: string | null;
  currentConfigTested: boolean;
};

type OtpTestResult = { delivered: boolean; statusCode: number | null; providerResponse: string };

/**
 * WhatsApp login codes through WA Engine.
 *
 * Order of use: paste the API key, Save (provider stays Development), send a
 * test to your own number, then choose WhatsApp and Save again. The server
 * refuses WhatsApp until the current key/URL/path has delivered a test, so a
 * typo cannot lock every user — and every admin — out of signing in.
 */
function WhatsAppOtpPanel() {
  const [s, setS] = useState<OtpSettings | null>(null);
  const [apiKey, setApiKey] = useState('');
  const [testPhone, setTestPhone] = useState('');
  const [testCode, setTestCode] = useState('');
  const [probe, setProbe] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');

  const apply = (x: OtpSettings) => {
    setS(x);
    setTestPhone(x.testPhone);
    setApiKey('');
    setTestCode('');
  };

  useEffect(() => {
    apiFetch<OtpSettings>('/api/v1/admin/otp-settings')
      .then(apply)
      .catch((e) => setError(e instanceof Error ? e.message : 'Could not load OTP settings.'));
  }, []);

  // Only the API key and the reviewer number ever change. The endpoint, path
  // and message text are fixed for WA Engine and stay on the server.
  async function save() {
    setBusy(true); setMsg(''); setError('');
    try {
      const saved = await apiFetch<OtpSettings>('/api/v1/admin/otp-settings', {
        method: 'PUT',
        body: JSON.stringify({
          apiKey: apiKey.trim() ? apiKey.trim() : null,
          testPhone,
          testCode: testCode.trim() ? testCode.trim() : null,
        }),
      });
      apply(saved);
      setMsg(saved.effectiveProvider === 'WhatsApp'
        ? 'Saved. Login codes are going out on WhatsApp.'
        : 'Saved. Send a test message to switch WhatsApp on.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Save failed.');
    } finally { setBusy(false); }
  }

  async function status() {
    setBusy(true); setMsg(''); setError('');
    try {
      const r = await apiFetch<OtpTestResult>('/api/v1/admin/otp-settings/status');
      if (r.delivered) setMsg(`WA Engine is connected. Reply: ${r.providerResponse || 'OK'}`);
      else setError(`WA Engine reported a problem (${r.statusCode ?? 'no response'}): ${r.providerResponse || 'empty reply'}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Status check failed.');
    } finally { setBusy(false); }
  }

  async function test() {
    if (!probe.trim()) { setError('Enter a WhatsApp number to send the test to.'); return; }
    setBusy(true); setMsg(''); setError('');
    try {
      const r = await apiFetch<OtpTestResult>('/api/v1/admin/otp-settings/test', {
        method: 'POST',
        body: JSON.stringify({ phoneNumber: probe.trim() }),
      });
      if (r.delivered) setMsg('Test message sent. WhatsApp login codes are now switched on.');
      else setError(`WA Engine did not accept it (${r.statusCode ?? 'no response'}): ${r.providerResponse || 'empty reply'}`);
      apply(await apiFetch<OtpSettings>('/api/v1/admin/otp-settings'));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Test failed.');
    } finally { setBusy(false); }
  }

  const live = s?.effectiveProvider === 'WhatsApp';

  return (
    <section className="panel">
      <header className="panelHeader">
        <div>
          <h2>WhatsApp OTP</h2>
          <p>
            Login codes go out on WhatsApp through WA Engine. Only the API key ever
            changes here: paste it, Save, then send yourself a test — WhatsApp switches
            on the moment the test arrives.
          </p>
        </div>
      </header>

      <div style={{ padding: '4px 18px 18px', display: 'grid', gap: '12px' }}>
        {error && <div className="errorBox">{error}</div>}
        {msg && <div className="successBox">{msg}</div>}
        {!s && !error && <Loading />}
        {s && (
          <>
            <p className="pingNote" style={{ margin: 0 }}>
              Login codes: <strong>{live ? 'WhatsApp — live' : 'Development code (WhatsApp off)'}</strong>
              {s.providerOverriddenByEnvironment && ' · forced by OTP_PROVIDER_OVERRIDE on the server'}
              {' · '}API key: {s.apiKeySet ? s.apiKeyHint : 'not set'}
              {s.lastTestOkAt && s.currentConfigTested
                ? ` · last test ${new Date(s.lastTestOkAt).toLocaleString()}`
                : ''}
            </p>

            <Field label={s.apiKeySet ? `WA Engine API key (saved ${s.apiKeyHint} — leave empty to keep)` : 'WA Engine API key'}>
              <input type="password" autoComplete="new-password" value={apiKey} placeholder="WA-XXXXXXXX…"
                onChange={(e) => setApiKey(e.target.value)} />
            </Field>

            <Field label="Google Play reviewer number (always accepts the reviewer code, nothing is sent)">
              <input value={testPhone} placeholder="03001234567" onChange={(e) => setTestPhone(e.target.value)} />
            </Field>
            <Field label={s.testCodeSet ? 'Reviewer code (saved — leave empty to keep)' : 'Reviewer code (4 digits)'}>
              <input type="password" inputMode="numeric" maxLength={4} value={testCode}
                onChange={(e) => setTestCode(e.target.value.replace(/\D/g, ''))} />
            </Field>

            <div>
              <button className="primaryButton" disabled={busy} onClick={() => void save()}>
                <Save size={15} />
                {busy ? 'Working…' : 'Save'}
              </button>
            </div>

            <Field label="Send a test message to (your WhatsApp number)">
              <input value={probe} placeholder="03xx xxxxxxx" onChange={(e) => setProbe(e.target.value)} />
            </Field>
            <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
              <button className="primaryButton" disabled={busy || !s.apiKeySet} onClick={() => void test()}>
                Send test message
              </button>
              <button className="primaryButton" disabled={busy || !s.apiKeySet} onClick={() => void status()}>
                Check WA connection
              </button>
            </div>
          </>
        )}
      </div>
    </section>
  );
}


/**
 * How a closed service looks on the customer's home screen.
 *
 * Deliberately plain: this is a check on the words, not a rendering of the
 * app. It shows the two things an Admin is choosing — the tile's name and the
 * badge sitting on it — at the size they will appear, dimmed the way a closed
 * tile is dimmed.
 */
function TilePreview({ name, badge }: { name: string; badge: string }) {
  return (
    <div className="tilePreview">
      <span className="tilePreviewCaption">On the customer&apos;s home screen</span>
      <div className="tilePreviewTile">
        <span className="tilePreviewBadge">{badge || 'SOON'}</span>
        <span className="tilePreviewName">{name}</span>
      </div>
    </div>
  );
}
