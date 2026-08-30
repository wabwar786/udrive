-- 027: Home hero artwork, editable from the admin portal.
--
-- Each Home service (Coaster/Bus, Car, Bike, Hotel) can carry its own hero
-- image URL. The mobile app reads these through GET /api/v1/settings/public
-- and falls back to its built-in vector illustration whenever a value is empty
-- or the image fails to load, so an unset or broken URL never breaks Home.
--
-- is_public is true on purpose: these are display assets shown to every
-- customer before they log in, not operational configuration.

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('home.hero.bus.imageUrl',   '""'::jsonb,
     'Home hero image for Coaster/Bus. Leave empty to use the built-in illustration.',
     true, now(), now()),
    ('home.hero.car.imageUrl',   '""'::jsonb,
     'Home hero image for Car. Leave empty to use the built-in illustration.',
     true, now(), now()),
    ('home.hero.bike.imageUrl',  '""'::jsonb,
     'Home hero image for Bike. Leave empty to use the built-in illustration.',
     true, now(), now()),
    ('home.hero.hotel.imageUrl', '""'::jsonb,
     'Home hero image for Hotel. Leave empty to use the built-in illustration.',
     true, now(), now())
ON CONFLICT (key) DO UPDATE
    SET description = EXCLUDED.description,
        is_public   = true,
        updated_at  = now();
