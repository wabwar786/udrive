# Shared-seat pricing and colorful Customer Home update

Overlay the included files on the latest uDrive project.

## Changes
- Per-seat booking displays one inclusive seat fare.
- Fuel, toll, and uDrive fees are not shown separately for shared-seat bookings.
- Selected seats and remaining seats are shown before submission.
- Whole-vehicle booking displays the vehicle fare and a short actual-toll notice.
- Submitted ride-request amount now matches the displayed total.
- Customer Home quick actions use colorful gradient buttons instead of white cards.

## Build
```bash
cd udrive_unified_mobile
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

## Tracking
Authenticated live tracking is already available from My Trips after a Driver is assigned. It reads `/api/v1/trips/{bookingId}/tracking` every 15 seconds. A Google Maps tile/provider key remains environment-specific and should be configured separately before replacing the current live route canvas.
