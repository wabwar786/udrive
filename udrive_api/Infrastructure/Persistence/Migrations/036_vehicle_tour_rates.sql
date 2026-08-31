-- Tourism is priced by the vehicle, not by the admin.
--
-- A multi-day Kashmir trip is not a metered ride: the driver is away from home,
-- feeding and housing themselves, on roads that punish a vehicle. What that is
-- worth is a judgement only the person driving can make, and a single per-km
-- figure set centrally cannot express it.
--
-- So the admin's pricing rules deliberately do not apply to Tour. These columns
-- let each driver publish their own asking price instead.

ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS tour_per_day_rate numeric(12,2),
    ADD COLUMN IF NOT EXISTS tour_per_km_rate numeric(12,2),
    ADD COLUMN IF NOT EXISTS tour_minimum_fare numeric(12,2),
    ADD COLUMN IF NOT EXISTS tour_notes text;

COMMENT ON COLUMN udrive.vehicles.tour_per_day_rate IS
    'Driver''s own asking price for one day of touring. Null means unset.';
COMMENT ON COLUMN udrive.vehicles.tour_per_km_rate IS
    'Optional. Some drivers price long transfers by distance instead.';
COMMENT ON COLUMN udrive.vehicles.tour_minimum_fare IS
    'Driver''s floor for any tour booking, whatever the length.';
COMMENT ON COLUMN udrive.vehicles.tour_notes IS
    'What the price includes — fuel, driver food and lodging, and so on.';

-- Only tour-ready vehicles are ever read for this, and only the ones that have
-- actually named a price.
CREATE INDEX IF NOT EXISTS idx_vehicles_tour_rates
    ON udrive.vehicles (category, tour_per_day_rate)
    WHERE available_for_tour = true AND tour_per_day_rate IS NOT NULL;
