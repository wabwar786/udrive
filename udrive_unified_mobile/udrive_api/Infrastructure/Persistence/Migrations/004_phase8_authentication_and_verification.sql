CREATE TABLE IF NOT EXISTS udrive.user_roles (
    user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    role varchar(32) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role)
);

INSERT INTO udrive.user_roles (user_id, role, created_at)
SELECT id, role, now()
FROM udrive.users
ON CONFLICT (user_id, role) DO NOTHING;

ALTER TABLE udrive.users
    ADD COLUMN IF NOT EXISTS token_version integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS locked_until timestamptz;

CREATE TABLE IF NOT EXISTS udrive.auth_otp_challenges (
    id uuid PRIMARY KEY,
    phone_number varchar(24) NOT NULL,
    purpose varchar(32) NOT NULL,
    code_hash varchar(128) NOT NULL,
    expires_at timestamptz NOT NULL,
    attempts integer NOT NULL DEFAULT 0,
    max_attempts integer NOT NULL DEFAULT 5,
    consumed_at timestamptz,
    requested_ip varchar(64),
    created_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_auth_otp_phone_purpose_created
    ON udrive.auth_otp_challenges(phone_number, purpose, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_auth_otp_cleanup
    ON udrive.auth_otp_challenges(expires_at, consumed_at);

CREATE TABLE IF NOT EXISTS udrive.refresh_tokens (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    token_hash varchar(128) NOT NULL UNIQUE,
    device_id varchar(120),
    device_name varchar(160),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    replaced_by_token_id uuid REFERENCES udrive.refresh_tokens(id),
    ip_address varchar(64),
    user_agent varchar(500),
    created_at timestamptz NOT NULL,
    last_used_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_refresh_tokens_user_active
    ON udrive.refresh_tokens(user_id, expires_at DESC)
    WHERE revoked_at IS NULL;

ALTER TABLE udrive.driver_profiles
    ADD COLUMN IF NOT EXISTS cnic_number_hash varchar(128),
    ADD COLUMN IF NOT EXISTS driving_licence_number_hash varchar(128),
    ADD COLUMN IF NOT EXISTS date_of_birth date,
    ADD COLUMN IF NOT EXISTS residential_address text,
    ADD COLUMN IF NOT EXISTS emergency_contact_name varchar(120),
    ADD COLUMN IF NOT EXISTS emergency_contact_phone varchar(24),
    ADD COLUMN IF NOT EXISTS bank_account_title varchar(120),
    ADD COLUMN IF NOT EXISTS payout_method varchar(40),
    ADD COLUMN IF NOT EXISTS payout_account_masked varchar(80),
    ADD COLUMN IF NOT EXISTS submitted_at timestamptz,
    ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
    ADD COLUMN IF NOT EXISTS reviewed_by_user_id uuid REFERENCES udrive.users(id),
    ADD COLUMN IF NOT EXISTS review_notes text;

CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_profiles_cnic_hash
    ON udrive.driver_profiles(cnic_number_hash)
    WHERE cnic_number_hash IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_profiles_licence_hash
    ON udrive.driver_profiles(driving_licence_number_hash)
    WHERE driving_licence_number_hash IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_documents_type
    ON udrive.driver_documents(driver_profile_id, document_type);
CREATE UNIQUE INDEX IF NOT EXISTS ux_vehicle_documents_type
    ON udrive.vehicle_documents(vehicle_id, document_type);

INSERT INTO udrive.users
    (id, phone_number, email, full_name, role, status, preferred_language,
     phone_verified, token_version, created_at, updated_at)
VALUES
    ('30000000-0000-0000-0000-000000000099', '+923000000099',
     'admin.demo@udrive.local', 'uDrive Demo Admin', 'Admin', 'Approved',
     'en', true, 0, now(), now())
ON CONFLICT (phone_number) DO UPDATE SET
    role = 'Admin', status = 'Approved', phone_verified = true, updated_at = now();

INSERT INTO udrive.user_roles (user_id, role, created_at)
SELECT id, 'Admin', now()
FROM udrive.users
WHERE phone_number = '+923000000099'
ON CONFLICT (user_id, role) DO NOTHING;

INSERT INTO udrive.user_roles (user_id, role, created_at)
SELECT id, 'Operations', now()
FROM udrive.users
WHERE phone_number = '+923000000099'
ON CONFLICT (user_id, role) DO NOTHING;
