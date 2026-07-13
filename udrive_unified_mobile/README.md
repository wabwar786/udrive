# UDrive Unified Mobile App

A single Flutter mobile application for UDrive customers and drivers.

## Main behavior

- The app opens in **Customer mode** by default.
- The customer can open **Profile → Switch to Driver mode**.
- The dummy account is already marked as an approved driver.
- Driver mode has its own dashboard and bottom navigation.
- The driver can return through **Driver Profile → Switch to Customer mode**.
- English and Urdu are supported in both modes, including RTL layout.

## Customer features included

- Tourism-focused home screen
- Local, intercity, full-day, shared and 4×4 ride entry points
- Ride request form with validation
- Suggested price and customer fare offer
- Simulated driver offers and driver selection
- Tour-package discovery
- Package detail and package price offer
- Trip history
- Wallet, safety, saved places and support UI
- Customer-to-driver mode switch

## Driver features included

- Online/offline control
- Nearby ride-request dashboard
- Accept customer offer
- Submit driver counteroffer
- Driver-created tourism packages
- Save package as draft
- Submit package for admin approval
- Package status and bookings
- Earnings, commission and payout UI
- Documents, vehicle, service areas and availability
- Driver-to-customer mode switch

## Run locally

Install Flutter and run:

```bash
./bootstrap_mobile.sh
flutter run
```

On Windows PowerShell:

```powershell
flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive
flutter pub get
flutter run
```

## Android builds

Customer-first unified build:

```bash
flutter build appbundle --release --dart-define=DEFAULT_MODE=customer
```

Driver-first build from the same codebase:

```bash
flutter build appbundle --release --dart-define=DEFAULT_MODE=driver
```

The app still allows switching between modes after launch.

For direct APK testing:

```bash
flutter build apk --release --dart-define=DEFAULT_MODE=customer
```

## Railway web preview

Create a Railway service from this folder and use the included `Dockerfile`.
No environment variables are required. Do not manually define `PORT`.

## Backend readiness

Dummy data is separated into `lib/data`. Replace it incrementally with API repositories for authentication, profiles, ride requests, driver offers, packages, live tracking, chat and payments.
