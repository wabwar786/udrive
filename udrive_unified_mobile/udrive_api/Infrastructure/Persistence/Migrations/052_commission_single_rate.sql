-- One commission percentage, read from one place.
--
-- UDrive has been running two commission systems side by side against the same
-- bookings.total_amount:
--
--   DriverWalletService.ChargeCommissionAsync debits the driver's prepaid
--   wallet at TripStarted, at driver.commission.percentage (default 10). This
--   is the one that actually moves money and the one the admin's slider edits.
--
--   ensure_driver_earning, the trigger below, books an earnings ledger row at
--   Completed at COALESCE(commission_rules.percentage, 15). This is the one
--   the finance dashboard reports.
--
-- So the wallet was debited 10% while the dashboard reported 15%, and the two
-- never reconciled. The slider moved one of them.
--
-- The fix is only to the fallback. An explicit commission_rules row still
-- wins — that is a deliberate override for a driver, city or booking type, and
-- taking it away would silently reprice those agreements. What changes is that
-- when no rule matches, both systems now read the same setting instead of one
-- reading a number compiled into a trigger.
--
-- Rows already written keep the percentage they were written with. Restating
-- settled earnings would change history that drivers have already been paid
-- against.

CREATE OR REPLACE FUNCTION udrive.ensure_driver_earning(p_booking_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_driver uuid;
    v_gross numeric(14,2);
    v_type varchar(40);
    v_city varchar(120);
    v_pct numeric(5,2);
    v_wallet uuid;
    v_earning uuid;
    v_net numeric(14,2);
BEGIN
    SELECT b.driver_profile_id, b.total_amount, b.booking_type, b.pickup_label
      INTO v_driver, v_gross, v_type, v_city
      FROM udrive.bookings b WHERE b.id=p_booking_id;
    IF v_driver IS NULL OR v_gross IS NULL THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM udrive.driver_earnings WHERE booking_id=p_booking_id) THEN RETURN; END IF;

    SELECT percentage INTO v_pct FROM udrive.commission_rules
     WHERE is_active=true AND effective_from<=now() AND (effective_to IS NULL OR effective_to>now())
       AND (booking_type IS NULL OR booking_type=v_type)
       AND (city IS NULL OR lower(city)=lower(v_city))
       AND (driver_profile_id IS NULL OR driver_profile_id=v_driver)
     ORDER BY (driver_profile_id IS NOT NULL) DESC,(city IS NOT NULL) DESC,(booking_type IS NOT NULL) DESC,effective_from DESC LIMIT 1;

    -- The fallback, previously the literal 15. Same key and same default as
    -- DriverWalletService.ChargeCommissionAsync, so the wallet debit and the
    -- ledger entry cannot drift apart again.
    IF v_pct IS NULL THEN
        SELECT (value_json #>> '{}')::numeric INTO v_pct
          FROM udrive.system_settings
         WHERE key = 'driver.commission.percentage';
    END IF;
    v_pct := COALESCE(v_pct, 10);

    v_net := round(v_gross - (v_gross*v_pct/100),2);
    v_earning := gen_random_uuid();
    INSERT INTO udrive.driver_earnings(id,booking_id,driver_profile_id,gross_amount,commission_percentage,commission_amount,net_amount,status,available_at,created_at,updated_at)
    VALUES(v_earning,p_booking_id,v_driver,v_gross,v_pct,round(v_gross*v_pct/100,2),v_net,'Available',now(),now(),now());
    INSERT INTO udrive.driver_wallets(id,driver_profile_id,available_balance,created_at,updated_at)
    VALUES(gen_random_uuid(),v_driver,v_net,now(),now())
    ON CONFLICT(driver_profile_id) DO UPDATE SET available_balance=udrive.driver_wallets.available_balance+excluded.available_balance,version=udrive.driver_wallets.version+1,updated_at=now()
    RETURNING id INTO v_wallet;
    INSERT INTO udrive.driver_wallet_entries(id,wallet_id,booking_id,earning_id,entry_type,amount,balance_bucket,description,idempotency_key,created_at)
    VALUES(gen_random_uuid(),v_wallet,p_booking_id,v_earning,'TripEarning',v_net,'Available','Net earning from completed trip','earning:'||p_booking_id,now());
END
$$;

-- Make sure the key the trigger now reads actually exists. 040 created it, but
-- an environment restored from an older dump may not have it, and a missing
-- key would silently fall to the hardcoded 10 above.
INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES ('driver.commission.percentage', '10'::jsonb,
        'Platform commission on a completed trip, as a percentage. Read by both the wallet debit and the earnings ledger.',
        false, now(), now())
ON CONFLICT (key) DO NOTHING;
