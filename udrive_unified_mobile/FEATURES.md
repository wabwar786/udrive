# Features

- Marketplace offer acceptance now creates `trip_operations` and `trip_assignments` records.
- Existing selected-offer bookings are backfilled by migration 013.
- Driver Home shows accepted/active rides in compact cards.
- Driver Start action changes the trip to `DriverEnRoute`.
- Driver in-app map shows vehicle, pickup, destination, distance, and approximate ETA.
- Driver GPS is sent every 10 seconds for active tracking states.
- Customer receives a `DriverOnTheWay` notification.
- Customer full-screen map refreshes every 10 seconds.
- Arrival, trip start, and completion notifications use customer-friendly text.
- Tracking stops when the trip screen/service is closed or the trip finishes/cancels through existing lifecycle controls.
