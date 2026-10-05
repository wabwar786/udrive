-- Place names for typing "From" and "To" on a tour departure.
--
-- Departures are typed by hand. The app suggests names while the driver types
-- and offers a spelling fix ("Did you mean Rawalpindi?"), from one list:
-- AJK tehsils (territories), UDrive destinations, and these other places in
-- Pakistan. Admins can add more in Settings → Areas. Coordinates are
-- approximate city centres, used only to place a new departure end on a map.

CREATE TABLE IF NOT EXISTS udrive.place_names (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name varchar(120) NOT NULL,
    region varchar(80) NOT NULL DEFAULT '',
    latitude double precision,
    longitude double precision,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_place_names_name ON udrive.place_names (lower(name));

INSERT INTO udrive.place_names (name, region, latitude, longitude)
VALUES
    ('Islamabad', 'Islamabad', 33.6844, 73.0479),
    ('Rawalpindi', 'Punjab', 33.5651, 73.0169),
    ('Faizabad (Islamabad)', 'Islamabad', 33.6640, 73.0840),
    ('Faisalabad', 'Punjab', 31.4504, 73.1350),
    ('Lahore', 'Punjab', 31.5204, 74.3587),
    ('Gujranwala', 'Punjab', 32.1877, 74.1945),
    ('Sialkot', 'Punjab', 32.4945, 74.5229),
    ('Gujrat', 'Punjab', 32.5731, 74.0789),
    ('Kharian', 'Punjab', 32.8110, 73.8650),
    ('Lalamusa', 'Punjab', 32.7017, 73.9580),
    ('Jhelum', 'Punjab', 32.9405, 73.7276),
    ('Dina', 'Punjab', 33.0281, 73.6011),
    ('Chakwal', 'Punjab', 32.9328, 72.8630),
    ('Taxila', 'Punjab', 33.7463, 72.8397),
    ('Wah Cantt', 'Punjab', 33.7715, 72.7510),
    ('Attock', 'Punjab', 33.7660, 72.3609),
    ('Murree', 'Punjab', 33.9070, 73.3943),
    ('Kohala', 'Punjab', 34.0975, 73.4950),
    ('Sargodha', 'Punjab', 32.0836, 72.6711),
    ('Multan', 'Punjab', 30.1575, 71.5249),
    ('Bahawalpur', 'Punjab', 29.3956, 71.6836),
    ('Peshawar', 'Khyber Pakhtunkhwa', 34.0151, 71.5249),
    ('Mardan', 'Khyber Pakhtunkhwa', 34.1986, 72.0404),
    ('Haripur', 'Khyber Pakhtunkhwa', 33.9946, 72.9334),
    ('Abbottabad', 'Khyber Pakhtunkhwa', 34.1688, 73.2215),
    ('Mansehra', 'Khyber Pakhtunkhwa', 34.3302, 73.1968),
    ('Balakot', 'Khyber Pakhtunkhwa', 34.5474, 73.3501),
    ('Kaghan', 'Khyber Pakhtunkhwa', 34.7765, 73.5277),
    ('Naran', 'Khyber Pakhtunkhwa', 34.9089, 73.6501),
    ('Mingora (Swat)', 'Khyber Pakhtunkhwa', 34.7717, 72.3600),
    ('Gilgit', 'Gilgit-Baltistan', 35.9208, 74.3080),
    ('Skardu', 'Gilgit-Baltistan', 35.2971, 75.6333),
    ('Hunza (Karimabad)', 'Gilgit-Baltistan', 36.3167, 74.6500),
    ('Chilas', 'Gilgit-Baltistan', 35.4206, 74.0947),
    ('Karachi', 'Sindh', 24.8607, 67.0011),
    ('Hyderabad', 'Sindh', 25.3960, 68.3578),
    ('Sukkur', 'Sindh', 27.7052, 68.8574),
    ('Quetta', 'Balochistan', 30.1798, 66.9750)
ON CONFLICT DO NOTHING;
