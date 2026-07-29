CREATE TABLE IF NOT EXISTS udrive.trusted_contacts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
 name varchar(160) NOT NULL, phone_number varchar(32) NOT NULL, relationship varchar(80) NOT NULL,
 is_primary boolean NOT NULL DEFAULT false, is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_trusted_contacts_user ON udrive.trusted_contacts(user_id,is_active);
CREATE UNIQUE INDEX IF NOT EXISTS ux_trusted_contacts_primary ON udrive.trusted_contacts(user_id) WHERE is_primary AND is_active;

CREATE TABLE IF NOT EXISTS udrive.trip_safety_pins (
 booking_id uuid PRIMARY KEY REFERENCES udrive.bookings(id) ON DELETE CASCADE,
 pin_hash varchar(128) NOT NULL, failed_attempts integer NOT NULL DEFAULT 0, locked_until timestamptz,
 verified_at timestamptz, verified_by_user_id uuid REFERENCES udrive.users(id),
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS udrive.emergency_cases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), case_reference varchar(32) NOT NULL UNIQUE,
 booking_id uuid REFERENCES udrive.bookings(id) ON DELETE SET NULL, raised_by_user_id uuid NOT NULL REFERENCES udrive.users(id),
 emergency_type varchar(64) NOT NULL, severity varchar(24) NOT NULL DEFAULT 'Critical', status varchar(32) NOT NULL DEFAULT 'Open',
 description text NOT NULL, latitude double precision, longitude double precision, accuracy_meters double precision,
 assigned_admin_user_id uuid REFERENCES udrive.users(id), acknowledged_at timestamptz, resolved_at timestamptz,
 resolution_notes text, version integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_emergency_cases_active ON udrive.emergency_cases(status,severity,created_at DESC);
CREATE INDEX IF NOT EXISTS ix_emergency_cases_booking ON udrive.emergency_cases(booking_id,created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.emergency_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), emergency_case_id uuid NOT NULL REFERENCES udrive.emergency_cases(id) ON DELETE CASCADE,
 actor_user_id uuid REFERENCES udrive.users(id), event_type varchar(64) NOT NULL, message text NOT NULL,
 latitude double precision, longitude double precision, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_emergency_events_case ON udrive.emergency_events(emergency_case_id,created_at);

CREATE TABLE IF NOT EXISTS udrive.safety_reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), booking_id uuid NOT NULL REFERENCES udrive.bookings(id) ON DELETE CASCADE,
 reported_by_user_id uuid NOT NULL REFERENCES udrive.users(id), report_type varchar(64) NOT NULL, severity varchar(24) NOT NULL DEFAULT 'Medium',
 description text NOT NULL, latitude double precision, longitude double precision, status varchar(32) NOT NULL DEFAULT 'Open',
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_safety_reports_active ON udrive.safety_reports(status,severity,created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.driver_compliance_documents (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), driver_profile_id uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
 document_type varchar(64) NOT NULL, document_number varchar(120), issued_at date, expires_at date,
 status varchar(32) NOT NULL DEFAULT 'Valid', verification_attachment_id uuid, notes text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(driver_profile_id,document_type)
);
CREATE INDEX IF NOT EXISTS ix_driver_compliance_expiry ON udrive.driver_compliance_documents(status,expires_at);

INSERT INTO udrive.system_settings(key,value_json,description,is_public,created_at,updated_at) VALUES
('safety.gps_stale_seconds','60'::jsonb,'Active trip GPS age before safety warning.',true,now(),now()),
('safety.long_stop_minutes','10'::jsonb,'Stationary duration before long-stop alert.',false,now(),now()),
('safety.pin_expiry_hours','24'::jsonb,'Trip boarding PIN validity.',false,now(),now())
ON CONFLICT(key) DO NOTHING;
