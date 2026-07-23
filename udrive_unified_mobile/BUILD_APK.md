# Build and Download the Android APK

## GitHub Actions method

The workflow is stored at the repository root:

```text
.github/workflows/build-mobile.yml
```

After pushing to `main`:

1. Open the GitHub repository.
2. Select **Actions**.
3. Select **Build uDrive APK and AAB**.
4. Select **Run workflow**.
5. Open the completed green run.
6. Download `udrive-premium-apk` under **Artifacts**.
7. Extract the downloaded artifact ZIP to get `app-release.apk`.

## Windows local method

Open this folder:

```text
udrive_unified_mobile
```

Double-click:

```text
build_apk_windows.bat
```

Or run:

```bat
build_apk_windows.bat
```

## Command-line method

```bash
cd udrive_unified_mobile
flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --dart-define=DEFAULT_MODE=customer
```

The APK appears at:

```text
udrive_unified_mobile/build/app/outputs/flutter-apk/app-release.apk
```

## Google Play

Download the `udrive-play-store-aab` artifact for Google Play testing. Before public publishing, configure a private production upload keystore; the included release configuration uses test signing.
