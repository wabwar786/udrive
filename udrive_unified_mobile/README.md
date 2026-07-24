# uDrive Kashmir Tourism Mobile 4.0

Unified Flutter mobile application with Customer and Driver modes, dummy authentication and local dummy data. The project already includes Android, iOS and web platform files.

## Demo login

- Mobile number: any valid-looking Pakistani number
- OTP: `1234`
- Or select **Use demo account**

## Phase 1 and Phase 2 features

- Faster startup with no artificial splash delay
- Tourism-first premium home screen
- Simple six-action customer dashboard
- Advance date/time and return booking
- Per-seat and whole-vehicle booking
- Transparent estimated price breakdown
- Vehicle suitability recommendations
- Family-only and women/family preferences
- Join-a-Tour departures with privacy-safe passenger counts
- Register tour interest and receive dummy matching notifications
- Smart match percentage and route safety score
- Family Tour Planner with generated itinerary
- Dummy family driver search
- Expanded Kashmir destinations and packages
- Driver package creation with per-seat and whole-vehicle prices
- Pickup point and family-only package options
- Customer/Driver mode switching
- English and Urdu RTL
- Complete vehicle registration
- Railway web Docker deployment
- GitHub APK and AAB build workflow

## Run locally

```bash
flutter pub get
flutter run
```

Run in Chrome:

```bash
flutter run -d chrome
```

## Build Android APK

```bash
flutter pub get
flutter build apk --release --dart-define=DEFAULT_MODE=customer
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Build Play Store AAB

```bash
flutter build appbundle --release --dart-define=DEFAULT_MODE=customer
```

Output:

```text
build/app/outputs/bundle/release/app-release.aab
```

## GitHub monorepo

Keep this folder at:

```text
udrive_unified_mobile/
```

The root workflow is located at:

```text
.github/workflows/build-mobile.yml
```

## Railway

Set the Railway Mobile service root directory to:

```text
/udrive_unified_mobile
```

Do not add a custom build command, start command or manual `PORT` variable.

## Architecture

All current workflows use models in `lib/data/` and state in `lib/core/state/app_controller.dart`. These local repositories can later be replaced by authenticated APIs without redesigning the screens.
