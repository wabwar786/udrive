# Phase 13.5 — Compact Vehicle Search & View All

## Apply
Copy the included files over the latest uDrive source, preserving paths.

## Changes
- Removed the large "Vehicles going your way" heading/subtitle block from Customer Home.
- Moved `View all` to the right of the destination search field.
- Kept the existing Home header unchanged.
- Added a dedicated `Find a vehicle` screen.
- Added destination-only search.
- Added tourist-point selection chips from live package destinations.
- Added All / 4 Wheel / 2 Wheel / 3 Wheel filters.
- Shows every active customer-bookable scheduled vehicle returned by the live API; Home still limits the preview list.
- Whole vehicle card remains clickable and opens live location plus booking details.

## Build
```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

No API or database migration is required.
