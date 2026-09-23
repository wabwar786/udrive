ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS idempotency_key varchar(120);
ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS refund_amount numeric(12,2) NOT NULL DEFAULT 0;
ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS review_notes varchar(1000);
ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS reviewed_by_user_id uuid REFERENCES udrive.users(id);
ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;
CREATE UNIQUE INDEX IF NOT EXISTS ux_payments_idempotency ON udrive.payments(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_payments_status_created ON udrive.payments(status, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.commission_rules (
    id uuid PRIMARY KEY,
    name varchar(160) NOT NULL,
    percentage numeric(5,2) NOT NULL CHECK (percentage >= 0 AND percentage <= 100),
    booking_type varchar(40),
    city varchar(120),
    driver_profile_id uuid REFERENCES udrive.driver_profiles(id),
    is_active boolean NOT NULL DEFAULT true,
    effective_from timestamptz NOT NULL,
    effective_to timestamptz,
    created_by_user_id uuid REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_commission_rules_match ON udrive.commission_rules(is_active, booking_type, city, driver_profile_id, effective_from DESC);

CREATE TABLE IF NOT EXISTS udrive.driver_wallets (
    id uuid PRIMARY KEY,
    driver_profile_id uuid NOT NULL UNIQUE REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    pending_balance numeric(14,2) NOT NULL DEFAULT 0,
    available_balance numeric(14,2) NOT NULL DEFAULT 0,
    paid_balance numeric(14,2) NOT NULL DEFAULT 0,
    currency varchar(3) NOT NULL DEFAULT 'PKR',
    version integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.driver_earnings (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL UNIQUE REFERENCES udrive.bookings(id),
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id),
    gross_amount numeric(14,2) NOT NULL,
    commission_percentage numeric(5,2) NOT NULL,
    commission_amount numeric(14,2) NOT NULL,
    net_amount numeric(14,2) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'Available',
    available_at timestamptz,
    paid_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_driver_earnings_driver_status ON udrive.driver_earnings(driver_profile_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.driver_wallet_entries (
    id uuid PRIMARY KEY,
    wallet_id uuid NOT NULL REFERENCES udrive.driver_wallets(id) ON DELETE CASCADE,
    booking_id uuid REFERENCES udrive.bookings(id),
    earning_id uuid REFERENCES udrive.driver_earnings(id),
    payout_request_id uuid,
    entry_type varchar(40) NOT NULL,
    amount numeric(14,2) NOT NULL,
    balance_bucket varchar(24) NOT NULL,
    description varchar(500) NOT NULL,
    reference varchar(160),
    idempotency_key varchar(160),
    created_by_user_id uuid REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_wallet_entries_idempotency ON udrive.driver_wallet_entries(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_wallet_entries_wallet_created ON udrive.driver_wallet_entries(wallet_id, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.driver_payout_requests (
    id uuid PRIMARY KEY,
    driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id),
    amount numeric(14,2) NOT NULL CHECK (amount > 0),
    currency varchar(3) NOT NULL DEFAULT 'PKR',
    status varchar(32) NOT NULL DEFAULT 'Pending',
    payout_method varchar(40) NOT NULL,
    destination_masked varchar(160),
    provider_reference varchar(160),
    driver_notes varchar(1000),
    review_notes varchar(1000),
    requested_at timestamptz NOT NULL,
    reviewed_by_user_id uuid REFERENCES udrive.users(id),
    reviewed_at timestamptz,
    paid_at timestamptz,
    version integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_payout_requests_status ON udrive.driver_payout_requests(status, requested_at DESC);

ALTER TABLE udrive.driver_wallet_entries DROP CONSTRAINT IF EXISTS fk_wallet_entry_payout;
ALTER TABLE udrive.driver_wallet_entries ADD CONSTRAINT fk_wallet_entry_payout FOREIGN KEY (payout_request_id) REFERENCES udrive.driver_payout_requests(id);

CREATE TABLE IF NOT EXISTS udrive.refund_requests (
    id uuid PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES udrive.bookings(id),
    payment_id uuid REFERENCES udrive.payments(id),
    requested_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
    amount numeric(14,2) NOT NULL CHECK (amount > 0),
    cancellation_fee numeric(14,2) NOT NULL DEFAULT 0,
    reason varchar(1000) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'Pending',
    provider_reference varchar(160),
    review_notes varchar(1000),
    reviewed_by_user_id uuid REFERENCES udrive.users(id),
    reviewed_at timestamptz,
    completed_at timestamptz,
    version integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_refund_requests_status ON udrive.refund_requests(status, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.financial_adjustments (
    id uuid PRIMARY KEY,
    driver_profile_id uuid REFERENCES udrive.driver_profiles(id),
    booking_id uuid REFERENCES udrive.bookings(id),
    adjustment_type varchar(32) NOT NULL,
    amount numeric(14,2) NOT NULL CHECK (amount <> 0),
    reason varchar(1000) NOT NULL,
    created_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_financial_adjustments_driver ON udrive.financial_adjustments(driver_profile_id, created_at DESC);

CREATE OR REPLACE FUNCTION udrive.ensure_driver_earning(p_booking_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
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
    v_pct := COALESCE(v_pct, 15);
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
END $$;

CREATE OR REPLACE FUNCTION udrive.booking_finance_completion_trigger()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status='Completed' AND OLD.status IS DISTINCT FROM NEW.status THEN PERFORM udrive.ensure_driver_earning(NEW.id); END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_booking_finance_completion ON udrive.bookings;
CREATE TRIGGER trg_booking_finance_completion AFTER UPDATE OF status ON udrive.bookings FOR EACH ROW EXECUTE FUNCTION udrive.booking_finance_completion_trigger();

INSERT INTO udrive.commission_rules(id,name,percentage,is_active,effective_from,created_at,updated_at)
SELECT gen_random_uuid(),'Default platform commission',15,true,now(),now(),now()
WHERE NOT EXISTS (SELECT 1 FROM udrive.commission_rules WHERE is_active=true);
