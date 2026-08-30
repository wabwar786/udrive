# Phase 9 End-to-End Testing

Development OTP is `1234`.

## Test A — Customer ride and Driver offer

1. Login with a new Customer phone number.
2. Open **Book a Vehicle**.
3. Select a pickup at least 30 minutes in the future.
4. Choose per-seat or whole vehicle.
5. Submit the Customer offer.
6. With `ENABLE_DEMO_MARKETPLACE=true`, a verified demo offer should appear.
7. Select the Driver.
8. Open **My Trips** and confirm the booking reference.
9. Test rescheduling.
10. Test cancellation on another booking.

## Test B — Real Driver counteroffer

1. Login with approved Driver `03000000001` / `1234` in another browser/profile.
2. Switch to Driver mode.
3. Open **Ride Requests**.
4. Choose a verified vehicle.
5. Submit a counteroffer and ETA.
6. Customer refreshes offers and selects it.

## Test C — Driver package approval

1. Driver opens **My Packages**.
2. Create a live package.
3. Submit for approval.
4. Admin opens `/marketplace` and logs in with `03000000099` / `1234`.
5. Approve the package.
6. Driver refreshes and activates it if required.
7. Customer opens **Tour Packages**.

## Test D — Seat hold and package booking

1. Customer opens an active package.
2. Select seats or whole vehicle.
3. Add tour persons.
4. Confirm within ten minutes.
5. Verify remaining seat inventory changes.
6. Driver opens **Package Bookings** and passenger manifest.

## Test E — Waiting list

1. Open a package without enough bookable seats.
2. Choose **Join waiting list**.
3. Verify it appears under Customer package waiting list.
4. Driver verifies demand under **Package Bookings**.

## Test F — Package negotiation

1. Customer sends a package offer.
2. Driver accepts or counters it.
3. Customer confirms the accepted/countered amount.
4. Verify a confirmed booking is created exactly once.

## Concurrency test

Use two Customer browsers and try to reserve the final seats simultaneously. Only one transaction should confirm inventory; the other should receive an availability conflict.
