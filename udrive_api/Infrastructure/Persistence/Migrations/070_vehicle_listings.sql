-- "Earn with your vehicle": owners list cars for rent and tours in three steps.
--
-- Until now the only way to put a vehicle on UDrive was the full Driver sign-up
-- (licence, CNIC, four document photos, two admin approvals in a fixed order),
-- even for a rent-a-car owner who never drives a customer anywhere. This adds a
-- lighter path beside it, without changing the Driver one:
--
--   * an owner profile — a driver_profiles row marked profile_kind = 'Owner' —
--     that needs a CNIC and a selfie, and a licence only if the owner drives;
--   * fleet_drivers: the people an owner lets drive customers. Each one has
--     their own CNIC, licence (with expiry) and selfie, uploaded from their own
--     phone, and is approved by an admin before they can be given a booking;
--   * rentals that wait for the owner: a booking starts as PendingOwner, the
--     owner is told on WhatsApp, and confirms or rejects. No answer in time
--     and it expires, advance refunded;
--   * handover and return records (four photos, odometer, fuel) on the booking;
--   * days the owner blocks on the rent calendar;
--   * the driver assigned to a rental or a tour departure.
--
-- Listing vehicles reuse udrive.vehicles and udrive.driver_profiles, so every
-- existing search (rent, tours) finds them once approved, with no second list
-- to keep in step.

-- ───────────────────────────────────────────── 1. the owner profile

ALTER TABLE udrive.driver_profiles
    ADD COLUMN IF NOT EXISTS profile_kind varchar(16) NOT NULL DEFAULT 'Driver',
    ADD COLUMN IF NOT EXISTS drives_self boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS owner_agreement_version integer,
    ADD COLUMN IF NOT EXISTS owner_agreement_accepted_at timestamptz;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_driver_profiles_kind') THEN
        ALTER TABLE udrive.driver_profiles
            ADD CONSTRAINT ck_driver_profiles_kind CHECK (profile_kind IN ('Driver', 'Owner'));
    END IF;
END $$;

-- ───────────────────────────────────────────── 2. what a listing asked for

ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS listed_via varchar(16) NOT NULL DEFAULT 'Driver',
    ADD COLUMN IF NOT EXISTS listing_wants_rent boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS listing_wants_tour boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS listing_submitted_at timestamptz,
    ADD COLUMN IF NOT EXISTS listing_review_note varchar(500),
    ADD COLUMN IF NOT EXISTS listing_added_by uuid REFERENCES udrive.users(id);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_vehicles_listed_via') THEN
        ALTER TABLE udrive.vehicles
            ADD CONSTRAINT ck_vehicles_listed_via CHECK (listed_via IN ('Driver', 'Listing', 'Staff'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_vehicles_listing_review
    ON udrive.vehicles (status, listing_submitted_at)
    WHERE listed_via IN ('Listing', 'Staff');

-- ───────────────────────────────────────────── 3. an owner's drivers

CREATE TABLE IF NOT EXISTS udrive.fleet_drivers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    -- The driver's own account, filled when they open the invite on their
    -- phone. The owner's own row has it from the start.
    user_id uuid REFERENCES udrive.users(id),
    phone_number varchar(20) NOT NULL,
    full_name varchar(120) NOT NULL,
    -- The owner, when the owner drives. One per owner.
    is_owner boolean NOT NULL DEFAULT false,
    status varchar(16) NOT NULL DEFAULT 'Invited',
    licence_number varchar(40),
    licence_expiry date,
    cnic_front_url text,
    cnic_back_url text,
    licence_front_url text,
    licence_back_url text,
    selfie_url text,
    agreement_version integer,
    agreement_accepted_at timestamptz,
    submitted_at timestamptz,
    reviewed_by uuid REFERENCES udrive.users(id),
    reviewed_at timestamptz,
    review_note varchar(500),
    expiry_reminded_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_fleet_drivers_status
        CHECK (status IN ('Invited', 'Submitted', 'Approved', 'Rejected', 'Removed', 'Declined'))
);

-- One live row per phone per owner; a removed or declined driver can be invited again.
CREATE UNIQUE INDEX IF NOT EXISTS ux_fleet_drivers_owner_phone
    ON udrive.fleet_drivers (owner_profile_id, phone_number)
    WHERE status NOT IN ('Removed', 'Declined');

CREATE UNIQUE INDEX IF NOT EXISTS ux_fleet_drivers_owner_self
    ON udrive.fleet_drivers (owner_profile_id)
    WHERE is_owner AND status NOT IN ('Removed', 'Declined');

CREATE INDEX IF NOT EXISTS ix_fleet_drivers_phone ON udrive.fleet_drivers (phone_number);
CREATE INDEX IF NOT EXISTS ix_fleet_drivers_status ON udrive.fleet_drivers (status, submitted_at);

-- ───────────────────────────────────────────── 4. rentals wait for the owner

ALTER TABLE udrive.rental_bookings
    ADD COLUMN IF NOT EXISTS owner_respond_by timestamptz,
    ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
    ADD COLUMN IF NOT EXISTS owner_notified_at timestamptz,
    ADD COLUMN IF NOT EXISTS owner_reminded_at timestamptz,
    ADD COLUMN IF NOT EXISTS fleet_driver_id uuid REFERENCES udrive.fleet_drivers(id),
    ADD COLUMN IF NOT EXISTS handover_json jsonb,
    ADD COLUMN IF NOT EXISTS return_json jsonb,
    ADD COLUMN IF NOT EXISTS handed_over_at timestamptz,
    ADD COLUMN IF NOT EXISTS returned_at timestamptz;

ALTER TABLE udrive.rental_bookings DROP CONSTRAINT IF EXISTS ck_rental_status;
ALTER TABLE udrive.rental_bookings
    ADD CONSTRAINT ck_rental_status CHECK (status IN (
        'PendingOwner', 'Confirmed', 'HandedOver', 'Returned',
        'Cancelled', 'NoShow', 'Declined', 'Expired'));

-- A request waiting for the owner holds the days too: two customers must not
-- both be told "waiting for the owner" for the same car on the same dates.
DROP INDEX IF EXISTS udrive.ix_rental_bookings_vehicle_dates;
CREATE INDEX IF NOT EXISTS ix_rental_bookings_vehicle_dates_live
    ON udrive.rental_bookings (vehicle_id, start_date, end_date)
    WHERE status IN ('PendingOwner', 'Confirmed', 'HandedOver');

CREATE INDEX IF NOT EXISTS ix_rental_bookings_pending_owner
    ON udrive.rental_bookings (owner_respond_by)
    WHERE status = 'PendingOwner';

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gist') THEN
        ALTER TABLE udrive.rental_bookings DROP CONSTRAINT IF EXISTS ex_rental_bookings_no_overlap;
        ALTER TABLE udrive.rental_bookings
            ADD CONSTRAINT ex_rental_bookings_no_overlap
            EXCLUDE USING gist (
                vehicle_id WITH =,
                daterange(start_date, end_date, '[]') WITH &&
            ) WHERE (status IN ('PendingOwner', 'Confirmed', 'HandedOver'));
    END IF;
END $$;

-- ───────────────────────────────────────────── 5. days the owner blocks

CREATE TABLE IF NOT EXISTS udrive.rental_blocked_days (
    vehicle_id uuid NOT NULL REFERENCES udrive.vehicles(id) ON DELETE CASCADE,
    day date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (vehicle_id, day)
);

-- ───────────────────────────────────────────── 6. the driver on a departure

ALTER TABLE udrive.tour_packages
    ADD COLUMN IF NOT EXISTS fleet_driver_id uuid REFERENCES udrive.fleet_drivers(id),
    ADD COLUMN IF NOT EXISTS posted_as_daily boolean NOT NULL DEFAULT false;

-- ───────────────────────────────────────────── 7. settings

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('rental.owner_response_minutes', to_jsonb(120),
     'Minutes an owner has to confirm a new rental before it expires and the advance is refunded.',
     false, now(), now()),
    ('rental.owner_response_short_minutes', to_jsonb(30),
     'The same, when the rental starts within rental.short_notice_hours.',
     false, now(), now()),
    ('rental.short_notice_hours', to_jsonb(6),
     'A rental starting within this many hours gets the short answer window.',
     false, now(), now()),
    ('listing.agreement_version', to_jsonb(1),
     'Version of the vehicle owner and driver agreements. Raise it when either text changes.',
     true, now(), now()),
    ('listing.owner_agreement_en', to_jsonb(
        'I own this vehicle or have the owner''s written permission to list it, and the details I give are true. '
        || 'The vehicle''s registration, fitness, token tax and insurance are my responsibility and will be valid whenever it carries a UDrive customer. '
        || 'Only drivers approved on UDrive will drive UDrive customers in it, and I am responsible for the conduct of anyone I let drive it. '
        || 'UDrive is a marketplace that checks documents; it does not own, operate or insure the vehicle.'),
     'Vehicle owner agreement shown in the app, English.', true, now(), now()),
    ('listing.driver_agreement_en', to_jsonb(
        'I hold a valid driving licence for this class of vehicle and will keep it valid. '
        || 'I will drive UDrive customers safely, within the law, and only when I am assigned to the booking in the app. '
        || 'The documents I upload are mine and true. UDrive may stop my access if they are not, or if my licence expires.'),
     'Driver agreement shown in the app, English.', true, now(), now())
ON CONFLICT (key) DO NOTHING;
