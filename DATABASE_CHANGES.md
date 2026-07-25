# Database Changes

Migration: `008_phase11_12_trip_operations_tracking.sql`

## Additive booking columns

- `payment_status`
- `special_instructions`
- `emergency_contact_name`
- `emergency_contact_phone`

## New tables

- `trip_operations`
- `trip_assignments`
- `driver_booking_offers`
- `trip_status_history`
- `trip_notes`
- `trip_incidents`
- `driver_latest_locations`
- `trip_location_history`
- `trip_tracking_tokens`

## Safety and concurrency

- One active assignment per booking.
- One pending offer per booking/driver.
- Unique client location event per driver.
- Version columns for optimistic concurrency.
- Overlap checks use trip time ranges.
- PostGIS GiST indexes support location access.
- Existing bookings are backfilled into `trip_operations` without changing original booking IDs.
