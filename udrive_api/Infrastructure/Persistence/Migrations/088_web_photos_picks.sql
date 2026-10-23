-- 088: website destination photos (found weekly on Wikimedia Commons, or
-- uploaded by the team) and the two facts "Where to go this week" needs that
-- the destinations table does not have yet: what kind of place it is and how
-- long the drive from Muzaffarabad takes (optional; estimated when empty).

ALTER TABLE udrive.destinations ADD COLUMN IF NOT EXISTS web_kind varchar(16);
ALTER TABLE udrive.destinations ADD COLUMN IF NOT EXISTS drive_hours numeric(4,1);
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'destinations_web_kind_check') THEN
        ALTER TABLE udrive.destinations ADD CONSTRAINT destinations_web_kind_check
            CHECK (web_kind IS NULL OR web_kind IN ('lake', 'meadow', 'river'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'destinations_drive_hours_check') THEN
        ALTER TABLE udrive.destinations ADD CONSTRAINT destinations_drive_hours_check
            CHECK (drive_hours IS NULL OR (drive_hours > 0 AND drive_hours <= 24));
    END IF;
END $$;

-- What each known place is. Unknown ones stay empty and count as "Any".
UPDATE udrive.destinations SET web_kind = 'lake'
 WHERE web_kind IS NULL AND slug IN ('ratti-gali-lake', 'chitta-katha-lake', 'banjosa-lake', 'mangla-lake');
UPDATE udrive.destinations SET web_kind = 'meadow'
 WHERE web_kind IS NULL AND slug IN ('arang-kel', 'taobat', 'toli-pir', 'pir-chinasi', 'ganga-choti', 'sudhan-gali',
                                     'las-danna', 'shaheed-gali', 'upper-neelum', 'baboon-valley', 'dao-khan');
UPDATE udrive.destinations SET web_kind = 'river'
 WHERE web_kind IS NULL AND slug IN ('muzaffarabad', 'neelum-valley', 'athmuqam', 'keran', 'kutton-jagran', 'sharda', 'kel',
                                     'leepa-valley', 'reshian', 'chakothi', 'rawalakot', 'poonch-river', 'haveli-kahuta',
                                     'mirpur', 'bhimber', 'samahni-valley', 'jhelum-valley', 'dhirkot', 'kotli', 'ramkot-fort');

CREATE TABLE IF NOT EXISTS udrive.web_photos (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    destination_id uuid NOT NULL REFERENCES udrive.destinations(id) ON DELETE CASCADE,
    source         varchar(16) NOT NULL CHECK (source IN ('Commons', 'Own')),
    source_ref     varchar(40) NOT NULL,             -- Commons page id, or the upload's own id
    url            varchar(600) NOT NULL CHECK (url ~ '^(https://upload\.wikimedia\.org/|/api/v1/web-images/)' AND url !~ '[<>"''\s]'),
    page_url       varchar(300) CHECK (page_url IS NULL OR page_url ~ '^https://commons\.wikimedia\.org/'),
    author         varchar(160) NOT NULL DEFAULT '' CHECK (author !~ '[<>]'),
    license        varchar(60)  NOT NULL DEFAULT '' CHECK (license !~ '[<>]'),
    license_url    varchar(300) CHECK (license_url IS NULL OR license_url ~ '^https://'),
    season         varchar(10)  NOT NULL DEFAULT 'any' CHECK (season IN ('snow', 'winter', 'spring', 'summer', 'autumn', 'any')),
    taken_month    smallint CHECK (taken_month IS NULL OR taken_month BETWEEN 1 AND 12),
    width          int NOT NULL DEFAULT 0,
    height         int NOT NULL DEFAULT 0,
    hidden         boolean NOT NULL DEFAULT false,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (destination_id, source, source_ref)
);
CREATE INDEX IF NOT EXISTS ix_web_photos_destination ON udrive.web_photos (destination_id) WHERE NOT hidden;
