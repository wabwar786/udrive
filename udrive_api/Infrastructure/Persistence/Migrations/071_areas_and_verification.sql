-- Areas (district / tehsil) and one verification page with a separate approval
-- for each use of a vehicle.
--
--   * Districts and tehsils live in the existing territory tree (migration 065):
--     a district is a 'City' node, a tehsil a 'Tehsil' node under it. Partner
--     territories and verification areas are then the same list, kept in one
--     place. Each tehsil gets a centre pin so a phone's GPS position can be
--     matched to it.
--   * Every vehicle, hotel and business gets the tehsil it belongs to. Drivers
--     already had driver_profiles.territory_id (065); it is now filled from the
--     driver's own choice at sign-up.
--   * A listed vehicle is approved for rent and for tours separately:
--     rent_review_status / tour_review_status.

-- ───────────────────────────────────────────── 1. centre pins

ALTER TABLE udrive.territories
    ADD COLUMN IF NOT EXISTS latitude double precision,
    ADD COLUMN IF NOT EXISTS longitude double precision;

-- ───────────────────────────────────────────── 2. Azad Kashmir districts and tehsils
--
-- Seeded under the existing "Azad Kashmir" region. A district or tehsil that an
-- admin already created with the same name is reused, never duplicated, and
-- keeps its own settings. Centre pins are approximate (the tehsil headquarters
-- town) and can be corrected in Settings → Areas.

DO $$
DECLARE
    region_id uuid;
    district_id uuid;
    d record;
    t record;
BEGIN
    SELECT id INTO region_id FROM udrive.territories
    WHERE kind = 'Region' AND lower(name) = 'azad kashmir' LIMIT 1;
    IF region_id IS NULL THEN
        INSERT INTO udrive.territories (kind, name, notes)
        VALUES ('Region', 'Azad Kashmir', 'Seeded by migration 071.')
        RETURNING id INTO region_id;
    END IF;

    FOR d IN
        SELECT * FROM (VALUES
            ('Muzaffarabad'), ('Hattian Bala'), ('Neelum'), ('Bagh'), ('Haveli'),
            ('Poonch'), ('Sudhnoti'), ('Kotli'), ('Mirpur'), ('Bhimber')) AS x(name)
    LOOP
        SELECT id INTO district_id FROM udrive.territories
        WHERE kind = 'City' AND lower(name) = lower(d.name)
        ORDER BY (parent_id = region_id) DESC NULLS LAST
        LIMIT 1;
        IF district_id IS NULL THEN
            INSERT INTO udrive.territories (parent_id, kind, name, notes)
            VALUES (region_id, 'City', d.name, 'District. Seeded by migration 071.')
            RETURNING id INTO district_id;
        END IF;

        FOR t IN
            SELECT * FROM (VALUES
                ('Muzaffarabad', 'Muzaffarabad', 34.3700, 73.4710),
                ('Muzaffarabad', 'Naseerabad', 34.4200, 73.5800),
                ('Hattian Bala', 'Hattian Bala', 34.1690, 73.7430),
                ('Hattian Bala', 'Chikar', 34.1480, 73.6170),
                ('Hattian Bala', 'Leepa', 34.3170, 73.9170),
                ('Neelum', 'Athmuqam', 34.5850, 73.9050),
                ('Neelum', 'Sharda', 34.7930, 74.1890),
                ('Bagh', 'Bagh', 33.9800, 73.7760),
                ('Bagh', 'Dhirkot', 34.0390, 73.5780),
                ('Bagh', 'Harighel', 33.9350, 73.8520),
                ('Haveli', 'Forward Kahuta', 33.8840, 74.1060),
                ('Haveli', 'Khurshidabad', 33.8060, 74.0220),
                ('Poonch', 'Rawalakot', 33.8580, 73.7600),
                ('Poonch', 'Hajira', 33.7720, 73.8950),
                ('Poonch', 'Abbaspur', 33.8130, 74.0300),
                ('Poonch', 'Thorar', 33.7920, 73.6650),
                ('Sudhnoti', 'Pallandri', 33.7150, 73.6870),
                ('Sudhnoti', 'Trarkhal', 33.7000, 73.8000),
                ('Sudhnoti', 'Mang', 33.6650, 73.6150),
                ('Sudhnoti', 'Baloch', 33.7620, 73.6150),
                ('Kotli', 'Kotli', 33.5180, 73.9020),
                ('Kotli', 'Sehnsa', 33.5330, 73.7400),
                ('Kotli', 'Fatehpur Thakiala', 33.4580, 74.0700),
                ('Kotli', 'Khuiratta', 33.3550, 74.0300),
                ('Kotli', 'Charhoi', 33.3000, 73.9900),
                ('Mirpur', 'Mirpur', 33.1480, 73.7510),
                ('Mirpur', 'Dadyal', 33.3800, 73.7000),
                ('Mirpur', 'Islamgarh', 33.2500, 73.8600),
                ('Bhimber', 'Bhimber', 32.9750, 74.0790),
                ('Bhimber', 'Barnala', 33.0700, 74.2400),
                ('Bhimber', 'Samahni', 33.0500, 74.1500)) AS y(district, name, lat, lng)
            WHERE y.district = d.name
        LOOP
            IF EXISTS (SELECT 1 FROM udrive.territories
                       WHERE parent_id = district_id AND lower(name) = lower(t.name)) THEN
                UPDATE udrive.territories
                SET latitude = COALESCE(latitude, t.lat), longitude = COALESCE(longitude, t.lng)
                WHERE parent_id = district_id AND lower(name) = lower(t.name);
            ELSE
                INSERT INTO udrive.territories (parent_id, kind, name, latitude, longitude, notes)
                VALUES (district_id, 'Tehsil', t.name, t.lat, t.lng, 'Seeded by migration 071.');
            END IF;
        END LOOP;
    END LOOP;
END $$;

-- ───────────────────────────────────────────── 3. which tehsil is nearest
--
-- Straight-line distance between a point and each active tehsil's centre pin;
-- nothing beyond 80 km counts as "in" a tehsil. Used to fill a business's or a
-- hotel's area from its map pin, and by the app to pre-fill the picker.

CREATE OR REPLACE FUNCTION udrive.nearest_tehsil(lat double precision, lng double precision)
RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT t.id
    FROM udrive.territories t
    WHERE t.kind = 'Tehsil' AND t.is_active
      AND t.latitude IS NOT NULL AND t.longitude IS NOT NULL
      AND lat IS NOT NULL AND lng IS NOT NULL
      AND (111.32 * sqrt(power(t.latitude - lat, 2)
             + power((t.longitude - lng) * cos(radians(lat)), 2))) <= 80
    ORDER BY power(t.latitude - lat, 2) + power((t.longitude - lng) * cos(radians(lat)), 2)
    LIMIT 1;
$$;

-- ───────────────────────────────────────────── 4. where each thing is

ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS territory_id uuid REFERENCES udrive.territories(id) ON DELETE SET NULL;
ALTER TABLE udrive.hotels
    ADD COLUMN IF NOT EXISTS territory_id uuid REFERENCES udrive.territories(id) ON DELETE SET NULL;
ALTER TABLE udrive.businesses
    ADD COLUMN IF NOT EXISTS territory_id uuid REFERENCES udrive.territories(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_vehicles_territory ON udrive.vehicles (territory_id) WHERE territory_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_hotels_territory ON udrive.hotels (territory_id) WHERE territory_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_businesses_territory ON udrive.businesses (territory_id) WHERE territory_id IS NOT NULL;

-- Hotels and businesses have a map pin, so their tehsil follows it: filled on
-- insert, and again whenever the pin moves. An admin's own correction stays
-- until the pin itself changes.
CREATE OR REPLACE FUNCTION udrive.fill_territory_from_pin()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.territory_id IS NULL THEN
            NEW.territory_id := udrive.nearest_tehsil(NEW.latitude, NEW.longitude);
        END IF;
    ELSIF NEW.latitude IS DISTINCT FROM OLD.latitude OR NEW.longitude IS DISTINCT FROM OLD.longitude THEN
        NEW.territory_id := udrive.nearest_tehsil(NEW.latitude, NEW.longitude);
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_hotels_territory ON udrive.hotels;
CREATE TRIGGER trg_hotels_territory BEFORE INSERT OR UPDATE ON udrive.hotels
    FOR EACH ROW EXECUTE FUNCTION udrive.fill_territory_from_pin();

DROP TRIGGER IF EXISTS trg_businesses_territory ON udrive.businesses;
CREATE TRIGGER trg_businesses_territory BEFORE INSERT OR UPDATE ON udrive.businesses
    FOR EACH ROW EXECUTE FUNCTION udrive.fill_territory_from_pin();

UPDATE udrive.hotels SET territory_id = udrive.nearest_tehsil(latitude, longitude)
WHERE territory_id IS NULL;
UPDATE udrive.businesses SET territory_id = udrive.nearest_tehsil(latitude, longitude)
WHERE territory_id IS NULL;

-- ───────────────────────────────────────────── 5. rent and tour approved separately

ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS rent_review_status varchar(16) NOT NULL DEFAULT 'None',
    ADD COLUMN IF NOT EXISTS rent_review_note varchar(500),
    ADD COLUMN IF NOT EXISTS tour_review_status varchar(16) NOT NULL DEFAULT 'None',
    ADD COLUMN IF NOT EXISTS tour_review_note varchar(500),
    ADD COLUMN IF NOT EXISTS reviewed_purpose_at timestamptz;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_vehicles_purpose_review') THEN
        ALTER TABLE udrive.vehicles ADD CONSTRAINT ck_vehicles_purpose_review CHECK (
            rent_review_status IN ('None', 'Pending', 'Approved', 'Rejected', 'Info')
            AND tour_review_status IN ('None', 'Pending', 'Approved', 'Rejected', 'Info'));
    END IF;
END $$;

-- Listings made before this: carry their current state over.
UPDATE udrive.vehicles
SET rent_review_status = CASE
        WHEN NOT listing_wants_rent THEN 'None'
        WHEN available_for_rent OR status = 'Verified' THEN 'Approved'
        WHEN status = 'PendingReview' THEN 'Pending'
        WHEN status = 'Rejected' THEN 'Rejected'
        ELSE 'None' END,
    tour_review_status = CASE
        WHEN NOT listing_wants_tour THEN 'None'
        WHEN available_for_tour OR status = 'Verified' THEN 'Approved'
        WHEN status = 'PendingReview' THEN 'Pending'
        WHEN status = 'Rejected' THEN 'Rejected'
        ELSE 'None' END
WHERE listed_via IN ('Listing', 'Staff')
  AND rent_review_status = 'None' AND tour_review_status = 'None';

CREATE INDEX IF NOT EXISTS ix_vehicles_purpose_queue
    ON udrive.vehicles (rent_review_status, tour_review_status)
    WHERE listed_via IN ('Listing', 'Staff');
