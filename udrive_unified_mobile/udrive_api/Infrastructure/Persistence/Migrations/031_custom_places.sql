-- 031: Places an admin can add by hand.
--
-- Google's coverage thins out fast in Azad Kashmir. Villages up the Neelum and
-- Leepa valleys, and anywhere reached by unpaved track, often have no entry at
-- all — and those are exactly the journeys this app exists for.
--
-- This lets an admin drop a pin and give it a name, so customers can search for
-- places Google has never heard of. Entries are matched ahead of Google's
-- results, because in this app a local name almost always means the local
-- place.

CREATE TABLE IF NOT EXISTS udrive.custom_places (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name          text NOT NULL,
    district      text NOT NULL DEFAULT '',
    -- Alternative spellings, one per row of the array. People type what they
    -- say, and Kashmiri place names have many romanisations.
    aliases       text[] NOT NULL DEFAULT '{}',
    latitude      double precision NOT NULL,
    longitude     double precision NOT NULL,
    -- Free text shown under the name in search results: "reached by jeep
    -- track", "ask for the school", that kind of thing.
    note          text NOT NULL DEFAULT '',
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT custom_places_latitude_range
        CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT custom_places_longitude_range
        CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT custom_places_name_not_blank
        CHECK (length(btrim(name)) > 0)
);

-- Search matches on lowercase name and aliases.
CREATE INDEX IF NOT EXISTS idx_custom_places_name_lower
    ON udrive.custom_places (lower(name))
    WHERE is_active = true;

CREATE UNIQUE INDEX IF NOT EXISTS idx_custom_places_unique_name
    ON udrive.custom_places (lower(btrim(name)));

-- Seeded from the built-in list so nothing is lost when the code stops
-- shipping one. Everything here is editable in the admin portal from now on.
INSERT INTO udrive.custom_places (name, district, aliases, latitude, longitude)
VALUES
    ('Muzaffarabad',  'Muzaffarabad', ARRAY['muzafarabad'],       34.3700, 73.4711),
    ('Domel',         'Muzaffarabad', ARRAY[]::text[],            34.3556, 73.4744),
    ('Garhi Dupatta', 'Muzaffarabad', ARRAY['ghari dupatta'],     34.2231, 73.6011),
    ('Chikar',        'Muzaffarabad', ARRAY['chikkar'],           34.1289, 73.6892),
    ('Pir Chinasi',   'Muzaffarabad', ARRAY['peer chinasi'],      34.3667, 73.5833),
    ('Hattian Bala',  'Hattian Bala', ARRAY['hattian'],           34.1631, 73.7519),
    ('Chakothi',      'Hattian Bala', ARRAY['chakoti'],           34.0356, 73.9028),
    ('Leepa Valley',  'Hattian Bala', ARRAY['leepa'],             34.1856, 73.9944),
    ('Athmuqam',      'Neelum',       ARRAY['atmuqam'],           34.5822, 73.8992),
    ('Kundal Shahi',  'Neelum',       ARRAY['kundalshahi'],       34.5342, 73.8189),
    ('Keran',         'Neelum',       ARRAY[]::text[],            34.6247, 73.9139),
    ('Sharda',        'Neelum',       ARRAY['shardi'],            34.7906, 74.1806),
    ('Kel',           'Neelum',       ARRAY['kail'],              34.8244, 74.3517),
    ('Arang Kel',     'Neelum',       ARRAY['arangkel'],          34.7900, 74.3400),
    ('Neelum Valley', 'Neelum',       ARRAY['neelam valley'],     34.5900, 73.9100),
    ('Bagh',          'Bagh',         ARRAY[]::text[],            33.9797, 73.7728),
    ('Dhirkot',       'Bagh',         ARRAY['dheerkot'],          33.9206, 73.6500),
    ('Rawalakot',     'Poonch',       ARRAY['rawlakot'],          33.8578, 73.7604),
    ('Toli Peer',     'Poonch',       ARRAY['tolipir'],           33.8167, 73.8833),
    ('Banjosa Lake',  'Poonch',       ARRAY['banjosa'],           33.7833, 73.8000),
    ('Kotli',         'Kotli',        ARRAY[]::text[],            33.5183, 73.9020),
    ('Mirpur',        'Mirpur',       ARRAY['mirpur ajk'],        33.1478, 73.7519),
    ('Dadyal',        'Mirpur',       ARRAY['dadial'],            33.1050, 73.6600),
    ('Bhimber',       'Bhimber',      ARRAY[]::text[],            32.9750, 74.0800),
    ('Pallandri',     'Sudhanoti',    ARRAY['palandri'],          33.7100, 73.6800)
ON CONFLICT DO NOTHING;
