-- Which services customers may open, and what they are told when they cannot.
--
-- A service being "coming soon" is an operational fact that changes without a
-- release: Coster needs vehicles registered first, car rental needs a fleet,
-- city-to-city needs drivers willing to leave town. Hard-coding that into the
-- app means a deploy every time one of them is ready.
--
-- Deliberately **customer-side only**. Closing a service does not touch the
-- Driver app at all: drivers keep registering vehicles and Admins keep
-- verifying them, so that on the day the toggle flips there are already
-- vehicles to serve it. Without that, the platform deadlocks — the service is
-- closed because there are no vehicles, and there are no vehicles because the
-- service is closed.
--
-- The key set is fixed. Each key maps to a screen in the app, so a row an Admin
-- invents would point at nothing; the portal offers on/off and wording, not new
-- services.

CREATE TABLE IF NOT EXISTS udrive.service_availability (
    service_key varchar(40) PRIMARY KEY,

    -- False means the tile is shown, dimmed, badged, and does not open.
    -- Not hidden: "can I do this yet" is a question customers ask, and a
    -- missing tile answers it with silence.
    is_open boolean NOT NULL DEFAULT true,

    -- What the tile says when closed. Short — it sits in a badge.
    badge_label varchar(24) NOT NULL DEFAULT 'SOON',

    -- What the customer is told on tapping. The Admin's own words, because
    -- "not available" tells nobody when to come back.
    closed_message varchar(200) NOT NULL
        DEFAULT 'This service is not open yet.',

    updated_by_user_id uuid REFERENCES udrive.users(id),
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO udrive.service_availability (service_key, is_open, badge_label, closed_message)
VALUES
    ('cityRides',  true,  'SOON', 'City rides are not open yet.'),
    ('tour',       true,  'SOON', 'Tours are not open yet.'),
    ('cityToCity', true,  'SOON', 'City to city trips are not open yet.'),
    ('hotels',     true,  'SOON', 'Hotel booking is not open yet.'),
    ('coster',     true,  'SOON', 'Coster and Hiace seats are not open yet.'),
    ('explore',    true,  'SOON', 'Explore is not open yet.'),
    -- The only one closed on arrival: it has no screen behind it yet.
    ('carRental',  false, 'SOON', 'Self-drive car rental is not open yet.')
ON CONFLICT (service_key) DO NOTHING;

COMMENT ON TABLE udrive.service_availability IS
    'Customer-side switches. Drivers are never affected: vehicles can be '
    'registered for a closed service so it has a fleet on the day it opens.';
