-- What the four-step driver sign-up needs and the schema did not have.
--
-- The old flow asked for four photographs and nothing else: the platform knew a
-- driver's phone number and whatever their user record happened to hold. It did
-- not know their date of birth, their licence number, when that licence
-- expires, or the registered colour of the car they turn up in.
--
-- Every one of those is something a reviewer needs to make a decision, and a
-- customer benefits from at the roadside — "the white Civic" is only useful if
-- the platform knows the car is white.

ALTER TABLE udrive.driver_profiles
    ADD COLUMN IF NOT EXISTS date_of_birth date,

    -- Unmasked, alongside the masked copies already there.
    --
    -- The masked ones are for display; a reviewer comparing a licence
    -- photograph against a typed number needs the number. These are visible
    -- only to admins and to the driver themselves.
    ADD COLUMN IF NOT EXISTS driving_licence_number varchar(64),
    ADD COLUMN IF NOT EXISTS driving_licence_expiry date,
    ADD COLUMN IF NOT EXISTS cnic_number varchar(32);

COMMENT ON COLUMN udrive.driver_profiles.driving_licence_expiry IS
    'When the licence runs out. A driver whose licence has expired should stop '
    'receiving work, and nothing could tell before this existed.';

-- `vehicles.colour` already exists and is NOT NULL, so nothing is added for it.

-- Document types the new steps collect.
--
-- Recorded here rather than only in code so the set is readable from the
-- database. `DRIVING_LICENCE_BACK` and `SELFIE_WITH_CNIC` are the two that
-- reviewers have been asking for by hand: a licence back carries the
-- categories, and a selfie held next to the CNIC is what proves the person and
-- the card belong together.
CREATE TABLE IF NOT EXISTS udrive.document_type_catalogue (
    document_type varchar(64) PRIMARY KEY,
    scope varchar(16) NOT NULL,
    label varchar(80) NOT NULL,
    is_required boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0
);

INSERT INTO udrive.document_type_catalogue
    (document_type, scope, label, is_required, sort_order)
VALUES
    ('SELFIE',                'Driver',  'Personal picture',          true,  1),
    ('DRIVING_LICENCE',       'Driver',  'Driver licence',            true,  2),
    ('DRIVING_LICENCE_BACK',  'Driver',  'Driver licence (back)',     true,  3),
    ('CNIC_FRONT',            'Driver',  'CNIC (front side)',         true,  4),
    ('CNIC_BACK',             'Driver',  'CNIC (back side)',          true,  5),
    ('SELFIE_WITH_CNIC',      'Driver',  'Selfie with CNIC',          true,  6),
    ('VEHICLE_FRONT',         'Vehicle', 'Photo of your vehicle',     true,  1),
    ('REGISTRATION_BOOK',     'Vehicle', 'Registration certificate',  true,  2),
    ('REGISTRATION_BOOK_BACK','Vehicle', 'Registration certificate (back)', true, 3),
    ('VEHICLE_REAR',          'Vehicle', 'Vehicle rear photograph',   false, 4),
    ('VEHICLE_INTERIOR',      'Vehicle', 'Vehicle interior photograph', false, 5)
ON CONFLICT (document_type) DO NOTHING;
