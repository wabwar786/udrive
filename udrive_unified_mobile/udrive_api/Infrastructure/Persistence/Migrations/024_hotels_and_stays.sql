CREATE SCHEMA IF NOT EXISTS udrive;

CREATE TABLE IF NOT EXISTS udrive.hotel_owner_profiles (
    user_id uuid PRIMARY KEY REFERENCES udrive.users(id) ON DELETE CASCADE,
    business_name text,
    phone text,
    status text NOT NULL DEFAULT 'Active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS udrive.hotels (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id uuid NOT NULL REFERENCES udrive.users(id),
    name text NOT NULL,
    description text NOT NULL DEFAULT '',
    address text NOT NULL,
    city text NOT NULL,
    district text NOT NULL DEFAULT '',
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    contact_phone text NOT NULL DEFAULT '',
    rating numeric(3,2) NOT NULL DEFAULT 0,
    main_image_url text NOT NULL DEFAULT '',
    amenities jsonb NOT NULL DEFAULT '[]'::jsonb,
    transport_available boolean NOT NULL DEFAULT true,
    approval_status text NOT NULL DEFAULT 'Pending',
    rejection_reason text,
    is_active boolean NOT NULL DEFAULT true,
    approved_by uuid REFERENCES udrive.users(id),
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_hotels_public ON udrive.hotels (approval_status, is_active, city);
CREATE INDEX IF NOT EXISTS ix_hotels_owner ON udrive.hotels (owner_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_hotels_location ON udrive.hotels USING gist (geography(ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)));

CREATE TABLE IF NOT EXISTS udrive.hotel_rooms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hotel_id uuid NOT NULL REFERENCES udrive.hotels(id) ON DELETE CASCADE,
    room_type text NOT NULL,
    description text NOT NULL DEFAULT '',
    capacity integer NOT NULL CHECK (capacity BETWEEN 1 AND 20),
    total_rooms integer NOT NULL CHECK (total_rooms BETWEEN 1 AND 500),
    base_rate numeric(12,2) NOT NULL CHECK (base_rate >= 0),
    image_url text NOT NULL DEFAULT '',
    amenities jsonb NOT NULL DEFAULT '[]'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_hotel_rooms_hotel ON udrive.hotel_rooms (hotel_id, is_active);

CREATE TABLE IF NOT EXISTS udrive.hotel_room_inventory (
    room_id uuid NOT NULL REFERENCES udrive.hotel_rooms(id) ON DELETE CASCADE,
    inventory_date date NOT NULL,
    available_rooms integer NOT NULL CHECK (available_rooms >= 0),
    rate numeric(12,2) NOT NULL CHECK (rate >= 0),
    PRIMARY KEY (room_id, inventory_date)
);

CREATE TABLE IF NOT EXISTS udrive.hotel_bookings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_user_id uuid NOT NULL REFERENCES udrive.users(id),
    hotel_id uuid NOT NULL REFERENCES udrive.hotels(id),
    room_id uuid NOT NULL REFERENCES udrive.hotel_rooms(id),
    check_in date NOT NULL,
    check_out date NOT NULL,
    guests integer NOT NULL CHECK (guests > 0),
    rooms integer NOT NULL CHECK (rooms > 0),
    amount numeric(12,2) NOT NULL CHECK (amount >= 0),
    status text NOT NULL DEFAULT 'Confirmed',
    payment_status text NOT NULL DEFAULT 'Pending',
    include_transport boolean NOT NULL DEFAULT false,
    ride_request_id uuid,
    trip_plan_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (check_out > check_in)
);
CREATE INDEX IF NOT EXISTS ix_hotel_bookings_customer ON udrive.hotel_bookings (customer_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_hotel_bookings_hotel ON udrive.hotel_bookings (hotel_id, check_in, check_out);
