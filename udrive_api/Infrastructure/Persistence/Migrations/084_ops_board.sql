-- Ops board ("Aaj ke kaam"): what is happening today, and what to do about it.
--
-- The board itself is computed live from the tables that already exist
-- (ride_requests, driver_offers, trip_operations, presence...). These tables
-- hold only what the board adds:
--
--   ops_fare_adjustments  a temporary +/- percent on the fare of one vehicle
--                         class in one tehsil, set from a Rush or Rate card and
--                         ending by itself (normally at midnight, Pakistan time).
--                         Applied in FareEngine. Clamped to +/-20 percent.
--   road_reports          "Road band hai" from the driver app, with the spot.
--   ops_actions           what an admin decided on a card, and when. The board
--                         hides a dismissed card for a while, and the log shows
--                         who did what.
--   ops_messages          every WhatsApp an admin sent from the board: the text
--                         as sent, to how many people, by whom. The messages
--                         themselves go through whatsapp_outbox as before.
--   weather_readings      the latest forecast per place, fetched hourly from
--                         Open-Meteo (free, no key).
--
-- Safe to run more than once.

CREATE TABLE IF NOT EXISTS udrive.ops_fare_adjustments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    territory_id uuid NOT NULL REFERENCES udrive.territories(id),
    vehicle_class text NOT NULL,
    percent numeric(5,2) NOT NULL CHECK (percent BETWEEN -20 AND 20),
    reason text NOT NULL DEFAULT '',
    card_key text,
    starts_at timestamptz NOT NULL DEFAULT now(),
    ends_at timestamptz NOT NULL,
    ended_early_at timestamptz,
    created_by uuid REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_ops_fare_adjustments_live
    ON udrive.ops_fare_adjustments (territory_id, vehicle_class, ends_at)
    WHERE ended_early_at IS NULL;

CREATE TABLE IF NOT EXISTS udrive.road_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id),
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    kind text NOT NULL DEFAULT 'Blocked',
    note text NOT NULL DEFAULT '',
    territory_id uuid REFERENCES udrive.territories(id),
    status text NOT NULL DEFAULT 'Open',
    reviewed_by uuid REFERENCES udrive.users(id),
    reviewed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_road_reports_recent ON udrive.road_reports (created_at DESC) WHERE status = 'Open';

CREATE TABLE IF NOT EXISTS udrive.ops_actions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    card_key text NOT NULL,
    card_kind text NOT NULL,
    title text NOT NULL DEFAULT '',
    decision text NOT NULL,
    detail text NOT NULL DEFAULT '',
    hide_until timestamptz,
    actor_user_id uuid REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_ops_actions_card ON udrive.ops_actions (card_key, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_ops_actions_day ON udrive.ops_actions (created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.ops_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    card_key text,
    audience text NOT NULL,
    recipients integer NOT NULL,
    body text NOT NULL,
    actor_user_id uuid REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS udrive.weather_readings (
    place_key text PRIMARY KEY,
    name text NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    payload jsonb NOT NULL,
    fetched_at timestamptz NOT NULL DEFAULT now()
);
