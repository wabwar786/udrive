# uDrive Kashmir Tourism Mobile — Phase 8

Unified Flutter Customer and Driver application connected to the live uDrive API.

## Live Phase 8 features

- Real server-side OTP request/verification
- JWT access and rotating refresh-token sessions
- Secure token storage
- Persistent login
- One account for Customer and approved Driver modes
- Driver onboarding connected to PostgreSQL
- CNIC, licence, selfie and identity-document uploads
- Live vehicle registration and document uploads
- Driver/vehicle approval status from the API
- Driver mode unlocked only after Admin approval
- Existing tourism, family-tour, shared-seat, package and safety dummy flows preserved

## Test accounts

- New Customer: any valid Pakistani mobile number, OTP `1234`
- Approved Driver demo: `03000000001`, OTP `1234`

## Driver approval sequence

1. Save Driver profile.
2. Upload CNIC front, CNIC back, driving licence and selfie.
3. Register a vehicle.
4. Upload registration book, front photo, rear photo and interior photo.
5. Submit the vehicle.
6. Admin verifies the vehicle.
7. Submit the Driver application.
8. Admin approves the Driver.
9. Refresh account status in the app; Driver mode becomes available.

## Run locally

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://udrive-api-production.up.railway.app
```

## Build APK

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

## Railway

Root directory:

```text
/udrive_unified_mobile
```

The default API URL is `https://udrive-api-production.up.railway.app`.
