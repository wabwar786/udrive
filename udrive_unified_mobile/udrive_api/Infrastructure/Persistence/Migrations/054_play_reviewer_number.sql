-- The Google Play reviewer number, set on deploy rather than by hand.
--
-- Play requires a working demo account under App access, and a reviewer who
-- cannot sign in fails the submission. Leaving that to somebody remembering to
-- fill in two fields in the admin portal — on a panel where a half-saved pair
-- is silently rejected — is how a release gets rejected for a reason nobody
-- can reproduce afterwards.
--
-- The number below is the seeded demo driver from 003_seed_catalog.sql:
-- "Adeel Khan", Approved, with a verified vehicle. Signing in with it lands in
-- Customer mode and can switch to Driver Mode from the home card, so one
-- credential shows a reviewer both sides of the product.
--
-- How this interacts with everything else:
--   * OtpDeliveryService.PlanAsync checks this number FIRST, before the
--     provider. It works whether WhatsApp is live or not, and nothing is sent
--     to it — which is the point, since +923000000001 belongs to nobody.
--   * It is therefore the one number that still signs in while production
--     refuses the fixed development code.
--
-- ON CONFLICT ... DO UPDATE WHERE the existing value is blank.
--
-- DO NOTHING was the original, on the reasoning that an admin who had already
-- set a reviewer number should keep it. That reasoning was wrong, because
-- DO NOTHING keys on the row existing, not on it holding anything. When an
-- admin saves the WhatsApp OTP panel — which is the only way the WA Engine API
-- key gets set at all — OtpDeliveryService.UpdateAsync writes all seven otp.*
-- keys, including otp.test.phone and otp.test.code as EMPTY STRINGS whenever
-- the two reviewer fields were left blank. So on every database where anybody
-- had ever configured WhatsApp, this migration inserted nothing, the rows
-- stayed empty, PlanAsync's reviewer branch (which requires both to be
-- non-empty) was skipped, and the Google Play reviewer got 503
-- otp_not_configured. The comment said one thing and the SQL did another.
--
-- The WHERE clause keeps the original intent: a real value an admin set is
-- left alone; only a blank is filled in.
--
-- CHANGE THE CODE AFTER REVIEW PASSES. It is a constant in the shipped app
-- (AppController.demoReviewerCode) and can be read out of the APK, and this
-- account is a real approved driver.

INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
VALUES
    ('otp.test.phone', to_jsonb('+923000000001'::text),
     'Google Play reviewer number. Always accepts otp.test.code under any provider, and nothing is sent to it.',
     false, now(), now()),
    ('otp.test.code', to_jsonb('5095'::text),
     'Reviewer code (secret). Rotate once Play review has passed.',
     false, now(), now())
ON CONFLICT (key) DO UPDATE
    SET value_json = EXCLUDED.value_json,
        description = EXCLUDED.description,
        -- Forced, not carried over: PublicSettingsController serves every
        -- is_public row anonymously, and AdminOperationsService hides otp.%
        -- from the portal, so a row that somehow arrived with is_public = true
        -- would publish the reviewer code and could not be corrected from the
        -- admin UI. The INSERT branch already sets false; this makes the
        -- UPDATE branch agree with it.
        is_public = false,
        updated_at = now()
    -- btrim with no second argument trims spaces only, while the C# side reads
    -- the value with IsNullOrWhiteSpace. A tab-only value would therefore look
    -- "already set" here and "empty" there, and the reviewer would get
    -- otp_not_configured — the exact failure this migration exists to prevent.
    WHERE coalesce(btrim(udrive.system_settings.value_json #>> '{}', E' \t\r\n'), '') = '';
