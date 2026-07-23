# uDrive Premium Mobile

A complete Flutter frontend for Azad Kashmir tourism with **Customer and Driver modes in one app**.

## Included

- Premium green uDrive visual identity and original route-shaped app icon
- Native splash screen plus animated Flutter splash
- Dummy phone login and OTP (`1234`)
- English and Urdu with RTL layout
- Premium left-side drawer in both modes
- Customer/Driver mode switching
- Ride request, suggested fare, customer offer and simulated driver counteroffers
- Local, intercity, full-day, 4×4, shared and airport services
- Destination discovery and driver-created tour packages
- Trips, wallet, notifications, saved places, safety centre and support chat
- Driver online/offline dashboard
- Ride accept/counteroffer flow
- Driver earnings, wallet and payout flow
- Driver package creation and approval state
- Four-step vehicle registration with document/photo status
- Android, iOS and web platform folders
- Railway web Dockerfile
- GitHub workflow that builds an APK and AAB

## Demo access

- Any valid-looking Pakistani mobile number
- OTP: `1234`
- Or tap **Use demo account**

## Run locally

Run the Flutter scaffold command once after extracting or cloning. It safely completes generated platform files such as the Gradle wrapper:

```bash
flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive
flutter pub get
flutter run
```

## Build an APK locally

```bash
flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive
flutter pub get
flutter build apk --release
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Build a Play Store AAB

```bash
flutter build appbundle --release
```

Output:

```text
build/app/outputs/bundle/release/app-release.aab
```

The included Android release build uses the debug signing key for testing. Before Google Play publishing, configure your private upload keystore.

## Build through GitHub

1. Keep this folder at `udrive_unified_mobile/` inside the existing UDrive repository.
2. Open **Actions**.
3. Open **Build uDrive APK and AAB**.
4. Press **Run workflow**.
5. Open the successful run and download:
   - `udrive-premium-apk`
   - `udrive-play-store-aab`

The workflow completes any Flutter-generated platform files before compiling, runs analysis/tests, and uploads both build artifacts.

## Railway web deployment

Deploy this folder as a Railway service using the included `Dockerfile`.

- No custom build command
- No custom start command
- No manual `PORT` variable

For the existing monorepo, set the Railway service root directory to `/udrive_unified_mobile`.

## Dummy-data architecture

All app workflows currently use local dummy models and controller state. Replace the files under `lib/data/` and the methods in `lib/core/state/app_controller.dart` with API repositories later without redesigning the screens.
