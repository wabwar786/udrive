-- What a vehicle is used for, chosen once it has been approved.
--
-- There is one way to put a vehicle on the platform and it does not change:
-- the Driver registers it, an Admin verifies it. What was missing is the step
-- after that — saying what the vehicle is *for*.
--
-- Until now "for" was decided by absence. Any verified vehicle took city rides,
-- because nothing asked. Tour was the single exception, available_for_tour,
-- added in migration 030. And rental had no representation at all, so the one
-- thing a Driver would most want to say — "this car goes out on rent, stop
-- sending me city requests for it" — could not be said.

-- ─────────────────────────────────────────────────── 1. the three usages

-- City rides default to on, because that is what every verified vehicle does
-- today and a migration must not take work away from a Driver overnight.
ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS available_for_city boolean NOT NULL DEFAULT true;

-- Rental defaults to off: a Driver has to mean it, and it costs them their
-- city requests on that vehicle.
ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS available_for_rent boolean NOT NULL DEFAULT false;

-- available_for_tour already exists (migration 030).

-- Rent and city cannot both be on. A car out on rent is physically with
-- somebody else; it cannot also be taking city rides. The service enforces this
-- when writing, and this says the same thing in the one place that cannot be
-- bypassed.
ALTER TABLE udrive.vehicles
    DROP CONSTRAINT IF EXISTS ck_vehicles_rent_excludes_city;

ALTER TABLE udrive.vehicles
    ADD CONSTRAINT ck_vehicles_rent_excludes_city
        CHECK (NOT (available_for_rent AND available_for_city));

-- ───────────────────────────────────────────────── 2. what renting needs

-- Two rates, because renting a car here means one of two different things, and
-- an owner may offer either, or both:
--
--   with a driver   — the owner's own man drives; the customer hands over
--                     nothing but money, and no identity documents are needed
--   self-drive      — the customer drives, which is why that path asks for a
--                     CNIC and a licence
--
-- Both are nullable and at least one must be set before renting can be turned
-- on; the service checks that, because "at least one of two columns" is not a
-- thing a CHECK can say without also forbidding the half-filled state a Driver
-- passes through while typing.
ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS rent_with_driver_daily numeric(12,2),
    ADD COLUMN IF NOT EXISTS rent_self_drive_daily numeric(12,2),
    ADD COLUMN IF NOT EXISTS rent_security_deposit numeric(12,2),
    ADD COLUMN IF NOT EXISTS rent_minimum_days integer NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS rent_km_per_day integer,
    ADD COLUMN IF NOT EXISTS rent_fuel_included boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS rent_pickup_point varchar(200);

ALTER TABLE udrive.vehicles
    DROP CONSTRAINT IF EXISTS ck_vehicles_rent_amounts;

ALTER TABLE udrive.vehicles
    ADD CONSTRAINT ck_vehicles_rent_amounts
        CHECK (
            (rent_with_driver_daily IS NULL OR rent_with_driver_daily > 0)
            AND (rent_self_drive_daily IS NULL OR rent_self_drive_daily > 0)
            AND (rent_security_deposit IS NULL OR rent_security_deposit >= 0)
            AND rent_minimum_days >= 1
            AND (rent_km_per_day IS NULL OR rent_km_per_day > 0));

-- Finding the rentable fleet for a date range is a listing query, so it wants
-- its own index rather than a scan of every vehicle on the platform.
CREATE INDEX IF NOT EXISTS ix_vehicles_for_rent
    ON udrive.vehicles (available_for_rent)
    WHERE available_for_rent;

CREATE INDEX IF NOT EXISTS ix_vehicles_for_city
    ON udrive.vehicles (available_for_city)
    WHERE available_for_city;

-- ──────────────────────────────────────────── 3. getting the next job early

-- How long a vehicle needs between one job ending and the next beginning.
--
-- This replaces an assumption buried in two queries: when a trip had no return
-- time, the overlap check padded it by **eight hours**. A Driver who finished a
-- morning run was therefore invisible to the platform until the evening, and
-- had no idea why no work was arriving. Eight hours is not a turnaround, it is
-- a working day.
--
-- Sixty minutes is a turnaround: drop the passengers, fuel, clean, drive to the
-- next pickup. An Admin can raise it where the roads are longer.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'fleet.turnaround_minutes',
    to_jsonb(60),
    'Minutes a vehicle needs between one booking ending and the next starting. '
    || 'Used by every availability and overlap check.',
    false, now(), now())
ON CONFLICT (key) DO NOTHING;

-- How far before a trip ends the Driver may take the next one.
--
-- The point of this is business, not bookkeeping. A Driver carrying a party to
-- Neelum knows three hours before arriving that they will be free; that is
-- exactly when the return load should be offered to them. Waiting until the
-- trip is marked complete means the next customer has already booked somebody
-- else, and the Driver comes back empty.
--
-- It does not permit overlapping work: the new booking must still start after
-- this one ends plus the turnaround. It only decides how early the Driver is
-- allowed to see it and say yes.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'fleet.lead_window_minutes',
    to_jsonb(180),
    'How long before a trip ends a Driver may accept the next booking. Does not '
    || 'allow overlap; the next booking still starts after this one plus the '
    || 'turnaround.',
    false, now(), now())
ON CONFLICT (key) DO NOTHING;

-- How long a trip is assumed to take when nothing says.
--
-- This is the other half of the eight hours. `trip_operations.return_at` is
-- null for every one-way booking, and the overlap check filled the gap with
-- `pickup_at + interval '8 hours'`. So a Driver who took a twenty-minute city
-- ride at nine in the morning was treated as busy until five in the evening,
-- and every booking offered to them in between was refused as "overlapping".
--
-- Four hours is the honest guess for a road here when the booking itself does
-- not say, and being a setting it can be argued with. A real return time always
-- wins over it.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'fleet.assumed_trip_minutes',
    to_jsonb(240),
    'Assumed trip length when a booking has no return time. Only used by the '
    || 'overlap check, and only when return_at is null.',
    false, now(), now())
ON CONFLICT (key) DO NOTHING;

-- How close to the destination counts as "about to be free".
--
-- The ride-request feed already had this rule and already had it at one
-- kilometre, hard-coded: a Driver inside 1 km of their drop-off starts seeing
-- new requests again. One kilometre on a mountain road can be fifteen minutes
-- of switchbacks, which is not much notice for lining up the next job.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'fleet.near_destination_metres',
    to_jsonb(1500),
    'How close to the drop-off a Driver must be before new ride requests start '
    || 'reaching them again while the current trip is still running.',
    false, now(), now())
ON CONFLICT (key) DO NOTHING;
