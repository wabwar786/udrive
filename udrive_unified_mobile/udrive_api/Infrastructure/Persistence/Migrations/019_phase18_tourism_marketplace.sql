-- Phase 18: complete tourism marketplace operations.
-- Additive and idempotent. Migration runner supplies the transaction.

CREATE TABLE IF NOT EXISTS udrive.tour_package_itinerary_days (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tour_package_id uuid NOT NULL REFERENCES udrive.tour_packages(id) ON DELETE CASCADE,
    day_number integer NOT NULL CHECK (day_number > 0),
    title varchar(180) NOT NULL,
    location varchar(200) NOT NULL,
    activity text NOT NULL,
    start_time time,
    end_time time,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tour_package_id, day_number)
);

CREATE TABLE IF NOT EXISTS udrive.tour_package_images (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tour_package_id uuid NOT NULL REFERENCES udrive.tour_packages(id) ON DELETE CASCADE,
    image_url text NOT NULL,
    caption varchar(240),
    sort_order integer NOT NULL DEFAULT 0,
    is_cover boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS udrive.tour_departures (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tour_package_id uuid NOT NULL REFERENCES udrive.tour_packages(id) ON DELETE CASCADE,
    departure_at timestamptz NOT NULL,
    return_at timestamptz,
    capacity integer NOT NULL CHECK (capacity > 0),
    available_seats integer NOT NULL CHECK (available_seats >= 0),
    status varchar(32) NOT NULL DEFAULT 'Scheduled',
    minimum_passengers integer NOT NULL DEFAULT 1 CHECK (minimum_passengers > 0),
    cancellation_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tour_package_id, departure_at)
);

CREATE TABLE IF NOT EXISTS udrive.tour_trip_operations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tour_package_id uuid NOT NULL REFERENCES udrive.tour_packages(id) ON DELETE CASCADE,
    departure_id uuid REFERENCES udrive.tour_departures(id) ON DELETE SET NULL,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id),
    vehicle_id uuid NOT NULL REFERENCES udrive.vehicles(id),
    status varchar(32) NOT NULL DEFAULT 'Scheduled',
    boarding_opened_at timestamptz,
    departed_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    cancellation_reason text,
    version integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tour_package_id, departure_id)
);

CREATE TABLE IF NOT EXISTS udrive.tour_passenger_checkins (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tour_operation_id uuid NOT NULL REFERENCES udrive.tour_trip_operations(id) ON DELETE CASCADE,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    passenger_id uuid REFERENCES udrive.booking_passengers(id) ON DELETE CASCADE,
    status varchar(32) NOT NULL DEFAULT 'Pending',
    checked_in_at timestamptz,
    boarded_at timestamptz,
    checked_in_by_user_id uuid REFERENCES udrive.users(id),
    notes varchar(500),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tour_operation_id, booking_id, passenger_id)
);

CREATE TABLE IF NOT EXISTS udrive.tour_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tour_operation_id uuid NOT NULL REFERENCES udrive.tour_trip_operations(id) ON DELETE CASCADE,
    from_status varchar(32),
    to_status varchar(32) NOT NULL,
    changed_by_user_id uuid REFERENCES udrive.users(id),
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS udrive.tour_cancellation_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tour_package_id uuid NOT NULL REFERENCES udrive.tour_packages(id) ON DELETE CASCADE,
    hours_before_departure integer NOT NULL CHECK (hours_before_departure >= 0),
    refund_percent numeric(5,2) NOT NULL CHECK (refund_percent >= 0 AND refund_percent <= 100),
    description varchar(300),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tour_package_id, hours_before_departure)
);

CREATE INDEX IF NOT EXISTS ix_tour_departures_public
    ON udrive.tour_departures(status, departure_at);
CREATE INDEX IF NOT EXISTS ix_tour_operations_driver
    ON udrive.tour_trip_operations(driver_profile_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_tour_checkins_operation
    ON udrive.tour_passenger_checkins(tour_operation_id, status);
CREATE INDEX IF NOT EXISTS ix_tour_history_operation
    ON udrive.tour_status_history(tour_operation_id, created_at);

INSERT INTO udrive.tour_departures
    (tour_package_id, departure_at, return_at, capacity, available_seats, status, minimum_passengers)
SELECT tp.id, tp.departure_at, tp.return_at, tp.total_seats, tp.available_seats,
       CASE WHEN tp.status='Active' THEN 'Scheduled' ELSE tp.status END, 1
FROM udrive.tour_packages tp
ON CONFLICT (tour_package_id, departure_at) DO NOTHING;

INSERT INTO udrive.tour_trip_operations
    (tour_package_id, departure_id, driver_profile_id, vehicle_id, status)
SELECT tp.id, td.id, tp.driver_profile_id, tp.vehicle_id,
       CASE WHEN td.status IN ('Cancelled','Completed') THEN td.status ELSE 'Scheduled' END
FROM udrive.tour_packages tp
JOIN udrive.tour_departures td ON td.tour_package_id=tp.id AND td.departure_at=tp.departure_at
ON CONFLICT (tour_package_id, departure_id) DO NOTHING;
