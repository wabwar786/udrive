-- Live testing and app usage.
--
-- 1. test_runs / test_steps / test_improvements: a test running on staging
--    (GitHub Actions emulator) reports each step with a screenshot; the Admin
--    watches it live in the portal and writes improvements against a step.
--    Screenshots are deleted after 7 days by the daily storage clean-up.
-- 2. app_devices / app_sessions: which phone, app version, network and
--    (from the IP only, never GPS) which city the app was opened in.
--    Sessions are kept 90 days, devices 180 days.
-- 3. ip_geo: city looked up once per IP, kept 60 days.
--
-- Safe to run more than once.

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('testing.reporter_key', to_jsonb(''::text), 'Key the automated tests send (X-Test-Key) to report steps. Generated from Admin → Live testing.', false, now(), now()),
    ('analytics.ipinfo_token', to_jsonb(''::text), 'ipinfo.io token used to turn an IP into a city. Empty: cities are not looked up.', false, now(), now())
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS udrive.test_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    suite varchar(80) NOT NULL,
    title varchar(160),
    status varchar(12) NOT NULL DEFAULT 'Running',
    source varchar(120),
    commit_sha varchar(64),
    steps_total int NOT NULL DEFAULT 0,
    steps_passed int NOT NULL DEFAULT 0,
    steps_failed int NOT NULL DEFAULT 0,
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    CONSTRAINT ck_test_runs_status CHECK (status IN ('Running', 'Passed', 'Failed', 'Stopped'))
);

CREATE INDEX IF NOT EXISTS ix_test_runs_started ON udrive.test_runs (started_at DESC);
CREATE INDEX IF NOT EXISTS ix_test_runs_suite ON udrive.test_runs (suite, started_at DESC);

CREATE TABLE IF NOT EXISTS udrive.test_steps (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid NOT NULL REFERENCES udrive.test_runs(id) ON DELETE CASCADE,
    seq int NOT NULL,
    name varchar(200) NOT NULL,
    status varchar(12) NOT NULL,
    detail varchar(2000),
    device varchar(40) NOT NULL DEFAULT 'customer',
    screenshot_url varchar(400),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_test_steps_status CHECK (status IN ('Running', 'Passed', 'Failed', 'Skipped', 'Info'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_test_steps_run_seq ON udrive.test_steps (run_id, seq);
CREATE INDEX IF NOT EXISTS ix_test_steps_created ON udrive.test_steps (created_at) WHERE screenshot_url IS NOT NULL;

CREATE TABLE IF NOT EXISTS udrive.test_improvements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid REFERENCES udrive.test_runs(id) ON DELETE SET NULL,
    step_id uuid REFERENCES udrive.test_steps(id) ON DELETE SET NULL,
    suite varchar(80),
    step_name varchar(200),
    screenshot_url varchar(400),
    note varchar(2000) NOT NULL,
    status varchar(12) NOT NULL DEFAULT 'Open',
    created_by_user_id uuid REFERENCES udrive.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    done_at timestamptz,
    CONSTRAINT ck_test_improvements_status CHECK (status IN ('Open', 'Done'))
);

CREATE INDEX IF NOT EXISTS ix_test_improvements_status ON udrive.test_improvements (status, created_at DESC);

CREATE TABLE IF NOT EXISTS udrive.app_devices (
    install_id varchar(64) PRIMARY KEY,
    user_id uuid REFERENCES udrive.users(id) ON DELETE SET NULL,
    platform varchar(16) NOT NULL DEFAULT 'android',
    manufacturer varchar(60),
    model varchar(80),
    os_version varchar(40),
    sdk int,
    app_version varchar(40),
    build_number varchar(20),
    build_flavor varchar(20),
    locale varchar(20),
    timezone varchar(60),
    screen varchar(20),
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    last_ip varchar(64),
    last_city varchar(120),
    last_network varchar(60)
);

CREATE INDEX IF NOT EXISTS ix_app_devices_seen ON udrive.app_devices (last_seen_at DESC);
CREATE INDEX IF NOT EXISTS ix_app_devices_user ON udrive.app_devices (user_id) WHERE user_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS udrive.app_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    install_id varchar(64) NOT NULL REFERENCES udrive.app_devices(install_id) ON DELETE CASCADE,
    user_id uuid REFERENCES udrive.users(id) ON DELETE SET NULL,
    ip varchar(64),
    city varchar(120),
    region varchar(120),
    country varchar(8),
    org varchar(160),
    network varchar(60),
    app_version varchar(40),
    pings int NOT NULL DEFAULT 1,
    started_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_app_sessions_install ON udrive.app_sessions (install_id, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS ix_app_sessions_started ON udrive.app_sessions (started_at DESC);
CREATE INDEX IF NOT EXISTS ix_app_sessions_nocity ON udrive.app_sessions (started_at) WHERE city IS NULL AND ip IS NOT NULL;

CREATE TABLE IF NOT EXISTS udrive.ip_geo (
    ip varchar(64) PRIMARY KEY,
    city varchar(120),
    region varchar(120),
    country varchar(8),
    org varchar(160),
    looked_up_at timestamptz NOT NULL DEFAULT now()
);
