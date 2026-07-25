# Customer ride request + Driver marketplace fix

Overlay this package on the latest uDrive source tree and replace the included files.

## Behaviour

1. Customer completes Advance Booking and taps **Find verified Drivers**.
2. The mobile client refreshes/validates the JWT before the write request.
3. `POST /api/v1/bookings/ride-requests` saves the request in `udrive.ride_requests`.
4. The customer is moved to the Driver offers screen.
5. Approved Drivers see the request through `GET /api/v1/driver/marketplace/ride-requests`.
6. The Driver requests screen refreshes automatically every 20 seconds and also supports pull-to-refresh.

## Build

```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

No API or database migration is required. The required backend persistence and Driver marketplace endpoints already exist.
