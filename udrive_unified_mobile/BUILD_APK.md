# Build and Download Android APK/AAB

## GitHub Actions

1. Push the update to `main`.
2. Open GitHub → Actions.
3. Open **Build uDrive APK and AAB**.
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

The current release build uses debug signing for test installation. Configure a private upload keystore before Google Play production publishing.
