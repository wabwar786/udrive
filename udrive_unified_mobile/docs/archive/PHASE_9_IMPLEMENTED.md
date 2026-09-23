# Phase 9 Implemented

## Live advance rides

- Future pickup and optional return date
- Per-seat and whole-vehicle requests
- Adults, children and luggage
- Family-only and women-only preferences
- Vehicle category and Customer price offer
- PostGIS pickup and destination coordinates
- Automatic request expiry
- Request and offer status history

## Driver offer marketplace

- Approved Driver-only request queue
- Verified vehicle requirement
- Driver accept/counteroffer amount
- ETA, message, rating and safety score
- Customer compares live offers
- Transactional offer selection
- Remaining offers expire automatically
- One booking per ride request

## Live bookings

- Booking reference
- Advance and remaining balance
- Trip OTP generated and hashed
- Customer/Driver booking list
- Cancellation workflow
- Rescheduling workflow
- Complete status history

## Tourism packages

- Driver-created database packages
- Admin approval route
- Per-seat and whole-vehicle pricing
- Ten-minute inventory holds
- PostgreSQL serializable transactions and row locks
- Double-booking protection
- Customer package offers and Driver counteroffers
- Package pause/activate controls
- Confirmed package booking list for Driver

## Tour persons and privacy

- Customer can add passenger names before package confirmation
- Passenger details stored against the confirmed booking
- Phone numbers are masked
- Driver can open an authorized passenger manifest
- Passenger manifest is not publicly exposed

## Waiting list

- Customers can join a package waiting list
- Per-seat or whole-vehicle demand recorded
- Driver can view waiting-list demand
- Notification delivery is reserved for Phase 11

## Tour matching

- Customer registers destination/date/budget/persons
- Matching active Driver packages
- Match score, Driver rating and safety score

## Admin

- New `/marketplace` route
- Pending package queue
- Approve, request changes or reject
- Package route, pricing, vehicle and safety review
