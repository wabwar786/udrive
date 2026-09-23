-- Phase 13.5 status compatibility and ride-request lifecycle support.
-- The migration runner owns the transaction; do not add BEGIN/COMMIT here.

-- Preserve existing data while allowing both accepted verification labels.
-- Runtime queries are case-insensitive and accept Approved or Verified.

-- Close stale requests immediately during deployment. Runtime services repeat
-- these idempotent transitions whenever customer/driver request lists load.
UPDATE udrive.ride_requests
SET status = 'Expired', version = version + 1, updated_at = now()
WHERE status IN ('Open', 'SearchingDrivers', 'ReceivingOffers')
  AND pickup_at <= now();

UPDATE udrive.ride_requests rr
SET status = 'NoDriverAccepted', version = version + 1, updated_at = now()
WHERE rr.status IN ('Open', 'SearchingDrivers', 'ReceivingOffers')
  AND rr.pickup_at > now()
  AND rr.expires_at IS NOT NULL
  AND rr.expires_at <= now()
  AND NOT EXISTS (
      SELECT 1 FROM udrive.driver_offers o WHERE o.ride_request_id = rr.id
  );

UPDATE udrive.ride_requests rr
SET status = 'Expired', version = version + 1, updated_at = now()
WHERE rr.status IN ('Open', 'SearchingDrivers', 'ReceivingOffers')
  AND rr.pickup_at > now()
  AND rr.expires_at IS NOT NULL
  AND rr.expires_at <= now()
  AND EXISTS (
      SELECT 1 FROM udrive.driver_offers o WHERE o.ride_request_id = rr.id
  );
