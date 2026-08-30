# Phase 9 Security and Limitations

## Implemented security controls

- Customer and Driver identity comes from JWT claims, never request payload IDs.
- Only approved Drivers can receive ride requests or create packages.
- Only verified vehicles can submit live ride offers or packages.
- Ride offer selection runs inside a serializable database transaction.
- One confirmed booking is allowed per ride request.
- Package inventory is locked with PostgreSQL row locks.
- Seat holds automatically expire after ten minutes.
- Whole-vehicle booking is blocked when any seat is confirmed or actively held.
- Passenger manifests require Customer or assigned Driver ownership.
- Passenger phone numbers are masked.
- Every important marketplace status transition is stored in history.
- Admin package approval requires an Admin or Operations JWT role.

## Current limitations

- `ENABLE_DEMO_MARKETPLACE=true` creates a test Driver offer. Disable it for real production operation.
- Payments are balances/status records only; no live payment gateway is connected yet.
- Waiting-list push alerts will be added in Phase 11.
- Google Maps and real Driver proximity filtering will be added in Phase 10.
- Driver offers are refreshed by polling in this phase; WebSockets/SignalR will arrive in Phase 11.
- Trip OTP is returned when the booking is created and stored as a hash server-side.
- Customer cancellation fees and refund rules will be added with Phase 13 payments.
