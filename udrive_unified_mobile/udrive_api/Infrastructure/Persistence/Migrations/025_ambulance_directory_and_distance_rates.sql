ALTER TABLE udrive.service_vehicle_rates
    ADD COLUMN IF NOT EXISTS per_km_rate numeric(12,2);

UPDATE udrive.service_vehicle_rates
SET per_km_rate = CASE lower(vehicle_category)
    WHEN 'bike' THEN 32
    WHEN 'car' THEN 65
    WHEN 'rickshaw' THEN 40
    WHEN 'coster' THEN 160
    ELSE 70
END
WHERE per_km_rate IS NULL;

ALTER TABLE udrive.service_vehicle_rates
    ALTER COLUMN per_km_rate SET NOT NULL;

CREATE TABLE IF NOT EXISTS udrive.ambulance_services (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name varchar(140) NOT NULL,
    city varchar(100) NOT NULL,
    phone_number varchar(32) NOT NULL,
    per_km_fare numeric(12,2) NOT NULL CHECK (per_km_fare > 0),
    currency varchar(8) NOT NULL DEFAULT 'PKR',
    image_url text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_ambulance_services_city_active
    ON udrive.ambulance_services(lower(city), is_active);
