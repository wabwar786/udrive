-- 030: Tour availability per vehicle.
--
-- Tour is a service the customer picks, not a vehicle category, so which
-- vehicles can serve a tour has to be a property of the vehicle rather than
-- something inferred from its make or seat count.
--
-- Defaults to false: a driver opts in. A vehicle that has not opted in must
-- never appear in a tour search, so silently defaulting everyone to true would
-- put drivers on multi-day mountain trips they never agreed to.

ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS available_for_tour boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_vehicles_available_for_tour
    ON udrive.vehicles (available_for_tour)
    WHERE available_for_tour = true;

-- Per-seat selling only makes sense when there are spare seats to sell. A car
-- with five seats or fewer is a whole-vehicle booking whatever the driver set,
-- and this is enforced again at booking time in BookingService.
UPDATE udrive.vehicles
   SET booking_mode = 'WholeVehicle'
 WHERE passenger_capacity <= 5
   AND booking_mode <> 'WholeVehicle';
