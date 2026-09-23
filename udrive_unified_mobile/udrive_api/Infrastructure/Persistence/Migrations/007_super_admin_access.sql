-- Promote the existing development Admin account so that the new
-- SuperAdmin-only user and deletion controls are immediately usable.
INSERT INTO udrive.user_roles (user_id, role, created_at)
SELECT id, 'SuperAdmin', now()
FROM udrive.users
WHERE phone_number = '+923000000099'
ON CONFLICT (user_id, role) DO NOTHING;

UPDATE udrive.users
SET role = 'SuperAdmin',
    token_version = token_version + 1,
    updated_at = now()
WHERE phone_number = '+923000000099';
