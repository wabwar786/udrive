-- 028: Per-vehicle booking mode.
--
-- A driver decides how their vehicle can be booked:
--
--   'WholeVehicle'  the customer books the whole vehicle (the default)
--   'PerSeat'       the customer books individual seats
--   'Both'          either is allowed
--
-- The customer app offers only what the vehicle actually supports, so a
-- seat-only vehicle can never be booked whole, and a whole-vehicle-only one can
-- never be booked by the seat.
--
-- Default is 'WholeVehicle' so existing vehicles keep behaving as they do today
-- until a driver opts into per-seat.

ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS booking_mode text NOT NULL DEFAULT 'WholeVehicle';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'vehicles_booking_mode_check'
    ) THEN
        ALTER TABLE udrive.vehicles
            ADD CONSTRAINT vehicles_booking_mode_check
            CHECK (booking_mode IN ('WholeVehicle', 'PerSeat', 'Both'));
    END IF;
END $$;

-- Single-seat vehicles cannot sensibly be sold "per seat" as a shared ride,
-- and large vehicles are commonly sold both ways. Seed sensible starting
-- values; drivers can change theirs at any time.
UPDATE udrive.vehicles
   SET booking_mode = 'Both'
 WHERE passenger_capacity >= 10
   AND booking_mode = 'WholeVehicle';

CREATE INDEX IF NOT EXISTS idx_vehicles_booking_mode
    ON udrive.vehicles (booking_mode);
