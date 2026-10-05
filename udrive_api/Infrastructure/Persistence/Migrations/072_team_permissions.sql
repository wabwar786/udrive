-- Team users with chosen modules and areas.
--
-- A team user signs in to the admin portal with the role 'Staff'. What they
-- may open is not decided by the role but by these rows: one per module with
-- view / edit / approve / delete, and the districts or tehsils whose
-- verification queues they may work. A district row covers all its tehsils,
-- including ones added later. all_areas = head-office staff.

CREATE TABLE IF NOT EXISTS udrive.staff_profiles (
    user_id uuid PRIMARY KEY REFERENCES udrive.users(id) ON DELETE CASCADE,
    template varchar(40) NOT NULL DEFAULT 'custom',
    all_areas boolean NOT NULL DEFAULT false,
    created_by uuid REFERENCES udrive.users(id),
    updated_by uuid REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS udrive.staff_permissions (
    user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    module varchar(40) NOT NULL,
    can_view boolean NOT NULL DEFAULT false,
    can_edit boolean NOT NULL DEFAULT false,
    can_approve boolean NOT NULL DEFAULT false,
    can_delete boolean NOT NULL DEFAULT false,
    PRIMARY KEY (user_id, module)
);

CREATE TABLE IF NOT EXISTS udrive.staff_areas (
    user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    territory_id uuid NOT NULL REFERENCES udrive.territories(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, territory_id)
);

CREATE INDEX IF NOT EXISTS ix_staff_areas_territory ON udrive.staff_areas (territory_id);
