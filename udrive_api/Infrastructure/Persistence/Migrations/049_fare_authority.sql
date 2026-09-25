-- Fare authority: the server prices the trip, and keeps the band it quoted.
--
-- Until now every fare was worked out in Flutter and the API stored whatever
-- it was handed. ValidateRideRequest never mentioned customer_offer and
-- SubmitDriverOfferAsync never compared an offer to it, so a PKR 1 ride
-- request and a PKR 1 driver offer were both valid. Every minimum an admin set
-- was a suggestion the client could ignore — and two different client screens
-- ignored it in two different ways.
--
-- Nothing in this file changes a single fare on the day it ships. Every new
-- column defaults to the value that reproduces today's arithmetic.

-- ---------------------------------------------------------------- base fare
--
-- The flagfall. Its absence is the reason the per-km rate does nothing inside
-- a city: with Car at 65/km, 2/min and a 1600 floor, the meter does not clear
-- the floor until roughly 23 km — so every car ride in Muzaffarabad costs
-- exactly 1600 and the distance rate is decorative. A base fare is what lets
-- the floor come down without short rides becoming free.
--
-- Defaults to 0. Until an admin sets one, the meter is what it always was.
ALTER TABLE udrive.service_vehicle_rates
    ADD COLUMN IF NOT EXISTS base_fare numeric(12,2) NOT NULL DEFAULT 0;

ALTER TABLE udrive.pricing_rules
    ADD COLUMN IF NOT EXISTS base_fare numeric(12,2) NOT NULL DEFAULT 0;

-- --------------------------------------------------------------- fuel type
--
-- Which pump price moves this vehicle. Coster and Hiace run on diesel here,
-- and diesel does not track petrol.
ALTER TABLE udrive.service_vehicle_rates
    ADD COLUMN IF NOT EXISTS fuel_type varchar(16) NOT NULL DEFAULT 'Petrol';

UPDATE udrive.service_vehicle_rates
SET fuel_type = 'Diesel', updated_at = now()
WHERE lower(vehicle_category) IN ('coster', 'hiace')
  AND fuel_type <> 'Diesel';

-- ---------------------------------------------------------- seat capacity
--
-- How many seats this category sells. The per-seat price is the whole-vehicle
-- price shared across the capacity, so the server cannot work one out without
-- it — and the client has been using a capacity compiled into Dart, which is
-- why a Hiace priced as a twelve-seater whatever the actual vehicle held.
ALTER TABLE udrive.service_vehicle_rates
    ADD COLUMN IF NOT EXISTS seat_capacity integer NOT NULL DEFAULT 4;

UPDATE udrive.service_vehicle_rates
SET seat_capacity = CASE lower(vehicle_category)
        WHEN 'bike' THEN 1
        WHEN 'rickshaw' THEN 3
        WHEN 'car' THEN 4
        WHEN 'hiace' THEN 12
        WHEN 'coster' THEN 22
        ELSE seat_capacity
    END,
    updated_at = now()
WHERE lower(vehicle_category) IN ('bike', 'rickshaw', 'car', 'hiace', 'coster');

-- ------------------------------------------------------------- the quote
--
-- What the server told this customer the band was. Written at create time and
-- read later when a driver offers, so the driver is held to the same floor the
-- customer was.
--
-- Nullable on purpose: rows created before this ships have no quote, and an
-- older app build still posts without one. Code that reads these must treat
-- NULL as "no band was quoted" and skip the check rather than refuse the ride.
ALTER TABLE udrive.ride_requests
    ADD COLUMN IF NOT EXISTS quoted_minimum numeric(12,2),
    ADD COLUMN IF NOT EXISTS quoted_recommended numeric(12,2),
    ADD COLUMN IF NOT EXISTS quoted_maximum numeric(12,2),
    ADD COLUMN IF NOT EXISTS quoted_surge numeric(5,3),
    ADD COLUMN IF NOT EXISTS quote_id uuid;

-- ------------------------------------------------------------- constraints
--
-- pricing_rules.per_km_rate has had a positive constraint since 035;
-- minimum_fare has had DEFAULT 0 and nothing at all. Zero is a legitimate
-- "this rule sets no floor", which is why this is >= rather than >, but a
-- negative minimum would subtract money from a fare and there was nothing
-- stopping one being typed.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'pricing_rules_minimum_nonneg'
    ) THEN
        ALTER TABLE udrive.pricing_rules
            ADD CONSTRAINT pricing_rules_minimum_nonneg CHECK (minimum_fare >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'service_vehicle_rates_base_nonneg'
    ) THEN
        ALTER TABLE udrive.service_vehicle_rates
            ADD CONSTRAINT service_vehicle_rates_base_nonneg CHECK (base_fare >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'pricing_rules_base_nonneg'
    ) THEN
        ALTER TABLE udrive.pricing_rules
            ADD CONSTRAINT pricing_rules_base_nonneg CHECK (base_fare >= 0);
    END IF;
END $$;

-- --------------------------------------------------------------- settings
--
-- The knobs that govern the band. All of them are read at quote time, so a
-- change takes effect on the next quote without a deploy.
INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('pricing.quote.ttl_minutes', '15'::jsonb,
     'How long a fare quote stays valid. A quote older than this is refused and the app asks for a new one.',
     false, now(), now()),
    ('pricing.offer.ceiling_multiplier', '3'::jsonb,
     'The most a customer may offer, as a multiple of the recommended fare. Stops a mistyped amount becoming a booking.',
     false, now(), now()),
    ('pricing.distance.max_detour_ratio', '4.0'::jsonb,
     'The most the claimed road distance may exceed the straight-line distance. Guards against a client understating a trip to pull the floor down. Generous on purpose: a mountain road that switchbacks over a pass can be three times the straight line, and Leepa is reached over one.',
     false, now(), now()),
    ('pricing.rounding.step', '5'::jsonb,
     'Fares are shown rounded to this many rupees. Always rounded up, so a rounded fare can never fall below the floor it was clamped to.',
     false, now(), now()),
    ('pricing.quote.required', 'false'::jsonb,
     'Whether a ride request must carry a signed fare quote. Ships off so app builds already installed keep working; turn it on once the build that sends one has rolled out.',
     false, now(), now()),
    ('pricing.per_seat.margin', '1.35'::jsonb,
     'What one seat costs relative to its share of the whole vehicle. Above 1 because a vehicle sold seat by seat rarely leaves full, and the driver carries the empty ones. This was a constant in Dart; it belongs here.',
     false, now(), now())
ON CONFLICT (key) DO NOTHING;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'service_vehicle_rates_capacity_positive'
    ) THEN
        ALTER TABLE udrive.service_vehicle_rates
            ADD CONSTRAINT service_vehicle_rates_capacity_positive
            CHECK (seat_capacity > 0 AND seat_capacity <= 60);
    END IF;
END $$;

COMMENT ON COLUMN udrive.service_vehicle_rates.base_fare IS
    'Flagfall in rupees, charged once per trip before distance and time.';
COMMENT ON COLUMN udrive.service_vehicle_rates.fuel_type IS
    'Petrol or Diesel. Selects which pump price indexes this vehicle''s rates.';
COMMENT ON COLUMN udrive.ride_requests.quoted_minimum IS
    'The floor the server quoted for this trip. NULL for rows created before fare authority shipped; treat NULL as no floor.';
