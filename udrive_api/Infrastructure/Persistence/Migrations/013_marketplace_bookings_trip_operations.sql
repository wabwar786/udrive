-- Phase 13.5: connect marketplace offer acceptance to live trip operations.
-- Additive and idempotent.

INSERT INTO udrive.trip_operations
    (id, booking_id, operational_status, trip_status, pickup_at, return_at,
     driver_accepted_at, last_activity_at, version, created_at, updated_at)
SELECT
    gen_random_uuid(), b.id, 'DriverAccepted', 'DriverAccepted', b.pickup_at, b.return_at,
    COALESCE(b.updated_at, now()), COALESCE(b.updated_at, now()), 0, now(), now()
FROM udrive.bookings b
WHERE b.selected_offer_id IS NOT NULL
  AND b.driver_profile_id IS NOT NULL
  AND b.vehicle_id IS NOT NULL
ON CONFLICT (booking_id) DO NOTHING;

INSERT INTO udrive.trip_assignments
    (id, booking_id, driver_profile_id, vehicle_id, assignment_type, status,
     assigned_by_user_id, assignment_notes, accepted_at, version, created_at, updated_at)
SELECT
    gen_random_uuid(), b.id, b.driver_profile_id, b.vehicle_id, 'Marketplace', 'Active',
    b.customer_user_id, 'Customer accepted the Driver fare offer.', COALESCE(b.updated_at, now()),
    0, now(), now()
FROM udrive.bookings b
WHERE b.selected_offer_id IS NOT NULL
  AND b.driver_profile_id IS NOT NULL
  AND b.vehicle_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM udrive.trip_assignments a
      WHERE a.booking_id=b.id AND a.status='Active'
  );

UPDATE udrive.trip_operations o
SET operational_status='DriverAccepted',
    trip_status='DriverAccepted',
    driver_accepted_at=COALESCE(o.driver_accepted_at, now()),
    last_activity_at=now(),
    updated_at=now(),
    version=o.version+1
FROM udrive.bookings b
WHERE b.id=o.booking_id
  AND b.selected_offer_id IS NOT NULL
  AND o.trip_status IN ('Confirmed','DriverAssigned');

UPDATE udrive.bookings
SET status='DriverAccepted', updated_at=now(), version=version+1
WHERE selected_offer_id IS NOT NULL
  AND driver_profile_id IS NOT NULL
  AND vehicle_id IS NOT NULL
  AND status IN ('Confirmed','DriverAssigned');
