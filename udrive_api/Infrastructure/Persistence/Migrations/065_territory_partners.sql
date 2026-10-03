-- Territory partners — a signed contract, a territory, and a monthly record
-- that both sides read from the same rows.
--
-- The shape of this is deliberate, and one decision drove all the others:
-- every tier is bound to WORK, not to money. A partner pays a refundable
-- security deposit and earns a share of what UDrive itself earns in their
-- territory — in exchange for bringing drivers, keeping them active, and
-- answering locally. That is a franchise/service arrangement. The alternative
-- shape — take money from the public, promise a return, require nothing in
-- exchange — is an investment scheme, which in Pakistan is SECP's business and
-- not something a database schema can make safe.
--
-- Three consequences you can see in the tables below:
--
--   * `partner_tier_commitments` exists at all. A tier is not a price list; it
--     is a price list plus what the partner owes every month.
--   * `partner_contracts.rendered_text` holds the whole contract as text at the
--     moment of signing, not a pointer to a template. Templates get edited.
--     The sentence somebody signed does not.
--   * `partner_month_statements` stores the computed share per month instead of
--     recomputing it on each page load. A partner who has been paid for March
--     must still see March's numbers after the share percentage changes in May.
--
-- No money moves anywhere in this migration. Payout happens outside the system
-- and these rows are the statement of what is owed, which is what was asked
-- for.

-- ═══════════════════════════════════════════════════════ 1. the territory tree

-- Region → City → Tehsil, in one self-referencing table.
--
-- One table rather than three because every question asked of it is asked of
-- the whole tree: who is the partner here, which drivers belong below this
-- node, is this node already taken. With three tables each of those is a union
-- of three queries and the recursive walk is impossible.
CREATE TABLE IF NOT EXISTS udrive.territories (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id       uuid REFERENCES udrive.territories(id) ON DELETE RESTRICT,
    kind            varchar(16) NOT NULL,
    name            varchar(120) NOT NULL,

    -- Set on City rows only, and that is where the join to everything else
    -- happens: drivers, bookings, waitlists and the coming-soon flag are all
    -- keyed by launch_city. A Tehsil reaches its city through parent_id; a
    -- Region reaches its cities by walking down.
    launch_city_id  uuid REFERENCES udrive.launch_cities(id) ON DELETE SET NULL,

    is_active       boolean NOT NULL DEFAULT true,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT territories_kind
        CHECK (kind IN ('Region', 'City', 'Tehsil')),

    -- A Region is a root; a Tehsil must hang off something. A City may or may
    -- not sit under a Region — Azad Kashmir's divisions are real but the
    -- business does not need them to open Mirpur.
    CONSTRAINT territories_parentage CHECK (
        (kind = 'Region' AND parent_id IS NULL)
        OR (kind = 'City')
        OR (kind = 'Tehsil' AND parent_id IS NOT NULL)),

    -- Only a City can be a launch city. Without this a Tehsil could carry its
    -- own launch_city_id and the driver counts would be counted twice.
    CONSTRAINT territories_launch_city_is_city
        CHECK (launch_city_id IS NULL OR kind = 'City'),

    CONSTRAINT territories_no_self_parent CHECK (parent_id IS NULL OR parent_id <> id)
);

-- Two names the same under one parent is an operator mistake every time:
-- whichever one the partner contract points at, the other looks identical in
-- every list.
CREATE UNIQUE INDEX IF NOT EXISTS ux_territories_sibling_name
    ON udrive.territories (COALESCE(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name));

-- One territory per launch city, so "the City Head of Mirpur" is a single row.
CREATE UNIQUE INDEX IF NOT EXISTS ux_territories_launch_city
    ON udrive.territories (launch_city_id) WHERE launch_city_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_territories_parent ON udrive.territories (parent_id);
CREATE INDEX IF NOT EXISTS ix_territories_kind ON udrive.territories (kind, is_active);

-- ─────────────────────────── which drivers belong to which tehsil

-- Nullable on purpose, and it stays nullable.
--
-- `driver_profiles.launch_city_id` already says which city a driver belongs to,
-- so city- and region-level counting works the day this migration runs. A
-- tehsil has no such column anywhere in the schema, so a Tehsil Head's
-- "drivers I brought" can only be counted once somebody says which tehsil each
-- driver is in — and that is a human judgement, not something to infer from a
-- GPS point.
--
-- So: a driver with no territory_id counts towards their city and their region
-- and towards no tehsil. The partner screens say this in those words rather
-- than showing a Tehsil Head a confident zero.
ALTER TABLE udrive.driver_profiles
    ADD COLUMN IF NOT EXISTS territory_id uuid;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'driver_profiles_territory_fk')
    THEN
        ALTER TABLE udrive.driver_profiles
            ADD CONSTRAINT driver_profiles_territory_fk
            FOREIGN KEY (territory_id) REFERENCES udrive.territories(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_driver_profiles_territory
    ON udrive.driver_profiles (territory_id) WHERE territory_id IS NOT NULL;

-- ══════════════════════════════════════════ 2. where a city actually is

-- The same shape as `pricing_zone_areas`, for the same reason: a city is a set
-- of circles, not a point, because Muzaffarabad plus Chattar Domel plus the
-- university side is three circles and one polygon nobody will ever draw by
-- hand in an admin form.
--
-- This is what makes "UDrive is not running here yet" possible at all. Until
-- now the app had no idea which city the customer was standing in, so somebody
-- in Rawalakot saw the same screen as somebody in Muzaffarabad and could try to
-- book a car where there are none.
CREATE TABLE IF NOT EXISTS udrive.launch_city_areas (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    launch_city_id  uuid NOT NULL REFERENCES udrive.launch_cities(id) ON DELETE CASCADE,
    label           varchar(120),
    latitude        double precision NOT NULL,
    longitude       double precision NOT NULL,
    radius_km       numeric(8,2) NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT launch_city_areas_radius_range
        CHECK (radius_km > 0 AND radius_km <= 200),
    CONSTRAINT launch_city_areas_lat_range
        CHECK (latitude >= -90 AND latitude <= 90),
    CONSTRAINT launch_city_areas_lng_range
        CHECK (longitude >= -180 AND longitude <= 180)
);

-- Stored, not computed per query, so the GIST index below can be used — the
-- lesson already paid for in migration 050.
ALTER TABLE udrive.launch_city_areas
    ADD COLUMN IF NOT EXISTS centre geography(Point, 4326)
    GENERATED ALWAYS AS (
        ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
    ) STORED;

CREATE INDEX IF NOT EXISTS ix_launch_city_areas_city
    ON udrive.launch_city_areas (launch_city_id);
CREATE INDEX IF NOT EXISTS ix_launch_city_areas_centre
    ON udrive.launch_city_areas USING GIST (centre);

-- ───────────────────────────────────────── who is waiting in a closed city

-- Registration stays open in a city that is not live. This table is what makes
-- that honest rather than merely polite: the person is counted, and the count
-- is the strongest argument there is for opening that city next — and the
-- strongest argument for the person who wants to be its City Head.
CREATE TABLE IF NOT EXISTS udrive.city_waitlist (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    launch_city_id  uuid NOT NULL REFERENCES udrive.launch_cities(id) ON DELETE CASCADE,
    user_id         uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,

    -- Snapshotted so the list survives an account deletion that nulls the user.
    phone_number    varchar(24),

    notify_on_open  boolean NOT NULL DEFAULT true,
    source          varchar(32) NOT NULL DEFAULT 'App',
    notified_at     timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_city_waitlist_user_city
    ON udrive.city_waitlist (launch_city_id, user_id);
CREATE INDEX IF NOT EXISTS ix_city_waitlist_city
    ON udrive.city_waitlist (launch_city_id, created_at DESC);

-- ══════════════════════════════════════════════════════════ 3. the tiers

-- Three tiers, each exclusive to its territory. Every figure here is a row an
-- admin can change, which is the whole point: the first partner in Mirpur and
-- the twentieth in Muzaffarabad will not be signed on the same terms, and
-- neither of those terms belongs in compiled code.
CREATE TABLE IF NOT EXISTS udrive.partner_tiers (
    tier_key            varchar(32) PRIMARY KEY,
    display_name        varchar(80) NOT NULL,
    territory_kind      varchar(16) NOT NULL,

    -- Refundable, held, returned at the end of the contract less anything owed.
    -- A deposit is not an investment and must not be described as one
    -- anywhere — there is no promised return on this number. What the partner
    -- earns is below, and it is earned by working.
    security_deposit    numeric(14,2) NOT NULL DEFAULT 0,

    -- Share of UDrive's OWN commission on completed rides in the territory —
    -- not a share of the fare.
    --
    -- This base matters more than the percentage. The fare belongs mostly to
    -- the driver; commission is what the business actually keeps (15% by
    -- default, migration 009). A percentage of the fare looks small and is
    -- enormous; a percentage of commission is the number that can be paid every
    -- month for years without the business going backwards.
    --
    -- Tiers nest, and the shares add up: a ride in a tehsil that has a Tehsil
    -- Head, inside a city that has a City Head, inside a region that has a
    -- Regional Head pays all three. The seeded figures below total 40% of
    -- commission for that worst case, which leaves the business 60% of 15% —
    -- 9% of the fare. Change them with that sum in mind, not one at a time.
    commission_share_pct numeric(5,2) NOT NULL DEFAULT 0,

    term_months         integer NOT NULL DEFAULT 24,
    description         text,
    sort_order          integer NOT NULL DEFAULT 0,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT partner_tiers_kind
        CHECK (territory_kind IN ('Region', 'City', 'Tehsil')),
    CONSTRAINT partner_tiers_share_range
        CHECK (commission_share_pct >= 0 AND commission_share_pct <= 100),
    CONSTRAINT partner_tiers_term_range
        CHECK (term_months BETWEEN 1 AND 120)
);

INSERT INTO udrive.partner_tiers
    (tier_key, display_name, territory_kind, security_deposit,
     commission_share_pct, term_months, description, sort_order)
VALUES
    ('RegionalHead', 'Regional Head', 'Region', 300000, 5, 24,
     'Brings and supports the City and Tehsil Heads of one region. Earns a '
     || 'share of UDrive''s commission on completed rides across the region.', 1),
    ('CityHead', 'City Head', 'City', 150000, 15, 24,
     'Brings drivers in one city, keeps them active, and is the local answer '
     || 'for drivers and customers. Earns a share of UDrive''s commission on '
     || 'completed rides in that city.', 2),
    ('TehsilHead', 'Tehsil Head', 'Tehsil', 50000, 20, 24,
     'The same work in one tehsil. Earns a share of UDrive''s commission on '
     || 'completed rides by the drivers assigned to that tehsil.', 3)
ON CONFLICT (tier_key) DO NOTHING;

-- ─────────────────────────────────── what each tier owes, every month

-- The default commitments a new contract is built from. Copied into
-- `partner_commitments` at contract time, so changing a default never rewrites
-- what somebody already signed.
--
-- Only metrics the database can actually answer are listed. 'Manual' exists for
-- the ones it cannot — local support quality, say — and those are recorded by
-- an admin rather than pretending to be measured.
CREATE TABLE IF NOT EXISTS udrive.partner_tier_commitments (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tier_key        varchar(32) NOT NULL REFERENCES udrive.partner_tiers(tier_key) ON DELETE CASCADE,
    metric_key      varchar(40) NOT NULL,
    target_value    numeric(12,2) NOT NULL,
    label           varchar(160) NOT NULL,
    sort_order      integer NOT NULL DEFAULT 0,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT partner_tier_commitments_metric CHECK (metric_key IN (
        'NewDrivers', 'ActiveDrivers', 'CompletedRides', 'NewSubPartners', 'Manual')),
    CONSTRAINT partner_tier_commitments_target CHECK (target_value >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_partner_tier_commitments
    ON udrive.partner_tier_commitments (tier_key, metric_key);

-- Starting targets, chosen against what the network actually looks like rather
-- than what sounds ambitious. A commitment a partner cannot meet in month two
-- is not a commitment, it is a termination clause with extra steps — and the
-- admin can raise every one of these from the portal once a city is deeper.
INSERT INTO udrive.partner_tier_commitments
    (tier_key, metric_key, target_value, label, sort_order)
VALUES
    ('RegionalHead', 'NewSubPartners', 1, 'New City or Tehsil Head signed, per month', 1),
    ('RegionalHead', 'NewDrivers', 12, 'New approved drivers across the region, per month', 2),
    ('CityHead',     'NewDrivers', 6, 'New approved drivers in the city, per month', 1),
    ('CityHead',     'ActiveDrivers', 20, 'Drivers with at least one completed ride, per month', 2),
    ('TehsilHead',   'NewDrivers', 3, 'New approved drivers in the tehsil, per month', 1),
    ('TehsilHead',   'ActiveDrivers', 8, 'Drivers with at least one completed ride, per month', 2)
ON CONFLICT (tier_key, metric_key) DO NOTHING;

-- ════════════════════════════════════ 4. the application, from the app

-- A customer asks; an admin decides. Nobody is "created" as a partner.
--
-- Worth saying because the first design had an admin typing a partner in by
-- hand, and that design has no record of who asked, when, for where, or why
-- they were turned down — which is exactly the record you want when the same
-- person asks again next year, or disputes the refusal.
CREATE TABLE IF NOT EXISTS udrive.partner_applications (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES udrive.users(id) ON DELETE CASCADE,
    tier_key            varchar(32) NOT NULL REFERENCES udrive.partner_tiers(tier_key),
    territory_id        uuid NOT NULL REFERENCES udrive.territories(id) ON DELETE RESTRICT,

    applicant_note      text,
    contact_phone       varchar(24),
    status              varchar(16) NOT NULL DEFAULT 'Pending',
    decided_by_user_id  uuid REFERENCES udrive.users(id),
    decided_at          timestamptz,
    decision_reason     text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT partner_applications_status
        CHECK (status IN ('Pending', 'Approved', 'Rejected', 'Withdrawn')),

    -- A rejection has to say why. The applicant is shown this sentence.
    CONSTRAINT partner_applications_reason_on_reject
        CHECK (status <> 'Rejected' OR nullif(btrim(coalesce(decision_reason, '')), '') IS NOT NULL)
);

-- One open application per person. Not per territory — somebody who is refused
-- Pattika may reasonably ask for Hattian next month, and should not have to
-- wait for a row to be deleted.
CREATE UNIQUE INDEX IF NOT EXISTS ux_partner_applications_one_open
    ON udrive.partner_applications (user_id) WHERE status = 'Pending';
CREATE INDEX IF NOT EXISTS ix_partner_applications_queue
    ON udrive.partner_applications (status, created_at);
CREATE INDEX IF NOT EXISTS ix_partner_applications_territory
    ON udrive.partner_applications (territory_id, status);

-- ═══════════════════════════════════════════════════════ 5. the partner

CREATE TABLE IF NOT EXISTS udrive.partners (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL REFERENCES udrive.users(id) ON DELETE RESTRICT,
    tier_key        varchar(32) NOT NULL REFERENCES udrive.partner_tiers(tier_key),
    territory_id    uuid NOT NULL REFERENCES udrive.territories(id) ON DELETE RESTRICT,
    application_id  uuid REFERENCES udrive.partner_applications(id) ON DELETE SET NULL,

    -- Pending  — approved, contract not signed yet. No territory rights.
    -- Active   — signed. This is the only state that earns.
    -- Suspended— signed but stopped, by agreement or for cause. Territory held.
    -- Ended    — contract over. Territory free.
    status          varchar(16) NOT NULL DEFAULT 'Pending',
    started_at      timestamptz,
    ended_at        timestamptz,
    end_reason      text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT partners_status
        CHECK (status IN ('Pending', 'Active', 'Suspended', 'Ended'))
);

-- Territory exclusivity, enforced here rather than in a service method.
--
-- This is the promise the whole feature rests on — "aik territory, aik
-- partner" — and the place to keep a promise like that is the one place no code
-- path can go around. Two admins approving two applications for Mirpur in the
-- same minute is not a hypothetical.
CREATE UNIQUE INDEX IF NOT EXISTS ux_partners_territory_held
    ON udrive.partners (territory_id)
    WHERE status IN ('Pending', 'Active', 'Suspended');

CREATE INDEX IF NOT EXISTS ix_partners_user ON udrive.partners (user_id, status);
CREATE INDEX IF NOT EXISTS ix_partners_status ON udrive.partners (status, created_at DESC);

-- ═══════════════════════════════════════════════════ 6. the contract

CREATE TABLE IF NOT EXISTS udrive.partner_contract_templates (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tier_key        varchar(32) NOT NULL REFERENCES udrive.partner_tiers(tier_key) ON DELETE CASCADE,
    version         integer NOT NULL,
    title           varchar(160) NOT NULL,

    -- Markdown with {{placeholders}}. Filled once, at send time, and the
    -- filled text is stored on the contract.
    body_md         text NOT NULL,

    -- The sentence the partner reads aloud on camera. One fixed wording for
    -- everybody, which is the only reason the video is evidence of anything: a
    -- hundred videos each saying something different cannot be compared with
    -- each other or with the contract.
    video_script    text NOT NULL,

    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_partner_contract_templates
    ON udrive.partner_contract_templates (tier_key, version);

CREATE TABLE IF NOT EXISTS udrive.partner_contracts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id          uuid NOT NULL REFERENCES udrive.partners(id) ON DELETE CASCADE,
    template_id         uuid REFERENCES udrive.partner_contract_templates(id) ON DELETE SET NULL,
    reference           varchar(32) NOT NULL,

    -- The whole agreement, as text, as it stood when it was sent. Not a
    -- reference to a template.
    --
    -- The rental disclaimer taught this the hard way: a template edited after
    -- the fact rewrote what people had already accepted, and there was no way
    -- to tell what the old wording had been.
    rendered_text       text NOT NULL,
    video_script        text NOT NULL,

    security_deposit    numeric(14,2) NOT NULL DEFAULT 0,
    commission_share_pct numeric(5,2) NOT NULL DEFAULT 0,
    term_months         integer NOT NULL DEFAULT 24,

    status              varchar(16) NOT NULL DEFAULT 'Draft',
    sent_at             timestamptz,
    signed_at           timestamptz,
    starts_at           timestamptz,
    ends_at             timestamptz,
    terminated_at       timestamptz,
    termination_reason  text,
    created_by_user_id  uuid REFERENCES udrive.users(id),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT partner_contracts_status
        CHECK (status IN ('Draft', 'Sent', 'Signed', 'Terminated')),
    CONSTRAINT partner_contracts_share_range
        CHECK (commission_share_pct >= 0 AND commission_share_pct <= 100),
    CONSTRAINT partner_contracts_signed_has_time
        CHECK (status <> 'Signed' OR signed_at IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_partner_contracts_reference
    ON udrive.partner_contracts (reference);

-- One live contract per partner. A second Draft alongside a Signed one is how a
-- partner ends up signing the wrong terms.
CREATE UNIQUE INDEX IF NOT EXISTS ux_partner_contracts_one_live
    ON udrive.partner_contracts (partner_id) WHERE status <> 'Terminated';

CREATE INDEX IF NOT EXISTS ix_partner_contracts_status
    ON udrive.partner_contracts (status, created_at DESC);

-- ───────────────────────────────────────────────── the first templates

-- Seeded so the first contract can be sent without anybody writing a document
-- first, and marked plainly for what they are. Placeholders are filled at send
-- time; the admin can edit the text before sending, and should.
--
-- This is a business agreement written to be understood, not a legal opinion.
-- Before the first real signature a lawyer should read it once — that is the
-- one step software cannot do, and the reason the deposit is written here as
-- refundable with no promised return on it.
INSERT INTO udrive.partner_contract_templates
    (tier_key, version, title, body_md, video_script)
SELECT
    t.tier_key,
    1,
    t.display_name || ' — UDrive partnership agreement',
    '# UDrive ' || t.display_name || ' agreement' || E'\n\n'
    || '**Reference:** {{reference}}' || E'\n'
    || '**Partner:** {{partner_name}} ({{partner_phone}})' || E'\n'
    || '**Territory:** {{territory_name}} ({{territory_kind}})' || E'\n'
    || '**Date sent:** {{sent_date}}' || E'\n\n'
    || '## 1. What this is' || E'\n\n'
    || 'UDrive appoints the partner as its ' || t.display_name
    || ' for {{territory_name}}. This is an agreement to do work in that area. '
    || 'It is not an investment, and UDrive promises no return on the security '
    || 'deposit held under clause 3.' || E'\n\n'
    || '## 2. Exclusivity' || E'\n\n'
    || 'For as long as this agreement is active, UDrive will not appoint '
    || 'another ' || t.display_name || ' for {{territory_name}}.' || E'\n\n'
    || '## 3. Security deposit' || E'\n\n'
    || 'The partner places a refundable security deposit of PKR '
    || '{{security_deposit}}. It is held, not spent, and is returned when this '
    || 'agreement ends, less anything the partner then owes UDrive. No profit, '
    || 'interest or return is paid on it.' || E'\n\n'
    || '## 4. What the partner earns' || E'\n\n'
    || 'The partner earns {{commission_share_pct}}% of the commission UDrive '
    || 'itself earns on completed rides in {{territory_name}}. This is a share '
    || 'of UDrive''s commission, not of the fare, and it is earned month by '
    || 'month against the commitments in clause 5. The monthly statement in the '
    || 'partner portal is the record of what is owed. Payment is made outside '
    || 'the app.' || E'\n\n'
    || '## 5. What the partner commits to, every month' || E'\n\n'
    || '{{commitments}}' || E'\n\n'
    || 'Both sides read these numbers from the same place: the partner portal, '
    || 'updated daily.' || E'\n\n'
    || '## 6. Term' || E'\n\n'
    || 'This agreement runs for {{term_months}} months from the date of '
    || 'signature and may be renewed in writing.' || E'\n\n'
    || '## 7. Ending it' || E'\n\n'
    || 'Either side may end this agreement with 30 days'' written notice. '
    || 'UDrive may suspend or end it sooner if the commitments in clause 5 are '
    || 'missed for three consecutive months, or on fraud. On ending, the '
    || 'territory becomes free and the deposit is returned under clause 3.'
    || E'\n\n'
    || '## 8. Signature' || E'\n\n'
    || 'The partner signs by confirming in the partner portal, with a live '
    || 'photograph and a short video reading the words shown on screen. UDrive '
    || 'records the time on its own server, the IP address and the device. '
    || 'These are kept only as proof of this signature, are visible to UDrive''s '
    || 'SuperAdmin alone, every viewing is logged, and they are deleted after '
    || 'this agreement ends.',
    'Mera naam {{partner_name}} hai. Main UDrive ke sath {{territory_name}} ka '
    || t.display_name || ' ban raha hoon. Maine contract number {{reference}} '
    || 'poora parh liya hai aur apni marzi se qubool karta hoon. Aaj '
    || '{{sign_date}} hai.'
FROM udrive.partner_tiers t
ON CONFLICT (tier_key, version) DO NOTHING;

-- ═══════════════════════════════════ 7. commitments, month by month

CREATE TABLE IF NOT EXISTS udrive.partner_commitments (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id     uuid NOT NULL REFERENCES udrive.partner_contracts(id) ON DELETE CASCADE,
    metric_key      varchar(40) NOT NULL,
    target_value    numeric(12,2) NOT NULL,
    label           varchar(160) NOT NULL,
    sort_order      integer NOT NULL DEFAULT 0,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT partner_commitments_metric CHECK (metric_key IN (
        'NewDrivers', 'ActiveDrivers', 'CompletedRides', 'NewSubPartners', 'Manual')),
    CONSTRAINT partner_commitments_target CHECK (target_value >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_partner_commitments
    ON udrive.partner_commitments (contract_id, metric_key);

-- One row per commitment per month: the target as it stood that month, what
-- actually happened, and whether it counted.
--
-- Stored rather than recomputed because a target changed in June must not
-- silently change whether March was met. Dispute resolution is the only reason
-- this table exists, and a table that rewrites history is no use for that.
CREATE TABLE IF NOT EXISTS udrive.partner_commitment_periods (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id     uuid NOT NULL REFERENCES udrive.partner_contracts(id) ON DELETE CASCADE,
    commitment_id   uuid NOT NULL REFERENCES udrive.partner_commitments(id) ON DELETE CASCADE,
    period_start    date NOT NULL,
    period_end      date NOT NULL,
    metric_key      varchar(40) NOT NULL,
    target_value    numeric(12,2) NOT NULL,
    actual_value    numeric(12,2) NOT NULL DEFAULT 0,

    -- Open   — the month is still running, or a Manual metric nobody has filled.
    -- Met     — actual reached target.
    -- Missed  — the month closed short.
    -- Waived  — missed, and an admin recorded a reason to let it go.
    status          varchar(16) NOT NULL DEFAULT 'Open',
    note            text,
    recorded_by_user_id uuid REFERENCES udrive.users(id),
    computed_at     timestamptz NOT NULL DEFAULT now(),
    created_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT partner_commitment_periods_status
        CHECK (status IN ('Open', 'Met', 'Missed', 'Waived')),
    CONSTRAINT partner_commitment_periods_range
        CHECK (period_end >= period_start)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_partner_commitment_periods
    ON udrive.partner_commitment_periods (commitment_id, period_start);
CREATE INDEX IF NOT EXISTS ix_partner_commitment_periods_contract
    ON udrive.partner_commitment_periods (contract_id, period_start DESC);

-- ─────────────────────────────── what the territory earned, month by month

-- The statement. Display only — no money moves through this table and nothing
-- here touches a wallet. It is the agreed record of what is owed, which is what
-- a partner needs when payment happens outside the app.
CREATE TABLE IF NOT EXISTS udrive.partner_month_statements (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id         uuid NOT NULL REFERENCES udrive.partner_contracts(id) ON DELETE CASCADE,
    period_start        date NOT NULL,
    period_end          date NOT NULL,

    completed_rides     integer NOT NULL DEFAULT 0,
    gross_fares         numeric(14,2) NOT NULL DEFAULT 0,

    -- UDrive's own commission on those rides, from `driver_earnings`. The share
    -- is a percentage of THIS, never of gross_fares.
    commission_base     numeric(14,2) NOT NULL DEFAULT 0,

    -- Snapshotted, because the tier's percentage will change and this month's
    -- figure must not move when it does.
    share_pct           numeric(5,2) NOT NULL DEFAULT 0,
    share_amount        numeric(14,2) NOT NULL DEFAULT 0,

    -- Open — month still running or not yet agreed.
    -- Closed — the admin has agreed the figure. Partner sees it as final.
    -- Paid — paid outside the app; an admin recorded that, with a reference.
    status              varchar(16) NOT NULL DEFAULT 'Open',
    paid_reference      varchar(120),
    paid_at             timestamptz,
    closed_by_user_id   uuid REFERENCES udrive.users(id),
    note                text,
    computed_at         timestamptz NOT NULL DEFAULT now(),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT partner_month_statements_status
        CHECK (status IN ('Open', 'Closed', 'Paid')),
    CONSTRAINT partner_month_statements_range
        CHECK (period_end >= period_start)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_partner_month_statements
    ON udrive.partner_month_statements (contract_id, period_start);
CREATE INDEX IF NOT EXISTS ix_partner_month_statements_contract
    ON udrive.partner_month_statements (contract_id, period_start DESC);

-- ═════════════════════════════════════════════ 8. the signature evidence

-- A live photograph, a video of fixed words, and the three facts a phone cannot
-- fake: the server's clock, the IP, and the device string.
--
-- Personal data, and treated as such. Access is SuperAdmin only, every view is
-- written to `audit_logs`, and `purge_after` is set when the contract is signed
-- so there is a date on which this stops being kept. None of that is automatic
-- deletion — somebody still has to press the button — but the date is recorded
-- rather than left to memory.
CREATE TABLE IF NOT EXISTS udrive.partner_signature_evidence (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id         uuid NOT NULL UNIQUE REFERENCES udrive.partner_contracts(id) ON DELETE CASCADE,

    selfie_url          text NOT NULL,
    video_url           text NOT NULL,

    -- The phone the signature was made from, and the one OTP had already
    -- proven. Login is OTP-based, so this is the one piece of identity that
    -- costs nothing and proves the most.
    phone_number        varchar(24),

    -- The server's own clock. Never the device's.
    signed_at_server    timestamptz NOT NULL DEFAULT now(),
    ip_address          varchar(64),
    device_info         varchar(300),

    -- The exact words that were on screen, stored with the evidence. Without
    -- this the video can be compared to nothing.
    script_shown        text NOT NULL,

    purge_after         date,
    purged_at           timestamptz,
    purged_by_user_id   uuid REFERENCES udrive.users(id),
    created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_partner_signature_evidence_purge
    ON udrive.partner_signature_evidence (purge_after)
    WHERE purged_at IS NULL;

-- ═══════════════════════════════════════════════════ 9. seed the tree

-- One Region, and a City row for every launch city that already exists, so the
-- territory list is not empty on first open and the first application has
-- something to point at. Tehsils are added by hand from the portal, because
-- only somebody who knows the area can say where one ends.
INSERT INTO udrive.territories (kind, name, is_active, notes)
SELECT 'Region', 'Azad Kashmir', true,
       'Seeded by migration 065. Rename or add regions from Territories & areas.'
WHERE NOT EXISTS (
    SELECT 1 FROM udrive.territories WHERE kind = 'Region');

INSERT INTO udrive.territories (parent_id, kind, name, launch_city_id, is_active)
SELECT
    (SELECT id FROM udrive.territories WHERE kind = 'Region' ORDER BY created_at LIMIT 1),
    'City',
    c.name,
    c.id,
    c.is_active
FROM udrive.launch_cities c
WHERE NOT EXISTS (
    SELECT 1 FROM udrive.territories t WHERE t.launch_city_id = c.id)
ON CONFLICT DO NOTHING;
