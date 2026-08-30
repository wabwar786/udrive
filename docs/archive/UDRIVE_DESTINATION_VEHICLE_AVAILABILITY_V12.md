# UDrive V12

- Rebuilt the four home service cards as a stable 2x2 responsive grid.
- Constrained all image assets inside clipped card bounds to prevent overlap/broken layout.
- Recent bookings remain limited to the latest two customer bookings from API data.
- Tour destination selection now lists every matching scheduled vehicle in the next 30 days.
- Each scheduled vehicle shows vehicle/driver, seats left, per-seat rate, whole-vehicle rate, pickup point, registration and pickup timing.
- Vehicles within 10 minutes of their scheduled pickup time or already past it are marked Closed and cannot be selected/booked.
- Timing and booking eligibility refresh every 10 seconds while the screen is open.
- Local/private flows continue to use database service rates.

Important: the current API model exposes scheduled departure time, not a per-stop live route-progress flag. Therefore the pickup-passed protection uses the scheduled pickup/departure cutoff. Exact road-position-based "vehicle has passed this pickup" enforcement will require the backend to expose driver live coordinates plus ordered route-stop coordinates/timestamps.
