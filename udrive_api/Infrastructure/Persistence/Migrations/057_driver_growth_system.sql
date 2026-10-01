-- The driver growth and retention system.
--
-- Why this exists. During launch UDrive will have more drivers than customers,
-- so a driver can stay online for days, take two rides and leave. Rides alone
-- cannot hold them; the platform has to be able to pay and inform them for
-- things other than rides — staying online at a useful hour, finishing a
-- milestone, bringing another driver — and it has to do that from admin
-- configuration rather than from a release.
--
-- Three decisions are built into this schema and are worth stating, because
-- everything else follows from them.
--
-- 1. Reward money is NOT a new kind of money.
--    A reward is credited to udrive.driver_wallets.commission_balance — the
--    prepaid balance the driver already pays commission from — and is written
--    as a udrive.driver_wallet_entries row with balance_bucket = 'Commission'
--    and entry_type = 'Bonus'. That is exactly the behaviour asked for: the
--    bonus is real money to the driver, it reduces what they owe UDrive, and
--    it can never be withdrawn as cash. It also means payouts, statements and
--    the finance screens keep working with no changes, and every reward is
--    already auditable through the wallet ledger that exists.
--
-- 2. Every campaign belongs to a city, and a city is switched on by an admin.
--    udrive.launch_cities is the switch. Nothing is offered to a driver whose
--    city is not active, so opening Mirpur does not start paying rewards in
--    Muzaffarabad.
--
-- 3. Nothing here is seeded.
--    No campaign, no milestone, no amount, no city. An empty install offers no
--    rewards at all and the driver app shows nothing — which is correct, and
--    is why this migration inserts no promotional rows.

-- ───────────────────────────────────────────────────────────── launch cities

CREATE TABLE IF NOT EXISTS udrive.launch_cities (
    id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name                      varchar(80) NOT NULL,
    is_active                 boolean NOT NULL DEFAULT false,

    -- What the driver sees on the launch card. Admin moves it forward by hand;
    -- it is a statement about the business, not something to infer from counts.
    launch_status             varchar(40) NOT NULL DEFAULT 'BuildingNetwork',
    customer_campaign_active  boolean NOT NULL DEFAULT false,

    -- Founding Driver window. A driver approved while the window is open and
    -- the city is active gets the next number in that city.
    founding_enabled          boolean NOT NULL DEFAULT false,
    founding_limit            integer,
    founding_window_ends_at   timestamptz,

    support_phone             varchar(32),
    community_url             varchar(300),

    activated_at              timestamptz,
    notes                     text,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_launch_cities_name
    ON udrive.launch_cities (lower(name));

ALTER TABLE udrive.launch_cities
    DROP CONSTRAINT IF EXISTS launch_cities_status_check;
ALTER TABLE udrive.launch_cities
    ADD CONSTRAINT launch_cities_status_check CHECK (launch_status IN (
        'BuildingNetwork', 'CampaignSoon', 'CampaignActive', 'PublicLaunch'));

-- ────────────────────────────────────────────────────── driver_profiles bits

ALTER TABLE udrive.driver_profiles
    ADD COLUMN IF NOT EXISTS launch_city_id uuid,
    ADD COLUMN IF NOT EXISTS referral_code varchar(24),
    ADD COLUMN IF NOT EXISTS referred_by_driver_profile_id uuid,
    -- Set when the driver's documents are approved. Used by the "new driver"
    -- segment and by the Founding Driver window, neither of which can use
    -- created_at: a driver who registered in July and was approved in October
    -- is a new driver in October.
    ADD COLUMN IF NOT EXISTS approved_at timestamptz;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_driver_profiles_launch_city'
    ) THEN
        ALTER TABLE udrive.driver_profiles
            ADD CONSTRAINT fk_driver_profiles_launch_city
            FOREIGN KEY (launch_city_id) REFERENCES udrive.launch_cities(id)
            ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_driver_profiles_referrer'
    ) THEN
        ALTER TABLE udrive.driver_profiles
            ADD CONSTRAINT fk_driver_profiles_referrer
            FOREIGN KEY (referred_by_driver_profile_id)
            REFERENCES udrive.driver_profiles(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_profiles_referral_code
    ON udrive.driver_profiles (upper(referral_code))
    WHERE referral_code IS NOT NULL;

-- Drivers already approved before this migration keep an approval date rather
-- than a null that would make every one of them look brand new.
UPDATE udrive.driver_profiles
SET approved_at = COALESCE(reviewed_at, updated_at)
WHERE approved_at IS NULL
  AND verification_status = 'Approved';

-- ──────────────────────────────────────────────────────────── online sessions

-- One row per stretch the driver was online, which is the measurement every
-- time-based reward depends on.
--
-- It is a session table rather than a counter because a counter cannot be
-- audited or disputed, cannot be scoped to a peak-hour window after the fact,
-- and cannot show that the "four hours online" were four hours of the app
-- sitting in a drawer with the GPS off.
CREATE TABLE IF NOT EXISTS udrive.driver_online_sessions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_profile_id   uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    launch_city_id      uuid REFERENCES udrive.launch_cities(id) ON DELETE SET NULL,

    started_at          timestamptz NOT NULL DEFAULT now(),
    last_heartbeat_at   timestamptz NOT NULL DEFAULT now(),
    ended_at            timestamptz,

    -- DriverOffline | Timeout | Replaced | Admin
    end_reason          varchar(24),

    heartbeat_count     integer NOT NULL DEFAULT 1,

    -- Seconds that count towards a reward. Only advanced by a heartbeat that
    -- arrived close enough to the last one, so a phone that slept for an hour
    -- adds the gap to wall-clock time but not to credited time.
    credited_seconds    integer NOT NULL DEFAULT 0,

    last_latitude       double precision,
    last_longitude      double precision,

    -- Anti-abuse, recorded rather than acted on. Admin decides.
    mock_location_seen  boolean NOT NULL DEFAULT false,
    gap_count           integer NOT NULL DEFAULT 0,

    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

-- A driver has at most one open session. This is the whole concurrency story:
-- two devices, or a retried request, cannot produce two sessions earning the
-- same minutes twice.
CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_online_sessions_open
    ON udrive.driver_online_sessions (driver_profile_id)
    WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_driver_online_sessions_driver
    ON udrive.driver_online_sessions (driver_profile_id, started_at DESC);

CREATE INDEX IF NOT EXISTS ix_driver_online_sessions_window
    ON udrive.driver_online_sessions (started_at, ended_at);

-- ───────────────────────────────────────────────────────── founding drivers

CREATE TABLE IF NOT EXISTS udrive.founding_drivers (
    driver_profile_id uuid PRIMARY KEY REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    launch_city_id    uuid NOT NULL REFERENCES udrive.launch_cities(id) ON DELETE CASCADE,
    sequence_no       integer NOT NULL,
    granted_at        timestamptz NOT NULL DEFAULT now(),
    revoked_at        timestamptz,
    revoke_reason     varchar(300),
    UNIQUE (launch_city_id, sequence_no)
);

-- ─────────────────────────────────────────────────────────────── campaigns

-- One table for every kind of reward, because they differ only in which
-- conditions are filled in. A separate table per kind would mean a separate
-- admin screen, a separate progress table and a separate crediting path per
-- kind — three places for the same duplicate-payment bug to appear.
CREATE TABLE IF NOT EXISTS udrive.growth_campaigns (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- WelcomeBonus | DailyMission | PeakHourReward | Referral | WeeklyReward
    -- | Reactivation | FoundingBenefit
    campaign_type        varchar(32) NOT NULL,

    -- Stable handle for support and for logs. Not shown to the driver.
    code                 varchar(60) NOT NULL,

    title                varchar(160) NOT NULL,
    description          text,

    launch_city_id       uuid REFERENCES udrive.launch_cities(id) ON DELETE CASCADE,
    zone_id              uuid REFERENCES udrive.pricing_zones(id) ON DELETE SET NULL,

    -- The payout. For a WelcomeBonus this is the headline total and the real
    -- amounts live on the milestones.
    reward_amount        numeric(12,2) NOT NULL DEFAULT 0,

    starts_at            timestamptz,
    ends_at              timestamptz,

    -- A peak-hour window repeats, so it is a time of day plus the days it runs
    -- on, not a pair of timestamps.
    daily_start_time     time,
    daily_end_time       time,
    days_of_week         smallint[],

    -- All | New | Founding | Inactive
    driver_segment       varchar(24) NOT NULL DEFAULT 'All',

    min_online_seconds   integer,
    min_completed_rides  integer,
    min_accepted_rides   integer,
    max_cancellations    integer,
    min_rating           numeric(3,2),
    min_acceptance_rate  numeric(5,2),

    -- Reactivation only: how many days without opening the app.
    inactive_days        integer,

    -- How often one driver may earn this. 1 for a one-off, higher for a daily
    -- mission that repeats; the progress table's period key does the rest.
    max_awards_per_driver integer NOT NULL DEFAULT 1,

    -- Stops an open-ended campaign from spending more than it was funded for.
    -- Null means no ceiling.
    total_budget         numeric(14,2),

    is_active            boolean NOT NULL DEFAULT false,

    -- Room for conditions this schema does not name yet, so a new rule does not
    -- need a migration. Read by the service, never by SQL joins.
    rules_json           jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_by_user_id   uuid REFERENCES udrive.users(id),
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_growth_campaigns_code
    ON udrive.growth_campaigns (upper(code));

CREATE INDEX IF NOT EXISTS ix_growth_campaigns_live
    ON udrive.growth_campaigns (launch_city_id, campaign_type, is_active);

ALTER TABLE udrive.growth_campaigns
    DROP CONSTRAINT IF EXISTS growth_campaigns_type_check;
ALTER TABLE udrive.growth_campaigns
    ADD CONSTRAINT growth_campaigns_type_check CHECK (campaign_type IN (
        'WelcomeBonus', 'DailyMission', 'PeakHourReward', 'Referral',
        'WeeklyReward', 'Reactivation', 'FoundingBenefit'));

ALTER TABLE udrive.growth_campaigns
    DROP CONSTRAINT IF EXISTS growth_campaigns_segment_check;
ALTER TABLE udrive.growth_campaigns
    ADD CONSTRAINT growth_campaigns_segment_check CHECK (driver_segment IN (
        'All', 'New', 'Founding', 'Inactive'));

-- ──────────────────────────────────────────────────────────── milestones

-- The steps of a staged reward — the Rs 1,000 welcome bonus is six of these.
-- Paying a staged bonus as six rows rather than one is what lets the app show
-- "unlocked Rs 500, next Rs 200 for …" without inventing the breakdown.
CREATE TABLE IF NOT EXISTS udrive.growth_campaign_milestones (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id     uuid NOT NULL REFERENCES udrive.growth_campaigns(id) ON DELETE CASCADE,
    sort_order      integer NOT NULL,
    title           varchar(160) NOT NULL,
    description     varchar(400),
    reward_amount   numeric(12,2) NOT NULL,

    -- AccountVerified | ProfileCompleted | VehicleApproved | FirstRide
    -- | CompletedRides | OnlineSeconds | OnlineSessions | AcceptanceRate
    -- | ReferralVerified | ReferralFirstRide | ReferralActive | Manual
    condition_type  varchar(32) NOT NULL,
    condition_value numeric(12,2) NOT NULL DEFAULT 1,

    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (campaign_id, sort_order)
);

-- ──────────────────────────────────────────────────────── progress / ledger

-- One row per driver per thing-that-can-be-earned, and the only place a reward
-- is ever marked as paid.
--
-- period_key is what makes a repeating reward safe: a daily mission uses the
-- date, a weekly reward the ISO week, a one-off the literal '-'. With it in the
-- unique index, the same mission can pay on Monday and again on Tuesday, and
-- can never pay twice on Monday however many times the evaluator runs.
CREATE TABLE IF NOT EXISTS udrive.driver_campaign_progress (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id        uuid NOT NULL REFERENCES udrive.growth_campaigns(id) ON DELETE CASCADE,
    milestone_id       uuid REFERENCES udrive.growth_campaign_milestones(id) ON DELETE CASCADE,
    driver_profile_id  uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,

    period_key         varchar(32) NOT NULL DEFAULT '-',

    progress_value     numeric(12,2) NOT NULL DEFAULT 0,
    target_value       numeric(12,2) NOT NULL DEFAULT 1,

    -- InProgress | Qualified | Credited | Expired | Rejected | OnHold
    status             varchar(16) NOT NULL DEFAULT 'InProgress',

    reward_amount      numeric(12,2) NOT NULL DEFAULT 0,

    qualified_at       timestamptz,
    credited_at        timestamptz,
    expires_at         timestamptz,

    wallet_entry_id    uuid REFERENCES udrive.driver_wallet_entries(id) ON DELETE SET NULL,
    reason             varchar(400),

    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_campaign_progress
    ON udrive.driver_campaign_progress (
        driver_profile_id,
        campaign_id,
        COALESCE(milestone_id, '00000000-0000-0000-0000-000000000000'::uuid),
        period_key);

CREATE INDEX IF NOT EXISTS ix_driver_campaign_progress_driver
    ON udrive.driver_campaign_progress (driver_profile_id, status);

CREATE INDEX IF NOT EXISTS ix_driver_campaign_progress_campaign
    ON udrive.driver_campaign_progress (campaign_id, status);

ALTER TABLE udrive.driver_campaign_progress
    DROP CONSTRAINT IF EXISTS driver_campaign_progress_status_check;
ALTER TABLE udrive.driver_campaign_progress
    ADD CONSTRAINT driver_campaign_progress_status_check CHECK (status IN (
        'InProgress', 'Qualified', 'Credited', 'Expired', 'Rejected', 'OnHold'));

-- ───────────────────────────────────────────────────────────────  referrals

-- Deliberately a row per referred driver with four separate timestamps rather
-- than a status flag. A referral reward that pays on sign-up pays for a SIM
-- card; the dates are what let an admin pay on verification, on the first ride,
-- or on sustained activity — and let a driver see exactly where their invite
-- has got to.
CREATE TABLE IF NOT EXISTS udrive.driver_referrals (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_driver_profile_id  uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    referred_driver_profile_id  uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    referral_code               varchar(24) NOT NULL,
    campaign_id                 uuid REFERENCES udrive.growth_campaigns(id) ON DELETE SET NULL,

    verified_at                 timestamptz,
    vehicle_approved_at         timestamptz,
    first_ride_at               timestamptz,
    active_at                   timestamptz,

    -- Pending | Verified | Active | Rejected
    status                      varchar(16) NOT NULL DEFAULT 'Pending',
    reject_reason               varchar(300),

    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),

    -- A driver can be referred once, by one person, ever.
    UNIQUE (referred_driver_profile_id),

    -- And cannot refer themselves, which is the cheapest referral loop there is.
    CONSTRAINT driver_referrals_not_self
        CHECK (referrer_driver_profile_id <> referred_driver_profile_id)
);

CREATE INDEX IF NOT EXISTS ix_driver_referrals_referrer
    ON udrive.driver_referrals (referrer_driver_profile_id, status);

-- ──────────────────────────────────────────────────── expected demand windows

-- "Expected Demand" — the honest version of a heatmap when there is not enough
-- live traffic to draw one. Live demand already has a home in
-- udrive.zone_demand_snapshots; this is what an admin can state in advance from
-- a customer campaign, a weekend, or last month's pattern, and the app labels
-- it as expected rather than live.
CREATE TABLE IF NOT EXISTS udrive.expected_demand_windows (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    launch_city_id  uuid REFERENCES udrive.launch_cities(id) ON DELETE CASCADE,
    zone_id         uuid NOT NULL REFERENCES udrive.pricing_zones(id) ON DELETE CASCADE,

    -- High | Medium | Low
    level           varchar(8) NOT NULL,
    reason          varchar(200),

    days_of_week    smallint[],
    start_time      time NOT NULL,
    end_time        time NOT NULL,
    valid_from      date,
    valid_to        date,

    campaign_id     uuid REFERENCES udrive.growth_campaigns(id) ON DELETE SET NULL,
    is_active       boolean NOT NULL DEFAULT true,

    created_by_user_id uuid REFERENCES udrive.users(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_expected_demand_city
    ON udrive.expected_demand_windows (launch_city_id, is_active);

ALTER TABLE udrive.expected_demand_windows
    DROP CONSTRAINT IF EXISTS expected_demand_level_check;
ALTER TABLE udrive.expected_demand_windows
    ADD CONSTRAINT expected_demand_level_check
    CHECK (level IN ('High', 'Medium', 'Low'));

-- ───────────────────────────────────────────────────────────  driver updates

-- The official feed. Separate from udrive.notifications because a notification
-- is addressed to one user and is read once, while an update is addressed to a
-- city and stays readable — a driver who installs today should still see that a
-- customer campaign started last week.
CREATE TABLE IF NOT EXISTS udrive.driver_updates (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    launch_city_id     uuid REFERENCES udrive.launch_cities(id) ON DELETE CASCADE,

    -- Demand | Rewards | Policy | Service | System
    category           varchar(16) NOT NULL,

    title              varchar(200) NOT NULL,
    body               text NOT NULL,
    action_path        varchar(240),

    publish_at         timestamptz NOT NULL DEFAULT now(),
    expires_at         timestamptz,
    is_published       boolean NOT NULL DEFAULT true,

    created_by_user_id uuid REFERENCES udrive.users(id),
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_driver_updates_feed
    ON udrive.driver_updates (launch_city_id, is_published, publish_at DESC);

-- ──────────────────────────────────────────────────────────────  fraud flags

-- Recorded, never enforced automatically. A launch incentive attracts people
-- who will try it on, and a system that bans on its own will also ban a driver
-- whose phone clock drifted. Everything here lands in a review queue.
CREATE TABLE IF NOT EXISTS udrive.driver_fraud_flags (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_profile_id  uuid NOT NULL REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,

    -- MockLocation | DuplicateDevice | DuplicateCnic | DuplicatePhone
    -- | ReferralLoop | OnlineToggleAbuse | RejectionAbuse | SelfBooking
    -- | WalletPattern
    flag_type          varchar(32) NOT NULL,
    detail             varchar(500),

    -- Notice | Review | Severe
    severity           varchar(12) NOT NULL DEFAULT 'Review',

    -- Open | Cleared | Confirmed
    status             varchar(12) NOT NULL DEFAULT 'Open',

    campaign_id        uuid REFERENCES udrive.growth_campaigns(id) ON DELETE SET NULL,
    session_id         uuid REFERENCES udrive.driver_online_sessions(id) ON DELETE SET NULL,

    reviewed_by_user_id uuid REFERENCES udrive.users(id),
    reviewed_at        timestamptz,
    review_notes       varchar(500),

    created_at         timestamptz NOT NULL DEFAULT now(),

    -- The local day this flag belongs to, stored rather than derived.
    -- `(created_at AT TIME ZONE 'Asia/Karachi')::date` cannot be indexed —
    -- casting a timestamptz is STABLE, not IMMUTABLE, so Postgres refuses it in
    -- an index expression. A column with the same expression as its DEFAULT has
    -- no such restriction and gives the one-flag-a-day rule below something it
    -- can actually be unique on.
    flag_day           date NOT NULL DEFAULT ((now() AT TIME ZONE 'Asia/Karachi')::date)
);

-- Separately, so a half-applied run of this file can be finished by running it
-- again: CREATE TABLE IF NOT EXISTS skips the table and would otherwise skip
-- the column with it.
ALTER TABLE udrive.driver_fraud_flags
    ADD COLUMN IF NOT EXISTS flag_day date NOT NULL
    DEFAULT ((now() AT TIME ZONE 'Asia/Karachi')::date);

CREATE INDEX IF NOT EXISTS ix_driver_fraud_flags_queue
    ON udrive.driver_fraud_flags (status, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_driver_fraud_flags_driver
    ON udrive.driver_fraud_flags (driver_profile_id, created_at DESC);

-- A driver is flagged once per kind per day. Without this a phone reporting a
-- mock location every ten seconds writes a flag every ten seconds and the
-- review queue becomes unusable within an hour.
CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_fraud_flags_daily
    ON udrive.driver_fraud_flags (driver_profile_id, flag_type, flag_day);
