-- Per-kilometre pricing the admin can set, scoped by day and by area.
--
-- `service_vehicle_rates` holds one flat rate per category and nothing else, so
-- charging more on a Sunday, or more in Muzaffarabad than in Rawalakot, meant
-- editing the single row every time and losing whatever it said before.
--
-- A rule is a per-km rate plus optional scopes. Leave a scope empty and it
-- means "everywhere" or "every day", so one global rule per category behaves
-- exactly like the old flat table.

CREATE TABLE IF NOT EXISTS udrive.pricing_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- What the admin calls it. Shown in the portal list, never to a customer.
    name text NOT NULL,

    service_type varchar(40) NOT NULL DEFAULT 'City',
    vehicle_category varchar(40) NOT NULL,

    -- The rate that scales with the trip. This is the number the admin came to
    -- change.
    per_km_rate numeric(12,2) NOT NULL,

    -- Flat floor. A short trip still costs this, because a driver does not
    -- start the engine for less.
    minimum_fare numeric(12,2) NOT NULL DEFAULT 0,

    -- Rupees per minute of expected travel time, so a short trip through heavy
    -- traffic is not priced as though it were quick.
    per_minute_rate numeric(12,2) NOT NULL DEFAULT 2,

    -- ISO days: 1 = Monday … 7 = Sunday. NULL or empty means every day.
    -- Stored as an array rather than seven booleans so "Fri, Sat, Sun" is one
    -- value the admin can read back at a glance.
    days_of_week smallint[] NULL,

    -- The area, as a circle. Rendering and editing a polygon is a mapping tool
    -- in its own right; a centre and a radius is something an admin can set
    -- from a place name in a few seconds, and it is accurate enough to tell
    -- Muzaffarabad from Rawalakot.
    area_label text NULL,
    area_latitude double precision NULL,
    area_longitude double precision NULL,
    area_radius_km double precision NULL,

    -- Breaks ties by hand when two rules are equally specific. Higher wins.
    priority integer NOT NULL DEFAULT 0,

    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- An area needs all three parts or none. A half-set circle would silently
    -- match nothing and look like a rule that simply does not work.
    CONSTRAINT pricing_rules_area_complete CHECK (
        (area_latitude IS NULL AND area_longitude IS NULL AND area_radius_km IS NULL)
        OR (area_latitude IS NOT NULL AND area_longitude IS NOT NULL
            AND area_radius_km IS NOT NULL AND area_radius_km > 0)
    ),
    CONSTRAINT pricing_rules_rate_positive CHECK (per_km_rate > 0)
);

CREATE INDEX IF NOT EXISTS ix_pricing_rules_lookup
    ON udrive.pricing_rules(service_type, lower(vehicle_category), is_active);

-- Seed one global rule per existing rate row, so the day this ships nothing
-- changes and the admin opens the portal to a filled table rather than an empty
-- one they have to guess the shape of.
INSERT INTO udrive.pricing_rules
    (name, service_type, vehicle_category, per_km_rate, minimum_fare, per_minute_rate)
SELECT
    r.vehicle_category || ' — standard (' || r.service_type || ')',
    r.service_type,
    r.vehicle_category,
    r.per_km_rate,
    r.whole_vehicle_rate,
    2
FROM udrive.service_vehicle_rates r
WHERE r.is_active
  AND r.per_km_rate > 0
  AND NOT EXISTS (
      SELECT 1 FROM udrive.pricing_rules p
      WHERE p.service_type = r.service_type
        AND lower(p.vehicle_category) = lower(r.vehicle_category)
        AND p.area_radius_km IS NULL
        AND p.days_of_week IS NULL
  );
