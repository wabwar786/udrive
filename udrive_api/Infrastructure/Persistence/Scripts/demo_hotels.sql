-- Idempotent demo hotels used by the Admin Data Management page.

INSERT INTO udrive.users
    (id, phone_number, email, full_name, role, status, preferred_language, phone_verified, created_at, updated_at)
VALUES
    ('51000000-0000-0000-0000-000000000001', '+923109900001', 'demo.hotelowner1@udrive.local', 'Adeel Kashmir Hotels', 'Customer', 'Approved', 'en', true, now(), now()),
    ('51000000-0000-0000-0000-000000000002', '+923109900002', 'demo.hotelowner2@udrive.local', 'Sana Mountain Stays', 'Customer', 'Approved', 'en', true, now(), now())
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    status = 'Approved',
    phone_verified = true,
    updated_at = now();

INSERT INTO udrive.user_roles(user_id, role, created_at)
VALUES
    ('51000000-0000-0000-0000-000000000001', 'Customer', now()),
    ('51000000-0000-0000-0000-000000000002', 'Customer', now()),
    ('51000000-0000-0000-0000-000000000001', 'HotelOwner', now()),
    ('51000000-0000-0000-0000-000000000002', 'HotelOwner', now())
ON CONFLICT (user_id, role) DO NOTHING;

INSERT INTO udrive.hotel_owner_profiles(user_id, business_name, phone, status, created_at, updated_at)
VALUES
    ('51000000-0000-0000-0000-000000000001', 'Kashmir Hospitality Group', '+923109900001', 'Active', now(), now()),
    ('51000000-0000-0000-0000-000000000002', 'Mountain Stays AJK', '+923109900002', 'Active', now(), now())
ON CONFLICT (user_id) DO UPDATE SET
    business_name = EXCLUDED.business_name,
    phone = EXCLUDED.phone,
    status = 'Active',
    updated_at = now();

INSERT INTO udrive.hotels
    (id, owner_user_id, name, description, address, city, district, latitude, longitude,
     contact_phone, rating, main_image_url, amenities, transport_available, approval_status,
     rejection_reason, is_active, approved_at, created_at, updated_at)
VALUES
    ('52000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001',
     'Neelum Riverside Lodge', 'A comfortable riverside stay for families visiting Keran and Upper Neelum.',
     'Main Neelum Road, Keran', 'Keran', 'Neelum', 34.6501, 73.9479, '+923109900011', 4.70,
     'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1400&q=80',
     '["Free WiFi","Family rooms","Parking","Restaurant","River view"]'::jsonb, true, 'Approved', null, true, now(), now(), now()),
    ('52000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000001',
     'Muzaffarabad Grand Stay', 'Central city hotel with easy access to transport, markets and tourism routes.',
     'Near Domel Bridge, Muzaffarabad', 'Muzaffarabad', 'Muzaffarabad', 34.3714, 73.4718, '+923109900012', 4.50,
     'https://images.unsplash.com/photo-1564501049412-61c2a3083791?auto=format&fit=crop&w=1400&q=80',
     '["Free WiFi","Breakfast","Heating","Parking","24-hour desk"]'::jsonb, true, 'Approved', null, true, now(), now(), now()),
    ('52000000-0000-0000-0000-000000000003', '51000000-0000-0000-0000-000000000002',
     'Rawalakot Pine View Hotel', 'Quiet hill stay near Rawalakot with family rooms and mountain views.',
     'Banjosa Road, Rawalakot', 'Rawalakot', 'Poonch', 33.8578, 73.7604, '+923109900013', 4.60,
     'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?auto=format&fit=crop&w=1400&q=80',
     '["Mountain view","Family rooms","Restaurant","Parking","Hot water"]'::jsonb, true, 'Approved', null, true, now(), now(), now()),
    ('52000000-0000-0000-0000-000000000004', '51000000-0000-0000-0000-000000000002',
     'Sharda Valley Guest House', 'Customer-submitted demo property waiting for admin review before publication.',
     'Sharda Main Bazaar, Neelum Valley', 'Sharda', 'Neelum', 34.7937, 74.1883, '+923109900014', 0,
     'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=1400&q=80',
     '["Family rooms","Parking","Valley view","Restaurant"]'::jsonb, true, 'Pending', null, true, null, now(), now())
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    address = EXCLUDED.address,
    city = EXCLUDED.city,
    district = EXCLUDED.district,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    contact_phone = EXCLUDED.contact_phone,
    rating = EXCLUDED.rating,
    main_image_url = EXCLUDED.main_image_url,
    amenities = EXCLUDED.amenities,
    transport_available = EXCLUDED.transport_available,
    approval_status = EXCLUDED.approval_status,
    rejection_reason = EXCLUDED.rejection_reason,
    is_active = true,
    approved_at = EXCLUDED.approved_at,
    updated_at = now();

INSERT INTO udrive.hotel_rooms
    (id, hotel_id, room_type, description, capacity, total_rooms, base_rate, image_url, amenities, is_active, created_at, updated_at)
VALUES
    ('53000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', 'Deluxe River View', 'King bed with river-facing balcony.', 2, 6, 14500, 'https://images.unsplash.com/photo-1611892440504-42a792e24d32?auto=format&fit=crop&w=1200&q=80', '["King bed","Balcony","Heating","Private bathroom"]'::jsonb, true, now(), now()),
    ('53000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000001', 'Family Suite', 'Two-room family suite for Kashmir trips.', 5, 3, 22500, 'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=1200&q=80', '["Two rooms","Family seating","Heating","River view"]'::jsonb, true, now(), now()),
    ('53000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000002', 'Executive Double', 'Modern double room in central Muzaffarabad.', 2, 10, 12000, 'https://images.unsplash.com/photo-1598928636135-d146006ff4be?auto=format&fit=crop&w=1200&q=80', '["Double bed","WiFi","Breakfast","Air conditioning"]'::jsonb, true, now(), now()),
    ('53000000-0000-0000-0000-000000000004', '52000000-0000-0000-0000-000000000003', 'Pine View Family Room', 'Family room with peaceful hillside view.', 4, 5, 13500, 'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=1200&q=80', '["Family beds","Heating","Mountain view","Hot water"]'::jsonb, true, now(), now()),
    ('53000000-0000-0000-0000-000000000005', '52000000-0000-0000-0000-000000000004', 'Standard Valley Room', 'Demo room attached to a pending hotel submission.', 2, 4, 8500, 'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=1200&q=80', '["Double bed","Hot water","Valley view"]'::jsonb, true, now(), now())
ON CONFLICT (id) DO UPDATE SET
    room_type = EXCLUDED.room_type,
    description = EXCLUDED.description,
    capacity = EXCLUDED.capacity,
    total_rooms = EXCLUDED.total_rooms,
    base_rate = EXCLUDED.base_rate,
    image_url = EXCLUDED.image_url,
    amenities = EXCLUDED.amenities,
    is_active = true,
    updated_at = now();
