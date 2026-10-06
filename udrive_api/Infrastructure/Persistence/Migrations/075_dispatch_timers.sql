-- Dispatch timers and the low-wallet warning.
--
-- 1. dispatch.driver_decision_seconds — how long a Driver has to answer a
--    ride request (the countdown on the card). Was 30 in the app.
-- 2. dispatch.offer_valid_seconds — how long a Driver's offer stays open to
--    the Customer for a ride wanted now. Was 120 in the API.
-- 3. driver.wallet.low_balance_alert — below this commission balance the
--    Driver is told to top up (one notification each time it drops below).
-- 4. driver_wallets.low_balance_notified_at — remembers that the warning for
--    the current drop has gone out; cleared when the balance is back above.
--
-- Safe to run more than once. Existing values are kept.

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES ('dispatch.driver_decision_seconds', to_jsonb('60'::text),
        'Seconds a driver has to answer a ride request.', true, now(), now())
ON CONFLICT (key) DO NOTHING;

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES ('dispatch.offer_valid_seconds', to_jsonb('180'::text),
        'Seconds a driver''s offer stays open to the customer (ride now).', true, now(), now())
ON CONFLICT (key) DO NOTHING;

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES ('driver.wallet.low_balance_alert', to_jsonb('50'::text),
        'Below this wallet balance (PKR) the driver is asked to top up.', true, now(), now())
ON CONFLICT (key) DO NOTHING;

ALTER TABLE udrive.driver_wallets
    ADD COLUMN IF NOT EXISTS low_balance_notified_at timestamptz;

-- One driver, one live offer hunt: finding a driver's open offers fast.
CREATE INDEX IF NOT EXISTS ix_driver_offers_driver_open
    ON udrive.driver_offers (driver_profile_id)
    WHERE status IN ('Pending', 'Countered', 'Accepted');
