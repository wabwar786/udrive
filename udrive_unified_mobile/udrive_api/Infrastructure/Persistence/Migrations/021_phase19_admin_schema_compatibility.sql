-- Phase 19 production schema compatibility and explicit wheel-family management.
-- Additive/idempotent; migration runner owns the transaction.

ALTER TABLE udrive.driver_profiles
    ADD COLUMN IF NOT EXISTS average_rating numeric(3,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS completed_trips integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS safety_score integer NOT NULL DEFAULT 100,
    ADD COLUMN IF NOT EXISTS is_online boolean NOT NULL DEFAULT false;

ALTER TABLE udrive.vehicles
    ADD COLUMN IF NOT EXISTS wheel_type varchar(16);

UPDATE udrive.vehicles
SET wheel_type = CASE
    WHEN lower(category) ~ '(motorcycle|motorbike|bike|scooter|2[ -]?wheel|two[ -]?wheel)' THEN '2Wheel'
    WHEN lower(category) ~ '(rickshaw|auto|tuk|3[ -]?wheel|three[ -]?wheel)' THEN '3Wheel'
    ELSE '4Wheel'
END
WHERE wheel_type IS NULL OR wheel_type NOT IN ('2Wheel','3Wheel','4Wheel');

ALTER TABLE udrive.vehicles
    ALTER COLUMN wheel_type SET DEFAULT '4Wheel',
    ALTER COLUMN wheel_type SET NOT NULL;

DO $$ BEGIN
    ALTER TABLE udrive.vehicles ADD CONSTRAINT ck_vehicles_wheel_type
        CHECK (wheel_type IN ('2Wheel','3Wheel','4Wheel'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS ix_vehicles_wheel_type_status
    ON udrive.vehicles(wheel_type, status);

CREATE TABLE IF NOT EXISTS udrive.support_tickets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference varchar(32) NOT NULL UNIQUE,
    created_by_user_id uuid REFERENCES udrive.users(id),
    assigned_admin_user_id uuid REFERENCES udrive.users(id),
    booking_id uuid REFERENCES udrive.bookings(id),
    category varchar(64) NOT NULL DEFAULT 'General',
    priority varchar(32) NOT NULL DEFAULT 'Normal',
    subject varchar(200) NOT NULL DEFAULT 'Support request',
    description text NOT NULL DEFAULT '',
    status varchar(32) NOT NULL DEFAULT 'Open',
    resolution_notes text,
    resolved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE udrive.support_tickets
    ADD COLUMN IF NOT EXISTS assigned_admin_user_id uuid REFERENCES udrive.users(id),
    ADD COLUMN IF NOT EXISTS booking_id uuid REFERENCES udrive.bookings(id),
    ADD COLUMN IF NOT EXISTS category varchar(64) NOT NULL DEFAULT 'General',
    ADD COLUMN IF NOT EXISTS priority varchar(32) NOT NULL DEFAULT 'Normal',
    ADD COLUMN IF NOT EXISTS subject varchar(200) NOT NULL DEFAULT 'Support request',
    ADD COLUMN IF NOT EXISTS description text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS status varchar(32) NOT NULL DEFAULT 'Open',
    ADD COLUMN IF NOT EXISTS resolution_notes text,
    ADD COLUMN IF NOT EXISTS resolved_at timestamptz,
    ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS udrive.system_settings (
    key varchar(120) PRIMARY KEY,
    value_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    description varchar(500),
    is_public boolean NOT NULL DEFAULT false,
    updated_by_user_id uuid REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE udrive.system_settings
    ADD COLUMN IF NOT EXISTS value_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS description varchar(500),
    ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS updated_by_user_id uuid REFERENCES udrive.users(id),
    ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE udrive.payments
    ADD COLUMN IF NOT EXISTS refund_amount numeric(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS review_notes text,
    ADD COLUMN IF NOT EXISTS reviewed_by_user_id uuid REFERENCES udrive.users(id),
    ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;

ALTER TABLE udrive.safety_incidents
    ADD COLUMN IF NOT EXISTS assigned_admin_user_id uuid REFERENCES udrive.users(id),
    ADD COLUMN IF NOT EXISTS resolution_notes text,
    ADD COLUMN IF NOT EXISTS assigned_at timestamptz,
    ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

CREATE OR REPLACE FUNCTION udrive.set_vehicle_wheel_type()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.wheel_type IS NULL OR NEW.wheel_type NOT IN ('2Wheel','3Wheel','4Wheel') THEN
        NEW.wheel_type := CASE
            WHEN lower(coalesce(NEW.category,'')) ~ '(motorcycle|motorbike|bike|scooter|2[ -]?wheel|two[ -]?wheel)' THEN '2Wheel'
            WHEN lower(coalesce(NEW.category,'')) ~ '(rickshaw|auto|tuk|3[ -]?wheel|three[ -]?wheel)' THEN '3Wheel'
            ELSE '4Wheel'
        END;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_vehicle_wheel_type ON udrive.vehicles;
CREATE TRIGGER trg_set_vehicle_wheel_type
BEFORE INSERT OR UPDATE OF category, wheel_type ON udrive.vehicles
FOR EACH ROW EXECUTE FUNCTION udrive.set_vehicle_wheel_type();
