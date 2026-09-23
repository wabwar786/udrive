CREATE TABLE IF NOT EXISTS udrive.service_vehicle_rates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    service_type varchar(40) NOT NULL,
    vehicle_category varchar(48) NOT NULL,
    per_seat_rate numeric(12,2) NOT NULL CHECK (per_seat_rate > 0),
    whole_vehicle_rate numeric(12,2) NOT NULL CHECK (whole_vehicle_rate > 0),
    currency varchar(8) NOT NULL DEFAULT 'PKR',
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(service_type, vehicle_category)
);

INSERT INTO udrive.service_vehicle_rates(service_type,vehicle_category,per_seat_rate,whole_vehicle_rate)
VALUES
 ('City','Bike',250,250),
 ('City','Car',450,1600),
 ('City','Rickshaw',300,850),
 ('City','Coster',350,7500),
 ('PrivateVehicle','Bike',300,300),
 ('PrivateVehicle','Car',550,2000),
 ('PrivateVehicle','Rickshaw',350,1000),
 ('PrivateVehicle','Coster',450,9000)
ON CONFLICT(service_type,vehicle_category) DO UPDATE SET
 per_seat_rate=EXCLUDED.per_seat_rate,
 whole_vehicle_rate=EXCLUDED.whole_vehicle_rate,
 currency='PKR',
 is_active=true,
 updated_at=now();

CREATE TABLE IF NOT EXISTS udrive.driver_presence_locations (
    driver_profile_id uuid PRIMARY KEY REFERENCES udrive.driver_profiles(id) ON DELETE CASCADE,
    location geography(Point,4326) NOT NULL,
    accuracy_meters double precision,
    device_timestamp timestamptz NOT NULL,
    server_timestamp timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_driver_presence_locations_geo ON udrive.driver_presence_locations USING GIST(location);
CREATE INDEX IF NOT EXISTS ix_driver_presence_locations_freshness ON udrive.driver_presence_locations(server_timestamp DESC);
