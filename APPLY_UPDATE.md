# Phase 13.5 Vehicle Location Controller Build Hotfix

Replace this file in the latest project:

`udrive_unified_mobile/lib/core/state/app_controller.dart`

This restores `loadPackageVehicleLocation(String packageId)`, which is required by `vehicle_live_map.dart`.

Then rebuild Flutter web:

```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```
