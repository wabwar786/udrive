-- Prepaid commission: the Driver pays the platform first, then earns.
--
-- The existing wallet columns describe the opposite arrangement — the platform
-- holds the Driver's earnings and pays them out. `available_balance` means
-- "money we owe this Driver". Reusing it for money the Driver owes us would put
-- two figures that move in opposite directions into one column, and the first
-- reconciliation would be unreadable.
--
-- So this is a separate balance with its own name.

ALTER TABLE udrive.driver_wallets
    ADD COLUMN IF NOT EXISTS commission_balance numeric(14,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN udrive.driver_wallets.commission_balance IS
    'Credit the Driver has paid the platform in advance. Commission on each '
    'completed booking is taken from here. Not money owed to the Driver.';

-- What a Driver sends, and the evidence they send with it.
CREATE TABLE IF NOT EXISTS udrive.driver_wallet_topups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_profile_id uuid NOT NULL
        REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,

    amount numeric(14,2) NOT NULL CHECK (amount > 0),
    method varchar(32) NOT NULL DEFAULT 'EasyPaisa',

    -- The transaction id from the Driver's own receipt. It is what an Admin
    -- matches against the company statement, so it is asked for separately
    -- rather than left for them to read off a screenshot.
    sender_reference varchar(120),

    -- The screenshot. Stored like every other verification file.
    screenshot_url text,

    -- Pending until an Admin has seen the money arrive.
    status varchar(24) NOT NULL DEFAULT 'Pending'
        CHECK (status IN ('Pending','Approved','Rejected')),

    admin_notes varchar(400),
    reviewed_by_user_id uuid REFERENCES udrive.users(id),
    reviewed_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_topups_driver
    ON udrive.driver_wallet_topups (driver_profile_id, created_at DESC);

-- The Admin queue is the only hot query: everything still waiting.
CREATE INDEX IF NOT EXISTS ix_topups_pending
    ON udrive.driver_wallet_topups (created_at)
    WHERE status = 'Pending';

-- How low the balance may go before a Driver stops receiving requests.
--
-- Zero, not a positive figure. A Driver whose credit runs out mid-shift should
-- be able to finish what they are doing and top up, not be cut off holding a
-- fare they cannot collect. Raise it here if that turns out to be too lenient.
INSERT INTO udrive.system_settings (key, value_json, is_public, created_at, updated_at)
VALUES ('driver.commission.minimum_balance', '0'::jsonb, false, now(), now())
ON CONFLICT (key) DO NOTHING;

-- The share of each completed booking taken as commission, as a percentage.
INSERT INTO udrive.system_settings (key, value_json, is_public, created_at, updated_at)
VALUES ('driver.commission.percentage', '10'::jsonb, false, now(), now())
ON CONFLICT (key) DO NOTHING;
