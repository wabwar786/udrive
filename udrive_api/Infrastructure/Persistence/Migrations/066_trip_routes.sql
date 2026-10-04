-- Live-ride routes, computed once per leg and shared by both apps.
--
-- Before this, the driver's live screen and the customer's live screen each
-- asked Google for the road on their own, and asked again every time the car
-- moved 150 metres — thirty to sixty paid Routes calls for one ride, at the
-- TRAFFIC_AWARE (Pro) rate. Now the road for a leg is fetched once, stored
-- here, and read by both screens. A new row is only written when the driver
-- has genuinely left the road (a reroute), and even that is capped per leg
-- and per day.
--
-- `steps` carries the turns (maneuver, distance, where it starts) so the
-- driver's phone can speak them in Urdu with no further network at all.

CREATE TABLE IF NOT EXISTS udrive.trip_routes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
    leg text NOT NULL CHECK (leg IN ('pickup', 'destination')),
    reason text NOT NULL DEFAULT 'initial' CHECK (reason IN ('initial', 'reroute')),
    origin_latitude double precision NOT NULL,
    origin_longitude double precision NOT NULL,
    target_latitude double precision NOT NULL,
    target_longitude double precision NOT NULL,
    distance_meters integer NOT NULL CHECK (distance_meters >= 0),
    duration_seconds integer NOT NULL CHECK (duration_seconds >= 0),
    polyline text NOT NULL,
    steps jsonb NOT NULL DEFAULT '[]'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- "The newest route for this leg of this trip" — the only read either app makes.
CREATE INDEX IF NOT EXISTS ix_trip_routes_booking_leg
    ON udrive.trip_routes (booking_id, leg, created_at DESC);

-- The daily cap counts rows since midnight; this keeps that count cheap.
CREATE INDEX IF NOT EXISTS ix_trip_routes_created_at
    ON udrive.trip_routes (created_at);

-- Hard ceiling on paid route calls per Google quota day (midnight US Pacific,
-- which is when Google's own daily quota resets). Kept below the Essentials
-- free allowance of 10,000 a month so live rides cannot create a bill. Set it
-- to match the daily quota on the Routes API in Google Cloud Console.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'routing.google_daily_cap',
    to_jsonb(300),
    'Maximum Google Routes calls per day for live-ride navigation. When it is '
    || 'reached, live rides keep their last route and no new paid call is made.',
    false, now(), now())
ON CONFLICT (key) DO NOTHING;

-- Reroutes allowed per leg of one trip. Each is a paid call, so a driver who
-- wanders through a town does not turn one ride into twenty requests.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'routing.max_reroutes_per_leg',
    to_jsonb(6),
    'Maximum new routes for one leg of one live ride after the driver leaves '
    || 'the road. After that the driver keeps the last route.',
    false, now(), now())
ON CONFLICT (key) DO NOTHING;
