-- What an Admin can change about renting without a release.
--
-- Three settings and one column. The settings are the two that could only be
-- changed by shipping an APK, and one that could not be changed at all.

-- ──────────────────────────────────────── 1. the disclaimer, in the database

-- The rental terms text, in both languages.
--
-- It was written into the app. That made the wording a **release**: changing a
-- single sentence meant a new build, a Play Store review and a wait, which is
-- an absurd price for a line of text that a lawyer may want altered the same
-- afternoon. Worse, the version number was already stored on every booking, so
-- the database was carefully recording which text a Customer agreed to while
-- the text itself lived somewhere the database could not see.
--
-- Public, so the app reads it from the route it already uses for public
-- settings. No new plumbing on the app side.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'rental.disclaimer_text_en',
    to_jsonb(
        'The car goes out in your care. UDrive introduces you to the owner and '
        || 'nothing more: we do not inspect the car, we do not check its '
        || 'papers, and we are not responsible for a fine, a crash, theft or '
        || 'damage.'),
    'The rental disclaimer shown to Customers, in English. Changing it should '
    || 'be accompanied by raising rental.disclaimer_version.',
    true, now(), now())
ON CONFLICT (key) DO NOTHING;

INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'rental.disclaimer_text_ur',
    to_jsonb(
        'گاڑی آپ کی ذمہ داری میں جاتی ہے۔ UDrive صرف آپ کو مالک سے ملاتا ہے: '
        || 'نہ ہم گاڑی جانچتے ہیں، نہ اس کے کاغذات، اور چالان، حادثے، چوری یا '
        || 'نقصان کے ذمہ دار نہیں۔'),
    'The rental disclaimer shown to Customers, in Urdu.',
    true, now(), now())
ON CONFLICT (key) DO NOTHING;

-- The version is published too, so the app sends back the number belonging to
-- the text it actually displayed. It was private, which meant the app had no
-- way to know what it was agreeing to and had to be told by the quote.
UPDATE udrive.system_settings
SET is_public = true, updated_at = now()
WHERE key = 'rental.disclaimer_version' AND is_public = false;

-- ─────────────────────────────────────────────── 2. a ceiling on the deposit

-- The largest security deposit an owner may ask for.
--
-- Nothing capped it. An owner could put a car on the platform at a fair daily
-- rate and demand two hundred thousand rupees as a deposit, which is not a
-- deposit — it is a way of appearing in the listing without ever being booked,
-- and it makes the whole rental page look dishonest to anyone scrolling it.
--
-- Zero means no ceiling, which is where this starts: the right number is a
-- judgement about this market and an Admin should set it after seeing what
-- owners actually ask.
INSERT INTO udrive.system_settings
    (key, value_json, description, is_public, created_at, updated_at)
VALUES (
    'rental.maximum_deposit',
    to_jsonb(0),
    'The largest security deposit an owner may set, in PKR. 0 means no limit.',
    true, now(), now())
ON CONFLICT (key) DO NOTHING;

-- ────────────────────────────────────────────── 3. an Admin may cancel

-- `cancelled_by` already exists and already takes 'Customer' or 'Owner'. This
-- adds the third case rather than a new column: an Admin settling a dispute
-- cancels on behalf of neither side, and the record has to say so, because
-- "Owner cancelled" counts against the owner and would be a lie.
--
-- A plain comment, not a constraint. The column has no CHECK on it today and
-- adding one here would reject rows written by an older build mid-deploy.
COMMENT ON COLUMN udrive.rental_bookings.cancelled_by IS
    'Who called the booking off: Customer, Owner, or Admin. An Admin '
    'cancellation counts against neither side and always returns the advance.';
