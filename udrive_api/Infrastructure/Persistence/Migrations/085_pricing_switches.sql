-- 085: two switches for the admin Pricing page ("Pricing — aasan").
--
-- Both default to ON, which is exactly how quotes already behave: zones still
-- apply only where a zone is active, and the petrol index still does nothing
-- while its baseline is 0. Nothing changes on deploy; the admin decides.

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('pricing.zones.enabled', 'true'::jsonb,
     'Pahari area (fare zones) on or off for every quote.', false, now(), now()),
    ('pricing.fuel.enabled', 'true'::jsonb,
     'Petrol / diesel index on or off for every quote.', false, now(), now())
ON CONFLICT (key) DO NOTHING;
