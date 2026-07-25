# Railway Deployment — Phase 11–12

## Required order

1. Confirm the API service has a persistent Railway volume mounted at `/app/uploads`.
2. Confirm API variable `UPLOAD_ROOT=/app/uploads`.
3. Confirm `DATABASE_URL`, JWT variables, allowed origins, and existing authentication variables.
4. Deploy `udrive_api`.
5. Check `GET /health/live` and `GET /health/ready`.
6. Inspect deployment logs for migration `008_phase11_12_trip_operations_tracking.sql`.
7. Confirm the new tables exist and legacy bookings were backfilled into `trip_operations`.
8. Deploy `admin_portal` with the current API base URL.
9. Hard refresh the Admin portal and test Operations & Dispatch and Live Tracking.
10. Deploy Flutter web only when needed. Do not generate APK/AAB.

## Suggested API variables

- `AUTO_APPLY_MIGRATIONS=true`
- `UPLOAD_ROOT=/app/uploads`
- `ALLOWED_ORIGINS=<admin URL>,<mobile web URL>`
- `ENABLE_SWAGGER=true` only while validating, then disable if not required.

## Location permissions

Native Flutter builds later require foreground location permission descriptions in AndroidManifest.xml and Info.plist. Location updates are started only for assigned/active trip states and stop after completion/cancellation.
