# Phase 18 — Complete Tourism Package Marketplace

## Implemented

- Normalized multi-day itinerary and tourist-stop content
- Package image gallery and cover-image ordering
- Tiered cancellation/refund rules
- Departure inventory and minimum-passenger settings
- Existing ten-minute seat holds and whole-vehicle locks preserved
- Customer package booking history with live tour status
- Driver tour operations: Scheduled → Boarding → Departed → InProgress → Completed/Cancelled
- Optimistic version protection for trip status updates
- Passenger check-in, boarded and no-show records
- Immutable tour status history
- Driver bookings and passenger manifest retained in a dedicated tab
- Admin marketplace dashboard with approval queue, status filters, inventory, bookings, seats and gross booking value
- Finance/payment integration preserved through existing booking totals, balances and Phase 16 payment APIs
- GPS/safety integration preserved through existing vehicle-location and Phase 17 Safety Hub APIs

## Migration

`019_phase18_tourism_marketplace.sql`

New tables:

- `tour_package_itinerary_days`
- `tour_package_images`
- `tour_departures`
- `tour_trip_operations`
- `tour_passenger_checkins`
- `tour_status_history`
- `tour_cancellation_rules`

## New APIs

- `GET /api/v1/tour-marketplace/packages/{packageId}/content`
- `PUT /api/v1/tour-marketplace/driver/packages/{packageId}/content`
- `GET /api/v1/tour-marketplace/customer/bookings`
- `GET /api/v1/tour-marketplace/driver/operations`
- `PUT /api/v1/tour-marketplace/driver/operations/{operationId}/status`
- `POST /api/v1/tour-marketplace/driver/operations/{operationId}/check-ins`
- `GET /api/v1/admin/tour-marketplace/packages`

## Deployment

1. Deploy API and confirm migration 019.
2. Deploy Admin portal and open Tourism Marketplace.
3. Deploy Flutter web.
4. Approve one package.
5. Confirm the Driver can open boarding, depart, start and complete the tour.
6. Confirm bookings/manifests and customer package history.
7. Re-test seat holds, payment balance, GPS tracking, SOS and Driver earnings.
