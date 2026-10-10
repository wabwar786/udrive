-- Hotel mode: the owner's own profile, and a hotel built step by step.
--
-- Until now a hotel was one long form (name, address, an image URL typed by
-- hand, latitude and longitude typed by hand) and the owner had no profile of
-- their own beyond a business name copied from the first hotel. The app now
-- has:
--   * an owner profile — name, business, contact, email and both sides of the
--     CNIC, checked by the admin once (verified when their first hotel is
--     approved);
--   * a five-step hotel wizard saved as a Draft after the first step, so an
--     owner can stop and carry on later, with a photo gallery, a property type
--     and check-in / check-out times.
--
-- A Draft is invisible everywhere: customer search only ever shows Approved,
-- and the admin list leaves Drafts out until the owner presses Submit.
--
-- Safe to run more than once.

ALTER TABLE udrive.hotel_owner_profiles
    ADD COLUMN IF NOT EXISTS owner_name text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS email text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS cnic_front_url text,
    ADD COLUMN IF NOT EXISTS cnic_back_url text,
    ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'NotSubmitted',
    ADD COLUMN IF NOT EXISTS verification_note text,
    ADD COLUMN IF NOT EXISTS verified_by uuid REFERENCES udrive.users(id),
    ADD COLUMN IF NOT EXISTS verified_at timestamptz;

ALTER TABLE udrive.hotels
    ADD COLUMN IF NOT EXISTS property_type text NOT NULL DEFAULT 'Hotel',
    ADD COLUMN IF NOT EXISTS check_in_time time,
    ADD COLUMN IF NOT EXISTS check_out_time time,
    ADD COLUMN IF NOT EXISTS submitted_at timestamptz;

-- The gallery. main_image_url on udrive.hotels stays the photo customers see
-- first, and is kept equal to the first row here (lowest sort_order).
CREATE TABLE IF NOT EXISTS udrive.hotel_photos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hotel_id uuid NOT NULL REFERENCES udrive.hotels(id) ON DELETE CASCADE,
    url text NOT NULL,
    file_url text NOT NULL,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_hotel_photos_hotel ON udrive.hotel_photos (hotel_id, sort_order);

-- Owners who already have a hotel keep working: their existing hotels are
-- untouched, and their profile simply shows what is still missing.
