# uDrive Phase 13.5 — Accepted Rides & Live Navigation

## Apply
Overlay the included `udrive_api` and `udrive_unified_mobile` folders on the latest source tree.

## Deployment order
1. Deploy API first.
2. Confirm migration `013_marketplace_bookings_trip_operations` is applied.
3. Verify `/health/live` and `/health/ready`.
4. Deploy Flutter web.
5. Log out/in once as Customer and Driver.

## Driver test
1. Customer accepts the Driver fare offer.
2. Login as Driver `03109000001`.
3. Driver Home shows the ride under **Accepted rides**.
4. Tap **Start**.
5. Status becomes `DriverEnRoute`, in-app OpenStreetMap opens, and GPS uploads every 10 seconds.
6. Tap **I have arrived** to notify the Customer.

## Customer test
1. Open My Trips after the Driver starts.
2. The full-screen live tracking map opens automatically while the screen is active.
3. Driver location refreshes every 10 seconds.

No Google Maps API key is required. OpenStreetMap tiles are used with attribution.
