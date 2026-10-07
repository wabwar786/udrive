-- Tour and rent bookings go straight through; a full vehicle takes waiting-list
-- requests the driver can accept when a place frees up.
--
-- 1. package_waitlist: when the driver accepts a request, the seats are held
--    for that customer (hold_id) until accept_expires_at. Status 'Notified'
--    is reused for "accepted, waiting for the customer to pay the advance",
--    so the existing one-open-request-per-customer index still holds.
-- 2. rental_waitlist: the same thing for a rent-a-car vehicle that is booked
--    on the customer's dates.
-- 3. waitlist.accept_hold_minutes: how long an accepted customer has to pay.
--
-- Safe to run more than once.

-- ───────────────────────────────────────────── 1. tour waiting list

ALTER TABLE udrive.package_waitlist
    ADD COLUMN IF NOT EXISTS hold_id uuid,
    ADD COLUMN IF NOT EXISTS accept_expires_at timestamptz,
    ADD COLUMN IF NOT EXISTS responded_at timestamptz;

-- ───────────────────────────────────────────── 2. rent waiting list

CREATE TABLE IF NOT EXISTS udrive.rental_waitlist (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id uuid NOT NULL REFERENCES udrive.vehicles(id) ON DELETE CASCADE,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    customer_user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    start_date date NOT NULL,
    end_date date NOT NULL,
    rental_mode varchar(16) NOT NULL,
    -- Waiting → Accepted (driver said yes, customer has until accept_expires_at
    -- to book) → Booked; or Declined / Cancelled / Expired.
    status varchar(16) NOT NULL DEFAULT 'Waiting',
    accept_expires_at timestamptz,
    responded_at timestamptz,
    rental_booking_id uuid,
    notes varchar(500),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_rental_waitlist_dates CHECK (end_date >= start_date),
    CONSTRAINT ck_rental_waitlist_mode CHECK (rental_mode IN ('WithDriver', 'SelfDrive')),
    CONSTRAINT ck_rental_waitlist_status CHECK (
        status IN ('Waiting', 'Accepted', 'Booked', 'Declined', 'Cancelled', 'Expired'))
);

CREATE INDEX IF NOT EXISTS ix_rental_waitlist_driver
    ON udrive.rental_waitlist (driver_profile_id, status, start_date);

CREATE UNIQUE INDEX IF NOT EXISTS ux_rental_waitlist_customer_open
    ON udrive.rental_waitlist (vehicle_id, customer_user_id)
    WHERE status IN ('Waiting', 'Accepted');

-- ───────────────────────────────────────────── 3. setting

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES ('waitlist.accept_hold_minutes', to_jsonb('120'::text),
        'After a driver accepts a waiting-list request, how many minutes the customer has to pay the advance.',
        true, now(), now())
ON CONFLICT (key) DO NOTHING;
