# Phase 13.5 — Driver Open Requests & Fare Offers

Apply this ZIP over the latest uDrive source tree. Preserve the folder paths exactly.

## Deployment order

1. Overlay all files.
2. Deploy `udrive_api` first.
3. Confirm `/health/live` and `/health/ready` return HTTP 200.
4. Confirm migration `011_driver_marketplace_expiry` is recorded in `udrive.schema_migrations`.
5. Deploy `udrive_unified_mobile` Flutter web.
6. Clear the Flutter service worker/site cache once after deployment.

No APK/AAB is included.
