-- Reports Centre: every booking and ride request knows its area, and who may
-- open which report.
--
-- 1. ride_requests.territory_id — the tehsil of the pickup point, filled on
--    insert and whenever the pickup moves.
-- 2. bookings.territory_id — the ride request's tehsil; for a tour or a
--    booking without a request, the vehicle's (or its driver's) area. Filled on
--    insert, and later if a vehicle is assigned to a booking that had none.
-- 3. staff_report_access — which reports a portal user may open. SuperAdmin
--    needs no rows: they see every report in every area.
-- 4. Two helpers the report queries share: an area's label ("Bagh › Dhirkot")
--    and the bucket a timestamp falls in (day / week / month, Pakistan time).
--
-- Safe to run more than once.

-- ───────────────────────────────────────────── 1. ride requests

ALTER TABLE udrive.ride_requests
    ADD COLUMN IF NOT EXISTS territory_id uuid REFERENCES udrive.territories(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION udrive.fill_ride_request_territory()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.pickup_location IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.pickup_location IS DISTINCT FROM OLD.pickup_location OR NEW.territory_id IS NULL) THEN
        NEW.territory_id := udrive.nearest_tehsil(
            ST_Y(NEW.pickup_location::geometry), ST_X(NEW.pickup_location::geometry));
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_ride_requests_territory ON udrive.ride_requests;
CREATE TRIGGER trg_ride_requests_territory BEFORE INSERT OR UPDATE OF pickup_location ON udrive.ride_requests
    FOR EACH ROW EXECUTE FUNCTION udrive.fill_ride_request_territory();

UPDATE udrive.ride_requests
SET territory_id = udrive.nearest_tehsil(ST_Y(pickup_location::geometry), ST_X(pickup_location::geometry))
WHERE territory_id IS NULL AND pickup_location IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_ride_requests_territory_created ON udrive.ride_requests (territory_id, created_at);
CREATE INDEX IF NOT EXISTS ix_ride_requests_created ON udrive.ride_requests (created_at);

-- ───────────────────────────────────────────── 2. bookings

ALTER TABLE udrive.bookings
    ADD COLUMN IF NOT EXISTS territory_id uuid REFERENCES udrive.territories(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION udrive.booking_territory(
    p_ride_request_id uuid, p_tour_package_id uuid, p_vehicle_id uuid, p_driver_profile_id uuid)
RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        (SELECT rr.territory_id FROM udrive.ride_requests rr WHERE rr.id = p_ride_request_id),
        (SELECT COALESCE(v.territory_id, dp.territory_id)
           FROM udrive.tour_packages tp
           LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id
           LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
          WHERE tp.id = p_tour_package_id),
        (SELECT COALESCE(v.territory_id, dp.territory_id)
           FROM udrive.vehicles v
           LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
          WHERE v.id = p_vehicle_id),
        (SELECT dp.territory_id FROM udrive.driver_profiles dp WHERE dp.id = p_driver_profile_id));
$$;

CREATE OR REPLACE FUNCTION udrive.fill_booking_territory()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.territory_id IS NULL THEN
        NEW.territory_id := udrive.booking_territory(
            NEW.ride_request_id, NEW.tour_package_id, NEW.vehicle_id, NEW.driver_profile_id);
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_bookings_territory ON udrive.bookings;
CREATE TRIGGER trg_bookings_territory BEFORE INSERT OR UPDATE OF ride_request_id, tour_package_id, vehicle_id, driver_profile_id ON udrive.bookings
    FOR EACH ROW EXECUTE FUNCTION udrive.fill_booking_territory();

UPDATE udrive.bookings b
SET territory_id = udrive.booking_territory(b.ride_request_id, b.tour_package_id, b.vehicle_id, b.driver_profile_id)
WHERE b.territory_id IS NULL;

CREATE INDEX IF NOT EXISTS ix_bookings_territory_created ON udrive.bookings (territory_id, created_at);
CREATE INDEX IF NOT EXISTS ix_bookings_created ON udrive.bookings (created_at);
CREATE INDEX IF NOT EXISTS ix_trip_operations_completed ON udrive.trip_operations (completed_at) WHERE completed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_driver_earnings_created ON udrive.driver_earnings (created_at);
CREATE INDEX IF NOT EXISTS ix_payments_created ON udrive.payments (created_at);
CREATE INDEX IF NOT EXISTS ix_driver_profiles_territory ON udrive.driver_profiles (territory_id) WHERE territory_id IS NOT NULL;

-- ───────────────────────────────────────────── 3. who may open which report

CREATE TABLE IF NOT EXISTS udrive.staff_report_access (
    user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    report_key varchar(64) NOT NULL,
    granted_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, report_key)
);

-- ───────────────────────────────────────────── 4. helpers

-- "Bagh › Dhirkot" for a tehsil, "Bagh" for a district, '—' for none.
CREATE OR REPLACE FUNCTION udrive.area_label(p_id uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        (SELECT CASE WHEN d.id IS NULL THEN t.name ELSE d.name || ' › ' || t.name END
           FROM udrive.territories t
           LEFT JOIN udrive.territories d ON d.id = t.parent_id AND t.kind = 'Tehsil'
          WHERE t.id = p_id),
        '—');
$$;

-- The district a tehsil belongs to (or the area itself when it is a district).
CREATE OR REPLACE FUNCTION udrive.area_district(p_id uuid)
RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN t.kind = 'Tehsil' THEN t.parent_id ELSE t.id END
    FROM udrive.territories t WHERE t.id = p_id;
$$;

-- The period a moment falls in, in Pakistan time: '2026-10-06', '2026-W41' or '2026-10'.
CREATE OR REPLACE FUNCTION udrive.report_bucket(p_at timestamptz, p_group text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_group
        WHEN 'month' THEN to_char(p_at AT TIME ZONE 'Asia/Karachi', 'YYYY-MM')
        WHEN 'week' THEN to_char(p_at AT TIME ZONE 'Asia/Karachi', 'IYYY-"W"IW')
        ELSE to_char(p_at AT TIME ZONE 'Asia/Karachi', 'YYYY-MM-DD')
    END;
$$;
