-- Let a customer accept another driver after one cancels.
--
-- The platform already does most of this. When a driver cancels,
-- TripOperationsService.ReopenRideRequestAsync puts the ride request back to
-- 'ReceivingOffers', releases the offers and rests the cancelling driver, so
-- other drivers bid again and the customer is sent back to the offers screen.
--
-- And then accepting one fails, every time.
--
-- BookingService.SelectDriverOfferAsync creates a NEW booking row for the
-- chosen offer, carrying the same ride_request_id. The index below was written
-- as "one booking per ride request", which was true while a request could only
-- ever be booked once:
--
--     CREATE UNIQUE INDEX ux_bookings_ride_request
--         ON udrive.bookings (ride_request_id) WHERE ride_request_id IS NOT NULL;
--
-- The cancelled booking still holds the request, so the insert hits that index:
--
--     ERROR: duplicate key value violates unique constraint "ux_bookings_ride_request"
--     DETAIL: Key (ride_request_id)=(cccc0000-...-0001) already exists.
--
-- There is no catch for it in SelectDriverOfferAsync, so it reaches the generic
-- unique-violation handler and the customer is told a CNIC or registration
-- number is already registered. Retrying never helps. The whole reopen feature
-- has therefore never worked in the one situation it exists for.
--
-- The fix is to say what the rule actually is: one *live* booking per ride
-- request. A cancelled booking, or one closed as a no-show, is history, and
-- history should not hold a request hostage. Every other status still blocks,
-- 'Completed' included: a finished ride must not be re-booked either.
--
-- Note the index is NOT dropped and recreated in one transaction without care:
-- dropping first and creating second inside this migration's transaction means
-- the uniqueness rule is never absent to another session, because the whole
-- migration commits atomically.

DROP INDEX IF EXISTS udrive.ux_bookings_ride_request;

CREATE UNIQUE INDEX IF NOT EXISTS ux_bookings_ride_request
    ON udrive.bookings (ride_request_id)
    WHERE ride_request_id IS NOT NULL
      AND status NOT IN ('Cancelled', 'NoShow');

-- A cancelled trip must release the driver and the vehicle.
--
-- Cancelling updates trip_operations and bookings and stops there, so the
-- trip_assignments row stays 'Active' for ever. SuitableDriversAsync's
-- availability check looks only at a2.status='Active' with no trip_status
-- filter, so after one cancelled ride the driver and vehicle read as busy for
-- that time window permanently — an admin trying to assign them is told
-- "Driver or vehicle has an overlapping active booking" about a ride that was
-- called off weeks ago.
--
-- Going forward the service ends the assignment itself. This closes the rows
-- that are already wrong, so no backfill script is needed.
UPDATE udrive.trip_assignments a
SET status = 'Ended',
    ended_at = COALESCE(o.cancelled_at, o.completed_at, now()),
    end_reason = CASE WHEN o.trip_status = 'TripCompleted'
                      THEN 'Trip completed' ELSE 'Trip cancelled' END,
    version = a.version + 1,
    updated_at = now()
FROM udrive.trip_operations o
WHERE o.booking_id = a.booking_id
  AND a.status = 'Active'
  AND o.trip_status IN ('Cancelled', 'NoShow', 'TripCompleted');
