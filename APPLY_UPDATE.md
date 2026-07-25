# uDrive free one-minute live tracking update

## What changed

- Google Maps JavaScript API and API-key dependency removed.
- Embedded map now uses `flutter_map` with OpenStreetMap tiles.
- Driver app sends authenticated GPS every 60 seconds while an eligible active trip exists and the app is open.
- Driver identity and trip ownership remain validated by the API/JWT.
- Customer vehicle map refreshes every 60 seconds.
- Customer sees vehicle, own position, destination, last update, straight-line distance and approximate ETA.
- Offline Driver points continue to queue and retry in chronological order.

## Replace/add files

Copy the `udrive_unified_mobile` folder over the current project and overwrite files.

## Build

```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

No Google Maps key is required after this update.

## Important behavior

- Tracking runs only for assigned active trip states: DriverAccepted, DriverEnRoute, DriverArrived, TripStarted, Emergency.
- It stops after completion/cancellation/no active assignment.
- Web browsers may throttle timers in a hidden/background tab. Native Android/iOS background tracking requires platform background-location permission and an OS foreground/background service configuration.
- ETA is approximate from straight-line distance and an assumed 30 km/h speed; it is not live-traffic routing.
