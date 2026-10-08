-- Welcome credit per kind of work, and a prepaid wallet + commission for hotels.
--
-- 1. Welcome credit: city stays driver.welcome.bonus; tour, rent and hotel get
--    their own amounts. Each is paid once per owner per kind.
-- 2. hotel_wallets / hotel_wallet_entries: the hotel owner's prepaid balance
--    and its ledger. Commission is taken from it when a booking is confirmed.
-- 3. driver_wallet_topups also carries hotel top-ups (wallet_kind = 'Hotel'),
--    so the Admin approves both on one page.
-- 4. WhatsApp message for a hotel wallet running low.
--
-- Hotel commission starts at 0%: nothing is charged until an Admin sets it.
-- Safe to run more than once.

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('driver.welcome.tour_bonus', to_jsonb('500'::text), 'Welcome credit (PKR) when a vehicle is first approved for tours.', false, now(), now()),
    ('driver.welcome.rent_bonus', to_jsonb('500'::text), 'Welcome credit (PKR) when a vehicle is first approved for rent-a-car.', false, now(), now()),
    ('hotel.welcome.bonus', to_jsonb('500'::text), 'Welcome credit (PKR) in the hotel owner''s wallet when a hotel is first approved.', false, now(), now()),
    ('hotel.commission.percentage', to_jsonb('0'::text), 'Commission (%) on a hotel booking, taken from the hotel wallet when the booking is confirmed.', false, now(), now()),
    ('hotel.wallet.minimum_balance', to_jsonb('0'::text), 'Below this hotel wallet balance (PKR) the hotel is hidden from new customers.', false, now(), now()),
    ('hotel.wallet.low_balance_alert', to_jsonb('500'::text), 'Below this hotel wallet balance (PKR) the owner is asked to top up.', false, now(), now())
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS udrive.hotel_wallets (
    owner_user_id uuid PRIMARY KEY REFERENCES udrive.users(id) ON DELETE CASCADE,
    balance numeric(14,2) NOT NULL DEFAULT 0,
    low_balance_notified_at timestamptz,
    version int NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS udrive.hotel_wallet_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    entry_type varchar(16) NOT NULL,
    amount numeric(14,2) NOT NULL,
    balance_after numeric(14,2) NOT NULL,
    hotel_id uuid,
    hotel_booking_id uuid,
    description varchar(300) NOT NULL,
    reference varchar(120),
    idempotency_key varchar(120) NOT NULL,
    created_by_user_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hotel_wallet_entries_type CHECK (entry_type IN ('Welcome', 'Topup', 'Commission', 'Refund', 'Adjustment'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_hotel_wallet_entries_key
    ON udrive.hotel_wallet_entries (idempotency_key);

CREATE INDEX IF NOT EXISTS ix_hotel_wallet_entries_owner
    ON udrive.hotel_wallet_entries (owner_user_id, created_at DESC);

ALTER TABLE udrive.driver_wallet_topups
    ADD COLUMN IF NOT EXISTS wallet_kind varchar(12) NOT NULL DEFAULT 'Driver',
    ADD COLUMN IF NOT EXISTS owner_user_id uuid REFERENCES udrive.users(id) ON DELETE CASCADE;

ALTER TABLE udrive.driver_wallet_topups ALTER COLUMN driver_profile_id DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_driver_wallet_topups_kind') THEN
        ALTER TABLE udrive.driver_wallet_topups ADD CONSTRAINT ck_driver_wallet_topups_kind CHECK (
            (wallet_kind = 'Driver' AND driver_profile_id IS NOT NULL)
            OR (wallet_kind = 'Hotel' AND owner_user_id IS NOT NULL));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_driver_wallet_topups_owner
    ON udrive.driver_wallet_topups (owner_user_id, created_at DESC)
    WHERE owner_user_id IS NOT NULL;

INSERT INTO udrive.message_templates
    (key, title, audience, description, placeholders, body, default_body, sort_order)
SELECT k, t, a, d, p, b, b, o
FROM (VALUES
    ('wallet_low_hotel', 'Wallet kam — hotel owner', 'Driver',
     'Hotel ka wallet setting wali had se neeche aa gaya.',
     ARRAY['balance','line'],
     E'UDrive: aap ke hotel wallet mein PKR {balance} reh gaye hain, {line} se kam.\nWallet khatam ho to naye customers ko hotel nazar nahi aayega.\nTop-up: UDrive app → Hotel → Wallet',
     110)
) AS v(k, t, a, d, p, b, o)
ON CONFLICT (key) DO NOTHING;
