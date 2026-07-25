# Phase 13.5 — Responsive Vehicle Cards + Embedded Live Map

## Apply
Overlay `udrive_unified_mobile` on the latest project and run:

```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

## Google Maps API key
For Flutter Web, replace `YOUR_GOOGLE_MAPS_API_KEY` in `udrive_unified_mobile/web/index.html` with a Google Maps JavaScript API key restricted to your deployed domain.

For Android/iOS, configure the same key using the standard `google_maps_flutter` platform setup before APK/AAB builds. APK/AAB is not part of this update.

## Behaviour
- Vehicle cards remain readable at narrow widths.
- The price never collapses into one character per line.
- Tapping a vehicle opens the detail page with an embedded map immediately.
- The app refreshes vehicle GPS every 15 seconds.
- Customer, vehicle and destination markers are shown when coordinates exist.
- Approximate distance and ETA to the customer are calculated from current coordinates. ETA is explicitly approximate and does not claim live traffic routing.
- If the Driver has not shared GPS, the destination map is shown with a clear waiting status.
