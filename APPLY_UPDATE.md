# Phase 13.5 Advance Booking Input Fix

Replace the included Flutter file in the latest codebase.

## Fixed
- Departure date remains clickable/editable.
- Departure time remains clickable/editable.
- Only matching vehicle preview cards remain non-clickable.
- Pickup GPS loading is isolated from marketplace/API loading failures.
- Pickup is automatically filled with current coordinates when browser/device permission is granted.
- Destination suggestions appear from live package destinations and the app destination catalogue.
- Selecting a suggestion fills the destination field and filters vehicles by destination/date.

## Browser location requirements
- The deployed site must use HTTPS.
- Browser location permission must be allowed for the uDrive domain.
- Device location services must be enabled.

## Build
```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```
