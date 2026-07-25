# Phase 13.5 — Customer Booking Flow Fix

Overlay the included `udrive_unified_mobile` folder on the latest source.

## Included fixes

- Home vehicle thumbnail containers now use a white background and bordered image surface.
- Vehicle/package images use `BoxFit.contain` so they do not look like blue icon tiles.
- Pickup defaults to the customer's current GPS location when permission is available.
- A location button lets the customer retry automatic pickup detection.
- Scheduled vehicle matches shown while entering pickup/destination are informational only and cannot be opened by tapping.
- Recommended vehicle selection now respects the selected passenger count.
- Vehicles with insufficient capacity are visibly disabled.
- The best matching vehicle is selected automatically when passenger count changes.
- Booking submission uses the authenticated customer's actual pickup coordinates when available.
- Booking submission failures now show useful session/server/network messages instead of only a generic error.

## Build

```bash
flutter pub get
flutter analyze
flutter build web --release --no-wasm-dry-run
```

No API or database migration is required for this UI patch.
