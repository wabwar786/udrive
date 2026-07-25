# uDrive Phase 13.5 — Customer Home Screen Update 1

Apply this ZIP over the latest deployed Phase 13.5 source tree.

## Deployment order

1. Replace the included API and Flutter files.
2. Deploy `udrive_api` first.
3. Confirm Swagger contains:
   `GET /api/v1/packages/{packageId}/vehicle-location`
4. Confirm `/health/live` and `/health/ready` return HTTP 200.
5. Deploy `udrive_unified_mobile`.
6. Flutter build runs `flutter pub get`; this update adds `url_launcher`.
7. Clear the Flutter web service-worker/site cache after deployment.

No database migration is required.
