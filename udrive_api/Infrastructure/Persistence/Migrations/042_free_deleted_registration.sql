-- Deleting a vehicle did not free its registration number.
--
-- `registration_number varchar(40) NOT NULL UNIQUE` applies to every row,
-- including the ones an Admin has deleted. Deletion here is a soft delete —
-- the row stays with `status = 'Deleted'` so bookings, earnings and audit
-- history that reference it do not break — but the constraint does not know
-- that.
--
-- So an Admin deleted a vehicle, the Driver tried to register the same plate
-- again, and was told it was already registered. By a record neither of them
-- could see.
--
-- The constraint becomes a partial unique index that ignores deleted rows. Two
-- live vehicles still cannot share a plate, which is the rule that matters.

ALTER TABLE udrive.vehicles
    DROP CONSTRAINT IF EXISTS vehicles_registration_number_key;

-- Older databases may carry it under a generated name instead.
DO $$
DECLARE
    constraint_name text;
BEGIN
    SELECT con.conname INTO constraint_name
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'udrive'
      AND rel.relname = 'vehicles'
      AND con.contype = 'u'
      AND pg_get_constraintdef(con.oid) ILIKE '%(registration_number)%'
    LIMIT 1;

    IF constraint_name IS NOT NULL THEN
        EXECUTE format(
            'ALTER TABLE udrive.vehicles DROP CONSTRAINT %I', constraint_name);
    END IF;
END $$;

-- Case-insensitive, because "ADL-955" and "adl-955" are the same plate and
-- letting both exist would defeat the point of the constraint.
CREATE UNIQUE INDEX IF NOT EXISTS ux_vehicles_registration_live
    ON udrive.vehicles (upper(btrim(registration_number)))
    WHERE status <> 'Deleted';

COMMENT ON INDEX udrive.ux_vehicles_registration_live IS
    'One live vehicle per registration number. Deleted rows are excluded so a '
    'plate can be registered again after an Admin removes the vehicle.';
