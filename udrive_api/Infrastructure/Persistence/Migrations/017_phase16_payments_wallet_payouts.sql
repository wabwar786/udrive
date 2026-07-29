ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS payment_type varchar(32) NOT NULL DEFAULT 'Full';
ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS provider varchar(40);
ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS failure_reason varchar(500);
ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS paid_at timestamptz;
ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS created_by_user_id uuid REFERENCES udrive.users(id);
ALTER TABLE udrive.payments ADD COLUMN IF NOT EXISTS metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS ix_payments_booking_created ON udrive.payments(booking_id, created_at DESC);

ALTER TABLE udrive.driver_wallets ADD COLUMN IF NOT EXISTS is_frozen boolean NOT NULL DEFAULT false;
ALTER TABLE udrive.driver_wallets ADD COLUMN IF NOT EXISTS freeze_reason varchar(500);
ALTER TABLE udrive.driver_wallets ADD COLUMN IF NOT EXISTS frozen_at timestamptz;
ALTER TABLE udrive.driver_wallets ADD COLUMN IF NOT EXISTS frozen_by_user_id uuid REFERENCES udrive.users(id);

CREATE TABLE IF NOT EXISTS udrive.payment_attempts (
  id uuid PRIMARY KEY,
  payment_id uuid NOT NULL REFERENCES udrive.payments(id) ON DELETE CASCADE,
  attempt_number integer NOT NULL,
  status varchar(32) NOT NULL,
  provider_reference varchar(160),
  request_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  response_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  failure_reason varchar(500),
  created_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_attempt_number ON udrive.payment_attempts(payment_id, attempt_number);

CREATE TABLE IF NOT EXISTS udrive.driver_payout_accounts (
  id uuid PRIMARY KEY,
  driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
  method varchar(40) NOT NULL,
  account_title varchar(160) NOT NULL,
  account_identifier_hash varchar(64) NOT NULL,
  account_identifier_masked varchar(80) NOT NULL,
  bank_name varchar(120),
  is_default boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_payout_accounts_driver ON udrive.driver_payout_accounts(driver_profile_id, is_default DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_payout_account_default ON udrive.driver_payout_accounts(driver_profile_id) WHERE is_default=true;

ALTER TABLE udrive.driver_payout_requests ADD COLUMN IF NOT EXISTS payout_account_id uuid REFERENCES udrive.driver_payout_accounts(id);
ALTER TABLE udrive.refund_requests ADD COLUMN IF NOT EXISTS refund_method varchar(40) NOT NULL DEFAULT 'OriginalMethod';
ALTER TABLE udrive.refund_requests ADD COLUMN IF NOT EXISTS idempotency_key varchar(160);
CREATE UNIQUE INDEX IF NOT EXISTS ux_refund_idempotency ON udrive.refund_requests(idempotency_key) WHERE idempotency_key IS NOT NULL;
