# Testing checklist

- [ ] `flutter pub get` succeeds.
- [ ] `flutter analyze` has no errors.
- [ ] Narrow mobile width shows `PKR 12,500` horizontally.
- [ ] Vehicle route and seat counts do not overflow.
- [ ] Tapping a vehicle opens an embedded map, not an external app.
- [ ] Customer location permission is handled.
- [ ] Vehicle marker appears when API returns fresh coordinates.
- [ ] Destination marker appears when destination coordinates exist.
- [ ] ETA appears only when customer and vehicle coordinates exist.
- [ ] GPS refreshes every 15 seconds.
- [ ] Stale and waiting states are clear.
