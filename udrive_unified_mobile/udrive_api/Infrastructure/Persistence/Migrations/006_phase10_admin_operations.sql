CREATE TABLE IF NOT EXISTS udrive.support_tickets (
    id uuid PRIMARY KEY,
    reference varchar(32) NOT NULL UNIQUE,
    created_by_user_id uuid REFERENCES udrive.users(id),
    assigned_admin_user_id uuid REFERENCES udrive.users(id),
    booking_id uuid REFERENCES udrive.bookings(id),
    category varchar(64) NOT NULL,
    priority varchar(32) NOT NULL,
    subject varchar(200) NOT NULL,
    description text NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'Open',
    resolution_notes text,
    resolved_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_support_tickets_queue
    ON udrive.support_tickets(status, priority, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.system_settings (
    key varchar(120) PRIMARY KEY,
    value_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    description varchar(500),
    is_public boolean NOT NULL DEFAULT false,
    updated_by_user_id uuid REFERENCES udrive.users(id),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

ALTER TABLE udrive.safety_incidents
    ADD COLUMN IF NOT EXISTS resolution_notes text,
    ADD COLUMN IF NOT EXISTS assigned_at timestamptz;

ALTER TABLE udrive.payments
    ADD COLUMN IF NOT EXISTS reviewed_by_user_id uuid REFERENCES udrive.users(id),
    ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
    ADD COLUMN IF NOT EXISTS review_notes text,
    ADD COLUMN IF NOT EXISTS refund_amount numeric(12,2) NOT NULL DEFAULT 0;

INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('booking.offer_expiry_minutes', '15'::jsonb, 'Minutes before a driver offer expires.', false, now(), now()),
    ('booking.seat_hold_minutes', '10'::jsonb, 'Minutes a package seat hold remains active.', false, now(), now()),
    ('support.phone', '"+92 300 0000000"'::jsonb, 'Public customer support number.', true, now(), now()),
    ('safety.check_in_minutes', '30'::jsonb, 'Safety check-in interval for active tourism trips.', false, now(), now())
ON CONFLICT (key) DO NOTHING;
