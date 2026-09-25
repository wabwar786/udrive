-- Two corrections to what 049-052 shipped.

-- ------------------------------------------------- one quote, one booking
--
-- quote_id was recorded and never checked, so a single signed quote could open
-- any number of ride requests for its whole lifetime. The band is per trip;
-- spending it twice is spending a price that was worked out for something else.
--
-- Partial, because rows created without a quote all carry NULL and there are
-- many of them.
CREATE UNIQUE INDEX IF NOT EXISTS ux_ride_requests_quote_id
    ON udrive.ride_requests(quote_id)
    WHERE quote_id IS NOT NULL;

-- ------------------------------------------- the commission default, really
--
-- 052 pointed ensure_driver_earning's fallback at
-- driver.commission.percentage, which was the right change and had no effect.
-- 009 seeds a commission_rules row -- 'Default platform commission', 15%, with
-- booking_type, city, driver_profile_id and effective_to all NULL -- and every
-- one of that lookup's `IS NULL OR ...` clauses is satisfied by it for every
-- booking. So the rule always matched, the fallback was unreachable, and the
-- ledger carried on booking 15% while the wallet was debited 10%.
--
-- Deactivated rather than deleted: it is the row that priced every settled
-- earning up to now, and those rows reference the percentage they were written
-- with. Any commission_rules row an admin created deliberately -- for a driver,
-- a city or a booking type -- is untouched and still wins.
UPDATE udrive.commission_rules
SET is_active = false, updated_at = now()
WHERE is_active = true
  AND name = 'Default platform commission'
  AND booking_type IS NULL
  AND city IS NULL
  AND driver_profile_id IS NULL
  AND effective_to IS NULL;

COMMENT ON INDEX udrive.ux_ride_requests_quote_id IS
    'One signed fare quote may open one ride request.';
