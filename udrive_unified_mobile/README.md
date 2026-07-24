# uDrive Kashmir Tourism Mobile 5.0

Unified Flutter application with Customer and Driver modes, premium tourism booking, advanced Driver package tools, safety workflows and a maps-ready live-trip experience.

## Demo login

- Phone: any valid-looking Pakistani mobile number
- OTP: `1234`
- Or tap **Use demo account**

## Customer highlights

- Advance one-way/return booking
- Per-seat and whole-vehicle booking
- Join a Tour and smart matching
- Family Tour Planner
- Kashmir destination and package discovery
- Driver offers and transparent pricing
- Live trip simulation and location sharing
- Trusted contacts and Tour Guardian
- Safety check-ins, SOS and Offline Travel Card
- Customer/Driver mode switching

## Driver highlights

- Ride requests and counteroffers
- Advanced tourism-package builder
- Per-seat/whole-vehicle pricing
- Package approval and booking controls
- Vehicle registration with tourism safety equipment
- Route suitability and mountain-readiness scoring
- Road-condition reports
- Live tracking and safety centre
- Earnings and payout simulation

## Languages

- English
- Urdu with RTL layout

## Run locally

```bash
flutter pub get
flutter run
```

If native platform wrappers are missing, run once:

```bash
flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive
```

## Build test APK

Linux/macOS:

```bash
./build_apk.sh
```

Windows:

```text
build_apk_windows.bat
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## GitHub Actions

The monorepo workflow is:

```text
.github/workflows/build-mobile.yml
```

It completes missing native scaffolding, validates files, analyzes source, runs tests, builds the Railway web release, APK and AAB, and uploads both Android artifacts.

## Railway

Set service root directory to:

```text
/udrive_unified_mobile
```

Do not add a custom build/start command or a manual `PORT` variable.

## Google Maps

The current map is a complete dummy simulation. See the repository-level `GOOGLE_MAPS_INTEGRATION.md` for the live provider plan.
