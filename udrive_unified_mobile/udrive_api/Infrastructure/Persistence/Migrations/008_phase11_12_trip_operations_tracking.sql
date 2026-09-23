ALTER TABLE udrive.bookings
    ADD COLUMN IF NOT EXISTS payment_status varchar(32) NOT NULL DEFAULT 'Pending',
    ADD COLUMN IF NOT EXISTS special_instructions varchar(1000),
    ADD COLUMN IF NOT EXISTS emergency_contact_name varchar(160),
    ADD COLUMN IF NOT EXISTS emergency_contact_phone varchar(32);

CREATE TABLE IF NOT EXISTS udrive.trip_operations (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL UNIQUE REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    operational_status varchar(40) NOT NULL DEFAULT 'PendingAssignment',
    trip_status varchar(40) NOT NULL DEFAULT 'Pending',
    pickup_at timestamptz NOT NULL,
    return_at timestamptz,
    driver_accepted_at timestamptz,
    en_route_at timestamptz,
    arrived_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    emergency_raised_at timestamptz,
    emergency_resolved_at timestamptz,
    last_activity_at timestamptz NOT NULL DEFAULT now(),
    version integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_trip_operations_status_pickup ON udrive.trip_operations(trip_status, pickup_at);
CREATE INDEX IF NOT EXISTS ix_trip_operations_operational ON udrive.trip_operations(operational_status, last_activity_at DESC);

INSERT INTO udrive.trip_operations(id, booking_id, operational_status, trip_status, pickup_at, return_at, last_activity_at, created_at, updated_at)
SELECT gen_random_uuid(), b.id,
       CASE WHEN b.driver_profile_id IS NULL THEN 'PendingAssignment' ELSE 'DriverAssigned' END,
       CASE b.status
         WHEN 'InProgress' THEN 'TripStarted'
         ELSE b.status
       END,
       b.pickup_at, b.return_at, b.updated_at, now(), now()
FROM udrive.bookings b
ON CONFLICT (booking_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS udrive.trip_assignments (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id),
    vehicle_id uuid NOT NULL REFERENCES udrive.vehicles(id),
    assignment_type varchar(32) NOT NULL DEFAULT 'Primary',
    status varchar(32) NOT NULL DEFAULT 'Active',
    assigned_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
    assignment_notes varchar(1000),
    accepted_at timestamptz,
    ended_at timestamptz,
    end_reason varchar(500),
    version integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_trip_assignments_active_booking ON udrive.trip_assignments(booking_id) WHERE status='Active';
CREATE INDEX IF NOT EXISTS ix_trip_assignments_driver_window ON udrive.trip_assignments(driver_profile_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_trip_assignments_vehicle_window ON udrive.trip_assignments(vehicle_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.driver_booking_offers (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id),
    vehicle_id uuid NOT NULL REFERENCES udrive.vehicles(id),
    offered_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
    status varchar(40) NOT NULL DEFAULT 'Pending',
    expires_at timestamptz NOT NULL,
    responded_at timestamptz,
    rejection_reason varchar(500),
    offer_notes varchar(1000),
    version integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_booking_offer_open ON udrive.driver_booking_offers(booking_id, driver_profile_id) WHERE status='Pending';
CREATE INDEX IF NOT EXISTS ix_driver_booking_offers_driver ON udrive.driver_booking_offers(driver_profile_id, status, expires_at);
CREATE INDEX IF NOT EXISTS ix_driver_booking_offers_booking ON udrive.driver_booking_offers(booking_id, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.trip_status_history (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    from_status varchar(40),
    to_status varchar(40) NOT NULL,
    changed_by_user_id uuid REFERENCES udrive.users(id),
    source varchar(32) NOT NULL,
    reason varchar(1000),
    metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_trip_status_history_booking ON udrive.trip_status_history(booking_id, created_at);

CREATE TABLE IF NOT EXISTS udrive.trip_notes (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    author_user_id uuid NOT NULL REFERENCES udrive.users(id),
    note_type varchar(32) NOT NULL DEFAULT 'Operational',
    note text NOT NULL,
    is_customer_visible boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_trip_notes_booking ON udrive.trip_notes(booking_id, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.trip_incidents (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    reported_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
    incident_type varchar(64) NOT NULL,
    severity varchar(32) NOT NULL,
    description text NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'Open',
    assigned_admin_user_id uuid REFERENCES udrive.users(id),
    resolution_notes text,
    resolved_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_trip_incidents_active ON udrive.trip_incidents(status, severity, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_trip_incidents_booking ON udrive.trip_incidents(booking_id, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.driver_latest_locations (
    driver_profile_id uuid PRIMARY KEY REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    location geography(Point,4326) NOT NULL,
    accuracy_meters double precision,
    heading double precision,
    speed_kph double precision,
    battery_level smallint,
    permission_status varchar(32),
    device_timestamp timestamptz NOT NULL,
    server_timestamp timestamptz NOT NULL,
    source varchar(64),
    is_emergency boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_driver_latest_locations_geo ON udrive.driver_latest_locations USING GIST(location);
CREATE INDEX IF NOT EXISTS ix_driver_latest_locations_booking ON udrive.driver_latest_locations(booking_id);
CREATE INDEX IF NOT EXISTS ix_driver_latest_locations_freshness ON udrive.driver_latest_locations(server_timestamp DESC);

CREATE TABLE IF NOT EXISTS udrive.trip_location_history (
    id uuid PRIMARY KEY,
    client_event_id uuid NOT NULL,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    location geography(Point,4326) NOT NULL,
    accuracy_meters double precision,
    heading double precision,
    speed_kph double precision,
    battery_level smallint,
    permission_status varchar(32),
    device_timestamp timestamptz NOT NULL,
    server_timestamp timestamptz NOT NULL,
    source varchar(64),
    is_emergency boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_trip_location_history_client_event ON udrive.trip_location_history(driver_profile_id, client_event_id);
CREATE INDEX IF NOT EXISTS ix_trip_location_history_trip_time ON udrive.trip_location_history(booking_id, server_timestamp DESC);
CREATE INDEX IF NOT EXISTS ix_trip_location_history_geo ON udrive.trip_location_history USING GIST(location);

CREATE TABLE IF NOT EXISTS udrive.trip_tracking_tokens (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    token_hash varchar(128) NOT NULL UNIQUE,
    created_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    last_accessed_at timestamptz,
    access_count integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_trip_tracking_tokens_booking ON udrive.trip_tracking_tokens(booking_id, expires_at);

INSERT INTO udrive.system_settings(key,value_json,description,is_public,created_at,updated_at)
VALUES
 ('tracking.active_interval_seconds','10'::jsonb,'Recommended active-trip GPS interval.',true,now(),now()),
 ('tracking.enroute_interval_seconds','30'::jsonb,'Recommended en-route GPS interval.',true,now(),now()),
 ('tracking.stale_after_seconds','120'::jsonb,'Location age before stale warning.',true,now(),now()),
 ('tracking.history_retention_days','30'::jsonb,'Trip location history retention period.',false,now(),now()),
 ('tracking.public_link_max_hours','24'::jsonb,'Maximum public tracking link duration.',false,now(),now())
ON CONFLICT(key) DO NOTHING;
