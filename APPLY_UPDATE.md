# uDrive Phase 13.5 — Home Vehicle Type Filters & Fast Loading

Overlay the `udrive_unified_mobile` folder on the latest source tree.

## Updated files

- `lib/screens/customer/customer_home_screen.dart`
- `lib/screens/main_shell.dart`
- `lib/core/state/app_controller.dart`

## Changes

- Added compact 4 Wheel, 2 Wheel and 3 Wheel filter controls with icons.
- Destination search and vehicle-type filters work together.
- Home AppBar shows Pakistan-time greeting and authenticated user's first name.
- Notification and profile actions are shown on the right.
- Removed the fake notification count.
- Added a dedicated public-package request so Home vehicles do not wait for slower booking/offers/tour-interest requests.
- Existing vehicle results remain in memory while background dashboard data refreshes.

## Build

```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

Redeploy Flutter web and clear the service worker/site data once after deployment.
