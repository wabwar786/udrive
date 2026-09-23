-- Fixed per-seat fares, by route.
--
-- A Coster running per seat in Kashmir is not a metered vehicle. It runs a
-- known route and every passenger pays the same known fare — Muzaffarabad to
-- Rawalakot is a price people already have in their heads, not a number
-- multiplied out of a distance.
--
-- Pricing that by kilometre produced a different figure for every pickup pin,
-- which is neither how the route works nor what anyone expects to pay. So a
-- per-seat trip on a route listed here is quoted the listed fare, and the
-- customer cannot bid it up or down. Whole-vehicle bookings are unaffected: a
-- hired Coster is still priced per kilometre and still negotiable.

CREATE TABLE IF NOT EXISTS udrive.seat_fares (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Defaults to Coster because that is what runs per seat here, but Hiace
    -- routes work the same way and the column keeps that open.
    vehicle_category varchar(40) NOT NULL DEFAULT 'Coster',

    -- Both ends as a named circle. Passengers do not board at a coordinate;
    -- they board somewhere in a town, so the radius is what makes "Rawalakot"
    -- mean the whole of Rawalakot.
    origin_label text NOT NULL,
    origin_latitude double precision NOT NULL,
    origin_longitude double precision NOT NULL,
    origin_radius_km double precision NOT NULL DEFAULT 10,

    destination_label text NOT NULL,
    destination_latitude double precision NOT NULL,
    destination_longitude double precision NOT NULL,
    destination_radius_km double precision NOT NULL DEFAULT 10,

    -- The fare, per passenger, for the whole route.
    per_seat_fare numeric(12,2) NOT NULL,

    -- Whether the same fare applies coming back. Almost always yes, and making
    -- an admin enter every route twice would guarantee the two halves drift.
    applies_both_ways boolean NOT NULL DEFAULT true,

    notes text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT seat_fares_fare_positive CHECK (per_seat_fare > 0),
    CONSTRAINT seat_fares_radius_positive CHECK (
        origin_radius_km > 0 AND destination_radius_km > 0
    )
);

CREATE INDEX IF NOT EXISTS ix_seat_fares_lookup
    ON udrive.seat_fares (lower(vehicle_category), is_active);

COMMENT ON TABLE udrive.seat_fares IS
    'Fixed per-seat route fares. Overrides per-km pricing for per-seat trips.';
COMMENT ON COLUMN udrive.seat_fares.per_seat_fare IS
    'What one passenger pays for the whole route. Not per kilometre.';
