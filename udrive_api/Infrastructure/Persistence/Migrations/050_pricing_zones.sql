-- Pricing zones: the same kilometre is not worth the same everywhere.
--
-- Azad Kashmir breaks a flat per-km rate in three ways a distance rate cannot
-- see:
--
--   Gradient.     Muzaffarabad to Pir Chinasi is about thirty kilometres and
--                 climbs roughly two thousand metres. It burns two to three
--                 times the fuel of thirty flat kilometres, and the return
--                 downhill burns almost none.
--
--   Empty return. A driver who drops a family in upper Neelum comes back
--                 empty. In the city he picks up the next fare in minutes.
--                 This is why local drivers quote "fixed" valley rates that
--                 look expensive per kilometre — they are pricing the way
--                 home, and a platform that ignores it simply gets no offers
--                 on those routes.
--
--   Season.       The same road in January is a different road.
--
-- A zone is a named set of circles. Circles rather than polygons because
-- pricing_rules already works that way, the portal already knows how to edit
-- a centre and a radius, and a long valley is covered well enough by four or
-- five overlapping circles along the road. Overlaps resolve by priority.

CREATE TABLE IF NOT EXISTS udrive.pricing_zones (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name varchar(120) NOT NULL UNIQUE,

    -- Multiplies the whole metered fare. 1.0 is flat ground.
    difficulty_factor numeric(5,3) NOT NULL DEFAULT 1.000,

    -- How much of the return journey the customer pays for when this zone is
    -- the DESTINATION. 0 in a city where the driver picks up again straight
    -- away; 0.7 up a valley he will drive back out of empty.
    return_share numeric(5,3) NOT NULL DEFAULT 0.000,

    -- Whether a shortage of drivers here may raise the fare.
    surge_enabled boolean NOT NULL DEFAULT true,

    -- Months this zone is priced at all, 1-12. NULL means all year. A zone
    -- that is out of season prices as if it were not there, which is the
    -- honest behaviour: closing the road is service_availability's job, not
    -- pricing's.
    active_months smallint[] NULL,

    -- Highest priority wins where zones overlap.
    priority int NOT NULL DEFAULT 0,

    is_active boolean NOT NULL DEFAULT true,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pricing_zones_difficulty_range
        CHECK (difficulty_factor >= 0.500 AND difficulty_factor <= 4.000),
    CONSTRAINT pricing_zones_return_share_range
        CHECK (return_share >= 0.000 AND return_share <= 1.000)
);

CREATE TABLE IF NOT EXISTS udrive.pricing_zone_areas (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_id uuid NOT NULL REFERENCES udrive.pricing_zones(id) ON DELETE CASCADE,
    label varchar(120),
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    radius_km numeric(8,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pricing_zone_areas_radius_range
        CHECK (radius_km > 0 AND radius_km <= 200),
    CONSTRAINT pricing_zone_areas_lat_range
        CHECK (latitude >= -90 AND latitude <= 90),
    CONSTRAINT pricing_zone_areas_lng_range
        CHECK (longitude >= -180 AND longitude <= 180)
);

-- Stored rather than computed per query, so the GIST index below can be used.
ALTER TABLE udrive.pricing_zone_areas
    ADD COLUMN IF NOT EXISTS centre geography(Point, 4326)
    GENERATED ALWAYS AS (
        ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
    ) STORED;

CREATE INDEX IF NOT EXISTS ix_pricing_zone_areas_zone
    ON udrive.pricing_zone_areas(zone_id);
CREATE INDEX IF NOT EXISTS ix_pricing_zone_areas_centre
    ON udrive.pricing_zone_areas USING GIST(centre);
CREATE INDEX IF NOT EXISTS ix_pricing_zones_lookup
    ON udrive.pricing_zones(is_active, priority DESC);

-- ------------------------------------------------------------------ seed
--
-- The two numbers compound, and by more than they look.
--
-- Difficulty multiplies the whole meter; the return share is a slice of the
-- distance cost, and it is charged through the same terrain, so it carries the
-- difficulty too. Difficulty 1.3 with a 0.55 return share is not a 30% uplift
-- and not an 85% one — on a long valley trip it is roughly double the flat
-- fare, because most of a long trip's cost is distance.
--
-- That is the right answer for a road a driver comes back down empty, but it
-- is not what "1.3" looks like at a glance. The zone editor shows the
-- compounded figure for a sample trip next to these fields; read that number,
-- not these.
--
-- A starting set, INACTIVE on purpose.
--
-- The coordinates below are approximate town centres, good enough to show the
-- shape of the thing on a map and nowhere near good enough to price real trips
-- with. Activating a zone changes what customers are charged, so that is a
-- decision for someone who can look at the map and say "yes, that circle is
-- Athmuqam" — not for a migration written from memory.
--
-- Open Pricing -> Fare zones, drag or retype each centre, set the radius, then
-- switch the zone on.
--
-- The difficulty and return figures are starting guesses too, and they are the
-- ones worth arguing about: return_share is what decides whether a driver ever
-- offers on a Neelum trip.
INSERT INTO udrive.pricing_zones
    (name, difficulty_factor, return_share, surge_enabled, active_months, priority, is_active, notes)
VALUES
    ('Muzaffarabad city', 1.000, 0.000, true, NULL, 100, false,
     'City rides. Flat ground, and a driver picks up again straight away, so no return share. Verify the centre and radius before activating.'),
    ('Pir Chinasi road', 1.200, 0.400, true, NULL, 90, false,
     'Short but a hard climb, and almost always a return trip for the driver. Verify coordinates before activating.'),
    ('Neelum lower (Athmuqam, Keran)', 1.200, 0.450, true, NULL, 80, false,
     'Valley road. Add more circles along the route rather than one large one. Verify coordinates before activating.'),
    ('Neelum upper (Sharda, Kel)', 1.300, 0.550, true, ARRAY[4,5,6,7,8,9,10]::smallint[], 80, false,
     'Long, high and almost always an empty return. Priced April to October only; outside those months it falls back to the default zone. Verify coordinates before activating.'),
    ('Leepa valley', 1.350, 0.600, true, ARRAY[4,5,6,7,8,9,10]::smallint[], 80, false,
     'Reached over a high pass. Verify coordinates before activating.'),
    ('Rawalakot and Banjosa', 1.100, 0.350, true, NULL, 70, false,
     'Verify coordinates before activating.'),
    ('Bagh', 1.100, 0.350, true, NULL, 70, false,
     'Verify coordinates before activating.')
ON CONFLICT (name) DO NOTHING;

INSERT INTO udrive.pricing_zone_areas (zone_id, label, latitude, longitude, radius_km)
SELECT z.id, v.label, v.lat, v.lng, v.radius
FROM (VALUES
    ('Muzaffarabad city',              'Muzaffarabad',  34.3700, 73.4711, 12.0),
    ('Pir Chinasi road',               'Pir Chinasi',   34.3800, 73.6000, 10.0),
    ('Neelum lower (Athmuqam, Keran)', 'Athmuqam',      34.5800, 73.8900, 15.0),
    ('Neelum lower (Athmuqam, Keran)', 'Keran',         34.6200, 73.9300, 15.0),
    ('Neelum upper (Sharda, Kel)',     'Sharda',        34.7900, 74.1800, 18.0),
    ('Neelum upper (Sharda, Kel)',     'Kel',           34.8000, 74.3700, 18.0),
    ('Leepa valley',                   'Leepa',         34.1500, 73.9200, 15.0),
    ('Rawalakot and Banjosa',          'Rawalakot',     33.8600, 73.7600, 15.0),
    ('Rawalakot and Banjosa',          'Banjosa',       33.8000, 73.7300, 10.0),
    ('Bagh',                           'Bagh',          33.9800, 73.7700, 15.0)
) AS v(zone_name, label, lat, lng, radius)
JOIN udrive.pricing_zones z ON z.name = v.zone_name
WHERE NOT EXISTS (
    SELECT 1 FROM udrive.pricing_zone_areas a
    WHERE a.zone_id = z.id AND a.label = v.label
);

COMMENT ON TABLE udrive.pricing_zones IS
    'Named areas that re-price a trip for terrain, empty returns and season.';
COMMENT ON COLUMN udrive.pricing_zones.return_share IS
    'Share of the return journey the customer pays when this zone is the destination. 0 = driver picks up again here.';
COMMENT ON COLUMN udrive.pricing_zones.active_months IS
    'Months 1-12 in which this zone prices. NULL = all year.';
