# Build and Download Android APK/AAB

## GitHub Actions

1. Push the update to `main`.
2. Open GitHub → Actions.
3. Open **Build Udrive APK and AAB**.
4. Run the workflow.
5. Download `udrive-tourism-phase-3-6-apk`.
6. Extract it to obtain `app-release.apk`.

The same run uploads `udrive-tourism-phase-3-6-aab` for later Play Store use.

The workflow automatically runs `flutter create` only when required native wrapper/project files are missing.

## Local Windows

Inside `udrive_unified_mobile`, run:

```text
build_apk_windows.bat
```

## Local Linux/macOS

```bash
chmod +x build_apk.sh
./build_apk.sh
```

## Outputs

```text
build/app/outputs/flutter-apk/app-release.apk
build/app/outputs/bundle/release/app-release.aab
```

Release signing uses your private upload keystore. `android/app/build.gradle.kts`
reads it from `android/key.properties` locally, or from `UDRIVE_KEYSTORE_PATH`,
`UDRIVE_KEYSTORE_PASSWORD`, `UDRIVE_KEY_ALIAS` and `UDRIVE_KEY_PASSWORD` in CI.
Neither the keystore nor `key.properties` is in the repository, and neither may
ever be committed.

If no upload key is configured, `flutter build apk --release` falls back to the
debug key so a tester can still install the file, but `flutter build appbundle`
fails on purpose — Google Play will not accept a debug-signed bundle.
