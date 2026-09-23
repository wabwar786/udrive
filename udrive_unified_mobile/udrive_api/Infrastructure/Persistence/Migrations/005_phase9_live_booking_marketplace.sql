ALTER TABLE udrive.ride_requests
    ADD COLUMN IF NOT EXISTS return_at timestamptz,
    ADD COLUMN IF NOT EXISTS party_type varchar(32) NOT NULL DEFAULT 'Family',
    ADD COLUMN IF NOT EXISTS women_only boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS notes varchar(1000),
    ADD COLUMN IF NOT EXISTS expires_at timestamptz,
    ADD COLUMN IF NOT EXISTS selected_offer_id uuid,
    ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 0;

ALTER TABLE udrive.driver_offers
    ADD COLUMN IF NOT EXISTS counter_amount numeric(12,2),
    ADD COLUMN IF NOT EXISTS responded_at timestamptz,
    ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 0;

ALTER TABLE udrive.bookings
    ADD COLUMN IF NOT EXISTS booking_reference varchar(32),
    ADD COLUMN IF NOT EXISTS return_at timestamptz,
    ADD COLUMN IF NOT EXISTS pickup_label varchar(240),
    ADD COLUMN IF NOT EXISTS destination_label varchar(240),
    ADD COLUMN IF NOT EXISTS party_type varchar(32),
    ADD COLUMN IF NOT EXISTS cancellation_reason varchar(1000),
    ADD COLUMN IF NOT EXISTS selected_offer_id uuid REFERENCES udrive.driver_offers(id),
    ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 0;

UPDATE udrive.bookings
SET booking_reference = 'LEGACY-' || upper(substr(replace(id::text, '-', ''), 1, 12))
WHERE booking_reference IS NULL;

ALTER TABLE udrive.bookings
    ALTER COLUMN booking_reference SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_bookings_reference
    ON udrive.bookings(booking_reference);
CREATE UNIQUE INDEX IF NOT EXISTS ux_bookings_ride_request
    ON udrive.bookings(ride_request_id)
    WHERE ride_request_id IS NOT NULL;

ALTER TABLE udrive.tour_packages
    ADD COLUMN IF NOT EXISTS description text,
    ADD COLUMN IF NOT EXISTS cancellation_policy text,
    ADD COLUMN IF NOT EXISTS passenger_policy varchar(160) NOT NULL DEFAULT 'Verified passengers only',
    ADD COLUMN IF NOT EXISTS luggage_allowance varchar(200),
    ADD COLUMN IF NOT EXISTS route_stops text[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS fuel_included boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS toll_included boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS hotel_included boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS meals_included boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS guide_included boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS jeep_transfer_included boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS driver_accommodation_included boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS submitted_at timestamptz,
    ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
    ADD COLUMN IF NOT EXISTS reviewed_by_user_id uuid REFERENCES udrive.users(id),
    ADD COLUMN IF NOT EXISTS review_notes text,
    ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 0;

ALTER TABLE udrive.package_bookings
    ADD COLUMN IF NOT EXISTS booking_id uuid REFERENCES udrive.bookings(id),
    ADD COLUMN IF NOT EXISTS booking_reference varchar(32),
    ADD COLUMN IF NOT EXISTS hold_id uuid,
    ADD COLUMN IF NOT EXISTS advance_amount numeric(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS remaining_amount numeric(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
    ADD COLUMN IF NOT EXISTS cancellation_reason varchar(1000),
    ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 0;

UPDATE udrive.package_bookings
SET booking_reference = 'PKG-' || upper(substr(replace(id::text, '-', ''), 1, 12))
WHERE booking_reference IS NULL;

ALTER TABLE udrive.package_bookings
    ALTER COLUMN booking_reference SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_package_bookings_reference
    ON udrive.package_bookings(booking_reference);
CREATE UNIQUE INDEX IF NOT EXISTS ux_package_bookings_booking_id
    ON udrive.package_bookings(booking_id)
    WHERE booking_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS udrive.package_seat_holds (
    id uuid PRIMARY KEY,
    tour_package_id uuid NOT NULL REFERENCES udrive.tour_packages(id) ON DELETE CASCADE,
    customer_user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    booking_type varchar(32) NOT NULL,
    seats_held integer NOT NULL CHECK (seats_held > 0),
    quoted_amount numeric(12,2) NOT NULL CHECK (quoted_amount >= 0),
    status varchar(32) NOT NULL,
    expires_at timestamptz NOT NULL,
    converted_booking_id uuid REFERENCES udrive.bookings(id),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_package_seat_holds_active
    ON udrive.package_seat_holds(tour_package_id, expires_at)
    WHERE status = 'Active';
CREATE UNIQUE INDEX IF NOT EXISTS ux_package_hold_customer_active
    ON udrive.package_seat_holds(tour_package_id, customer_user_id)
    WHERE status = 'Active';

CREATE TABLE IF NOT EXISTS udrive.package_offers (
    id uuid PRIMARY KEY,
    tour_package_id uuid NOT NULL REFERENCES udrive.tour_packages(id) ON DELETE CASCADE,
    customer_user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    booking_type varchar(32) NOT NULL,
    seats_requested integer NOT NULL CHECK (seats_requested > 0),
    offered_amount numeric(12,2) NOT NULL CHECK (offered_amount > 0),
    counter_amount numeric(12,2),
    message varchar(500),
    driver_message varchar(500),
    status varchar(32) NOT NULL,
    expires_at timestamptz NOT NULL,
    confirmed_booking_id uuid REFERENCES udrive.bookings(id),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_package_offers_driver_queue
    ON udrive.package_offers(tour_package_id, status, expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS ux_package_offer_customer_open
    ON udrive.package_offers(tour_package_id, customer_user_id)
    WHERE status IN ('Pending', 'Countered', 'Accepted');


CREATE TABLE IF NOT EXISTS udrive.package_waitlist (
    id uuid PRIMARY KEY,
    tour_package_id uuid NOT NULL REFERENCES udrive.tour_packages(id) ON DELETE CASCADE,
    customer_user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    booking_type varchar(32) NOT NULL,
    seats_requested integer NOT NULL CHECK (seats_requested > 0),
    status varchar(32) NOT NULL DEFAULT 'Waiting',
    notes varchar(500),
    notified_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_package_waitlist_driver_queue
    ON udrive.package_waitlist(tour_package_id, status, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS ux_package_waitlist_customer_open
    ON udrive.package_waitlist(tour_package_id, customer_user_id)
    WHERE status IN ('Waiting', 'Notified');

CREATE TABLE IF NOT EXISTS udrive.booking_passengers (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    full_name varchar(160) NOT NULL,
    gender varchar(24),
    age_group varchar(24) NOT NULL,
    phone_number_masked varchar(32),
    identity_verified boolean NOT NULL DEFAULT false,
    emergency_contact boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_booking_passengers_booking
    ON udrive.booking_passengers(booking_id);

CREATE TABLE IF NOT EXISTS udrive.booking_status_history (
    id uuid PRIMARY KEY,
    entity_type varchar(32) NOT NULL,
    entity_id uuid NOT NULL,
    booking_reference varchar(32),
    from_status varchar(32),
    to_status varchar(32) NOT NULL,
    changed_by_user_id uuid REFERENCES udrive.users(id),
    reason varchar(1000),
    metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_booking_status_history_entity
    ON udrive.booking_status_history(entity_type, entity_id, created_at);

CREATE INDEX IF NOT EXISTS ix_tour_interests_matching
    ON udrive.tour_interests(destination_id, preferred_start_date, preferred_end_date)
    WHERE is_active = true;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_ride_requests_selected_offer'
          AND conrelid = 'udrive.ride_requests'::regclass
    ) THEN
        ALTER TABLE udrive.ride_requests
            ADD CONSTRAINT fk_ride_requests_selected_offer
            FOREIGN KEY (selected_offer_id)
            REFERENCES udrive.driver_offers(id)
            DEFERRABLE INITIALLY DEFERRED;
    END IF;
END $$;
