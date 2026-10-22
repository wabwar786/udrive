-- 086: the UDrive website ("UDrive – Travel & Tour").
--
-- The website is static files. It never touches this database: everything it
-- shows comes from the read-only /api/v1/web endpoints, and a tour booking or
-- hotel registration goes through the same OTP sign-in and server-side checks
-- as the app. These columns and the ads table are all it adds.

-- Where a booking / hotel came from, so the admin "Website" page can list them.
ALTER TABLE udrive.bookings ADD COLUMN IF NOT EXISTS channel varchar(16) NOT NULL DEFAULT 'App';
ALTER TABLE udrive.hotels   ADD COLUMN IF NOT EXISTS source  varchar(16) NOT NULL DEFAULT 'App';

CREATE INDEX IF NOT EXISTS ix_bookings_channel_web ON udrive.bookings (created_at DESC) WHERE channel = 'Web';
CREATE INDEX IF NOT EXISTS ix_hotels_source_web    ON udrive.hotels (created_at DESC) WHERE source = 'Web';

-- Ad places on the website, filled by the admin (no Google AdSense).
CREATE TABLE IF NOT EXISTS udrive.web_ads (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slot        varchar(16) NOT NULL CHECK (slot IN ('home', 'tours', 'tour', 'hotels', 'hotel')),
    title       varchar(120) NOT NULL,
    body        varchar(300) NOT NULL DEFAULT '',
    image_url   text,
    link_url    text,
    cta_label   varchar(40) NOT NULL DEFAULT 'View',
    starts_on   date,
    ends_on     date,
    is_active   boolean NOT NULL DEFAULT true,
    sort_order  integer NOT NULL DEFAULT 0,
    clicks      integer NOT NULL DEFAULT 0,
    created_by  uuid REFERENCES udrive.users(id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT web_ads_link_https CHECK (link_url IS NULL OR link_url ~* '^https://'),
    CONSTRAINT web_ads_dates CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on)
);

CREATE INDEX IF NOT EXISTS ix_web_ads_slot ON udrive.web_ads (slot, sort_order) WHERE is_active;
