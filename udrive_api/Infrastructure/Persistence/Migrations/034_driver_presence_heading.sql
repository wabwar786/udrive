-- Nearby vehicles are drawn on the customer's map as small top-down cars
-- rotated to the direction they are facing. That needs a heading, and presence
-- was only storing position and accuracy.
--
-- Nullable on purpose: a stationary phone reports no heading, and an older
-- Driver build sends none at all. The map draws those unrotated rather than
-- pointing them somewhere invented.

ALTER TABLE udrive.driver_presence_locations
    ADD COLUMN IF NOT EXISTS heading double precision;

COMMENT ON COLUMN udrive.driver_presence_locations.heading IS
    'Compass bearing in degrees, 0 = north. Null when the device reports none.';
