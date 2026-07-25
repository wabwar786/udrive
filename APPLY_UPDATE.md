# uDrive Phase 13.5 — Vehicle Card Layout V2 + Embedded Map

Overlay the included `udrive_unified_mobile` directory on the latest source.

This V2 removes the responsive horizontal fare/button row entirely. The fare is rendered in a full-width colored strip and the map/booking action is a full-width button below it, preventing narrow-width vertical text.

After overlay:

```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

Deploy the Flutter service and clear its service worker/site storage once.
