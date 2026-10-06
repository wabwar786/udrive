-- One registration in Driver mode for every kind of work, and a commission
-- rate for each kind.
--
-- 1. vehicles: what the driver registered the vehicle FOR (city rides, city
--    to city, tours, rent), and who drives it. Applied to the usage switches
--    once, when an Admin first verifies the vehicle. NULL wants_city = a
--    vehicle registered before this, left exactly as it is.
-- 2. vehicles.available_for_intercity: takes city-to-city requests. Starts
--    as a copy of the city switch for every existing vehicle. Like city
--    rides, it cannot be on while the vehicle is out on rent.
-- 3. ride_requests.is_intercity: pickup and drop are in different districts.
--    Filled by the same trigger that fills the pickup tehsil.
-- 4. Commission rate per kind of work. Each starts at today's single rate, so
--    nothing a driver pays changes until an Admin changes it.
--
-- Safe to run more than once.

-- ───────────────────────────────────────────── 1. registration intent

ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS wants_city boolean,
    ADD COLUMN IF NOT EXISTS wants_intercity boolean,
    ADD COLUMN IF NOT EXISTS driven_by varchar(16),
    ADD COLUMN IF NOT EXISTS uses_applied_at timestamptz;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_vehicles_driven_by') THEN
        ALTER TABLE udrive.vehicles
            ADD CONSTRAINT ck_vehicles_driven_by
                CHECK (driven_by IS NULL OR driven_by IN ('Self', 'Drivers', 'Both'));
    END IF;
END $$;

-- ───────────────────────────────────────────── 2. city to city

-- Starts as a copy of the city switch, once, when the column is added: a
-- vehicle that took city rides took city-to-city rides too, and one taken out
-- of the city pool (on rent, or a listed rent/tour vehicle) was out of both.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'udrive' AND table_name = 'vehicles'
          AND column_name = 'available_for_intercity') THEN
        ALTER TABLE udrive.vehicles
            ADD COLUMN available_for_intercity boolean NOT NULL DEFAULT true;
        UPDATE udrive.vehicles
        SET available_for_intercity = COALESCE(available_for_city, true)
                                      AND NOT COALESCE(available_for_rent, false);
    END IF;
END $$;

ALTER TABLE udrive.vehicles
    DROP CONSTRAINT IF EXISTS ck_vehicles_rent_excludes_intercity;
ALTER TABLE udrive.vehicles
    ADD CONSTRAINT ck_vehicles_rent_excludes_intercity
        CHECK (NOT (available_for_rent AND available_for_intercity));

-- ───────────────────────────────────────────── 3. which requests are city to city

ALTER TABLE udrive.ride_requests
    ADD COLUMN IF NOT EXISTS is_intercity boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION udrive.fill_ride_request_territory()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT'
       OR NEW.pickup_location IS DISTINCT FROM OLD.pickup_location
       OR NEW.destination_location IS DISTINCT FROM OLD.destination_location
       OR NEW.territory_id IS NULL THEN
        IF NEW.pickup_location IS NOT NULL THEN
            NEW.territory_id := udrive.nearest_tehsil(
                ST_Y(NEW.pickup_location::geometry), ST_X(NEW.pickup_location::geometry));
        END IF;
        NEW.is_intercity := COALESCE(
            NEW.destination_location IS NOT NULL
            AND NEW.territory_id IS NOT NULL
            AND udrive.area_district(NEW.territory_id)
                IS DISTINCT FROM udrive.area_district(udrive.nearest_tehsil(
                    ST_Y(NEW.destination_location::geometry),
                    ST_X(NEW.destination_location::geometry))),
            false);
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_ride_requests_territory ON udrive.ride_requests;
CREATE TRIGGER trg_ride_requests_territory
    BEFORE INSERT OR UPDATE OF pickup_location, destination_location ON udrive.ride_requests
    FOR EACH ROW EXECUTE FUNCTION udrive.fill_ride_request_territory();

UPDATE udrive.ride_requests rr
SET is_intercity = true
WHERE NOT rr.is_intercity
  AND rr.territory_id IS NOT NULL
  AND rr.destination_location IS NOT NULL
  AND udrive.area_district(rr.territory_id)
      IS DISTINCT FROM udrive.area_district(udrive.nearest_tehsil(
          ST_Y(rr.destination_location::geometry), ST_X(rr.destination_location::geometry)));

-- ───────────────────────────────────────────── 4. commission per kind of work

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
SELECT k.key,
       COALESCE((SELECT value_json FROM udrive.system_settings WHERE key = 'driver.commission.percentage'),
                to_jsonb('10'::text)),
       k.description, true, now(), now()
FROM (VALUES
    ('driver.commission.intercity_percentage', 'Commission on city-to-city rides, taken when the ride starts.'),
    ('driver.commission.tour_percentage', 'Commission on tour bookings, taken when the tour starts.'),
    ('driver.commission.rent_percentage', 'Commission on rent-a-car bookings, taken when the driver accepts.')
) AS k(key, description)
ON CONFLICT (key) DO NOTHING;
