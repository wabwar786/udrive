# Driver pickup-first navigation + Customer Home live trip card

Overlay the `udrive_unified_mobile` folder on the latest project.

## What changes

- Driver map targets pickup while status is `DriverAccepted`, `DriverEnRoute`, `DriverArrived`, or `Emergency`.
- After the Driver confirms `Customer boarded · Start trip`, status becomes `TripStarted` and the map targets the destination.
- Driver action sequence is now: Start/En Route -> I have arrived -> Customer boarded / Start trip -> Complete trip.
- Customer Home shows a compact live trip card directly below the booking hero while the trip is en route, arrived, started, or emergency.
- Tapping the Home live card opens full-screen live tracking.
- Customer and Driver maps refresh every 10 seconds.
- The Home live trip card disappears automatically after completion or cancellation.

## Deploy

```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

No API migration is required. Existing trip status notifications are reused.
