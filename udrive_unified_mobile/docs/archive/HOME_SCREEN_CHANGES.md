# Customer Home Screen — Completed changes

- Home app-bar title replaced with time-aware `Good Morning/Good Afternoon/Good Evening, FirstName` using Pakistan time.
- Notification icon retained; fake notification badge removed.
- Profile initials button added beside notifications and opens the live Customer profile.
- Duplicate account greeting card removed, moving the booking hero upward.
- Live tourism package section replaced by `Vehicles going your way`.
- Live scheduled vehicles are sourced from `/api/v1/packages`.
- City, destination, pickup point, vehicle and registration search added.
- Results filter while typing and display a maximum of 10 vehicles.
- Vehicle cards show route, date/time, per-seat rate, total/free seats, vehicle and registration.
- Full vehicles cannot be booked.
- Vehicle card opens the existing real seat/whole-vehicle booking detail.
- Booking detail can request the scheduled vehicle's fresh GPS location and open Google Maps.
- The API only returns live coordinates when the Driver has a GPS update from the last 15 minutes; otherwise the destination point is used and the UI clearly states that live GPS is unavailable.
- Package loading is isolated so another marketplace endpoint failure no longer prevents vehicles from appearing.
