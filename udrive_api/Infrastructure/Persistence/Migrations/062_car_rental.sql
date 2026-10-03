-- Car rental: renting a Driver's own vehicle by the day.
--
-- Deliberately small. One new table, four columns on an existing one, three
-- settings — no photo table, no customer-document table, no review queue. Every
-- one of those was considered and dropped, and the reasoning is at each place
-- it was dropped, because a schema grows by nobody asking "do we need this".
--
-- Migration 061 already built the half a Driver sets: available_for_rent and
-- the seven rent_* columns. This is the half a Customer uses.

-- ──────────────────────────────────────────────── 1. the booking itself

-- btree_gist, so one index can hold both a uuid and a date range.
--
-- Wrapped because an extension needs rights a managed Postgres may not grant.
-- Without it the exclusion constraint below is skipped and the service's row
-- lock is the only thing keeping two bookings off one vehicle — which works,
-- but is a promise made in code rather than by the database. Failing the whole
-- migration over it would be worse.
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS btree_gist;
EXCEPTION WHEN insufficient_privilege OR feature_not_supported THEN
    RAISE NOTICE 'btree_gist unavailable; rental overlap rests on the row lock.';
END $$;

CREATE TABLE IF NOT EXISTS udrive.rental_bookings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_reference varchar(32) NOT NULL UNIQUE,
    vehicle_id uuid NOT NULL REFERENCES udrive.vehicles(id),
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id),
    customer_user_id uuid NOT NULL REFERENCES udrive.users(id),

    -- Dates, not timestamps. A rental is counted in days by everyone involved:
    -- the rate is per day, the minimum is in days, and the argument at handover
    -- is about days. Storing an hour nobody agreed on would invent precision.
    start_date date NOT NULL,
    end_date date NOT NULL,

    -- 'WithDriver' or 'SelfDrive'. This decides whether the Customer's
    -- documents are needed at all, and whether the Driver is blocked along with
    -- the vehicle.
    rental_mode varchar(16) NOT NULL,

    daily_rate numeric(12,2) NOT NULL,
    days integer NOT NULL,
    subtotal numeric(12,2) NOT NULL,

    -- Recorded, never collected.
    --
    -- The deposit is paid in cash to the owner at handover and returned by the
    -- owner at the end. UDrive holding it would make the platform the custodian
    -- of other people's money and put every argument about a scratch on the
    -- bumper through our support queue, which helps nobody and earns nothing.
    -- It is stored so both sides see the same figure before they meet.
    security_deposit numeric(12,2) NOT NULL DEFAULT 0,

    -- What the Customer pays now, and what is left for the owner at handover.
    advance_amount numeric(12,2) NOT NULL DEFAULT 0,
    balance_due numeric(12,2) NOT NULL DEFAULT 0,

    km_per_day integer,
    fuel_included boolean NOT NULL DEFAULT false,
    pickup_point varchar(200),

    status varchar(24) NOT NULL DEFAULT 'Confirmed',
    cancelled_at timestamptz,
    cancelled_by varchar(16),
    cancel_reason varchar(500),

    -- The disclaimer, as two columns rather than a table of its own.
    --
    -- A separate acceptances table was the obvious shape and it buys nothing: a
    -- booking has exactly one acceptance, made at the moment it is created, and
    -- the only question ever asked of it is "which text did they agree to".
    -- The version answers that, and the text of every version lives in the
    -- repository where it can be read.
    disclaimer_version integer NOT NULL DEFAULT 1,
    disclaimer_accepted_at timestamptz NOT NULL DEFAULT now(),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT ck_rental_dates CHECK (end_date >= start_date),
    CONSTRAINT ck_rental_mode CHECK (rental_mode IN ('WithDriver', 'SelfDrive')),
    CONSTRAINT ck_rental_status
        CHECK (status IN ('Confirmed', 'HandedOver', 'Returned', 'Cancelled', 'NoShow')),
    CONSTRAINT ck_rental_amounts CHECK (
        daily_rate > 0 AND days >= 1 AND subtotal >= 0
        AND security_deposit >= 0 AND advance_amount >= 0 AND balance_due >= 0)
);

CREATE INDEX IF NOT EXISTS ix_rental_bookings_vehicle_dates
    ON udrive.rental_bookings (vehicle_id, start_date, end_date)
    WHERE status IN ('Confirmed', 'HandedOver');

CREATE INDEX IF NOT EXISTS ix_rental_bookings_customer
    ON udrive.rental_bookings (customer_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_rental_bookings_driver
    ON udrive.rental_bookings (driver_profile_id, start_date);

-- Two live bookings cannot touch the same vehicle on the same day.
--
-- The service locks the vehicle row before it writes, which is enough in
-- ordinary use. This is for the case the lock cannot see: two application
-- instances, two requests, the same car, the same week. A double-booked rental
-- is not a glitch to apologise for — one of the two customers turns up to find
-- the car gone.
--
-- Skipped silently when btree_gist is not installed.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gist')
       AND NOT EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conname = 'ex_rental_bookings_no_overlap')
    THEN
        ALTER TABLE udrive.rental_bookings
            ADD CONSTRAINT ex_rental_bookings_no_overlap
            EXCLUDE USING gist (
                vehicle_id WITH =,
                daterange(start_date, end_date, '[]') WITH &&
            ) WHERE (status IN ('Confirmed', 'HandedOver'));
    END IF;
END $$;

-- ───────────────────────────────────────── 2. the Customer's documents

-- Four columns on customer_profiles, not a customer_documents table.
--
-- A table would have brought a status, a reviewer, review notes and a queue —
-- the whole driver-verification machine — for something nobody reviews. Nobody
-- reviews it on purpose: the person handing over the car checks the documents
-- against the person standing in front of them, which is the only check that
-- actually proves anything. An Admin looking at a photograph of a CNIC a week
-- earlier proves nothing and makes the platform look responsible for it.
--
-- Asked once. The second rental does not ask again.
ALTER TABLE udrive.customer_profiles
    ADD COLUMN IF NOT EXISTS cnic_front_url text,
    ADD COLUMN IF NOT EXISTS cnic_back_url text,
    ADD COLUMN IF NOT EXISTS driving_licence_url text,
    ADD COLUMN IF NOT EXISTS selfie_url text,
    ADD COLUMN IF NOT EXISTS documents_updated_at timestamptz;

-- ─────────────────────────────────────────────────────── 3. the settings

-- What the Customer pays through the platform at booking.
--
-- Twenty per cent, not the whole rent. The rest and the deposit are cash to the
-- owner at handover. The advance exists to make a booking cost something to
-- break — a free booking is a reservation nobody honours — not to move the
-- whole transaction onto the platform.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'rental.advance_percent',
    to_jsonb(20),
    'Percentage of the rent a Customer pays at booking. The balance and the '
    || 'security deposit are paid to the owner at handover.',
    true, now(), now())
ON CONFLICT (key) DO NOTHING;

-- How long before the start a Customer may cancel and get the advance back.
--
-- Forty-eight hours is the point where the owner can still sell those days to
-- somebody else. Inside it the advance goes to the owner, who turned other
-- bookings away. An owner who cancels refunds in full whenever they do it, and
-- it counts against them: they are the one who made a promise.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'rental.free_cancel_hours',
    to_jsonb(48),
    'Hours before the rental starts within which a Customer cancellation still '
    || 'returns the advance in full.',
    true, now(), now())
ON CONFLICT (key) DO NOTHING;

-- Which disclaimer text is current.
--
-- Stamped onto every booking. Raise it whenever the wording changes, and old
-- bookings keep pointing at the text their Customer actually read.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'rental.disclaimer_version',
    to_jsonb(1),
    'The version of the rental disclaimer a new booking records. Raise it when '
    || 'the wording changes; existing bookings keep the version they accepted.',
    true, now(), now())
ON CONFLICT (key) DO NOTHING;
