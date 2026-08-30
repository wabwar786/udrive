-- 032: Vehicle images, set from the admin portal.
--
-- The app ships stock illustrations. They are placeholders: real photographs of
-- the vehicles actually on the road in Azad Kashmir will do more for trust than
-- any amount of layout work, and only someone on the ground can supply those.
--
-- These are public settings because the customer app reads them before sign-in,
-- and an image URL is not a secret.
--
-- Empty means "use the built-in illustration", so the app is never broken by an
-- unset key — it just looks generic until a picture is added.

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('vehicle.image.bike',     '""'::jsonb,
     'Photograph shown for Bike in the vehicle picker. Empty = built-in illustration.',
     true, now(), now()),
    ('vehicle.image.car',      '""'::jsonb,
     'Photograph shown for Car. Empty = built-in illustration.',
     true, now(), now()),
    ('vehicle.image.ac_car',   '""'::jsonb,
     'Photograph shown for Car with AC. Empty = built-in illustration.',
     true, now(), now()),
    ('vehicle.image.hiace',    '""'::jsonb,
     'Photograph shown for Hiace. Empty = built-in illustration.',
     true, now(), now()),
    ('vehicle.image.coaster',  '""'::jsonb,
     'Photograph shown for Coaster. Empty = built-in illustration.',
     true, now(), now())
ON CONFLICT (key) DO UPDATE
    SET description = EXCLUDED.description,
        is_public   = true,
        updated_at  = now();
