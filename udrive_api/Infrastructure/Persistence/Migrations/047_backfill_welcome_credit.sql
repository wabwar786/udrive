-- Approved drivers who never got their welcome credit.
--
-- The credit is paid inside the approval transaction — but that code shipped
-- after some drivers were already approved. They have an approved profile, a
-- wallet, and nothing in it, which looks to them exactly like the feature not
-- working.
--
-- Migration 041 credited everyone approved at that moment, for a different
-- reason. Anyone approved between then and now falls in the gap.
--
-- Idempotent through the same `welcome:<driver_profile_id>` key the runtime
-- code uses, so a driver who was already credited is not credited again, and
-- re-running this changes nothing.

INSERT INTO udrive.driver_wallets
    (id, driver_profile_id, created_at, updated_at)
SELECT gen_random_uuid(), dp.id, now(), now()
FROM udrive.driver_profiles dp
WHERE dp.verification_status = 'Approved'
ON CONFLICT (driver_profile_id) DO NOTHING;

WITH bonus AS (
    SELECT COALESCE((SELECT (value_json #>> '{}')::numeric
                       FROM udrive.system_settings
                      WHERE key = 'driver.welcome.bonus'), 1000) AS amount
), owed AS (
    SELECT w.id AS wallet_id, w.driver_profile_id, bonus.amount
    FROM udrive.driver_wallets w
    JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
    CROSS JOIN bonus
    WHERE dp.verification_status = 'Approved'
      AND bonus.amount > 0
      AND NOT EXISTS (
            SELECT 1 FROM udrive.driver_wallet_entries e
            WHERE e.idempotency_key = 'welcome:' || w.driver_profile_id)
), credited AS (
    UPDATE udrive.driver_wallets w
    SET commission_balance = w.commission_balance + owed.amount,
        version = w.version + 1,
        updated_at = now()
    FROM owed
    WHERE w.id = owed.wallet_id
    RETURNING w.id AS wallet_id, owed.driver_profile_id, owed.amount
)
INSERT INTO udrive.driver_wallet_entries
    (id, wallet_id, entry_type, amount, balance_bucket,
     description, idempotency_key, created_at)
SELECT gen_random_uuid(), credited.wallet_id, 'CommissionTopup',
       credited.amount, 'Commission',
       'Welcome credit on approval',
       'welcome:' || credited.driver_profile_id, now()
FROM credited
ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL
DO NOTHING;
