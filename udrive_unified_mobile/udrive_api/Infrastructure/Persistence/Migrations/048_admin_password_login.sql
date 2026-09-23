-- Username + password sign-in for the admin portal.
--
-- Why the portal cannot stay on OTP: the WhatsApp settings that make OTP work
-- are configured *inside* the portal. If WA Engine is down, or the key is wrong,
-- nobody can sign in to fix the very setting that is broken. Customers and
-- drivers keep OTP; portal staff get a password.
--
-- Only portal users ever have these columns filled. A customer row keeps
-- username and password_hash NULL and can never use the password endpoint.

ALTER TABLE udrive.users
    ADD COLUMN IF NOT EXISTS username varchar(64),
    ADD COLUMN IF NOT EXISTS password_hash varchar(256),
    ADD COLUMN IF NOT EXISTS password_updated_at timestamptz,
    ADD COLUMN IF NOT EXISTS failed_login_attempts integer NOT NULL DEFAULT 0;

-- Case-insensitive uniqueness: "Admin" and "admin" must not be two accounts.
-- Partial, so the thousands of customer rows with no username do not collide.
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_username_lower
    ON udrive.users (lower(username))
    WHERE username IS NOT NULL;

COMMENT ON COLUMN udrive.users.password_hash IS
    'PBKDF2-HMAC-SHA256, stored as pbkdf2$<iterations>$<salt-b64>$<hash-b64>. '
    'Portal sign-in only; never used by the customer or driver app.';
COMMENT ON COLUMN udrive.users.failed_login_attempts IS
    'Consecutive failed password attempts. Five of them set locked_until '
    '15 minutes ahead; a correct password resets it to zero.';
