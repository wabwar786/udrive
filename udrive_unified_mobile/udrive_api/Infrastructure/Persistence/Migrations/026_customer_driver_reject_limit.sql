-- Per ride + per Driver explicit Customer reject counter.
ALTER TABLE udrive.driver_ride_request_decisions
    ADD COLUMN IF NOT EXISTS customer_reject_count integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_customer_rejected_at timestamptz;

ALTER TABLE udrive.driver_ride_request_decisions
    DROP CONSTRAINT IF EXISTS ck_driver_request_customer_reject_count;
ALTER TABLE udrive.driver_ride_request_decisions
    ADD CONSTRAINT ck_driver_request_customer_reject_count
    CHECK (customer_reject_count BETWEEN 0 AND 5);

CREATE INDEX IF NOT EXISTS ix_driver_request_customer_reject_limit
    ON udrive.driver_ride_request_decisions(ride_request_id, driver_profile_id, customer_reject_count);
