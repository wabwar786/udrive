# Customer App Runtime Screen Fix

## Updated customer flow

- City-to-City Ride, Tours & Trips and Private Vehicle open a complete responsive destination-search page.
- The destination field is no longer auto-focused when the page opens, preventing the screen from collapsing on mobile/PWA builds.
- Saved Kashmir destinations are available immediately, even while live destination sync is unavailable.
- Selecting a destination opens the full vehicle-selection page.
- Live approved vehicles are loaded from the API. A clearly labelled demo fleet is shown as a safe fallback while a Railway deployment is propagating.
- Hotels & Stays uses a responsive date row and no longer compresses dates vertically.
- Approved hotels are returned without requiring room-inventory rows for the selected date.
- Three approved demo hotels and rooms remain visible in the mobile app while the updated API is being deployed.

## Deployment

1. Deploy the updated `udrive_api` service to Railway.
2. In Admin Portal, open **Data Management** and run **Add / refresh demo data** once.
3. Build and install the updated Flutter customer app.
