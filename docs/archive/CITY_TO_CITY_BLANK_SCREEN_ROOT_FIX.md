# City-to-City blank-screen root fix — 2026-08-15

Exact flow addressed:
Home → City-to-City Ride → Pickup/Destination → Popular Kashmir destination → Results screen.

Changes:
- Replaced the City-to-City results first-frame UI with a standalone Material Scaffold/ListView.
- City fallback rates and vehicle categories are seeded synchronously before first render.
- AppController/API access is deferred until after the first frame.
- No map, tour-marketplace state, network image, or complex overlay is required to render the first frame.
- Live rates/vehicles refresh after the page is already visible.
- Booking continues through the existing ride request → driver offers flow.
