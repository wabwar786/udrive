-- The customer app offers four vehicles for travel: Car, Bike, Coster and
-- Hiace. Hiace had no row here at all, so its fare came from the app's built-in
-- fallback and the admin could not change it. This adds it.
--
-- `whole_vehicle_rate` and `per_seat_rate` are flat MINIMUMS, not rates per
-- kilometre; `per_km_rate` is what scales with the trip. The app previously
-- multiplied `whole_vehicle_rate` by the distance, which is why these three
-- columns are documented here rather than left to be inferred.

INSERT INTO udrive.service_vehicle_rates
    (service_type, vehicle_category, per_seat_rate, whole_vehicle_rate, per_km_rate)
VALUES
    ('City', 'Hiace', 400, 4500, 110),
    ('PrivateVehicle', 'Hiace', 500, 5500, 130)
ON CONFLICT (service_type, vehicle_category) DO UPDATE SET
    per_seat_rate = EXCLUDED.per_seat_rate,
    whole_vehicle_rate = EXCLUDED.whole_vehicle_rate,
    per_km_rate = EXCLUDED.per_km_rate,
    currency = 'PKR',
    is_active = true,
    updated_at = now();

-- Rickshaw is not one of the four travel options, so it stops being offered
-- rather than being deleted: an admin who wants it back flips is_active.
UPDATE udrive.service_vehicle_rates
SET is_active = false, updated_at = now()
WHERE lower(vehicle_category) = 'rickshaw'
  AND service_type IN ('City', 'PrivateVehicle');

COMMENT ON COLUMN udrive.service_vehicle_rates.per_km_rate IS
    'Rupees per kilometre. This is the rate that scales with trip distance.';
COMMENT ON COLUMN udrive.service_vehicle_rates.whole_vehicle_rate IS
    'Flat MINIMUM fare for the whole vehicle. Not a per-kilometre figure.';
COMMENT ON COLUMN udrive.service_vehicle_rates.per_seat_rate IS
    'Flat MINIMUM fare for one seat. Not a per-kilometre figure.';
