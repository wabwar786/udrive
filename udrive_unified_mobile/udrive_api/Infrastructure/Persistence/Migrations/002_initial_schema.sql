CREATE TABLE IF NOT EXISTS udrive.users (
    id uuid PRIMARY KEY,
    phone_number varchar(24) NOT NULL UNIQUE,
    email varchar(320),
    full_name varchar(160) NOT NULL,
    role varchar(32) NOT NULL,
    status varchar(32) NOT NULL,
    preferred_language varchar(8) NOT NULL DEFAULT 'en',
    phone_verified boolean NOT NULL DEFAULT false,
    last_login_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_email ON udrive.users (email) WHERE email IS NOT NULL;

CREATE TABLE IF NOT EXISTS udrive.customer_profiles (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL UNIQUE REFERENCES udrive.users(id) ON DELETE CASCADE,
    profile_image_url text,
    emergency_notes text,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.driver_profiles (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL UNIQUE REFERENCES udrive.users(id) ON DELETE CASCADE,
    cnic_number_masked varchar(32),
    driving_licence_number_masked varchar(64),
    verification_status varchar(32) NOT NULL,
    average_rating numeric(3,2) NOT NULL DEFAULT 0,
    completed_trips integer NOT NULL DEFAULT 0,
    safety_score integer NOT NULL DEFAULT 80,
    languages text[] NOT NULL DEFAULT '{}',
    service_areas text[] NOT NULL DEFAULT '{}',
    is_online boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.driver_documents (
    id uuid PRIMARY KEY,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    document_type varchar(64) NOT NULL,
    file_url text NOT NULL,
    expiry_date date,
    status varchar(32) NOT NULL,
    review_notes text,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.vehicles (
    id uuid PRIMARY KEY,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    category varchar(48) NOT NULL,
    make varchar(64) NOT NULL,
    model varchar(64) NOT NULL,
    year integer NOT NULL CHECK (year BETWEEN 1980 AND 2100),
    registration_number varchar(40) NOT NULL UNIQUE,
    colour varchar(40) NOT NULL,
    passenger_capacity integer NOT NULL CHECK (passenger_capacity > 0),
    luggage_capacity integer NOT NULL DEFAULT 0,
    has_air_conditioning boolean NOT NULL DEFAULT false,
    has_heating boolean NOT NULL DEFAULT false,
    is_four_by_four boolean NOT NULL DEFAULT false,
    has_first_aid_kit boolean NOT NULL DEFAULT false,
    has_fire_extinguisher boolean NOT NULL DEFAULT false,
    has_spare_tyre boolean NOT NULL DEFAULT false,
    has_snow_chains boolean NOT NULL DEFAULT false,
    has_child_seat boolean NOT NULL DEFAULT false,
    mountain_readiness_score integer NOT NULL DEFAULT 0 CHECK (mountain_readiness_score BETWEEN 0 AND 100),
    status varchar(32) NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.vehicle_documents (
    id uuid PRIMARY KEY,
    vehicle_id uuid NOT NULL REFERENCES udrive.vehicles(id) ON DELETE CASCADE,
    document_type varchar(64) NOT NULL,
    file_url text NOT NULL,
    expiry_date date,
    status varchar(32) NOT NULL,
    review_notes text,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.trusted_contacts (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    name varchar(120) NOT NULL,
    relationship varchar(60) NOT NULL,
    phone_number varchar(24) NOT NULL,
    is_guardian boolean NOT NULL DEFAULT false,
    emergency_notifications_enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.destinations (
    id uuid PRIMARY KEY,
    slug varchar(120) NOT NULL UNIQUE,
    name_en varchar(160) NOT NULL,
    name_ur varchar(200) NOT NULL,
    summary_en text NOT NULL,
    summary_ur text NOT NULL,
    location geography(Point, 4326) NOT NULL,
    district varchar(100) NOT NULL,
    best_season varchar(100) NOT NULL,
    recommended_vehicle varchar(80) NOT NULL,
    network_status varchar(80) NOT NULL,
    family_suitability_score integer NOT NULL CHECK (family_suitability_score BETWEEN 0 AND 100),
    route_safety_score integer NOT NULL CHECK (route_safety_score BETWEEN 0 AND 100),
    cover_image_url text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_destinations_location ON udrive.destinations USING GIST(location);

CREATE TABLE IF NOT EXISTS udrive.routes (
    id uuid PRIMARY KEY,
    name varchar(200) NOT NULL,
    origin_destination_id uuid REFERENCES udrive.destinations(id),
    destination_id uuid REFERENCES udrive.destinations(id),
    origin_location geography(Point, 4326) NOT NULL,
    destination_location geography(Point, 4326) NOT NULL,
    route_path geography(LineString, 4326),
    distance_km numeric(10,2) NOT NULL,
    estimated_minutes integer NOT NULL,
    recommended_vehicle varchar(80) NOT NULL,
    four_by_four_required boolean NOT NULL DEFAULT false,
    daylight_only boolean NOT NULL DEFAULT false,
    safety_score integer NOT NULL CHECK (safety_score BETWEEN 0 AND 100),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_routes_origin_location ON udrive.routes USING GIST(origin_location);
CREATE INDEX IF NOT EXISTS ix_routes_destination_location ON udrive.routes USING GIST(destination_location);

CREATE TABLE IF NOT EXISTS udrive.route_advisories (
    id uuid PRIMARY KEY,
    route_id uuid REFERENCES udrive.routes(id) ON DELETE CASCADE,
    severity varchar(32) NOT NULL,
    title_en varchar(200) NOT NULL,
    title_ur varchar(240) NOT NULL,
    details_en text NOT NULL,
    details_ur text NOT NULL,
    source_name varchar(160) NOT NULL,
    starts_at timestamptz NOT NULL,
    ends_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.tour_interests (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    destination_id uuid NOT NULL REFERENCES udrive.destinations(id),
    preferred_start_date date NOT NULL,
    preferred_end_date date,
    persons integer NOT NULL CHECK (persons > 0),
    group_preference varchar(40) NOT NULL,
    budget_per_seat numeric(12,2),
    pickup_city varchar(120) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.tour_packages (
    id uuid PRIMARY KEY,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id),
    vehicle_id uuid NOT NULL REFERENCES udrive.vehicles(id),
    destination_id uuid NOT NULL REFERENCES udrive.destinations(id),
    title varchar(200) NOT NULL,
    starting_city varchar(120) NOT NULL,
    pickup_point varchar(200) NOT NULL,
    departure_at timestamptz NOT NULL,
    return_at timestamptz,
    total_seats integer NOT NULL CHECK (total_seats > 0),
    available_seats integer NOT NULL CHECK (available_seats >= 0),
    price_per_seat numeric(12,2) NOT NULL,
    whole_vehicle_price numeric(12,2) NOT NULL,
    family_only boolean NOT NULL DEFAULT false,
    women_only boolean NOT NULL DEFAULT false,
    customer_offers_allowed boolean NOT NULL DEFAULT true,
    status varchar(32) NOT NULL,
    inclusions text[] NOT NULL DEFAULT '{}',
    exclusions text[] NOT NULL DEFAULT '{}',
    itinerary_json jsonb NOT NULL DEFAULT '[]'::jsonb,
    cover_image_url text,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CHECK (available_seats <= total_seats)
);
CREATE INDEX IF NOT EXISTS ix_tour_packages_departure ON udrive.tour_packages(departure_at, status);

CREATE TABLE IF NOT EXISTS udrive.ride_requests (
    id uuid PRIMARY KEY,
    customer_user_id uuid NOT NULL REFERENCES udrive.users(id),
    pickup_location geography(Point, 4326) NOT NULL,
    destination_location geography(Point, 4326) NOT NULL,
    pickup_label varchar(240) NOT NULL,
    destination_label varchar(240) NOT NULL,
    pickup_at timestamptz NOT NULL,
    booking_type varchar(32) NOT NULL,
    seats_requested integer NOT NULL,
    adults integer NOT NULL,
    children integer NOT NULL,
    luggage_count integer NOT NULL,
    customer_offer numeric(12,2) NOT NULL,
    vehicle_category varchar(80) NOT NULL,
    family_only boolean NOT NULL DEFAULT false,
    status varchar(32) NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_ride_requests_pickup_location ON udrive.ride_requests USING GIST(pickup_location);
CREATE INDEX IF NOT EXISTS ix_ride_requests_open ON udrive.ride_requests(status, pickup_at);

CREATE TABLE IF NOT EXISTS udrive.driver_offers (
    id uuid PRIMARY KEY,
    ride_request_id uuid NOT NULL REFERENCES udrive.ride_requests(id) ON DELETE CASCADE,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id),
    vehicle_id uuid NOT NULL REFERENCES udrive.vehicles(id),
    amount numeric(12,2) NOT NULL,
    estimated_arrival_minutes integer NOT NULL,
    message varchar(500),
    status varchar(32) NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_offer_per_request ON udrive.driver_offers(ride_request_id, driver_profile_id) WHERE status IN ('Pending','Countered','Accepted');

CREATE TABLE IF NOT EXISTS udrive.bookings (
    id uuid PRIMARY KEY,
    customer_user_id uuid NOT NULL REFERENCES udrive.users(id),
    driver_profile_id uuid REFERENCES udrive.driver_profiles(id),
    vehicle_id uuid REFERENCES udrive.vehicles(id),
    ride_request_id uuid REFERENCES udrive.ride_requests(id),
    tour_package_id uuid REFERENCES udrive.tour_packages(id),
    booking_type varchar(32) NOT NULL,
    status varchar(32) NOT NULL,
    seats_booked integer NOT NULL,
    total_amount numeric(12,2) NOT NULL,
    advance_amount numeric(12,2) NOT NULL DEFAULT 0,
    remaining_amount numeric(12,2) NOT NULL DEFAULT 0,
    pickup_at timestamptz NOT NULL,
    trip_otp_hash varchar(256) NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CHECK ((ride_request_id IS NOT NULL)::int + (tour_package_id IS NOT NULL)::int = 1)
);

CREATE TABLE IF NOT EXISTS udrive.package_bookings (
    id uuid PRIMARY KEY,
    tour_package_id uuid NOT NULL REFERENCES udrive.tour_packages(id),
    customer_user_id uuid NOT NULL REFERENCES udrive.users(id),
    booking_type varchar(32) NOT NULL,
    seats_booked integer NOT NULL,
    total_amount numeric(12,2) NOT NULL,
    status varchar(32) NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.live_locations (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES udrive.users(id),
    actor_type varchar(32) NOT NULL,
    location geography(Point, 4326) NOT NULL,
    heading double precision,
    speed_kph double precision,
    accuracy_meters double precision,
    recorded_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_live_locations_geo ON udrive.live_locations USING GIST(location);
CREATE INDEX IF NOT EXISTS ix_live_locations_booking_time ON udrive.live_locations(booking_id, recorded_at DESC);

CREATE TABLE IF NOT EXISTS udrive.safety_incidents (
    id uuid PRIMARY KEY,
    booking_id uuid REFERENCES udrive.bookings(id),
    reported_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
    severity varchar(32) NOT NULL,
    incident_type varchar(80) NOT NULL,
    description text NOT NULL,
    status varchar(32) NOT NULL,
    assigned_admin_user_id uuid REFERENCES udrive.users(id),
    resolved_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_safety_incidents_open ON udrive.safety_incidents(status, severity, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.notifications (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    type varchar(80) NOT NULL,
    title varchar(200) NOT NULL,
    body text NOT NULL,
    data_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    read_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_notifications_user_unread ON udrive.notifications(user_id, read_at, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.payments (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id),
    method varchar(40) NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency varchar(3) NOT NULL DEFAULT 'PKR',
    status varchar(32) NOT NULL,
    provider_reference varchar(160),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.audit_logs (
    id uuid PRIMARY KEY,
    actor_user_id uuid REFERENCES udrive.users(id),
    action varchar(120) NOT NULL,
    entity_type varchar(120) NOT NULL,
    entity_id varchar(120) NOT NULL,
    ip_address varchar(64),
    changes_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_audit_logs_entity ON udrive.audit_logs(entity_type, entity_id, created_at DESC);
