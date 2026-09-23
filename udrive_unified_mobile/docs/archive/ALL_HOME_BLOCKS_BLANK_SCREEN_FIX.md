# All Home Blocks Blank Screen Fix

Updated 2026-08-15.

- City-to-City, Tours & Trips and Private Vehicle now share the same guarded, first-frame-safe results renderer.
- All three route flows seed local fallback vehicles/rates before any network/AppController dependency is used.
- Live API refresh happens after the first frame and cannot leave the page blank.
- Tours keeps tour date selection; Private Vehicle defaults to whole-vehicle booking.
- Hotels & Stays now guards AppController/repository initialization and shows an explicit retry/error state instead of failing before build.
- Emergency/Ambulance already uses a guarded loading/error state and database-only ambulance list.
