-- 029: Google Places key, settable from the admin portal.
--
-- is_public is FALSE and must stay false. This key is used server-side only,
-- by PlacesController. Marking it public would expose it through
-- GET /api/v1/settings/public, which is exactly what proxying the calls was
-- meant to prevent.
--
-- Leave the value empty and address search falls back to OpenStreetMap
-- Nominatim, which needs no key. Set it and the proxy switches to Google
-- immediately — no app rebuild, no redeploy.

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('places.google.apiKey', '""'::jsonb,
     'Server-side Google Places / Geocoding key. Never exposed to clients. Empty = use OpenStreetMap.',
     false, now(), now())
ON CONFLICT (key) DO UPDATE
    SET description = EXCLUDED.description,
        is_public   = false,
        updated_at  = now();
