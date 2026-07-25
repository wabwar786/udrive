# uDrive Kashmir Demo Data + Live UI Hotfix

## Included
- Pakistan-time greeting fix (UTC+05:00)
- 50 approved demo Driver accounts
- 50 verified demo vehicles with remote vehicle image URLs
- 35 major AJK/Kashmir tourism destinations with coordinates and cover images
- 15 active tour packages
- Live Explore screen backed by `/api/v1/catalog/destinations`
- Package cards render `coverImageUrl`
- Driver vehicle cards render `imageUrl`

## Apply
1. Overlay all files on the latest project.
2. Deploy the API first. Migration `010_demo_fleet_kashmir_catalog.sql` is additive and idempotent.
3. Confirm `/health/live`, `/health/ready`, and `/api/v1/catalog/destinations`.
4. Deploy Flutter web.
5. Hard refresh and clear the Flutter service-worker cache if the previous greeting remains visible.

## Test Driver accounts
Phones: `+923109000001` through `+923109000050`.
Use the configured Development OTP only in a non-production test environment.

## Important
The seeded records are clearly identifiable by `demo.driverXX@udrive.local`, deterministic UUID ranges `400...` / `410...` / `420...`, and registrations `AJK-1001` through `AJK-1050`.
