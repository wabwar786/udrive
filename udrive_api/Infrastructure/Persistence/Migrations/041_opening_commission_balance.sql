-- Migration 040 switched the marketplace off for every existing Driver.
--
-- It added `commission_balance` defaulting to 0, and a rule in
-- `GetEligibleRideRequestsAsync` that a Driver only sees requests while their
-- balance is *above* the minimum — which also defaults to 0. So every Driver
-- already on the platform went from 0 to `0 > 0`, which is false, and stopped
-- receiving any request at all. No error, no notice: the requests simply
-- stopped arriving.
--
-- That is the wrong way to introduce a charge. Someone who was driving
-- yesterday should not be cut off by a rule they were never told about, and the
-- first they knew of it was an empty screen.
--
-- Every Driver who is approved today is given an opening credit. New Drivers
-- registering after this still start at zero and must top up before their first
-- ride, which is the intended arrangement.

INSERT INTO udrive.driver_wallets
    (id, driver_profile_id, commission_balance, created_at, updated_at)
SELECT gen_random_uuid(), dp.id, 1000, now(), now()
FROM udrive.driver_profiles dp
WHERE dp.verification_status = 'Approved'
ON CONFLICT (driver_profile_id) DO UPDATE SET
    -- Only tops up a wallet that is at or below zero. A Driver who has already
    -- paid keeps what they paid; this is not a bonus on top.
    commission_balance = GREATEST(udrive.driver_wallets.commission_balance, 1000),
    updated_at = now();

-- A balance with no entry behind it cannot be explained to the Driver who asks
-- where it came from.
INSERT INTO udrive.driver_wallet_entries
    (id, wallet_id, entry_type, amount, balance_bucket, description,
     idempotency_key, created_at)
SELECT gen_random_uuid(), w.id, 'CommissionTopup', 1000, 'Commission',
       'Opening balance when prepaid commission was introduced',
       'opening:' || w.id, now()
FROM udrive.driver_wallets w
JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
WHERE dp.verification_status = 'Approved'
ON CONFLICT (idempotency_key) DO NOTHING;
