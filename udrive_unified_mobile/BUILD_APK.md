# Build and Download the Android APK

## GitHub Actions

The monorepo contains:

```text
.github/workflows/build-mobile.yml
```

After pushing to `main`:

1. Open the GitHub repository.
2. Select **Actions**.
3. Open **Build uDrive APK and AAB**.
4. Select **Run workflow**.
5. Open the completed green run.
6. Download `udrive-tourism-apk`.
7. Extract the downloaded artifact to obtain `app-release.apk`.

The same run also provides `udrive-play-store-aab`.

## Local Windows build

Open Terminal in `udrive_unified_mobile` and run:

```bash
flutter doctor
flutter pub get
flutter build apk --release
```

APK output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

A private upload keystore is required before publishing to Google Play. The current configuration is suitable for testing builds.
