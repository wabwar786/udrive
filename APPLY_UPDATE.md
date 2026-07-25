# Phase 13.5 — Home Vehicle Cards Final Cleanup

Replace the included files under `udrive_unified_mobile`.

Changes:
- Compact vehicle cards with image, route, date/time, fare and free seats.
- Entire vehicle card opens the existing live-location and booking page.
- Search filters **destination only** (not vehicle, registration, pickup or starting city).
- Maximum 10 cards remain visible on Home.
- A failed optional marketplace request no longer adds a generic error below successfully loaded vehicles.
- Missing Driver GPS now shows a clean waiting state; booking remains usable.

Deploy Flutter web and clear the service-worker/site cache once after deployment.
