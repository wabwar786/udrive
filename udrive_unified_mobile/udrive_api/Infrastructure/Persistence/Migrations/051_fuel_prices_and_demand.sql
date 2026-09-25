-- Fuel prices, and the demand snapshot the surge multiplier is read from.
--
-- Both are inputs to the fare engine, and both are inert until there is data:
-- with no fuel price recorded the fuel factor is 1.0, and with too few
-- requests or drivers to measure, the surge multiplier is 1.0.

-- ----------------------------------------------------------------- fuel
--
-- Pakistan revises pump prices roughly every fortnight, so this is a short
-- table that grows a couple of rows a month. The current price is the newest
-- row whose effective_from has arrived.
CREATE TABLE IF NOT EXISTS udrive.fuel_prices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    fuel_type varchar(16) NOT NULL,
    price_per_litre numeric(10,2) NOT NULL,
    effective_from date NOT NULL,
    source varchar(200),
    created_by_user_id uuid REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fuel_prices_price_positive CHECK (price_per_litre > 0),
    CONSTRAINT fuel_prices_type_known CHECK (fuel_type IN ('Petrol', 'Diesel')),
    CONSTRAINT fuel_prices_unique_day UNIQUE (fuel_type, effective_from)
);

CREATE INDEX IF NOT EXISTS ix_fuel_prices_current
    ON udrive.fuel_prices(fuel_type, effective_from DESC);

-- The baselines are the pump prices that the rate card was set against. The
-- index is current / baseline, so while they match, every fare is exactly what
-- it is today.
--
-- Both are seeded as 0, which the engine reads as "no baseline set" and
-- answers with a factor of 1.0. Setting them is a deliberate act: the moment a
-- baseline exists, fares start moving with the pump.
INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('pricing.fuel.baseline.petrol', '0'::jsonb,
     'Petrol price per litre that the current rate card was set against. 0 disables fuel indexing.',
     false, now(), now()),
    ('pricing.fuel.baseline.diesel', '0'::jsonb,
     'Diesel price per litre that the current rate card was set against. 0 disables fuel indexing.',
     false, now(), now()),
    ('pricing.fuel.factor.min', '0.85'::jsonb,
     'Floor on the fuel index, so a crash in pump prices cannot gut every fare.',
     false, now(), now()),
    ('pricing.fuel.factor.max', '1.25'::jsonb,
     'Ceiling on the fuel index, so a spike cannot price the platform out of the market overnight.',
     false, now(), now())
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------- demand
--
-- A rolling record of how many open requests and how many online drivers a
-- zone had. The multiplier is computed live at quote time; this table is the
-- history behind it, so a rate that looks wrong next month can be explained.
CREATE TABLE IF NOT EXISTS udrive.zone_demand_snapshots (
    zone_id uuid NOT NULL REFERENCES udrive.pricing_zones(id) ON DELETE CASCADE,
    captured_at timestamptz NOT NULL,
    open_requests integer NOT NULL,
    online_drivers integer NOT NULL,
    ratio numeric(8,3) NOT NULL,
    multiplier numeric(5,3) NOT NULL,
    PRIMARY KEY (zone_id, captured_at)
);

CREATE INDEX IF NOT EXISTS ix_zone_demand_snapshots_time
    ON udrive.zone_demand_snapshots(captured_at DESC);

-- Surge thresholds, as steps rather than a curve.
--
-- Steps because a multiplier that slides continuously is one nobody can
-- predict or explain, and because a fare that moves every time the page is
-- refreshed reads as the app making it up.
--
-- The sample floors matter more than the thresholds. Early on there will be
-- two requests and one driver in a zone on a quiet evening, which is a ratio
-- of 2.0 and means nothing at all. Below these counts the multiplier stays at
-- 1.0 rather than inventing a shortage.
INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('pricing.surge.enabled', 'false'::jsonb,
     'Master switch. Off until there are enough drivers online for the ratio to mean anything.',
     false, now(), now()),
    ('pricing.surge.request_window_minutes', '15'::jsonb,
     'How far back open ride requests are counted when measuring demand.',
     false, now(), now()),
    ('pricing.surge.driver_window_minutes', '5'::jsonb,
     'How recently a driver must have reported a position to count as online.',
     false, now(), now()),
    ('pricing.surge.min_requests', '5'::jsonb,
     'Fewest open requests in the window before a shortage is believed.',
     false, now(), now()),
    ('pricing.surge.min_drivers', '3'::jsonb,
     'Fewest online drivers in the window before a shortage is believed.',
     false, now(), now()),
    ('pricing.surge.steps', '[{"ratio":1.0,"multiplier":1.15},{"ratio":2.0,"multiplier":1.30},{"ratio":3.0,"multiplier":1.50}]'::jsonb,
     'Demand steps. Each entry raises the multiplier once requests-per-driver reaches its ratio. Highest matching step wins.',
     false, now(), now()),
    ('pricing.surge.minimum_share', '0.5'::jsonb,
     'How much of the surge applies to the floor as opposed to the suggested fare. 0.5 means the suggestion rises twice as fast as the minimum, so a customer in a busy area is guided up but not forced up.',
     false, now(), now())
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE udrive.fuel_prices IS
    'Pump prices by fuel type. The newest row on or before today is current.';
COMMENT ON TABLE udrive.zone_demand_snapshots IS
    'History of requests-per-driver by zone, behind the surge multiplier.';
