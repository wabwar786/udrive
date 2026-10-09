-- One vehicle class for matching ride requests to drivers.
--
-- A customer asks for one of five kinds: Car, Bike, Rickshaw, Hiace, Coster.
-- A driver registers a vehicle under any of a dozen names (Motorcycle,
-- Scooter, Sedan, SUV, 7-Seater, Auto Rickshaw, Coaster...). Nothing tied the
-- two together, so the driver feed ignored the kind entirely: a car request
-- reached bike and coster drivers, and the map showed every vehicle whatever
-- the customer chose.
--
-- udrive.vehicle_class() turns either side into the same five names. The app
-- has the same rule in lib/core/vehicles/vehicle_class.dart; keep them equal.
--
-- Safe to run more than once.

CREATE OR REPLACE FUNCTION udrive.vehicle_class(category text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN c ~ '(coaster|coster|bus)' THEN 'Coster'
        WHEN c ~ '(hiace|van)' THEN 'Hiace'
        WHEN c ~ '(bike|motor|scoot)' THEN 'Bike'
        WHEN c ~ '(rickshaw|auto|tuk|qingqi|chingchi)' THEN 'Rickshaw'
        ELSE 'Car'
    END
    FROM (SELECT lower(coalesce(category, '')) AS c) x;
$$;

COMMENT ON FUNCTION udrive.vehicle_class(text) IS
    'Car / Bike / Rickshaw / Hiace / Coster for a vehicle category or a ride request category. Same rule as the app (vehicle_class.dart).';
