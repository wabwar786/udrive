-- Self-test harness: history and schedule. No accounts, and no guards.
--
-- This migration deliberately seeds NOTHING that looks like a user.
--
-- Migration 010 once inserted 54 invented drivers, and migration 055 had to
-- delete them again. The reason it gave applies word for word here:
--
--   "It is a MIGRATION, so it ran automatically on every boot of every
--    environment, production included."
--
-- The three self-test accounts are therefore created by SelfTestService the
-- first time an Admin presses Run, not here. A database where nobody ever ran
-- the test carries no self-test rows at all.

-- ---------------------------------------------------------------- history

CREATE TABLE IF NOT EXISTS udrive.self_test_runs (
    id uuid PRIMARY KEY,

    -- Who asked for it: 'Manual' (an Admin pressed Run) or 'Scheduled'.
    trigger_source varchar(16) NOT NULL,

    -- The Admin who pressed Run. NULL for a scheduled run, which has no actor.
    started_by_user_id uuid REFERENCES udrive.users(id) ON DELETE SET NULL,

    -- 'Running', 'Passed', 'Failed'.
    --
    -- 'Passed' means no step failed. Skipped steps are counted separately and
    -- never fold into the pass count, so "38 passed, 3 skipped" cannot be read
    -- as "41 passed".
    status varchar(16) NOT NULL,

    total_steps integer NOT NULL DEFAULT 0,
    passed_steps integer NOT NULL DEFAULT 0,
    failed_steps integer NOT NULL DEFAULT 0,
    skipped_steps integer NOT NULL DEFAULT 0,

    duration_ms integer NOT NULL DEFAULT 0,

    -- The first failure, in plain words, so the history list is readable
    -- without opening the run.
    failure_summary text,

    -- Every step: name, role, method, path, http status, ms, outcome, detail.
    --
    -- JSONB rather than a child table because a run is written once and read
    -- whole. There is no query that wants one step across many runs.
    steps jsonb NOT NULL DEFAULT '[]'::jsonb,

    -- What the run created and what it managed to remove again.
    --
    -- Written even when cleanup fails, which is the case that matters: a row
    -- left behind in a live database has to be visible to somebody.
    cleanup jsonb NOT NULL DEFAULT '{}'::jsonb,

    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz
);

CREATE INDEX IF NOT EXISTS ix_self_test_runs_started
    ON udrive.self_test_runs (started_at DESC);

COMMENT ON TABLE udrive.self_test_runs IS
    'One row per self-test run. Steps and cleanup are stored whole as JSONB.';

-- The guards that hide self-test traffic from real users are NOT here.
--
-- They are four WHERE clauses written out inline in BookingService,
-- MarketplacePricingService (twice) and HotelService, each matching
-- SelfTestAccounts.EmailPattern.
--
-- They were SQL functions created by this migration at first, which was neater
-- to read and wrong: it would have made hotel search, the vehicle map and the
-- whole driver marketplace depend on this file having been applied. A
-- deployment with AUTO_APPLY_MIGRATIONS=false would have lost all three at
-- once. Four copies of one pattern is the cheaper mistake to live with.

-- ---------------------------------------------------------------- schedule
--
-- Off until an Admin turns it on. Stored in system_settings like every other
-- operational switch, rather than in an environment variable only a deploy can
-- change.
--
-- The time is local Pakistan time (UTC+5), because that is the clock an Admin
-- reading "03:00" is thinking in.

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('selftest.schedule.enabled', 'false'::jsonb,
     'Run the end-to-end self-test automatically once a day.', false, now(), now()),
    ('selftest.schedule.time', '"03:00"'::jsonb,
     'Local Pakistan time (UTC+5) for the daily self-test run, as HH:mm.', false, now(), now())
ON CONFLICT (key) DO NOTHING;
