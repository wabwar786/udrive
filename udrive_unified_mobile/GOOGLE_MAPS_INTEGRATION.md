# Google Maps Integration — Next Live Step

The current application uses a simulated map and location stream so the complete dummy app works without billing-enabled API keys.

## Current configuration

`lib/core/services/map_config.dart` reads:

```text
GOOGLE_MAPS_ENABLED
GOOGLE_MAPS_API_KEY
```

Example web/Android build defines:

```bash
flutter run \
  --dart-define=GOOGLE_MAPS_ENABLED=true \
  --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY
```

## Live integration work later

1. Add `google_maps_flutter` and a location package.
2. Configure Android Maps SDK key in Android resources/manifest.
3. Configure iOS Maps SDK key.
4. Restrict keys by package name, signing certificate, bundle ID and allowed web origins.
5. Replace `SimulatedLocationService` with a permission-aware live location repository.
6. Replace `_AnimatedRouteMap` with the Google Map widget.
7. Connect route polyline, Places search and distance/ETA APIs.
8. Send Driver coordinates to the backend and stream them to the Customer app.
9. Create expiring, access-controlled tracking links instead of the current dummy URL.

No secret API key should be committed to GitHub.
