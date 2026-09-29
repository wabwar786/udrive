-- Put the rickshaw back among the city ride options.
--
-- Migration 023 seeded rate rows for Bike, Car, Rickshaw and Coster on both
-- City and PrivateVehicle. Migration 033 then added Hiace, settled on four
-- travel options, and switched the rickshaw rows off:
--
--     -- Rickshaw is not one of the four travel options, so it stops being
--     -- offered rather than being deleted: an admin who wants it back flips
--     -- is_active.
--
-- This is that being flipped back. Nothing was deleted, so nothing has to be
-- reinvented: the per-km rate (40, from migration 025) and the seat capacity
-- (3, from migration 049) are still on the rows.
--
-- Why it has to be a migration rather than a change in the app.
--
-- MarketplacePricingService reads service_vehicle_rates WHERE is_active, so an
-- inactive rickshaw never reaches GET /catalog/service-rates. FareEngine then
-- refuses any category with no rate row — 422 rate_not_configured. Adding the
-- option to the picker without this would show a price built from the app's
-- own fallback numbers and then fail at the quote, which is worse than not
-- offering it at all.

UPDATE udrive.service_vehicle_rates
SET is_active = true,
    updated_at = now()
WHERE lower(vehicle_category) = 'rickshaw'
  AND service_type IN ('City', 'PrivateVehicle');

-- A pricing rule so the rickshaw appears in the admin portal's pricing table
-- alongside every other category.
--
-- Migration 035 seeded rules from active rate rows only, so the rickshaw was
-- skipped and has had no row an admin could edit. This copies the shape 035
-- used, and does nothing where a rule already exists.
INSERT INTO udrive.pricing_rules
    (name, service_type, vehicle_category, per_km_rate, minimum_fare, per_minute_rate)
SELECT
    r.vehicle_category || ' — standard (' || r.service_type || ')',
    r.service_type,
    r.vehicle_category,
    r.per_km_rate,
    r.whole_vehicle_rate,
    2
FROM udrive.service_vehicle_rates r
WHERE lower(r.vehicle_category) = 'rickshaw'
  AND r.service_type IN ('City', 'PrivateVehicle')
  AND r.is_active
  AND r.per_km_rate > 0
  AND NOT EXISTS (
      SELECT 1 FROM udrive.pricing_rules p
      WHERE p.service_type = r.service_type
        AND lower(p.vehicle_category) = lower(r.vehicle_category)
        AND p.area_radius_km IS NULL
        AND p.days_of_week IS NULL
  );
