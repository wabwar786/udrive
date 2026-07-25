# uDrive Phase 13.5 — Booking-First Customer Home

Apply this update over the latest Phase 13.5 mobile source.

## Files

Copy and overwrite:

- `udrive_unified_mobile/lib/screens/customer/customer_home_screen.dart`
- `udrive_unified_mobile/lib/screens/customer/tourism_booking_screen.dart`
- `udrive_unified_mobile/lib/screens/customer/live_packages_screen.dart`

No API or database migration is required.

## Build

```bash
cd udrive_unified_mobile
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

Deploy the Flutter web service and clear the service-worker/site cache once after deployment.

## Verification

1. Home shows the booking hero first.
2. `Vehicles going your way` appears immediately below it.
3. Active/Upcoming/Offers and Quick Actions appear after vehicles.
4. Home vehicle search filters destination only.
5. Tapping the hero opens the premium route-search screen.
6. Entering destination and departure date filters live package vehicles.
7. Tapping a matching vehicle opens live location and booking detail.
8. Itinerary appears as a numbered formatted timeline.
