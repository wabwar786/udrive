INSERT INTO udrive.destinations (
    id, slug, name_en, name_ur, summary_en, summary_ur, location, district,
    best_season, recommended_vehicle, network_status, family_suitability_score,
    route_safety_score, cover_image_url, is_active, created_at, updated_at)
VALUES
('10000000-0000-0000-0000-000000000001', 'muzaffarabad', 'Muzaffarabad', 'مظفرآباد',
 'The capital of Azad Kashmir, surrounded by rivers, viewpoints and mountain routes.',
 'آزاد کشمیر کا دارالحکومت، دریاؤں، خوبصورت مقامات اور پہاڑی راستوں سے گھرا ہوا۔',
 ST_SetSRID(ST_MakePoint(73.4711, 34.3700), 4326)::geography, 'Muzaffarabad',
 'March to November', 'Sedan / SUV', 'Good', 92, 88, null, true, now(), now()),
('10000000-0000-0000-0000-000000000002', 'neelum-valley', 'Neelum Valley', 'وادی نیلم',
 'A major Kashmir tourism corridor with riverside towns, mountain scenery and family stays.',
 'کشمیر کا مشہور سیاحتی علاقہ، دریائی قصبوں، پہاڑی مناظر اور خاندانی قیام کے لیے موزوں۔',
 ST_SetSRID(ST_MakePoint(73.8943, 34.5843), 4326)::geography, 'Neelum',
 'April to October', 'SUV / 4x4', 'Limited in upper areas', 90, 78, null, true, now(), now()),
('10000000-0000-0000-0000-000000000003', 'sharda', 'Sharda', 'شاردا',
 'Historic riverside destination and a gateway to upper Neelum Valley.',
 'دریا کنارے تاریخی مقام اور بالائی وادی نیلم کا اہم دروازہ۔',
 ST_SetSRID(ST_MakePoint(74.1863, 34.7939), 4326)::geography, 'Neelum',
 'May to October', 'SUV / 4x4', 'Limited', 86, 72, null, true, now(), now()),
('10000000-0000-0000-0000-000000000004', 'rawalakot', 'Rawalakot', 'راولاکوٹ',
 'A family-friendly hill city close to Banjosa Lake and Toli Pir.',
 'خاندانی سیاحت کے لیے موزوں پہاڑی شہر، بنجوسہ جھیل اور تولی پیر کے قریب۔',
 ST_SetSRID(ST_MakePoint(73.7604, 33.8578), 4326)::geography, 'Poonch',
 'March to November', 'Sedan / SUV', 'Good', 94, 87, null, true, now(), now()),
('10000000-0000-0000-0000-000000000005', 'banjosa-lake', 'Banjosa Lake', 'بنجوسہ جھیل',
 'A pine-surrounded artificial lake popular for short family tours.',
 'چیڑ کے جنگلات سے گھری خوبصورت مصنوعی جھیل، مختصر خاندانی دوروں کے لیے مشہور۔',
 ST_SetSRID(ST_MakePoint(73.8168, 33.8162), 4326)::geography, 'Poonch',
 'March to November', 'Sedan / SUV', 'Good', 96, 90, null, true, now(), now()),
('10000000-0000-0000-0000-000000000006', 'pir-chinasi', 'Pir Chinasi', 'پیر چناسی',
 'High-altitude viewpoint above Muzaffarabad with changing mountain weather.',
 'مظفرآباد کے اوپر بلند پہاڑی مقام، جہاں موسم تیزی سے تبدیل ہو سکتا ہے۔',
 ST_SetSRID(ST_MakePoint(73.5363, 34.3168), 4326)::geography, 'Muzaffarabad',
 'April to October', 'SUV recommended', 'Variable', 82, 70, null, true, now(), now())
ON CONFLICT (slug) DO NOTHING;

INSERT INTO udrive.routes (
    id, name, origin_destination_id, destination_id, origin_location, destination_location,
    distance_km, estimated_minutes, recommended_vehicle, four_by_four_required,
    daylight_only, safety_score, is_active, created_at, updated_at)
VALUES
('20000000-0000-0000-0000-000000000001', 'Muzaffarabad to Neelum Valley',
 '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002',
 ST_SetSRID(ST_MakePoint(73.4711,34.3700),4326)::geography,
 ST_SetSRID(ST_MakePoint(73.8943,34.5843),4326)::geography,
 85.00, 180, 'SUV', false, true, 78, true, now(), now()),
('20000000-0000-0000-0000-000000000002', 'Neelum Valley to Sharda',
 '10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003',
 ST_SetSRID(ST_MakePoint(73.8943,34.5843),4326)::geography,
 ST_SetSRID(ST_MakePoint(74.1863,34.7939),4326)::geography,
 70.00, 210, '4x4 / SUV', true, true, 70, true, now(), now()),
('20000000-0000-0000-0000-000000000003', 'Rawalakot to Banjosa Lake',
 '10000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000005',
 ST_SetSRID(ST_MakePoint(73.7604,33.8578),4326)::geography,
 ST_SetSRID(ST_MakePoint(73.8168,33.8162),4326)::geography,
 20.00, 45, 'Sedan / SUV', false, false, 90, true, now(), now())
ON CONFLICT (id) DO NOTHING;


INSERT INTO udrive.users (
    id, phone_number, email, full_name, role, status, preferred_language,
    phone_verified, created_at, updated_at)
VALUES
('30000000-0000-0000-0000-000000000001', '+923000000001', 'driver.demo@udrive.local',
 'Adeel Khan', 'Driver', 'Approved', 'en', true, now(), now())
ON CONFLICT (phone_number) DO NOTHING;

INSERT INTO udrive.driver_profiles (
    id, user_id, cnic_number_masked, driving_licence_number_masked,
    verification_status, average_rating, completed_trips, safety_score,
    languages, service_areas, is_online, created_at, updated_at)
VALUES
('31000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001',
 '*****-*******-*', 'AJK-****-01', 'Approved', 4.90, 184, 94,
 ARRAY['Urdu','English','Pahari'], ARRAY['Muzaffarabad','Neelum Valley'], true, now(), now())
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO udrive.vehicles (
    id, driver_profile_id, category, make, model, year, registration_number,
    colour, passenger_capacity, luggage_capacity, has_air_conditioning,
    has_heating, is_four_by_four, has_first_aid_kit, has_fire_extinguisher,
    has_spare_tyre, has_snow_chains, has_child_seat, mountain_readiness_score,
    status, created_at, updated_at)
VALUES
('32000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001',
 'SUV', 'Toyota', 'Fortuner', 2023, 'AJK-DEMO-01', 'White', 7, 5, true,
 true, true, true, true, true, true, true, 96, 'Verified', now(), now())
ON CONFLICT (registration_number) DO NOTHING;

INSERT INTO udrive.tour_packages (
    id, driver_profile_id, vehicle_id, destination_id, title, starting_city,
    pickup_point, departure_at, return_at, total_seats, available_seats,
    price_per_seat, whole_vehicle_price, family_only, women_only,
    customer_offers_allowed, status, inclusions, exclusions, itinerary_json,
    cover_image_url, created_at, updated_at)
VALUES
('33000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001',
 '32000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002',
 '3-Day Neelum Valley Family Tour', 'Muzaffarabad', 'Srinagar Highway Pickup Point',
 now() + interval '14 days', now() + interval '17 days', 7, 5, 12500, 78000,
 true, false, true, 'Active', ARRAY['Fuel','Toll','Driver','First aid kit'],
 ARRAY['Hotel','Meals','Entry tickets'],
 '[{"day":1,"route":"Muzaffarabad to Keran"},{"day":2,"route":"Keran to Sharda"},{"day":3,"route":"Return to Muzaffarabad"}]'::jsonb,
 null, now(), now())
ON CONFLICT (id) DO NOTHING;
