-- Two things the product needs and the database was not carrying.

-- ─────────────────────────────── 1. The customer-side service switches, again

-- Migration 045 created udrive.service_availability and seeded seven rows.
-- If those rows are not there, nothing in the product works the way it reads:
-- GET /api/v1/services returns an empty list, the app's _availabilityOf falls
-- back to "open" for every key it does not recognise, no SOON badge can ever
-- appear, and the Admin's Services page shows nothing to switch. An Admin
-- wanting to close Hotels for a month has no way to do it and no error telling
-- them why.
--
-- Re-seeding is safe: ON CONFLICT DO NOTHING leaves whatever an Admin has
-- already set, so a row that exists keeps its is_open, its badge and its
-- message. This only fills gaps.
INSERT INTO udrive.service_availability (service_key, is_open, badge_label, closed_message)
VALUES
    ('cityRides',  true,  'SOON', 'City rides are not open yet.'),
    ('tour',       true,  'SOON', 'Tours are not open yet.'),
    ('cityToCity', true,  'SOON', 'City to city trips are not open yet.'),
    ('hotels',     true,  'SOON', 'Hotel booking is not open yet.'),
    ('coster',     true,  'SOON', 'Coster and Hiace seats are not open yet.'),
    ('explore',    true,  'SOON', 'Explore is not open yet.'),
    ('carRental',  false, 'SOON', 'Self-drive car rental is not open yet.')
ON CONFLICT (service_key) DO NOTHING;

-- ───────────────────────────────── 2. The tour readiness bar, as a setting

-- A vehicle may carry a tour package only if its mountain readiness score
-- reaches a bar. That bar was the number 60, written into
-- PackageMarketplaceService.ValidatePackage.
--
-- Two problems with a number in code. The obvious one: changing it needs a
-- deploy, so the bar cannot respond to what the fleet actually looks like —
-- and at 60 most of a real Azad Kashmir fleet does not qualify, because the
-- score starts at 20 and only a 4x4 with a first-aid kit and a spare tyre
-- clears it. The quieter one: a number in code cannot be shown to anyone, so a
-- Driver was told "this vehicle does not meet the minimum tourism readiness
-- score" without being told the score, the minimum, or which box to tick.
--
-- As a setting it can be read by the API that serves the Driver's vehicle
-- screen, so the Driver sees 45 / 60 and the three items that would close the
-- gap, and an Admin can move the bar when the fleet tells them to.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'tour.minimum_readiness',
    to_jsonb(60),
    'Minimum vehicle mountain readiness score (0-100) required to publish a '
    || 'tour package. The score is computed from the vehicle''s equipment.',
    false,
    now(),
    now())
ON CONFLICT (key) DO NOTHING;
