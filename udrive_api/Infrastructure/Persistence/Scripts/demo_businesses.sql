-- Demo Near me businesses, added by Admin portal → Data management →
-- Restore / refresh and taken away by Remove demo data.
--
-- One demo owner (demo.business1@udrive.local) holds ten approved listings
-- around central Muzaffarabad, so Near me has something to show there. They
-- belong to a demo.% account, so the app labels them "Demo". The names are
-- invented; the phone numbers are in the same unused +92310990xxxx range as
-- the other demo accounts. Re-running refreshes the rows in place.

INSERT INTO udrive.users
    (id, phone_number, email, full_name, role, status, preferred_language, phone_verified, created_at, updated_at)
VALUES
    ('57000000-0000-0000-0000-000000000001', '+923109902001', 'demo.business1@udrive.local',
     'Demo Business Owner', 'Customer', 'Approved', 'en', true, now(), now())
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    status = 'Approved',
    phone_verified = true,
    updated_at = now();

INSERT INTO udrive.user_roles (user_id, role, created_at)
VALUES ('57000000-0000-0000-0000-000000000001', 'Customer', now())
ON CONFLICT (user_id, role) DO NOTHING;

INSERT INTO udrive.businesses
    (id, owner_user_id, name, category, address, phone, description,
     latitude, longitude, open_24_hours, opens_at, closes_at,
     approval_status, rejection_reason, is_active, reviewed_at, created_at, updated_at)
VALUES
    ('58000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000001',
     'Neelum Karahi House', 'Restaurant', 'Main Bazar, Chella Bandi, Muzaffarabad', '+923109902011',
     'Demo listing — karahi, BBQ and family seating.',
     34.3726, 73.4722, false, '12:00', '23:00', 'Approved', NULL, true, now(), now(), now()),
    ('58000000-0000-0000-0000-000000000002', '57000000-0000-0000-0000-000000000001',
     'Al-Shifa Pharmacy', 'MedicalStore', 'Chella Bandi Chowk, Muzaffarabad', '+923109902012',
     'Demo listing — medicines and first-aid supplies.',
     34.3712, 73.4698, true, NULL, NULL, 'Approved', NULL, true, now(), now(), now()),
    ('58000000-0000-0000-0000-000000000003', '57000000-0000-0000-0000-000000000001',
     'Kashmir Mart', 'Grocery', 'Neelum Road, Muzaffarabad', '+923109902013',
     'Demo listing — groceries, snacks and travel essentials.',
     34.3668, 73.4745, false, '08:00', '22:00', 'Approved', NULL, true, now(), now(), now()),
    ('58000000-0000-0000-0000-000000000004', '57000000-0000-0000-0000-000000000001',
     'City Care Hospital', 'Hospital', 'Upper Chattar, Muzaffarabad', '+923109902014',
     'Demo listing — emergency open 24 hours.',
     34.3790, 73.4770, true, NULL, NULL, 'Approved', NULL, true, now(), now(), now()),
    ('58000000-0000-0000-0000-000000000005', '57000000-0000-0000-0000-000000000001',
     'Chella Filling Station', 'Fuel', 'Chella Bandi Bypass, Muzaffarabad', '+923109902015',
     'Demo listing — petrol and diesel.',
     34.3652, 73.4676, false, '06:00', '23:30', 'Approved', NULL, true, now(), now(), now()),
    ('58000000-0000-0000-0000-000000000006', '57000000-0000-0000-0000-000000000001',
     'Main Bazar ATM', 'Bank', 'Main Bazar, Muzaffarabad', '+923109902016',
     'Demo listing — cash machine.',
     34.3705, 73.4735, true, NULL, NULL, 'Approved', NULL, true, now(), now(), now()),
    ('58000000-0000-0000-0000-000000000007', '57000000-0000-0000-0000-000000000001',
     'Jamia Masjid Chella', 'Mosque', 'Chella Bandi, Muzaffarabad', '+923109902017',
     'Demo listing — five daily prayers and Jumma.',
     34.3735, 73.4690, true, NULL, NULL, 'Approved', NULL, true, now(), now(), now()),
    ('58000000-0000-0000-0000-000000000008', '57000000-0000-0000-0000-000000000001',
     'Domel Tea & Tikka', 'Restaurant', 'Near Domel, Muzaffarabad', '+923109902018',
     'Demo listing — chai, tikka and paratha by the river.',
     34.3630, 73.4790, false, '17:00', '02:00', 'Approved', NULL, true, now(), now(), now()),
    ('58000000-0000-0000-0000-000000000009', '57000000-0000-0000-0000-000000000001',
     'Green Leaf Medical Store', 'MedicalStore', 'Secretariat Road, Muzaffarabad', '+923109902019',
     'Demo listing — medicines and baby care.',
     34.3770, 73.4650, false, '09:00', '22:00', 'Approved', NULL, true, now(), now(), now()),
    ('58000000-0000-0000-0000-000000000010', '57000000-0000-0000-0000-000000000001',
     'Plate General Store', 'Grocery', 'Plate, Muzaffarabad', '+923109902020',
     'Demo listing — daily groceries.',
     34.3820, 73.4710, false, '07:30', '21:30', 'Approved', NULL, true, now(), now(), now())
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    category = EXCLUDED.category,
    address = EXCLUDED.address,
    phone = EXCLUDED.phone,
    description = EXCLUDED.description,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    open_24_hours = EXCLUDED.open_24_hours,
    opens_at = EXCLUDED.opens_at,
    closes_at = EXCLUDED.closes_at,
    approval_status = 'Approved',
    rejection_reason = NULL,
    is_active = true,
    updated_at = now();
