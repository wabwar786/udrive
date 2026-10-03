-- Referral, finally connected — and the weekly reward made visible.
--
-- Nothing here is a new idea. `driver_referrals` has existed since migration
-- 057, carefully designed: four milestone timestamps, a unique index so a
-- driver can be referred once ever, and a CHECK against referring yourself. The
-- growth engine has known the three referral triggers all along.
--
-- What never existed is a single INSERT. The table has only ever been read, so
-- every driver sees "0 invites" for ever and a Referral campaign can be funded,
-- switched on, and measure nothing until it is switched off again. This
-- migration adds the two numbers that decide when a referred driver counts as
-- "active", and seeds the campaign that pays for all of it.

-- ───────────────────────────────────────── 1. when a referral counts as real

-- How many completed rides make a referred driver "active".
--
-- The whole point of paying the biggest share here rather than at sign-up: a
-- referral programme that pays for registrations buys registrations, and a
-- platform full of drivers who signed up once is worth nothing to the customer
-- waiting for a car.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'referral.active_rides',
    to_jsonb(20),
    'Completed rides a referred driver must finish, inside '
    || 'referral.active_window_days, before the referrer earns the active reward.',
    false, now(), now())
ON CONFLICT (key) DO NOTHING;

-- The window those rides must fall inside, counted from the first one.
--
-- Without a window "active" means "will get there eventually", and a reward
-- that pays eventually does not change anybody's behaviour this month.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'referral.active_window_days',
    to_jsonb(30),
    'Days from a referred driver''s first ride within which they must reach '
    || 'referral.active_rides.',
    false, now(), now())
ON CONFLICT (key) DO NOTHING;

-- ────────────────────────────────────────────── 2. the campaign that pays

-- One Referral campaign per live city, with three milestones.
--
-- Per city because that is the only shape the engine loads: campaign rows are
-- joined to launch_cities and filtered by the driver's own city, so a campaign
-- with no city is invisible to everybody. (That join is why nothing here is
-- seeded globally, however much tidier it would look.)
--
-- Seeded active, with real amounts, because the alternative is shipping a
-- referral screen that shows a driver their code and pays them nothing until
-- somebody remembers to build the campaign by hand. An Admin can change every
-- number, or switch the campaign off, from the growth page.
INSERT INTO udrive.growth_campaigns
    (campaign_type, code, title, description, launch_city_id, reward_amount,
     driver_segment, max_awards_per_driver, is_active, created_at, updated_at)
SELECT
    'Referral',
    'REFERRAL-' || upper(substr(replace(c.id::text, '-', ''), 1, 8)),
    'Refer a driver',
    'Earn as the driver you brought gets verified, takes their first ride, and '
    || 'becomes active.',
    c.id,
    2000,
    'All',
    -- One award per milestone per referred driver. The progress table's
    -- period_key carries the referred driver's id, so this is a per-referral
    -- guarantee rather than a lifetime cap — the same way it means "once a day"
    -- for a daily mission.
    1,
    true,
    now(), now()
FROM udrive.launch_cities c
WHERE c.is_active
ON CONFLICT DO NOTHING;

-- The three steps. Amounts rise as the referred driver becomes worth more:
-- a verified driver is a promise, a driver with twenty rides behind them is a
-- car on the road.
INSERT INTO udrive.growth_campaign_milestones
    (campaign_id, sort_order, title, description, reward_amount,
     condition_type, condition_value, created_at, updated_at)
SELECT g.id, 1, 'They get verified',
       'Admin has approved their documents.',
       300, 'ReferralVerified', 1, now(), now()
FROM udrive.growth_campaigns g
WHERE g.campaign_type = 'Referral'
  AND g.code LIKE 'REFERRAL-%'
  AND NOT EXISTS (SELECT 1 FROM udrive.growth_campaign_milestones m
                   WHERE m.campaign_id = g.id AND m.sort_order = 1);

INSERT INTO udrive.growth_campaign_milestones
    (campaign_id, sort_order, title, description, reward_amount,
     condition_type, condition_value, created_at, updated_at)
SELECT g.id, 2, 'Their first ride',
       'They have completed a ride.',
       500, 'ReferralFirstRide', 1, now(), now()
FROM udrive.growth_campaigns g
WHERE g.campaign_type = 'Referral'
  AND g.code LIKE 'REFERRAL-%'
  AND NOT EXISTS (SELECT 1 FROM udrive.growth_campaign_milestones m
                   WHERE m.campaign_id = g.id AND m.sort_order = 2);

INSERT INTO udrive.growth_campaign_milestones
    (campaign_id, sort_order, title, description, reward_amount,
     condition_type, condition_value, created_at, updated_at)
SELECT g.id, 3, 'They become active',
       'They have reached the required rides inside the window.',
       1200, 'ReferralActive', 1, now(), now()
FROM udrive.growth_campaigns g
WHERE g.campaign_type = 'Referral'
  AND g.code LIKE 'REFERRAL-%'
  AND NOT EXISTS (SELECT 1 FROM udrive.growth_campaign_milestones m
                   WHERE m.campaign_id = g.id AND m.sort_order = 3);

-- ─────────────────────────────────────────────── 3. finding a code quickly

-- Applying a code looks a driver up by it, which nothing has ever needed to do
-- — the column existed only to be printed on a screen.
CREATE UNIQUE INDEX IF NOT EXISTS ux_driver_profiles_referral_code
    ON udrive.driver_profiles (upper(referral_code))
    WHERE referral_code IS NOT NULL;

-- Syncing milestones asks "which rows does this referrer have" and "is this
-- driver already referred", on every growth evaluation.
CREATE INDEX IF NOT EXISTS ix_driver_referrals_referrer
    ON udrive.driver_referrals (referrer_driver_profile_id, status);
