-- Near me: local businesses that list themselves.
--
-- Restaurants, grocery shops, pharmacies, hospitals, ATMs, fuel stations and
-- mosques register from the app the way hotel owners do. A listing starts as
-- Pending and appears to customers only after an admin approves it in the
-- portal (Near me businesses). An owner's edit sends it back to Pending.
--
-- Opening hours are one daily window (opens_at → closes_at, which may cross
-- midnight) or open_24_hours. Both empty means the owner gave no hours, and
-- the app then says nothing about open or closed rather than guessing.
--
-- Distance is worked out with the haversine formula on latitude/longitude; a
-- listing count in the hundreds per town does not need a spatial index.

CREATE TABLE IF NOT EXISTS udrive.businesses (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id    uuid NOT NULL REFERENCES udrive.users(id),
    name             varchar(120) NOT NULL,
    category         varchar(30)  NOT NULL,
    address          varchar(300) NOT NULL,
    phone            varchar(30)  NOT NULL DEFAULT '',
    description      varchar(400) NOT NULL DEFAULT '',
    latitude         double precision NOT NULL,
    longitude        double precision NOT NULL,
    photo_url        varchar(500),
    open_24_hours    boolean NOT NULL DEFAULT false,
    opens_at         time,
    closes_at        time,
    approval_status  varchar(20) NOT NULL DEFAULT 'Pending',
    rejection_reason varchar(500),
    is_active        boolean NOT NULL DEFAULT true,
    reviewed_by      uuid REFERENCES udrive.users(id),
    reviewed_at      timestamptz,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_businesses_category CHECK (category IN
        ('Restaurant','Grocery','MedicalStore','Hospital','Bank','Fuel','Mosque')),
    CONSTRAINT ck_businesses_status CHECK (approval_status IN ('Pending','Approved','Rejected')),
    CONSTRAINT ck_businesses_latitude CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_businesses_longitude CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_businesses_hours CHECK (
        open_24_hours OR (opens_at IS NULL) = (closes_at IS NULL))
);

CREATE INDEX IF NOT EXISTS ix_businesses_live
    ON udrive.businesses (latitude, longitude)
    WHERE approval_status = 'Approved' AND is_active;

CREATE INDEX IF NOT EXISTS ix_businesses_owner
    ON udrive.businesses (owner_user_id);

CREATE INDEX IF NOT EXISTS ix_businesses_status
    ON udrive.businesses (approval_status, created_at);
