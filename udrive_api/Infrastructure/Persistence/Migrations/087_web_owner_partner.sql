-- 087: website owner area, "Become a partner" requests, hotel special dates,
-- and database-level limits on text that strangers can type.
--
-- Old rows are cleaned first (< and > removed, over-long text cut), so a
-- later update of an old row can never trip the new limits. The limits are
-- then added NOT VALID, so the deploy itself never scans or fails on data.
-- "No < or >" means no HTML or script can be stored, whatever client sends it.

-- ───────────────────────────── partner requests (website "Become a partner")
CREATE TABLE IF NOT EXISTS udrive.partner_requests (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference     varchar(20) NOT NULL UNIQUE,
    user_id       uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    full_name     varchar(80)  NOT NULL CHECK (full_name !~ '[<>]'),
    phone         varchar(20)  NOT NULL,
    email         varchar(160) CHECK (email IS NULL OR email ~* '^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$'),
    current_city  varchar(60)  NOT NULL CHECK (current_city !~ '[<>]'),
    target_city   varchar(60)  NOT NULL CHECK (target_city !~ '[<>]'),
    work          varchar(120) CHECK (work IS NULL OR work !~ '[<>]'),
    budget        varchar(8)   NOT NULL CHECK (budget IN ('1M', '2M', '3M', '4M+')),
    status        varchar(16)  NOT NULL DEFAULT 'New'
                  CHECK (status IN ('New', 'Contacted', 'Meeting', 'Approved', 'Declined', 'Closed')),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_partner_requests_status ON udrive.partner_requests (status, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_partner_requests_user ON udrive.partner_requests (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.partner_request_messages (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id     uuid NOT NULL REFERENCES udrive.partner_requests(id) ON DELETE CASCADE,
    author         varchar(12) NOT NULL CHECK (author IN ('Applicant', 'Team', 'Note')),
    body           varchar(1000) NOT NULL CHECK (length(btrim(body)) > 0 AND body !~ '[<>]'),
    whatsapp_sent  boolean NOT NULL DEFAULT false,
    created_by     uuid REFERENCES udrive.users(id) ON DELETE SET NULL,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_partner_messages_request ON udrive.partner_request_messages (request_id, created_at);

-- ───────────────────────────── hotel special dates (Eid, season…)
-- The owner's ranges. Each range is also written into hotel_room_inventory,
-- which is where search and booking already read a date's rate.
CREATE TABLE IF NOT EXISTS udrive.hotel_special_rates (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hotel_id    uuid NOT NULL REFERENCES udrive.hotels(id) ON DELETE CASCADE,
    room_id     uuid REFERENCES udrive.hotel_rooms(id) ON DELETE CASCADE,
    starts_on   date NOT NULL,
    ends_on     date NOT NULL,
    rate        numeric(12,2) CHECK (rate IS NULL OR (rate >= 1 AND rate <= 1000000)),
    percent     integer CHECK (percent IS NULL OR (percent BETWEEN -50 AND 200)),
    rooms_open  integer CHECK (rooms_open IS NULL OR rooms_open BETWEEN 0 AND 500),
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT hotel_special_rates_one_kind CHECK ((rate IS NULL) <> (percent IS NULL)),
    CONSTRAINT hotel_special_rates_range CHECK (ends_on >= starts_on AND ends_on - starts_on <= 120)
);
CREATE INDEX IF NOT EXISTS ix_hotel_special_rates_hotel ON udrive.hotel_special_rates (hotel_id, starts_on);

-- ───────────────────────────── clean old rows before the limits
UPDATE udrive.hotels SET
       name = left(regexp_replace(name, '[<>]', '', 'g'), 160),
       description = left(regexp_replace(description, '[<>]', '', 'g'), 3000),
       address = left(regexp_replace(address, '[<>]', '', 'g'), 300),
       city = left(regexp_replace(city, '[<>]', '', 'g'), 80),
       district = left(regexp_replace(district, '[<>]', '', 'g'), 80),
       contact_phone = left(contact_phone, 32)
 WHERE name ~ '[<>]' OR length(name) > 160
    OR description ~ '[<>]' OR length(description) > 3000
    OR address ~ '[<>]' OR length(address) > 300
    OR city ~ '[<>]' OR length(city) > 80
    OR district ~ '[<>]' OR length(district) > 80
    OR length(contact_phone) > 32;
UPDATE udrive.hotel_rooms SET
       room_type = left(regexp_replace(room_type, '[<>]', '', 'g'), 80),
       description = left(regexp_replace(description, '[<>]', '', 'g'), 600)
 WHERE room_type ~ '[<>]' OR length(room_type) > 80 OR description ~ '[<>]' OR length(description) > 600;
UPDATE udrive.vehicles SET
       make = regexp_replace(make, '[<>]', '', 'g'), model = regexp_replace(model, '[<>]', '', 'g'),
       rent_pickup_point = regexp_replace(rent_pickup_point, '[<>]', '', 'g'),
       registration_number = regexp_replace(registration_number, '[<>]', '', 'g')
 WHERE make ~ '[<>]' OR model ~ '[<>]' OR rent_pickup_point ~ '[<>]' OR registration_number ~ '[<>]';
UPDATE udrive.tour_packages SET
       title = regexp_replace(title, '[<>]', '', 'g'), starting_city = regexp_replace(starting_city, '[<>]', '', 'g'),
       pickup_point = regexp_replace(pickup_point, '[<>]', '', 'g'),
       description = left(regexp_replace(description, '[<>]', '', 'g'), 4000)
 WHERE title ~ '[<>]' OR starting_city ~ '[<>]' OR pickup_point ~ '[<>]' OR description ~ '[<>]' OR length(description) > 4000;
UPDATE udrive.fleet_drivers SET full_name = regexp_replace(full_name, '[<>]', '', 'g') WHERE full_name ~ '[<>]';
UPDATE udrive.web_ads SET
       title = regexp_replace(title, '[<>]', '', 'g'), body = regexp_replace(body, '[<>]', '', 'g'),
       cta_label = regexp_replace(cta_label, '[<>]', '', 'g')
 WHERE title ~ '[<>]' OR body ~ '[<>]' OR cta_label ~ '[<>]';

-- ───────────────────────────── text limits on owner-typed columns
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'hotels_text_limits') THEN
        ALTER TABLE udrive.hotels ADD CONSTRAINT hotels_text_limits CHECK (
            length(name) <= 160 AND name !~ '[<>]'
            AND length(COALESCE(description, '')) <= 3000 AND COALESCE(description, '') !~ '[<>]'
            AND length(COALESCE(address, '')) <= 300 AND COALESCE(address, '') !~ '[<>]'
            AND length(COALESCE(city, '')) <= 80 AND COALESCE(city, '') !~ '[<>]'
            AND length(COALESCE(district, '')) <= 80 AND COALESCE(district, '') !~ '[<>]'
            AND length(COALESCE(contact_phone, '')) <= 32
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'hotel_rooms_text_limits') THEN
        ALTER TABLE udrive.hotel_rooms ADD CONSTRAINT hotel_rooms_text_limits CHECK (
            length(room_type) <= 80 AND room_type !~ '[<>]'
            AND length(COALESCE(description, '')) <= 600 AND COALESCE(description, '') !~ '[<>]'
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'vehicles_text_markup') THEN
        ALTER TABLE udrive.vehicles ADD CONSTRAINT vehicles_text_markup CHECK (
            COALESCE(make, '') !~ '[<>]' AND COALESCE(model, '') !~ '[<>]'
            AND COALESCE(rent_pickup_point, '') !~ '[<>]' AND COALESCE(registration_number, '') !~ '[<>]'
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tour_packages_text_markup') THEN
        ALTER TABLE udrive.tour_packages ADD CONSTRAINT tour_packages_text_markup CHECK (
            title !~ '[<>]' AND starting_city !~ '[<>]' AND pickup_point !~ '[<>]'
            AND length(COALESCE(description, '')) <= 4000 AND COALESCE(description, '') !~ '[<>]'
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fleet_drivers_text_markup') THEN
        ALTER TABLE udrive.fleet_drivers ADD CONSTRAINT fleet_drivers_text_markup CHECK (full_name !~ '[<>]') NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'web_ads_text_markup') THEN
        ALTER TABLE udrive.web_ads ADD CONSTRAINT web_ads_text_markup CHECK (
            title !~ '[<>]' AND body !~ '[<>]' AND cta_label !~ '[<>]'
        ) NOT VALID;
    END IF;
END $$;
