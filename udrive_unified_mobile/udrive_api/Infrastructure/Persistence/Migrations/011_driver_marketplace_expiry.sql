-- Phase 13.5: Driver marketplace response window and request expiry.
-- Additive/idempotent; the migration runner owns the transaction.

UPDATE udrive.ride_requests
SET expires_at = created_at + interval '1 hour',
    updated_at = now()
WHERE status IN ('Open', 'ReceivingOffers')
  AND (expires_at IS NULL OR expires_at < created_at + interval '1 hour');

CREATE INDEX IF NOT EXISTS ix_ride_requests_driver_marketplace
    ON udrive.ride_requests(status, expires_at, pickup_at)
    WHERE status IN ('Open', 'ReceivingOffers');

CREATE INDEX IF NOT EXISTS ix_driver_offers_request_created
    ON udrive.driver_offers(ride_request_id, created_at DESC);
