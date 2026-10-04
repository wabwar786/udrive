-- Demo fleet: drivers, vehicles, tour departures and rental cars.
--
-- Runs only when an admin presses "Add demo data" in the portal. Every row
-- here hangs off a demo account (email demo.%@udrive.local), which is how
-- "Remove demo data" finds them again — and the only thing it ever deletes.
-- Real drivers, vehicles and bookings are never touched by either button.
--
-- Rules the rows follow, on purpose:
--   * No invented ratings or trip counts. average_rating 0 and completed_trips
--     0 show as "New"; safety_score is the default every driver starts with.
--   * Never offered for city rides: available_for_city = false and is_online =
--     false, so a demo car can never appear on a live ride map or receive a
--     real ride request. They show in Tours and Car rental only.
--   * Every listing carries the "Demo" label in the app and refuses bookings
--     (see DemoListing on the server).
--   * Departures are dated from the moment the button is pressed, so pressing
--     it again later brings them back into the future.
--   * Photographs are filled in afterwards by the server, which downloads them
--     once into its own storage. The app never contacts a third party for them.
--
-- Safe to run as often as you like: every statement is ON CONFLICT DO UPDATE.

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------
INSERT INTO udrive.users
    (id, phone_number, email, full_name, role, status, preferred_language, phone_verified, created_at, updated_at)
VALUES
    ('53000000-0000-0000-0000-000000000001', '+923109901001', 'demo.driver1@udrive.local', 'Demo Driver · Neelum Tours',    'Driver', 'Approved', 'en', true, now(), now()),
    ('53000000-0000-0000-0000-000000000002', '+923109901002', 'demo.driver2@udrive.local', 'Demo Driver · Kashmir Travel',  'Driver', 'Approved', 'en', true, now(), now()),
    ('53000000-0000-0000-0000-000000000003', '+923109901003', 'demo.driver3@udrive.local', 'Demo Driver · Group Coaster',   'Driver', 'Approved', 'en', true, now(), now()),
    ('53000000-0000-0000-0000-000000000004', '+923109901004', 'demo.driver4@udrive.local', 'Demo Driver · Mountain 4x4',    'Driver', 'Approved', 'en', true, now(), now()),
    ('53000000-0000-0000-0000-000000000005', '+923109901005', 'demo.driver5@udrive.local', 'Demo Driver · Poonch Trips',    'Driver', 'Approved', 'en', true, now(), now()),
    ('53000000-0000-0000-0000-000000000006', '+923109901006', 'demo.driver6@udrive.local', 'Demo Rentals · Muzaffarabad',   'Driver', 'Approved', 'en', true, now(), now())
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    role = 'Driver',
    status = 'Approved',
    phone_verified = true,
    updated_at = now();

INSERT INTO udrive.user_roles(user_id, role, created_at)
SELECT u.id, r.role, now()
FROM udrive.users u
CROSS JOIN (VALUES ('Customer'), ('Driver')) AS r(role)
WHERE u.id IN (
    '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000002',
    '53000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000004',
    '53000000-0000-0000-0000-000000000005', '53000000-0000-0000-0000-000000000006')
ON CONFLICT (user_id, role) DO NOTHING;

INSERT INTO udrive.driver_profiles
    (id, user_id, verification_status, average_rating, completed_trips, is_online,
     languages, service_areas, approved_at, created_at, updated_at)
VALUES
    ('54000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001', 'Approved', 0, 0, false, '{Urdu,English}', '{Muzaffarabad,Neelum}', now(), now(), now()),
    ('54000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000002', 'Approved', 0, 0, false, '{Urdu,English}', '{Muzaffarabad,Neelum}', now(), now(), now()),
    ('54000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000003', 'Approved', 0, 0, false, '{Urdu}',         '{Muzaffarabad,Kohala}', now(), now(), now()),
    ('54000000-0000-0000-0000-000000000004', '53000000-0000-0000-0000-000000000004', 'Approved', 0, 0, false, '{Urdu,English}', '{Neelum,Poonch}',       now(), now(), now()),
    ('54000000-0000-0000-0000-000000000005', '53000000-0000-0000-0000-000000000005', 'Approved', 0, 0, false, '{Urdu}',         '{Poonch,Bagh}',         now(), now(), now()),
    ('54000000-0000-0000-0000-000000000006', '53000000-0000-0000-0000-000000000006', 'Approved', 0, 0, false, '{Urdu,English}', '{Muzaffarabad}',        now(), now(), now())
ON CONFLICT (id) DO UPDATE SET
    verification_status = 'Approved',
    average_rating = 0,
    completed_trips = 0,
    is_online = false,
    updated_at = now();

-- ---------------------------------------------------------------------------
-- Vehicles. image_url is set by the server after it downloads the photo.
-- ---------------------------------------------------------------------------
INSERT INTO udrive.vehicles
    (id, driver_profile_id, category, make, model, year, registration_number, colour,
     passenger_capacity, luggage_capacity, has_air_conditioning, has_heating, is_four_by_four,
     has_first_aid_kit, has_spare_tyre, mountain_readiness_score, status, booking_mode,
     available_for_city, available_for_tour, tour_per_day_rate,
     available_for_rent, rent_with_driver_daily, rent_self_drive_daily, rent_security_deposit,
     rent_minimum_days, rent_km_per_day, rent_fuel_included, rent_pickup_point,
     created_at, updated_at)
VALUES
    -- Tour vehicles
    ('55000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000001', 'Hiace',  'Toyota', 'Hiace',          2019, 'DEMO-TR-101', 'White',  12, 8,  true,  true,  false, true, true, 70, 'Verified', 'Both',         false, true,  14000, false, NULL,  NULL,  NULL,  1, NULL, false, NULL, now(), now()),
    ('55000000-0000-0000-0000-000000000002', '54000000-0000-0000-0000-000000000002', 'Hiace',  'Toyota', 'Hiace',          2018, 'DEMO-TR-102', 'White',  12, 8,  true,  true,  false, true, true, 70, 'Verified', 'Both',         false, true,  13500, false, NULL,  NULL,  NULL,  1, NULL, false, NULL, now(), now()),
    ('55000000-0000-0000-0000-000000000003', '54000000-0000-0000-0000-000000000003', 'Coster', 'Toyota', 'Coaster',        2016, 'DEMO-TR-103', 'White',  22, 15, true,  true,  false, true, true, 60, 'Verified', 'Both',         false, true,  26000, false, NULL,  NULL,  NULL,  1, NULL, false, NULL, now(), now()),
    ('55000000-0000-0000-0000-000000000004', '54000000-0000-0000-0000-000000000004', 'Car',    'Toyota', 'Land Cruiser Prado', 2018, 'DEMO-TR-104', 'Black', 7, 4,  true,  true,  true,  true, true, 90, 'Verified', 'WholeVehicle', false, true,  18000, false, NULL,  NULL,  NULL,  1, NULL, false, NULL, now(), now()),
    ('55000000-0000-0000-0000-000000000005', '54000000-0000-0000-0000-000000000005', 'Car',    'Suzuki', 'APV',            2017, 'DEMO-TR-105', 'Silver',  7, 3,  true,  false, false, true, true, 55, 'Verified', 'Both',         false, true,  9000,  false, NULL,  NULL,  NULL,  1, NULL, false, NULL, now(), now()),
    ('55000000-0000-0000-0000-000000000006', '54000000-0000-0000-0000-000000000005', 'Car',    'Toyota', 'Corolla',        2021, 'DEMO-TR-106', 'White',   4, 2,  true,  true,  false, true, true, 60, 'Verified', 'WholeVehicle', false, true,  9500,  false, NULL,  NULL,  NULL,  1, NULL, false, NULL, now(), now()),
    -- Rental vehicles
    ('55000000-0000-0000-0000-000000000011', '54000000-0000-0000-0000-000000000006', 'Car',    'Toyota', 'Corolla',        2021, 'DEMO-RN-111', 'White',   4, 2,  true,  true,  false, true, true, 60, 'Verified', 'WholeVehicle', false, false, NULL,  true,  6500,  5000,  15000, 1, 200, false, 'Chattar Klas, Muzaffarabad', now(), now()),
    ('55000000-0000-0000-0000-000000000012', '54000000-0000-0000-0000-000000000006', 'Car',    'Honda',  'Civic',          2022, 'DEMO-RN-112', 'Grey',    4, 2,  true,  true,  false, true, true, 60, 'Verified', 'WholeVehicle', false, false, NULL,  true,  8000,  6500,  20000, 1, 200, false, 'Upper Chattar, Muzaffarabad', now(), now()),
    ('55000000-0000-0000-0000-000000000013', '54000000-0000-0000-0000-000000000004', 'Car',    'Toyota', 'Land Cruiser Prado', 2018, 'DEMO-RN-113', 'Black', 7, 4,  true,  true,  true,  true, true, 90, 'Verified', 'WholeVehicle', false, false, NULL,  true,  16000, NULL,  40000, 2, 250, false, 'Main Bazar, Rawalakot', now(), now()),
    ('55000000-0000-0000-0000-000000000014', '54000000-0000-0000-0000-000000000004', 'Car',    'Suzuki', 'Jimny',          2017, 'DEMO-RN-114', 'Red',     4, 1,  false, true,  true,  true, true, 85, 'Verified', 'WholeVehicle', false, false, NULL,  true,  9000,  7500,  20000, 2, 150, false, 'Bagh Chowk, Bagh', now(), now()),
    ('55000000-0000-0000-0000-000000000015', '54000000-0000-0000-0000-000000000006', 'Car',    'Toyota', 'Hilux Revo',     2021, 'DEMO-RN-115', 'White',   5, 4,  true,  true,  true,  true, true, 85, 'Verified', 'WholeVehicle', false, false, NULL,  true,  14000, 12000, 35000, 1, 250, false, 'Chattar Klas, Muzaffarabad', now(), now()),
    ('55000000-0000-0000-0000-000000000016', '54000000-0000-0000-0000-000000000002', 'Hiace',  'Toyota', 'Hiace',          2019, 'DEMO-RN-116', 'White',  12, 8,  true,  true,  false, true, true, 70, 'Verified', 'WholeVehicle', false, false, NULL,  true,  14000, NULL,  25000, 1, 300, false, 'Kotli Bypass, Kotli', now(), now()),
    ('55000000-0000-0000-0000-000000000017', '54000000-0000-0000-0000-000000000003', 'Coster', 'Toyota', 'Coaster',        2016, 'DEMO-RN-117', 'White',  22, 15, true,  true,  false, true, true, 60, 'Verified', 'WholeVehicle', false, false, NULL,  true,  26000, NULL,  50000, 1, 300, false, 'Mirpur Chowk, Mirpur', now(), now())
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category, make = EXCLUDED.make, model = EXCLUDED.model, year = EXCLUDED.year,
    colour = EXCLUDED.colour, passenger_capacity = EXCLUDED.passenger_capacity,
    luggage_capacity = EXCLUDED.luggage_capacity, has_air_conditioning = EXCLUDED.has_air_conditioning,
    is_four_by_four = EXCLUDED.is_four_by_four, status = 'Verified', booking_mode = EXCLUDED.booking_mode,
    available_for_city = false, available_for_tour = EXCLUDED.available_for_tour,
    tour_per_day_rate = EXCLUDED.tour_per_day_rate, available_for_rent = EXCLUDED.available_for_rent,
    rent_with_driver_daily = EXCLUDED.rent_with_driver_daily, rent_self_drive_daily = EXCLUDED.rent_self_drive_daily,
    rent_security_deposit = EXCLUDED.rent_security_deposit, rent_minimum_days = EXCLUDED.rent_minimum_days,
    rent_km_per_day = EXCLUDED.rent_km_per_day, rent_pickup_point = EXCLUDED.rent_pickup_point,
    updated_at = now();

-- ---------------------------------------------------------------------------
-- Tour departures, dated from today (Pakistan time). Mixed on purpose so every
-- filter on the Tours screen has something: seats left, fully free, today,
-- whole-vehicle only.
-- ---------------------------------------------------------------------------
WITH today AS (
    SELECT (date_trunc('day', now() AT TIME ZONE 'Asia/Karachi')) AT TIME ZONE 'Asia/Karachi' AS d
), rows(id, profile, vehicle, slug, title, city, pickup, day_offset, hour, days, total, free, seat, whole) AS (
    VALUES
    ('56000000-0000-0000-0000-000000000001'::uuid, '54000000-0000-0000-0000-000000000001'::uuid, '55000000-0000-0000-0000-000000000001'::uuid, 'keran',        'Keran & Neelum river day trip',      'Muzaffarabad', 'Chattar Klas stop, Muzaffarabad',    0, 14, 1, 12, 5,  2200, 26000),
    ('56000000-0000-0000-0000-000000000002'::uuid, '54000000-0000-0000-0000-000000000004'::uuid, '55000000-0000-0000-0000-000000000004'::uuid, 'banjosa-lake', 'Banjosa Lake family trip',           'Muzaffarabad', 'Secretariat Chowk, Muzaffarabad',    0, 17, 1,  7, 7,  3000, 18000),
    ('56000000-0000-0000-0000-000000000003'::uuid, '54000000-0000-0000-0000-000000000005'::uuid, '55000000-0000-0000-0000-000000000006'::uuid, 'toli-pir',     'Toli Pir sunrise — whole car',       'Rawalakot',    'Main Bazar, Rawalakot',              0, 11, 1,  4, 4,  0,    9500),
    ('56000000-0000-0000-0000-000000000004'::uuid, '54000000-0000-0000-0000-000000000003'::uuid, '55000000-0000-0000-0000-000000000003'::uuid, 'arang-kel',    'Arang Kel 3-day group tour',         'Muzaffarabad', 'Kohala Bridge',                      1,  7, 3, 22, 9,  2800, 60000),
    ('56000000-0000-0000-0000-000000000005'::uuid, '54000000-0000-0000-0000-000000000002'::uuid, '55000000-0000-0000-0000-000000000002'::uuid, 'sharda',       'Sharda & Kel 2-day trip',            'Muzaffarabad', 'Chella Bandi, Muzaffarabad',         2,  6, 2, 12, 12, 2500, 27000),
    ('56000000-0000-0000-0000-000000000006'::uuid, '54000000-0000-0000-0000-000000000005'::uuid, '55000000-0000-0000-0000-000000000005'::uuid, 'pir-chinasi',  'Pir Chinasi evening trip',           'Muzaffarabad', 'Domel Chowk, Muzaffarabad',          3, 15, 1,  7, 2,  1800, 11000),
    ('56000000-0000-0000-0000-000000000007'::uuid, '54000000-0000-0000-0000-000000000001'::uuid, '55000000-0000-0000-0000-000000000001'::uuid, 'ratti-gali-lake','Ratti Gali Lake 2-day jeep tour',   'Muzaffarabad', 'Chattar Klas stop, Muzaffarabad',    5,  5, 2, 12, 8,  3500, 40000),
    ('56000000-0000-0000-0000-000000000008'::uuid, '54000000-0000-0000-0000-000000000004'::uuid, '55000000-0000-0000-0000-000000000004'::uuid, 'taobat',       'Taobat & Upper Neelum 4-day',        'Muzaffarabad', 'Secretariat Chowk, Muzaffarabad',    7,  6, 4,  7, 7,  0,    72000),
    ('56000000-0000-0000-0000-000000000009'::uuid, '54000000-0000-0000-0000-000000000002'::uuid, '55000000-0000-0000-0000-000000000002'::uuid, 'leepa-valley', 'Leepa 2-day trip',                   'Muzaffarabad', 'Chella Bandi, Muzaffarabad',         9,  7, 2, 12, 6,  2600, 28000),
    ('56000000-0000-0000-0000-000000000010'::uuid, '54000000-0000-0000-0000-000000000003'::uuid, '55000000-0000-0000-0000-000000000003'::uuid, 'muzaffarabad', 'Muzaffarabad city & Red Fort tour',  'Muzaffarabad', 'Kohala Bridge',                     12,  9, 1, 22, 22, 1200, 22000)
)
INSERT INTO udrive.tour_packages
    (id, driver_profile_id, vehicle_id, destination_id, title, starting_city, pickup_point,
     departure_at, return_at, total_seats, available_seats, price_per_seat, whole_vehicle_price,
     customer_offers_allowed, status, description, cancellation_policy, inclusions,
     created_at, updated_at)
SELECT r.id, r.profile, r.vehicle, d.id, r.title, r.city, r.pickup,
       x.dep,
       x.dep + make_interval(days => r.days - 1, hours => 6),
       r.total, r.free,
       -- 0 = sold only as the whole vehicle; the app shows "Full vehicle".
       r.seat,
       r.whole, true, 'Active',
       'Demo departure for showing how UDrive tours work. It cannot be booked.',
       'Demo listing — no booking, no charge.',
       ARRAY['Driver','Fuel'],
       now(), now()
FROM rows r
CROSS JOIN today t
-- "Today" departures that would already have left by the time the button is
-- pressed are moved to a little later this evening, so they still show.
CROSS JOIN LATERAL (
    SELECT CASE WHEN r.day_offset = 0
                THEN GREATEST(t.d + make_interval(hours => r.hour),
                              LEAST(now() + make_interval(mins => 20 + r.hour),
                                    t.d + make_interval(hours => 23, mins => 55)))
                ELSE t.d + make_interval(days => r.day_offset, hours => r.hour)
           END AS dep
) x
JOIN udrive.destinations d ON d.slug = r.slug
ON CONFLICT (id) DO UPDATE SET
    departure_at = EXCLUDED.departure_at,
    return_at = EXCLUDED.return_at,
    available_seats = EXCLUDED.available_seats,
    total_seats = EXCLUDED.total_seats,
    price_per_seat = EXCLUDED.price_per_seat,
    whole_vehicle_price = EXCLUDED.whole_vehicle_price,
    status = 'Active',
    updated_at = now();
